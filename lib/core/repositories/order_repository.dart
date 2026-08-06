import 'dart:typed_data';

import '../models/cart_item.dart';
import '../models/order.dart';
import '../models/vendor.dart';
import '../supabase_client.dart';
import 'catalog_repository.dart';
import 'wallet_repository.dart';

class OrderRepository {
  OrderRepository({CatalogRepository? catalog})
    : _catalog = catalog ?? CatalogRepository();

  final CatalogRepository _catalog;

  static const _vendorJoin = '*, vendors(name, logo_url)';

  /// Places the cart as an order.
  ///
  /// [orderType] decides three things the server enforces: a pickup order
  /// carries no delivery fee and skips the service-area check, and a scheduled
  /// one may be placed while the store is shut because it is for later.
  Future<String> placeOrder({
    required String addressId,
    required String paymentMethod,
    String? couponCode,
    String? notes,
    String orderType = 'delivery',
    DateTime? scheduledAt,
  }) async {
    final result = await supabase.rpc(
      'place_order',
      params: {
        'p_address_id': addressId,
        'p_payment_method': paymentMethod,
        'p_coupon_code': (couponCode?.trim().isEmpty ?? true)
            ? null
            : couponCode!.trim(),
        'p_notes': notes,
        'p_order_type': orderType,
        'p_scheduled_at': scheduledAt?.toUtc().toIso8601String(),
      },
    );
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

  /// What a code is worth on this basket, and whether it waives delivery.
  ///
  /// Every rule lives in the RPC — start date, expiry, per-customer limit,
  /// first-order-only, store scope — so the preview a customer sees at
  /// checkout is decided by exactly the code that will run when they order.
  /// It raises the specific rule it failed, which is what lets the app say
  /// "you have already used this code" rather than "not valid".
  Future<CouponPreview> previewCoupon({
    required String code,
    required String vendorId,
    required double subtotal,
  }) async {
    final result =
        await supabase.rpc(
              'preview_coupon',
              params: {
                'p_code': code,
                'p_vendor_id': vendorId,
                'p_subtotal': subtotal,
              },
            )
            as Map<String, dynamic>;
    return CouponPreview(
      discount: ((result['discount'] as num?) ?? 0).toDouble(),
      freeDelivery: (result['free_delivery'] as bool?) ?? false,
      title: result['title'] as String?,
    );
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
    final data = await supabase
        .from('order_items')
        .select()
        .eq('order_id', orderId);
    return data.map(OrderItem.fromMap).toList();
  }

  /// Assigned driver's name + phone for an order the caller owns.
  /// Returns null when no driver is assigned yet.
  Future<DriverContact?> fetchDriverContact(String orderId) async {
    final rows =
        await supabase.rpc(
              'order_driver_contact',
              params: {'p_order_id': orderId},
            )
            as List;
    if (rows.isEmpty) return null;
    final row = rows.first as Map<String, dynamic>;
    final phone = row['phone'] as String?;
    if (phone == null || phone.isEmpty) return null;
    return DriverContact(
      name: row['full_name'] as String? ?? 'Driver',
      phone: phone,
    );
  }

  /// The store's name and phone for one order.
  ///
  /// A driver at a locked door, or holding an order with an item missing, had
  /// the customer's number and no way to reach the restaurant. Goes through an
  /// RPC because `vendors` only exposes stores the customer catalogue shows,
  /// and the driver needs the one they are carrying.
  Future<DriverContact?> fetchVendorContact(String orderId) async {
    final rows =
        await supabase.rpc(
              'order_vendor_contact',
              params: {'p_order_id': orderId},
            )
            as List;
    if (rows.isEmpty) return null;
    final row = rows.first as Map<String, dynamic>;
    final phone = row['phone'] as String?;
    if (phone == null || phone.isEmpty) return null;
    return DriverContact(name: row['name'] as String? ?? '', phone: phone);
  }

  /// The driver's last stored position, for an order that is on the road.
  ///
  /// Tracking is broadcast from the driver's phone, so a customer who opens
  /// the page between two broadcasts has nothing to draw. This is the starting
  /// point they see immediately; the broadcasts take over from there. Null
  /// when the order is not out for delivery, or the driver never reported one.
  Future<({double lat, double lng, DateTime? at})?> fetchDriverPosition(
    String orderId,
  ) async {
    final rows =
        await supabase.rpc(
              'order_driver_position',
              params: {'p_order_id': orderId},
            )
            as List;
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
  ///
  /// A scheduled order is withheld until `released_at` is stamped — a job
  /// does that shortly before its slot, and that write is itself a row change
  /// the stream carries, so the order appears on the dashboard by itself.
  Stream<List<AppOrder>> vendorOrdersStream(String vendorId) => supabase
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('vendor_id', vendorId)
      .order('created_at')
      .map(
        (rows) => rows
            .map(AppOrder.fromMap)
            .where(
              (o) =>
                  o.isReleased &&
                  (o.paymentMethod == 'cod' ||
                      o.paymentMethod == 'wallet' ||
                      o.isPaid ||
                      o.paymentStatus == 'paid'),
            )
            .toList(),
      );

  /// Realtime stream of unclaimed ready_for_pickup orders (driver pool).
  ///
  /// A collection order looks identical from here — ready, no driver — so it
  /// is excluded explicitly, or a driver would be sent for food the customer
  /// is on their way to fetch. `claim_delivery` refuses them too; this only
  /// keeps them off the screen.
  Stream<List<AppOrder>> driverPoolStream() => supabase
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('status', 'ready_for_pickup')
      .order('created_at')
      .map(
        (rows) => rows
            .map(AppOrder.fromMap)
            .where((o) => o.driverId == null && !o.isPickup)
            .toList(),
      );

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
        .neq('order_type', 'pickup')
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
    final result = await supabase.rpc(
      'claim_delivery',
      params: {'p_order_id': orderId},
    );
    return result == true;
  }

  Future<void> updateStatus(
    String orderId,
    OrderStatus newStatus, {
    String? reason,
    String? proofUrl,
  }) async {
    await supabase.rpc(
      'update_order_status',
      params: {
        'p_order_id': orderId,
        'p_new_status': newStatus.wireName,
        'p_reason': reason,
      },
    );

    if (proofUrl != null && proofUrl.isNotEmpty) {
      try {
        await supabase
            .from('orders')
            .update({
              'proof_image_url': proofUrl,
              'delivery_proof_url': proofUrl,
            })
            .eq('id', orderId);
      } catch (_) {}
    }

    // The customer's "order update" push comes from the notify_order_event
    // database trigger, so it fires for every status change no matter which
    // app made it. Loyalty points work the same way now: awarded by
    // trg_award_order_loyalty from the order row. They used to be awarded from
    // here, which credited whoever marked the order delivered — the driver.
  }

  /// Vendor name/logo for orders coming from realtime streams (which can't
  /// embed joins).
  Future<Map<String, ({String name, String? logoUrl})>> vendorLabels(
    Set<String> vendorIds,
  ) async {
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
        .map(
          (rows) => rows
              .map(AppOrder.fromMap)
              .where((o) => !o.status.isTerminal)
              .toList(),
        );
  }

  /// Fetch all orders completed by the driver during the current week.
  Future<List<AppOrder>> fetchDriverCurrentWeekOrders() async {
    final userId = supabase.auth.currentUser!.id;
    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
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

  /// Tips the driver of a delivered order from the customer's wallet.
  ///
  /// One RPC rather than the two client writes this replaced: those inserted a
  /// tip row and stamped the order without any money moving, so a driver ended
  /// up owed an amount nobody had collected. The transfer, both ledger entries
  /// and the order stamp now happen in one transaction, and the server refuses
  /// a second tip on the same order.
  Future<void> addDriverTip(String orderId, double amount) => supabase.rpc(
    'add_driver_tip',
    params: {'p_order_id': orderId, 'p_amount': amount},
  );

  Future<void> updateDeliveryProof(
    String orderId, {
    String? proofUrl,
    String? otp,
  }) async {
    final Map<String, dynamic> updates = {};
    if (proofUrl != null) updates['delivery_proof_url'] = proofUrl;
    if (otp != null) updates['delivery_otp'] = otp;

    if (updates.isNotEmpty) {
      await supabase.from('orders').update(updates).eq('id', orderId);
    }
  }

  /// Re-order all items from a previous past order into the active cart
  /// Rebuilds a past order as a cart, without touching the cart tables.
  ///
  /// The previous version wrote rows straight into `carts`/`cart_items` and
  /// then sent the customer to the cart screen — which reads [CartCubit], an
  /// in-memory cart that is only loaded from the server at sign-in. The screen
  /// therefore showed whatever it had before, usually nothing. It also matched
  /// products by *name*, dropped every option the customer had chosen, and
  /// silently skipped anything it could not find.
  ///
  /// Items are re-read from `order_items` rather than taken from
  /// [AppOrder.items]: the orders list comes from a realtime stream, which
  /// cannot join its items, so an order from that screen carries none.
  Future<ReorderDraft> buildReorderDraft(AppOrder order) async {
    final results = await Future.wait<dynamic>([
      _catalog.fetchVendor(order.vendorId),
      fetchOrderItems(order.id),
    ]);
    final vendor = results[0] as Vendor;
    final orderItems = results[1] as List<OrderItem>;

    final productIds = orderItems
        .map((i) => i.productId)
        .whereType<String>()
        .toSet()
        .toList();
    final products = await _catalog.fetchProductsByIds(productIds);
    final byId = {for (final product in products) product.id: product};

    final items = <CartItem>[];
    final unavailable = <String>[];
    var optionsChanged = false;

    for (final line in orderItems) {
      final product = line.productId == null ? null : byId[line.productId];
      // Gone from the menu, or the store has it switched off today. Either way
      // it cannot go in a cart, and the customer is told which ones.
      if (product == null || !product.isAvailable) {
        unavailable.add(line.productName);
        continue;
      }

      final wanted = line.optionIds.toSet();
      final options = [
        for (final group in product.optionGroups)
          for (final option in group.options)
            if (wanted.contains(option.id) && option.isAvailable) option,
      ];
      // An option that has since been removed or switched off: the item still
      // goes in, minus that choice, and the caller says so.
      if (options.length != wanted.length) optionsChanged = true;

      items.add(
        CartItem(
          product: product,
          quantity: line.quantity,
          selectedOptions: options,
        ),
      );
    }

    return ReorderDraft(
      vendor: vendor,
      items: items,
      unavailable: unavailable,
      optionsChanged: optionsChanged,
    );
  }

  /// Throws rather than returning null on failure.
  ///
  /// It used to swallow everything and return null, which made a refused
  /// upload indistinguishable from a driver who chose not to take a photo —
  /// the delivery completed with no proof and nobody was told why.
  Future<String> uploadDeliveryProofImage(
    String orderId,
    Uint8List bytes,
    String fileName,
  ) async {
    final path =
        'proofs/$orderId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    await supabase.storage.from('vendor-assets').uploadBinary(path, bytes);
    return supabase.storage.from('vendor-assets').getPublicUrl(path);
  }
}

/// Assigned driver's contact details for a customer to reach the rider.
class DriverContact {
  const DriverContact({required this.name, required this.phone});

  final String name;
  final String phone;
}

/// A past order rebuilt against the current menu.
///
/// Nothing is applied by producing one: the caller decides, because putting
/// this in the cart may mean discarding a cart from another store.
class ReorderDraft {
  const ReorderDraft({
    required this.vendor,
    required this.items,
    required this.unavailable,
    required this.optionsChanged,
  });

  final Vendor vendor;

  /// What can be added, with the options the customer originally picked.
  final List<CartItem> items;

  /// Names of items the store no longer sells, for a message rather than a
  /// silent gap.
  final List<String> unavailable;

  /// At least one item lost a choice that no longer exists on the menu.
  final bool optionsChanged;

  bool get isEmpty => items.isEmpty;
  bool get isPartial => unavailable.isNotEmpty || optionsChanged;

  /// The store is not taking orders at all, so there is nothing worth
  /// rebuilding — the cart would only fail at checkout.
  bool get vendorUnavailable => !vendor.isActive || !vendor.isOpenNow();
}

/// A coupon as it applies to one basket.
class CouponPreview {
  const CouponPreview({
    required this.discount,
    required this.freeDelivery,
    this.title,
  });

  final double discount;

  /// A free-delivery code discounts exactly the delivery fee, so the totals
  /// still add up; this is what lets the summary label it as such instead of
  /// showing an unexplained discount that happens to match the fee.
  final bool freeDelivery;

  /// The campaign's name, when it has one, rather than the raw code.
  final String? title;
}
