import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

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

/// A driver application as the admin reviews it. A driver cannot go online or
/// claim an order until [approvalStatus] is 'active' — enforced in the
/// database, not here.
class DriverAccount {
  const DriverAccount({
    required this.id,
    required this.name,
    required this.approvalStatus,
    required this.isOnline,
    this.phone,
    this.vehicleType,
    this.idCardUrl,
    this.licenseUrl,
  });

  final String id;
  final String name;
  final String approvalStatus;
  final bool isOnline;
  final String? phone;
  final String? vehicleType;
  final String? idCardUrl;
  final String? licenseUrl;

  bool get isPending => approvalStatus == 'pending';
  bool get isApproved => approvalStatus == 'active';
  bool get isSuspended => approvalStatus == 'suspended';

  /// Only the document links are ever swapped — a stored path for a signed URL.
  DriverAccount copyWith({String? idCardUrl, String? licenseUrl}) =>
      DriverAccount(
        id: id,
        name: name,
        approvalStatus: approvalStatus,
        isOnline: isOnline,
        phone: phone,
        vehicleType: vehicleType,
        idCardUrl: idCardUrl,
        licenseUrl: licenseUrl,
      );

  factory DriverAccount.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'];
    return DriverAccount(
      id: map['id'] as String,
      name: profile is Map
          ? ((profile['full_name'] as String?)?.trim().isNotEmpty == true
              ? profile['full_name'] as String
              : 'Driver')
          : 'Driver',
      phone: profile is Map ? profile['phone'] as String? : null,
      approvalStatus: (map['approval_status'] as String?) ?? 'pending',
      isOnline: (map['is_online'] as bool?) ?? false,
      vehicleType: map['vehicle_type'] as String?,
      idCardUrl: map['id_card_url'] as String?,
      licenseUrl: map['license_url'] as String?,
    );
  }
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

  /// One page of stores, newest first, optionally narrowed to one approval
  /// state so the list tabs page server-side instead of filtering loaded rows.
  Future<List<Vendor>> fetchVendorsPage({
    required int limit,
    required int offset,
    String? status,
  }) async {
    var query = supabase.from('vendors').select();
    if (status != null) query = query.eq('approval_status', status);
    final data = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List).map((e) => Vendor.fromMap(e)).toList();
  }

  /// Exact store counts per approval state. The list is paged, so the filter
  /// chips cannot count loaded rows.
  Future<({int all, int pending, int active, int suspended})>
      fetchVendorCounts() async {
    final counts = await Future.wait([
      supabase.from('vendors').count(),
      supabase.from('vendors').count().eq('approval_status', 'pending'),
      supabase.from('vendors').count().eq('approval_status', 'active'),
      supabase.from('vendors').count().eq('approval_status', 'suspended'),
    ]);
    return (
      all: counts[0],
      pending: counts[1],
      active: counts[2],
      suspended: counts[3],
    );
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

  /// Statuses an order can sit in while it is still in flight.
  static const _liveStatuses = [
    'pending',
    'accepted',
    'preparing',
    'ready_for_pickup',
    'out_for_delivery',
  ];

  static const _finishedStatuses = ['delivered', 'cancelled', 'rejected'];

  /// Realtime stream of the orders still in flight platform-wide (RLS admin
  /// read). Bounded by how many orders are actually live, so the monitor never
  /// streams the entire order history; finished orders are paged instead
  /// ([fetchOrdersHistoryPage]).
  ///
  /// Card orders awaiting Paymob settlement are drafts — invisible to vendors
  /// and drivers by RLS — so they are hidden here too until they are paid.
  /// A `.stream()` accepts a single server-side filter, hence the client-side
  /// draft check.
  Stream<List<AppOrder>> liveOrdersStream() => supabase
      .from('orders')
      .stream(primaryKey: ['id'])
      .inFilter('status', _liveStatuses)
      .order('created_at')
      .map((rows) => rows
          .map(AppOrder.fromMap)
          .where((order) => order.paymentMethod != 'paymob' || order.isPaid)
          .toList());

  /// One page of finished orders, newest first. The unpaid-Paymob-draft rule is
  /// applied server-side so a short page always means "no more results".
  Future<List<AppOrder>> fetchOrdersHistoryPage({
    required int limit,
    required int offset,
  }) async {
    final data = await supabase
        .from('orders')
        .select('*, vendors(name, logo_url)')
        .inFilter('status', _finishedStatuses)
        .or('payment_method.neq.paymob,payment_status.eq.paid')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List)
        .map((e) => AppOrder.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<AppOrder> fetchOrder(String orderId) async {
    final data = await supabase
        .from('orders')
        .select('*, vendors(name, logo_url), order_items(*)')
        .eq('id', orderId)
        .single();
    return AppOrder.fromMap(data);
  }

  /// Every driver account, pending applications first — that is the queue the
  /// admin is actually here to work.
  Future<List<DriverAccount>> fetchDrivers() async {
    List data;
    try {
      data = await supabase
          .from('drivers')
          .select('id, approval_status, is_online, vehicle_type, id_card_url, license_url,'
              ' profiles(full_name, phone)');
    } catch (_) {
      data = await supabase
          .from('drivers')
          .select('id, approval_status, is_online, vehicle_type,'
              ' profiles(full_name, phone)');
    }
    final drivers = (data)
        .map((e) => DriverAccount.fromMap(e as Map<String, dynamic>))
        .toList();
    drivers.sort((a, b) {
      if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
      return a.name.compareTo(b.name);
    });

    // The columns hold private storage paths; the screen needs something it
    // can put in an <img>. Signed here so the review queue works offline of
    // any per-tap round trip.
    return Future.wait(drivers.map((d) async {
      final signed = await Future.wait([
        signedDriverDocumentUrl(d.idCardUrl),
        signedDriverDocumentUrl(d.licenseUrl),
      ]);
      return d.copyWith(idCardUrl: signed[0], licenseUrl: signed[1]);
    }));
  }

  Future<void> setDriverStatus(String driverId, String status,
          {String? reason}) =>
      supabase.rpc('admin_set_driver_status', params: {
        'p_driver_id': driverId,
        'p_status': status,
        'p_reason': reason,
      });

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

  /// Credits a cancelled, paid card order's total back to the customer's
  /// wallet. Server-side the RPC is admin-only and idempotent (paid ->
  /// refunded exactly once). Returns the refunded amount.
  Future<double> refundOrderToWallet(String orderId) async {
    final amount = await supabase.rpc('admin_refund_order_to_wallet',
        params: {'p_order_id': orderId});
    // The refund is committed once the RPC returns; never let a parse issue
    // on the returned amount surface as a failure.
    if (amount is num) return amount.toDouble();
    return num.tryParse('$amount')?.toDouble() ?? 0;
  }

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
    await supabase.storage.from('vendor-assets').uploadBinary(
          path,
          Uint8List.fromList(bytes),
        );
    return supabase.storage.from('vendor-assets').getPublicUrl(path);
  }

  /// What each store sold and what the platform keeps, for the settlement the
  /// admin actually pays out.
  ///
  /// Aggregated by the database, not here: the commission is each store's own
  /// `vendors.commission_rate`, and paging the whole order history into the app
  /// to add it up client-side was both wrong and unbounded.
  Future<List<VendorReportItem>> fetchVendorSalesReport({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final data = await supabase.rpc('admin_vendor_sales_report', params: {
      'p_start': startDate?.toUtc().toIso8601String(),
      'p_end': endDate?.toUtc().toIso8601String(),
    });
    return (data as List)
        .map((e) => VendorReportItem.fromMap((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// What each driver is owed for the same period.
  ///
  /// [driverSharePercent] is the cut of the delivery fee the driver keeps; tips
  /// are passed through in full.
  Future<List<DriverReportItem>> fetchDriverEarningsReport({
    DateTime? startDate,
    DateTime? endDate,
    double driverSharePercent = 90,
  }) async {
    final data = await supabase.rpc('admin_driver_payout_report', params: {
      'p_start': startDate?.toUtc().toIso8601String(),
      'p_end': endDate?.toUtc().toIso8601String(),
      'p_driver_share': driverSharePercent,
    });
    return (data as List)
        .map((e) => DriverReportItem.fromMap((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Uploads a driver's ID or licence scan and records where it landed.
  ///
  /// These are identity documents, so the bucket is private and the column
  /// holds the object path — never a public URL. [fetchDrivers] turns the path
  /// into a short-lived signed URL when the admin opens the queue.
  Future<String> uploadDriverDocument({
    required String driverId,
    required String docType,
    required List<int> bytes,
    required String filename,
  }) async {
    final dot = filename.lastIndexOf('.');
    final extension = dot == -1 ? 'jpg' : filename.substring(dot + 1);
    // The first path segment is the owner, which is what the storage policies
    // key off — so it must stay the bare driver id.
    final path = '$driverId/$docType-'
        '${DateTime.now().millisecondsSinceEpoch}.$extension';
    await supabase.storage.from(_driverDocsBucket).uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(upsert: true),
        );
    await supabase.from('drivers').update({docType: path}).eq('id', driverId);
    return path;
  }

  /// A viewable link for a stored document path, good for an hour.
  Future<String?> signedDriverDocumentUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    // Rows written before the private bucket existed hold a full URL.
    if (path.startsWith('http')) return path;
    try {
      return await supabase.storage
          .from(_driverDocsBucket)
          .createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }
}

const _driverDocsBucket = 'driver-documents';

class VendorReportItem {
  const VendorReportItem({
    required this.vendorId,
    required this.vendorName,
    required this.totalOrders,
    required this.grossSales,
    required this.commissionRate,
    required this.commissionFee,
    required this.netPayout,
  });

  final String vendorId;
  final String vendorName;
  final int totalOrders;
  final double grossSales;

  /// Platform cut as a percentage, e.g. `10` for 10%.
  final double commissionRate;
  final double commissionFee;
  final double netPayout;

  factory VendorReportItem.fromMap(Map<String, dynamic> map) =>
      VendorReportItem(
        vendorId: map['vendor_id'] as String,
        vendorName: (map['vendor_name'] as String?) ?? 'Store',
        totalOrders: _money(map['total_orders']).toInt(),
        grossSales: _money(map['gross_sales']),
        commissionRate: _money(map['commission_rate']),
        commissionFee: _money(map['commission_fee']),
        netPayout: _money(map['net_payout']),
      );
}

/// Postgres `numeric` arrives as a number over PostgREST but as a string from
/// some transports, so neither is assumed.
double _money(Object? value) => switch (value) {
      num n => n.toDouble(),
      String s => double.tryParse(s) ?? 0,
      _ => 0,
    };

class DriverReportItem {
  const DriverReportItem({
    required this.driverId,
    required this.driverName,
    required this.deliveredOrders,
    required this.deliveryFeesEarned,
    required this.tipsEarned,
    required this.netDriverPayout,
  });

  final String driverId;
  final String driverName;
  final int deliveredOrders;
  final double deliveryFeesEarned;
  final double tipsEarned;
  final double netDriverPayout;

  factory DriverReportItem.fromMap(Map<String, dynamic> map) =>
      DriverReportItem(
        driverId: map['driver_id'] as String,
        driverName: (map['driver_name'] as String?) ?? 'Driver',
        deliveredOrders: _money(map['delivered_orders']).toInt(),
        deliveryFeesEarned: _money(map['delivery_fees']),
        tipsEarned: _money(map['tips']),
        netDriverPayout: _money(map['net_payout']),
      );
}
