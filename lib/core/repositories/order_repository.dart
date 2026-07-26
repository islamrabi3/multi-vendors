import '../models/order.dart';
import '../supabase_client.dart';

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
    return result as String;
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

  /// Realtime stream of all orders for a vendor (dashboard).
  Stream<List<AppOrder>> vendorOrdersStream(String vendorId) => supabase
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('vendor_id', vendorId)
      .order('created_at')
      .map((rows) => rows.map(AppOrder.fromMap).toList());

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
  }) =>
      supabase.rpc('update_order_status', params: {
        'p_order_id': orderId,
        'p_new_status': newStatus.wireName,
        'p_reason': reason,
      });

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
        .order('created_at')
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
}

/// Assigned driver's contact details for a customer to reach the rider.
class DriverContact {
  const DriverContact({required this.name, required this.phone});

  final String name;
  final String phone;
}
