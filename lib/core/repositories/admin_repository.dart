import 'dart:typed_data';

import '../models/order.dart';
import '../models/vendor.dart';
import '../supabase_client.dart';

/// A pending platform snapshot for the admin control-room dashboard.
class AdminStats {
  const AdminStats({
    this.gmvToday = 0,
    this.ordersToday = 0,
    this.vendorsActive = 0,
    this.vendorsOpen = 0,
    this.vendorsPending = 0,
    this.driversOnline = 0,
    this.ordersAttention = 0,
  });

  final double gmvToday;
  final int ordersToday;
  final int vendorsActive;
  final int vendorsOpen;
  final int vendorsPending;
  final int driversOnline;
  final int ordersAttention;

  factory AdminStats.fromMap(Map<String, dynamic> m) => AdminStats(
        gmvToday: ((m['gmv_today'] as num?) ?? 0).toDouble(),
        ordersToday: ((m['orders_today'] as num?) ?? 0).toInt(),
        vendorsActive: ((m['vendors_active'] as num?) ?? 0).toInt(),
        vendorsOpen: ((m['vendors_open'] as num?) ?? 0).toInt(),
        vendorsPending: ((m['vendors_pending'] as num?) ?? 0).toInt(),
        driversOnline: ((m['drivers_online'] as num?) ?? 0).toInt(),
        ordersAttention: ((m['orders_attention'] as num?) ?? 0).toInt(),
      );
}

/// A store owner's contact details, shown on the approval detail screen.
class VendorOwner {
  const VendorOwner({required this.name, this.phone});
  final String name;
  final String? phone;
}

/// An online driver available for manual dispatch.
class DriverOption {
  const DriverOption({required this.id, required this.name, this.phone});
  final String id;
  final String name;
  final String? phone;
}

/// Platform-wide operations for the admin role. Every read/write here is gated
/// server-side by `is_admin()` (RLS + SECURITY DEFINER RPCs), so a non-admin
/// session simply gets permission errors.
class AdminRepository {
  Future<AdminStats> fetchStats() async {
    final data = await supabase.rpc('admin_dashboard_stats');
    return AdminStats.fromMap((data as Map).cast<String, dynamic>());
  }

  /// All stores across every approval state, newest first.
  Future<List<Vendor>> fetchVendors() async {
    final data = await supabase
        .from('vendors')
        .select()
        .order('created_at', ascending: false);
    return (data as List).map((e) => Vendor.fromMap(e)).toList();
  }

  Future<Vendor> fetchVendor(String vendorId) async {
    final data =
        await supabase.from('vendors').select().eq('id', vendorId).single();
    return Vendor.fromMap(data);
  }

  Future<VendorOwner?> fetchVendorOwner(String ownerId) async {
    final data = await supabase
        .from('profiles')
        .select('full_name, phone')
        .eq('id', ownerId)
        .maybeSingle();
    if (data == null) return null;
    return VendorOwner(
      name: (data['full_name'] as String?)?.trim().isNotEmpty == true
          ? data['full_name'] as String
          : 'Owner',
      phone: data['phone'] as String?,
    );
  }

  Future<void> setVendorStatus(String vendorId, String status) =>
      supabase.rpc('admin_set_vendor_status', params: {
        'p_vendor_id': vendorId,
        'p_status': status,
      });

  /// Realtime stream of every order on the platform (RLS admin read).
  Stream<List<AppOrder>> allOrdersStream() => supabase
      .from('orders')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .map((rows) => rows.map(AppOrder.fromMap).toList());

  Future<AppOrder> fetchOrder(String orderId) async {
    final data = await supabase
        .from('orders')
        .select('*, vendors(name, logo_url), order_items(*)')
        .eq('id', orderId)
        .single();
    return AppOrder.fromMap(data);
  }

  Future<List<DriverOption>> fetchOnlineDrivers() async {
    final data = await supabase
        .from('drivers')
        .select('id, profiles(full_name, phone)')
        .eq('is_online', true);
    return (data as List).map((row) {
      final p = row['profiles'];
      return DriverOption(
        id: row['id'] as String,
        name: p is Map ? (p['full_name'] as String?) ?? 'Driver' : 'Driver',
        phone: p is Map ? p['phone'] as String? : null,
      );
    }).toList();
  }

  Future<void> assignDriver(String orderId, String driverId) =>
      supabase.rpc('admin_assign_driver', params: {
        'p_order_id': orderId,
        'p_driver_id': driverId,
      });

  Future<void> cancelOrder(String orderId, {String? reason}) =>
      supabase.rpc('update_order_status', params: {
        'p_order_id': orderId,
        'p_new_status': 'cancelled',
        'p_reason': reason,
      });

  /// Vendor name/logo lookup for orders arriving over realtime (no joins).
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

  /// Fetch all vendor categories.
  Future<List<VendorCategory>> fetchVendorCategories() async {
    final data = await supabase
        .from('vendor_categories')
        .select()
        .order('name');
    return (data as List).map((row) => VendorCategory.fromMap(row)).toList();
  }

  /// Create a new vendor category.
  Future<void> createVendorCategory({required String name, String? imageUrl}) async {
    await supabase.from('vendor_categories').insert({
      'name': name,
      'image_url': imageUrl,
    });
  }

  /// Update an existing vendor category.
  Future<void> updateVendorCategory(String id, {required String name, String? imageUrl}) async {
    await supabase.from('vendor_categories').update({
      'name': name,
      'image_url': imageUrl,
    }).eq('id', id);
  }

  /// Delete a vendor category.
  Future<void> deleteVendorCategory(String id) async {
    await supabase.from('vendor_categories').delete().eq('id', id);
  }

  /// Upload category banner/icon image to Supabase storage.
  Future<String> uploadCategoryImage({
    required String path,
    required List<int> bytes,
  }) async {
    await supabase.storage.from('vendor_assets').uploadBinary(
          path,
          Uint8List.fromList(bytes),
        );
    return supabase.storage.from('vendor_assets').getPublicUrl(path);
  }
}
