import '../models/order.dart';
import '../supabase_client.dart';
import 'loyalty_repository.dart';
import 'wallet_repository.dart';

class OrderRepository {
  static const _vendorJoin = '*, vendors(name, logo_url)';

  Future<String> placeOrder({
    required String addressId,
    required String paymentMethod,
    String? couponCode,
    String? notes,
  }) async {
    final result = await supabase.rpc('place_order', params: {
      'p_address_id': addressId,
      'p_payment_method': paymentMethod,
      'p_coupon_code':
          (couponCode?.trim().isEmpty ?? true) ? null : couponCode!.trim(),
      'p_notes': notes,
    });
    final orderId = result as String;

    if (paymentMethod == 'wallet') {
      // Debited through the RPC so the balance check and the ledger entry are
      // one transaction — wallets are not client-writable.
      try {
        await WalletRepository().payOrder(orderId);
      } catch (error) {
        await discardUnpaidOrder(orderId);
        rethrow;
      }
    }

    return orderId;
  }

  Future<double> validateCoupon({
    required String code,
    required String vendorId,
    required double subtotal,
  }) async {
    final result = await supabase.rpc('validate_coupon', params: {
      'p_code': code,
      'p_vendor_id': vendorId,
      'p_subtotal': subtotal,
    });
    return (result as num).toDouble();
  }

  Future<AppOrder> fetchOrder(String orderId) async {
    final data = await supabase
        .from('orders')
        .select('$_vendorJoin, order_items(*)')
        .eq('id', orderId)
        .single();
    return AppOrder.fromMap(data);
  }

  Future<List<OrderItem>> fetchOrderItems(String orderId) async {
    final data =
        await supabase.from('order_items').select().eq('order_id', orderId);
    return data.map(OrderItem.fromMap).toList();
  }

  /// Assigned driver's name + phone for an order the caller owns.
  /// Returns null when no driver is assigned yet.
  Future<DriverContact?> fetchDriverContact(String orderId) async {
    final rows = await supabase
        .rpc('order_driver_contact', params: {'p_order_id': orderId}) as List;
    if (rows.isEmpty) return null;
    final row = rows.first as Map<String, dynamic>;
    final phone = row['phone'] as String?;
    if (phone == null || phone.isEmpty) return null;
    return DriverContact(
      name: row['full_name'] as String? ?? 'Driver',
      phone: phone,
    );
  }

  /// The driver's last stored position, for an order that is on the road.
  ///
  /// Tracking is broadcast from the driver's phone, so a customer who opens
  /// the page between two broadcasts has nothing to draw. This is the starting
  /// point they see immediately; the broadcasts take over from there. Null
  /// when the order is not out for delivery, or the driver never reported one.
  Future<({double lat, double lng, DateTime? at})?> fetchDriverPosition(
      String orderId) async {
    final rows = await supabase
        .rpc('order_driver_position', params: {'p_order_id': orderId}) as List;
    if (rows.isEmpty) return null;
    final row = rows.first as Map<String, dynamic>;
    final lat = (row['lat'] as num?)?.toDouble();
    final lng = (row['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return (
      lat: lat,
      lng: lng,
      at: row['updated_at'] == null
          ? null
          : DateTime.parse(row['updated_at'] as String).toLocal(),
    );
  }

  /// Realtime stream of a single order row (status + payment changes).
  Stream<AppOrder?> orderStream(String orderId) => supabase
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('id', orderId)
      .map((rows) => rows.isEmpty ? null : AppOrder.fromMap(rows.first));

  /// Realtime stream of the signed-in customer's orders.
  Stream<List<AppOrder>> myOrdersStream() {
    final userId = supabase.auth.currentUser!.id;
    return supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('customer_id', userId)
        .order('created_at')
        .map((rows) => rows.map(AppOrder.fromMap).toList());
  }

  /// Deletes an unpaid card order after a failed or abandoned payment, so it
  /// never reaches the restaurant. No-op once the order has been paid.
  Future<bool> discardUnpaidOrder(String orderId) async {
    try {
      final result = await supabase.rpc(
        'discard_unpaid_order',
        params: {'p_order_id': orderId},
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Realtime stream of all orders for a vendor (dashboard).
  Stream<List<AppOrder>> vendorOrdersStream(String vendorId) => supabase
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('vendor_id', vendorId)
      .order('created_at')
      .map((rows) => rows
          .map(AppOrder.fromMap)
          .where((o) =>
              o.paymentMethod == 'cod' ||
              o.paymentMethod == 'wallet' ||
              o.isPaid ||
              o.paymentStatus == 'paid')
          .toList());

  /// Realtime stream of unclaimed ready_for_pickup orders (driver pool).
  Stream<List<AppOrder>> driverPoolStream() => supabase
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('status', 'ready_for_pickup')
      .order('created_at')
      .map((rows) => rows
          .map(AppOrder.fromMap)
          .where((o) => o.driverId == null)
          .toList());

  /// Realtime stream of the driver's own orders (active + history).
  Stream<List<AppOrder>> driverOrdersStream() {
    final userId = supabase.auth.currentUser!.id;
    return supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('driver_id', userId)
        .order('created_at')
        .map((rows) => rows.map(AppOrder.fromMap).toList());
  }

  /// One-shot fetch of a vendor's orders (pull-to-refresh).
  Future<List<AppOrder>> fetchVendorOrders(String vendorId) async {
    final data = await supabase
        .from('orders')
        .select(_vendorJoin)
        .eq('vendor_id', vendorId)
        .order('created_at');
    return (data as List)
        .map((e) => AppOrder.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// One-shot fetch of the unclaimed ready_for_pickup pool (pull-to-refresh).
  Future<List<AppOrder>> fetchDriverPool() async {
    final data = await supabase
        .from('orders')
        .select(_vendorJoin)
        .eq('status', 'ready_for_pickup')
        .isFilter('driver_id', null)
        .order('created_at');
    return (data as List)
        .map((e) => AppOrder.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// One-shot fetch of the driver's own orders (pull-to-refresh).
  Future<List<AppOrder>> fetchDriverOrders() async {
    final userId = supabase.auth.currentUser!.id;
    final data = await supabase
        .from('orders')
        .select(_vendorJoin)
        .eq('driver_id', userId)
        .order('created_at');
    return (data as List)
        .map((e) => AppOrder.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<bool> claimDelivery(String orderId) async {
    final result =
        await supabase.rpc('claim_delivery', params: {'p_order_id': orderId});
    return result == true;
  }

  Future<void> updateStatus(
    String orderId,
    OrderStatus newStatus, {
    String? reason,
    String? proofUrl,
  }) async {
    await supabase.rpc('update_order_status', params: {
      'p_order_id': orderId,
      'p_new_status': newStatus.wireName,
      'p_reason': reason,
    });

    if (proofUrl != null && proofUrl.isNotEmpty) {
      try {
        await supabase.from('orders').update({
          'proof_image_url': proofUrl,
          'delivery_proof_url': proofUrl,
        }).eq('id', orderId);
      } catch (_) {}
    }

    // The customer's "order update" push comes from the notify_order_event
    // database trigger, so it fires for every status change no matter which
    // app made it.
    if (newStatus == OrderStatus.delivered) {
      try {
        await LoyaltyRepository()
            .earnPoints(10, 'Order #${orderId.substring(0, 8)} reward');
      } catch (_) {}
    }
  }

  /// Vendor name/logo for orders coming from realtime streams (which can't
  /// embed joins).
  Future<Map<String, ({String name, String? logoUrl})>> vendorLabels(
      Set<String> vendorIds) async {
    if (vendorIds.isEmpty) return {};
    final data = await supabase
        .from('vendors')
        .select('id, name, logo_url')
        .inFilter('id', vendorIds.toList());
    return {
      for (final row in data)
        row['id'] as String: (
          name: row['name'] as String,
          logoUrl: row['logo_url'] as String?,
        ),
    };
  }

  /// Paginated fetch of customer's past (terminal) orders.
  Future<List<AppOrder>> fetchCustomerPastOrders({
    required int limit,
    required int offset,
  }) async {
    final userId = supabase.auth.currentUser!.id;
    final data = await supabase
        .from('orders')
        .select(_vendorJoin)
        .eq('customer_id', userId)
        .inFilter('status', ['delivered', 'cancelled', 'rejected'])
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List)
        .map((e) => AppOrder.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Paginated fetch of driver's completed (delivered) orders.
  Future<List<AppOrder>> fetchDriverHistory({
    required int limit,
    required int offset,
  }) async {
    final userId = supabase.auth.currentUser!.id;
    final data = await supabase
        .from('orders')
        .select(_vendorJoin)
        .eq('driver_id', userId)
        .eq('status', 'delivered')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List)
        .map((e) => AppOrder.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Stream of active (non-terminal) customer orders.
  Stream<List<AppOrder>> myActiveOrdersStream() {
    final userId = supabase.auth.currentUser!.id;
    return supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('customer_id', userId)
        .map((rows) => rows
            .map(AppOrder.fromMap)
            .where((o) => !o.status.isTerminal)
            .toList());
  }

  /// Fetch all orders completed by the driver during the current week.
  Future<List<AppOrder>> fetchDriverCurrentWeekOrders() async {
    final userId = supabase.auth.currentUser!.id;
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final data = await supabase
        .from('orders')
        .select()
        .eq('driver_id', userId)
        .eq('status', 'delivered')
        .gte('created_at', monday.toIso8601String());
    return (data as List)
        .map((e) => AppOrder.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addDriverTip(String orderId, String driverId, double amount) async {
    await supabase.from('driver_tips').insert({
      'order_id': orderId,
      'driver_id': driverId,
      'amount': amount,
    });
    await supabase.from('orders').update({
      'driver_tip': amount,
    }).eq('id', orderId);
  }

  Future<void> updateDeliveryProof(String orderId, {String? proofUrl, String? otp}) async {
    final Map<String, dynamic> updates = {};
    if (proofUrl != null) updates['delivery_proof_url'] = proofUrl;
    if (otp != null) updates['delivery_otp'] = otp;

    if (updates.isNotEmpty) {
      await supabase.from('orders').update(updates).eq('id', orderId);
    }
  }

  /// Re-order all items from a previous past order into the active cart
  Future<void> reorderPastOrder(AppOrder order) async {
    final userId = supabase.auth.currentUser!.id;
    // Clear current cart or create cart for this vendor
    await supabase.from('carts').upsert({
      'user_id': userId,
      'vendor_id': order.vendorId,
      'updated_at': DateTime.now().toIso8601String(),
    });

    // Fetch items and insert into cart
    final cartRes = await supabase
        .from('carts')
        .select('id')
        
        .eq('user_id', userId)
        .single();
    final cartId = cartRes['id'] as String;

    await supabase.from('cart_items').delete().eq('cart_id', cartId);

    for (final item in order.items) {
      // Find product matching name or product_id
      final products = await supabase
          .from('products')
          .select('id')
          .eq('vendor_id', order.vendorId)
          .eq('name', item.productName)
          .limit(1);

      if ((products as List).isNotEmpty) {
        final productId = products.first['id'] as String;
        await supabase.from('cart_items').insert({
          'cart_id': cartId,
          'product_id': productId,
          'quantity': item.quantity,
        });
      }
    }
  }

  Future<String?> uploadDeliveryProofImage(
      String orderId, List<int> bytes, String fileName) async {
    try {
      final path =
          'proofs/$orderId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
      await supabase.storage.from('vendor-assets').uploadBinary(path, bytes as dynamic);
      return supabase.storage.from('vendor-assets').getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }
}


/// Assigned driver's contact details for a customer to reach the rider.
class DriverContact {
  const DriverContact({required this.name, required this.phone});

  final String name;
  final String phone;
}
