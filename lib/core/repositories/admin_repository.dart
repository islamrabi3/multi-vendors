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
    this.driversPending = 0,
    this.supportOpen = 0,
    this.ordersAttention = 0,
  });

  final double gmvToday;
  final int ordersToday;
  final int vendorsActive;
  final int vendorsOpen;
  final int vendorsPending;
  final int driversOnline;

  /// Driver applications waiting on a decision.
  final int driversPending;

  /// Support threads nobody has closed.
  final int supportOpen;
  final int ordersAttention;

  factory AdminStats.fromMap(Map<String, dynamic> m) => AdminStats(
    gmvToday: ((m['gmv_today'] as num?) ?? 0).toDouble(),
    ordersToday: ((m['orders_today'] as num?) ?? 0).toInt(),
    vendorsActive: ((m['vendors_active'] as num?) ?? 0).toInt(),
    vendorsOpen: ((m['vendors_open'] as num?) ?? 0).toInt(),
    vendorsPending: ((m['vendors_pending'] as num?) ?? 0).toInt(),
    driversOnline: ((m['drivers_online'] as num?) ?? 0).toInt(),
    driversPending: ((m['drivers_pending'] as num?) ?? 0).toInt(),
    supportOpen: ((m['support_open'] as num?) ?? 0).toInt(),
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
    this.idCardBackUrl,
    this.licenseUrl,
    this.licenseBackUrl,
  });

  final String id;
  final String name;
  final String approvalStatus;
  final bool isOnline;
  final String? phone;
  final String? vehicleType;
  final String? idCardUrl;
  final String? idCardBackUrl;
  final String? licenseUrl;
  final String? licenseBackUrl;

  /// Both sides of both documents, in the order a reviewer reads them.
  List<({String column, String? url})> get documents => [
    (column: 'id_card_url', url: idCardUrl),
    (column: 'id_card_back_url', url: idCardBackUrl),
    (column: 'license_url', url: licenseUrl),
    (column: 'license_back_url', url: licenseBackUrl),
  ];

  bool get hasAnyDocument => documents.any((d) => d.url != null);

  bool get isPending => approvalStatus == 'pending';
  bool get isApproved => approvalStatus == 'active';
  bool get isSuspended => approvalStatus == 'suspended';

  /// Only the document links are ever swapped — a stored path for a signed URL.
  DriverAccount copyWith({
    String? idCardUrl,
    String? idCardBackUrl,
    String? licenseUrl,
    String? licenseBackUrl,
  }) => DriverAccount(
    id: id,
    name: name,
    approvalStatus: approvalStatus,
    isOnline: isOnline,
    phone: phone,
    vehicleType: vehicleType,
    idCardUrl: idCardUrl,
    idCardBackUrl: idCardBackUrl,
    licenseUrl: licenseUrl,
    licenseBackUrl: licenseBackUrl,
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
      idCardBackUrl: map['id_card_back_url'] as String?,
      licenseUrl: map['license_url'] as String?,
      licenseBackUrl: map['license_back_url'] as String?,
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
    String? search,
  }) async {
    var query = supabase.from('vendors').select();
    if (status != null) query = query.eq('approval_status', status);
    // Server-side, so it searches every store rather than the page already
    // loaded — the point of a search is finding what is not on screen.
    final term = search?.trim();
    if (term != null && term.isNotEmpty) {
      // Commas and parentheses would be read as PostgREST filter syntax.
      final safe = term.replaceAll(RegExp(r'[,()]'), ' ');
      query = query.or('name.ilike.%$safe%,phone.ilike.%$safe%');
    }
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
    final data = await supabase
        .from('vendors')
        .select()
        .eq('id', vendorId)
        .single();
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

  Future<void> setVendorStatus(String vendorId, String status) => supabase.rpc(
    'admin_set_vendor_status',
    params: {'p_vendor_id': vendorId, 'p_status': status},
  );

  /// Every account, newest first. Admin-only by RLS.
  /// One page of accounts, newest first.
  ///
  /// Previously unbounded and filtered in the app, which meant every profile
  /// on the platform crossed the wire so that a search box could hide most of
  /// them. Both the search and the limit are now the database's job.
  /// [role] is one of the `user_role` enum values, or null for every role.
  /// [status] is 'active', 'blocked' or 'closed', or null for all.
  ///
  /// Both are applied in the query rather than over the returned page. The
  /// list is paged, so filtering client-side would filter one page of 40 and
  /// silently hide every match further down — the more users exist, the more
  /// wrong it gets.
  Future<List<AdminUser>> fetchUsers({
    String? search,
    String? role,
    String? status,
    int limit = 40,
    int offset = 0,
  }) async {
    var query = supabase
        .from('profiles')
        .select(
          'id, full_name, phone, role, is_blocked, blocked_reason, '
          'deleted_at, created_at',
        );
    final needle = search?.trim() ?? '';
    if (needle.isNotEmpty) {
      query = query.or('full_name.ilike.%$needle%,phone.ilike.%$needle%');
    }
    if (role != null) query = query.eq('role', role);
    switch (status) {
      case 'active':
        query = query.eq('is_blocked', false).isFilter('deleted_at', null);
      case 'blocked':
        query = query.eq('is_blocked', true).isFilter('deleted_at', null);
      case 'closed':
        query = query.not('deleted_at', 'is', null);
    }
    final data = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List)
        .map((e) => AdminUser.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Blocking is reversible and keeps the account; the server refuses to block
  /// an admin or the caller themselves.
  Future<void> setUserBlocked(String userId, bool blocked, {String? reason}) =>
      supabase.rpc(
        'admin_set_user_blocked',
        params: {'p_user_id': userId, 'p_blocked': blocked, 'p_reason': reason},
      );

  /// Credits (positive) or debits (negative) a customer's wallet.
  ///
  /// Goes through an RPC rather than writing the table: the balance and the
  /// ledger row have to move together, under a lock, or a wallet history stops
  /// adding up to its balance. Returns the new balance.
  Future<double> adjustWallet({
    required String userId,
    required double amount,
    required String reason,
  }) async {
    final result = await supabase.rpc(
      'admin_adjust_wallet',
      params: {'p_user_id': userId, 'p_amount': amount, 'p_reason': reason},
    );
    return double.tryParse('$result') ?? 0;
  }

  /// Removes an account.
  ///
  /// Returns true when the row was really deleted. An account with order
  /// history cannot be: `orders` references it with NO ACTION, and deleting it
  /// anyway would take the order ledger with it. Those are anonymised and
  /// locked out of sign-in instead, and the caller is told so rather than
  /// being shown "deleted" over a row that is still there.
  Future<bool> deleteUser(String userId) async {
    final result = await supabase.rpc(
      'admin_delete_user',
      params: {'p_user_id': userId},
    );
    return result is Map && result['hard_deleted'] == true;
  }

  /// Promotes or demotes a store on the customer home's recommended rail.
  Future<void> setVendorRecommended(
    String vendorId,
    bool recommended, {
    int rank = 0,
  }) => supabase.rpc(
    'admin_set_vendor_recommended',
    params: {
      'p_vendor_id': vendorId,
      'p_recommended': recommended,
      'p_rank': rank,
    },
  );

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
      .map(
        (rows) => rows
            .map(AppOrder.fromMap)
            .where((order) => order.paymentMethod != 'paymob' || order.isPaid)
            .toList(),
      );

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
          .select(
            'id, approval_status, is_online, vehicle_type,'
            ' id_card_url, id_card_back_url, license_url, license_back_url,'
            ' profiles(full_name, phone)',
          );
    } catch (_) {
      data = await supabase
          .from('drivers')
          .select(
            'id, approval_status, is_online, vehicle_type,'
            ' profiles(full_name, phone)',
          );
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
    return Future.wait(
      drivers.map((d) async {
        final signed = await Future.wait([
          signedDriverDocumentUrl(d.idCardUrl),
          signedDriverDocumentUrl(d.idCardBackUrl),
          signedDriverDocumentUrl(d.licenseUrl),
          signedDriverDocumentUrl(d.licenseBackUrl),
        ]);
        return d.copyWith(
          idCardUrl: signed[0],
          idCardBackUrl: signed[1],
          licenseUrl: signed[2],
          licenseBackUrl: signed[3],
        );
      }),
    );
  }

  Future<void> setDriverStatus(
    String driverId,
    String status, {
    String? reason,
  }) => supabase.rpc(
    'admin_set_driver_status',
    params: {'p_driver_id': driverId, 'p_status': status, 'p_reason': reason},
  );

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

  Future<void> assignDriver(String orderId, String driverId) => supabase.rpc(
    'admin_assign_driver',
    params: {'p_order_id': orderId, 'p_driver_id': driverId},
  );

  /// Credits a cancelled, paid card order's total back to the customer's
  /// wallet. Server-side the RPC is admin-only and idempotent (paid ->
  /// refunded exactly once). Returns the refunded amount.
  Future<double> refundOrderToWallet(String orderId) async {
    final amount = await supabase.rpc(
      'admin_refund_order_to_wallet',
      params: {'p_order_id': orderId},
    );
    // The refund is committed once the RPC returns; never let a parse issue
    // on the returned amount surface as a failure.
    if (amount is num) return amount.toDouble();
    return num.tryParse('$amount')?.toDouble() ?? 0;
  }

  Future<void> cancelOrder(String orderId, {String? reason}) => supabase.rpc(
    'update_order_status',
    params: {
      'p_order_id': orderId,
      'p_new_status': 'cancelled',
      'p_reason': reason,
    },
  );

  /// Vendor name/logo lookup for orders arriving over realtime (no joins).
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

  /// Fetch all vendor categories.
  Future<List<VendorCategory>> fetchVendorCategories() async {
    final data = await supabase
        .from('vendor_categories')
        .select()
        .order('name', ascending: true);
    return (data as List).map((row) => VendorCategory.fromMap(row)).toList();
  }

  /// Create a new vendor category.
  ///
  /// [parentId] null makes it a top-level kind of shop; set it to file the
  /// category under one. The database refuses a third level.
  Future<void> createVendorCategory({
    required String name,
    String? nameAr,
    String? imageUrl,
    String? parentId,
  }) async {
    await supabase.from('vendor_categories').insert({
      'name': name,
      'name_ar': _blankToNull(nameAr),
      'image_url': imageUrl,
      'parent_id': parentId,
    });
  }

  /// Update an existing vendor category.
  Future<void> updateVendorCategory(
    String id, {
    required String name,
    String? nameAr,
    String? imageUrl,
    String? parentId,
  }) async {
    await supabase
        .from('vendor_categories')
        .update({
          'name': name,
          'name_ar': _blankToNull(nameAr),
          'image_url': imageUrl,
          'parent_id': parentId,
        })
        .eq('id', id);
  }

  /// An empty box means "no translation", not "translated to nothing" — the
  /// UI falls back to the canonical name on null and would show a blank label
  /// on an empty string.
  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  // ===== Per-category promoted stores =====

  /// The admin's picks for [categoryId], best rank first.
  Future<List<({Vendor vendor, int rank})>> fetchCategoryRecommendations(
    String categoryId,
  ) async {
    final rows = await supabase
        .from('category_recommendations')
        .select('rank, vendors!inner(*)')
        .eq('category_id', categoryId)
        .order('rank', ascending: true);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .where((row) => row['vendors'] is Map)
        .map(
          (row) => (
            vendor: Vendor.fromMap(
              (row['vendors'] as Map).cast<String, dynamic>(),
            ),
            rank: ((row['rank'] as num?) ?? 0).toInt(),
          ),
        )
        .toList();
  }

  /// Promotes [vendorId] in [categoryId], or moves it if it is already there.
  Future<void> addCategoryRecommendation({
    required String categoryId,
    required String vendorId,
    int rank = 0,
  }) async {
    await supabase.from('category_recommendations').upsert({
      'category_id': categoryId,
      'vendor_id': vendorId,
      'rank': rank,
    }, onConflict: 'category_id,vendor_id');
  }

  Future<void> removeCategoryRecommendation({
    required String categoryId,
    required String vendorId,
  }) async {
    await supabase
        .from('category_recommendations')
        .delete()
        .eq('category_id', categoryId)
        .eq('vendor_id', vendorId);
  }

  // ===== Bulk price control =====

  /// How many items the given scope would touch. Shown before the button so
  /// the blast radius is a decision rather than a discovery.
  Future<int> priceScopeCount({
    required String scope,
    String? vendorId,
    String? categoryId,
  }) async {
    final count = await supabase.rpc(
      'admin_price_scope_count',
      params: {
        'p_scope': scope,
        'p_vendor_id': vendorId,
        'p_category_id': categoryId,
      },
    );
    return ((count as num?) ?? 0).toInt();
  }

  /// Moves every price in scope by [value] — a percentage of each price when
  /// [mode] is `percent`, a flat amount when it is `fixed`.
  ///
  /// Negative values are how a reduction is expressed. Nothing is allowed below
  /// [minPrice], so a large cut floors rather than going negative. Returns the
  /// number of products and option surcharges actually changed.
  Future<({int products, int options})> adjustPrices({
    required String mode,
    required double value,
    required String scope,
    String? vendorId,
    String? categoryId,
    double minPrice = 1,
  }) async {
    final result = await supabase.rpc(
      'admin_adjust_prices',
      params: {
        'p_mode': mode,
        'p_value': value,
        'p_scope': scope,
        'p_vendor_id': vendorId,
        'p_category_id': categoryId,
        'p_min_price': minPrice,
      },
    );
    final map = (result as Map).cast<String, dynamic>();
    return (
      products: ((map['products'] as num?) ?? 0).toInt(),
      options: ((map['options'] as num?) ?? 0).toInt(),
    );
  }

  /// Past runs, newest first — the record that makes a mistaken run reversible.
  Future<List<Map<String, dynamic>>> fetchPriceAdjustments({
    int limit = 20,
  }) async {
    final rows = await supabase
        .from('price_adjustments')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).cast<Map<String, dynamic>>();
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
    await supabase.storage
        .from('vendor-assets')
        .uploadBinary(path, Uint8List.fromList(bytes));
    return supabase.storage.from('vendor-assets').getPublicUrl(path);
  }

  /// Ad artwork. Shares the public product-images bucket, under `ads/`, so
  /// there is no second public bucket to keep policies in step with.
  Future<String> uploadAdImage(Uint8List bytes, String filename) async {
    final path = 'ads/${DateTime.now().microsecondsSinceEpoch}-$filename';
    await supabase.storage.from('product-images').uploadBinary(path, bytes);
    return supabase.storage.from('product-images').getPublicUrl(path);
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
    final data = await supabase.rpc(
      'admin_vendor_sales_report',
      params: {
        'p_start': startDate?.toUtc().toIso8601String(),
        'p_end': endDate?.toUtc().toIso8601String(),
      },
    );
    return (data as List)
        .map(
          (e) => VendorReportItem.fromMap((e as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  /// Platform-level settlement figures for the period: what came in, what is
  /// owed out, and how much of it drivers are still holding as cash.
  Future<PlatformReport> fetchPlatformReport({
    DateTime? startDate,
    DateTime? endDate,
    double driverSharePercent = 90,
  }) async {
    final data = await supabase.rpc(
      'admin_platform_report',
      params: {
        'p_start': startDate?.toUtc().toIso8601String(),
        'p_end': endDate?.toUtc().toIso8601String(),
        'p_driver_share': driverSharePercent,
      },
    );
    return PlatformReport.fromMap((data as Map).cast<String, dynamic>());
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
    final data = await supabase.rpc(
      'admin_driver_payout_report',
      params: {
        'p_start': startDate?.toUtc().toIso8601String(),
        'p_end': endDate?.toUtc().toIso8601String(),
        'p_driver_share': driverSharePercent,
      },
    );
    return (data as List)
        .map(
          (e) => DriverReportItem.fromMap((e as Map).cast<String, dynamic>()),
        )
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
    final path =
        '$driverId/$docType-'
        '${DateTime.now().millisecondsSinceEpoch}.$extension';
    await supabase.storage
        .from(_driverDocsBucket)
        .uploadBinary(
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

/// One account row in the admin's user list.
class AdminUser {
  const AdminUser({
    required this.id,
    required this.name,
    required this.role,
    required this.isBlocked,
    required this.isDeleted,
    this.phone,
    this.blockedReason,
    this.createdAt,
  });

  final String id;
  final String name;
  final String role;
  final bool isBlocked;

  /// Closed accounts keep their row so past orders still resolve a customer.
  final bool isDeleted;
  final String? phone;
  final String? blockedReason;

  /// When the account was opened. Null only for rows written before the
  /// column existed.
  final DateTime? createdAt;

  /// Admins are exempt from both levers, matching the server-side guards.
  bool get isAdmin => role == 'admin';

  factory AdminUser.fromMap(Map<String, dynamic> map) => AdminUser(
    id: map['id'] as String,
    name: (map['full_name'] as String?)?.trim().isNotEmpty == true
        ? map['full_name'] as String
        : 'User',
    role: (map['role'] as String?) ?? 'customer',
    isBlocked: (map['is_blocked'] as bool?) ?? false,
    isDeleted: map['deleted_at'] != null,
    phone: map['phone'] as String?,
    blockedReason: map['blocked_reason'] as String?,
    createdAt: DateTime.tryParse(
      (map['created_at'] as String?) ?? '',
    )?.toLocal(),
  );
}

/// Headline settlement figures for the whole platform over a period.
class PlatformReport {
  const PlatformReport({
    this.deliveredOrders = 0,
    this.cancelledOrders = 0,
    this.grossRevenue = 0,
    this.itemSales = 0,
    this.deliveryFees = 0,
    this.discounts = 0,
    this.vendorDiscounts = 0,
    this.platformDiscounts = 0,
    this.commission = 0,
    this.deliveryMargin = 0,
    this.driverCost = 0,
    this.driverTips = 0,
    this.vendorPayout = 0,
    this.cashCollected = 0,
    this.cardCollected = 0,
    this.averageOrder = 0,
    this.subscriptionFeesMonthly = 0,
    this.subscriptionStores = 0,
    this.driverShare = 90,
  });

  final int deliveredOrders;
  final int cancelledOrders;

  /// Everything customers paid on delivered orders.
  final double grossRevenue;
  final double itemSales;
  final double deliveryFees;

  /// Every discount given, however it was funded.
  final double discounts;

  /// The share of [discounts] carried by the stores — a coupon scoped to one
  /// store is that store's own marketing spend.
  final double vendorDiscounts;

  /// The share of [discounts] the platform funded, which is the only part that
  /// costs it anything.
  final double platformDiscounts;

  /// The platform's cut of item sales, at each store's own model and rate.
  /// Subscription stores contribute nothing here — they pay a flat fee.
  final double commission;

  /// The part of the delivery fee the platform keeps once the driver is paid.
  final double deliveryMargin;

  /// Delivery-fee share plus tips owed to drivers.
  final double driverCost;

  /// Tips, which pass straight through: the customer pays them on top of
  /// `total` and the driver keeps all of them.
  final double driverTips;

  /// What the stores are owed, after their own discounts and commission.
  final double vendorPayout;

  /// Cash the drivers physically hold and still owe the platform.
  final double cashCollected;
  final double cardCollected;
  final double averageOrder;

  /// Billed monthly rather than per order, so it is reported beside the order
  /// P&L rather than inside it: prorating a monthly fee across an arbitrary
  /// date range would put an invented number in a settlement.
  final double subscriptionFeesMonthly;
  final int subscriptionStores;

  /// The percentage of the delivery fee the driver keeps.
  final double driverShare;

  /// What the platform actually keeps on the orders in this period.
  ///
  /// Commission plus its slice of the delivery fee, less the discounts it
  /// funded itself. Tips are absent on purpose: the platform never earns them,
  /// so booking them as a cost understated this by the whole tip. Subscription
  /// fees are absent too — see [subscriptionFeesMonthly].
  double get netMargin => commission + deliveryMargin - platformDiscounts;

  factory PlatformReport.fromMap(Map<String, dynamic> map) => PlatformReport(
    deliveredOrders: _money(map['delivered_orders']).toInt(),
    cancelledOrders: _money(map['cancelled_orders']).toInt(),
    grossRevenue: _money(map['gross_revenue']),
    itemSales: _money(map['item_sales']),
    deliveryFees: _money(map['delivery_fees']),
    discounts: _money(map['discounts']),
    vendorDiscounts: _money(map['vendor_discounts']),
    platformDiscounts: _money(map['platform_discounts']),
    commission: _money(map['commission']),
    deliveryMargin: _money(map['delivery_margin']),
    driverCost: _money(map['driver_cost']),
    driverTips: _money(map['driver_tips']),
    vendorPayout: _money(map['vendor_payout']),
    cashCollected: _money(map['cash_collected']),
    cardCollected: _money(map['card_collected']),
    averageOrder: _money(map['average_order']),
    subscriptionFeesMonthly: _money(map['subscription_fees_monthly']),
    subscriptionStores: _money(map['subscription_stores']).toInt(),
    driverShare: map['driver_share'] == null ? 90 : _money(map['driver_share']),
  );
}

class VendorReportItem {
  const VendorReportItem({
    required this.vendorId,
    required this.vendorName,
    required this.totalOrders,
    required this.grossSales,
    required this.vendorDiscounts,
    required this.billingModel,
    required this.commissionRate,
    required this.subscriptionFee,
    required this.commissionFee,
    required this.netPayout,
  });

  final String vendorId;
  final String vendorName;
  final int totalOrders;
  final double grossSales;

  /// Discounts funded by this store's own coupons, deducted from its payout.
  final double vendorDiscounts;

  /// `commission` or `subscription`. Decides whether [commissionRate] or
  /// [subscriptionFee] is the one that applies.
  final String billingModel;
  bool get isSubscription => billingModel == 'subscription';

  /// Platform cut as a percentage, e.g. `10` for 10%. Reported as zero on a
  /// subscription store so it always matches [commissionFee].
  final double commissionRate;

  /// The flat monthly fee, on the subscription plan.
  final double subscriptionFee;

  /// Per-order commission for the period. Always zero on subscription.
  final double commissionFee;
  final double netPayout;

  factory VendorReportItem.fromMap(Map<String, dynamic> map) =>
      VendorReportItem(
        vendorId: map['vendor_id'] as String,
        vendorName: (map['vendor_name'] as String?) ?? 'Store',
        totalOrders: _money(map['total_orders']).toInt(),
        grossSales: _money(map['gross_sales']),
        vendorDiscounts: _money(map['vendor_discounts']),
        billingModel: (map['billing_model'] as String?) ?? 'commission',
        commissionRate: _money(map['commission_rate']),
        subscriptionFee: _money(map['subscription_fee']),
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
    required this.deliveryFeesCollected,
    required this.driverFeeShare,
    required this.platformFeeShare,
    required this.tipsEarned,
    required this.netDriverPayout,
  });

  final String driverId;
  final String driverName;
  final int deliveredOrders;

  /// The whole delivery fee the customers paid, before it is split.
  final double deliveryFeesCollected;

  /// The driver's cut of [deliveryFeesCollected].
  final double driverFeeShare;

  /// What the platform keeps from the same fees. The report used to show only
  /// the driver's side, so the platform's slice appeared nowhere.
  final double platformFeeShare;

  /// Passed through in full — the platform takes no cut of a tip.
  final double tipsEarned;

  final double netDriverPayout;

  factory DriverReportItem.fromMap(Map<String, dynamic> map) =>
      DriverReportItem(
        driverId: map['driver_id'] as String,
        driverName: (map['driver_name'] as String?) ?? 'Driver',
        deliveredOrders: _money(map['delivered_orders']).toInt(),
        deliveryFeesCollected: _money(map['delivery_fees']),
        driverFeeShare: _money(map['driver_fee_share']),
        platformFeeShare: _money(map['platform_fee_share']),
        tipsEarned: _money(map['tips']),
        netDriverPayout: _money(map['net_payout']),
      );
}
