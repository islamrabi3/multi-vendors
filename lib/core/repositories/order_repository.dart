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
}
