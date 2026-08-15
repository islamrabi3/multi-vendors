import 'dart:typed_data';

import '../models/order.dart';
import '../models/product.dart';
import '../models/vendor.dart';
import '../supabase_client.dart';

/// Menu management and store settings for the vendor role.
class VendorAdminRepository {
  static const _finishedStatuses = ['delivered', 'cancelled', 'rejected'];

  /// One page of the store's finished orders, newest first. The dashboard's
  /// live tabs come from a realtime stream (`OrderRepository`); this is the
  /// history behind them, which grows forever and must be paged.
  Future<List<AppOrder>> fetchVendorOrdersPage({
    required String vendorId,
    required int limit,
    required int offset,
  }) async {
    final data = await supabase
        .from('orders')
        .select('*, vendors(name, logo_url)')
        .eq('vendor_id', vendorId)
        .inFilter('status', _finishedStatuses)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List)
        .map((e) => AppOrder.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<Vendor> updateVendor(String vendorId, Map<String, dynamic> values) async {
    final data = await supabase
        .from('vendors')
        .update(values)
        .eq('id', vendorId)
        .select('*, vendor_schedules(*)')
        .single();
    return Vendor.fromMap(data);
  }

  /// [nameAr] is optional: sections without a translation fall back to [name]
  /// in the Arabic UI, and a blank value is stored as null so the fallback can
  /// tell "not translated" from "translated to empty".
  Future<ProductCategory> saveCategory({
    required String vendorId,
    required String name,
    String? nameAr,
    String? id,
  }) async {
    final values = {
      'name': name,
      'name_ar': (nameAr?.trim().isEmpty ?? true) ? null : nameAr!.trim(),
    };
    final query = id == null
        ? supabase
            .from('product_categories')
            .insert({'vendor_id': vendorId, ...values})
        : supabase.from('product_categories').update(values).eq('id', id);
    final data = await query.select().single();
    return ProductCategory.fromMap(data);
  }

  /// Deleting a section does not delete its items: `products.category_id` is
  /// `on delete set null`, so they fall into the uncategorised bucket and stay
  /// on sale. The vendor is told as much before confirming.
  Future<void> deleteCategory(String id) =>
      supabase.from('product_categories').delete().eq('id', id);

  /// Renumbers whole lists rather than moving one row: two rows swapping
  /// places is two writes that must agree, and a client that sends only the
  /// moved row leaves the rest of the menu holding stale positions.
  Future<void> reorderCategories(String vendorId, List<String> ids) =>
      supabase.rpc('vendor_reorder_categories',
          params: {'p_vendor_id': vendorId, 'p_ids': ids});

  Future<void> reorderProducts(String vendorId, List<String> ids) =>
      supabase.rpc('vendor_reorder_products',
          params: {'p_vendor_id': vendorId, 'p_ids': ids});

  /// Copies an item with its option groups and options. The copy arrives
  /// unavailable, directly after its source.
  Future<String> duplicateProduct(String productId) async {
    final id = await supabase
        .rpc('vendor_duplicate_product', params: {'p_product_id': productId});
    return id as String;
  }

  /// Marks a whole section available or sold out. [categoryId] null means the
  /// entire menu. Returns how many items actually changed.
  Future<int> setSectionAvailability({
    required String vendorId,
    required String? categoryId,
    required bool available,
  }) async {
    final count = await supabase.rpc('vendor_set_section_availability', params: {
      'p_vendor_id': vendorId,
      'p_category_id': categoryId,
      'p_available': available,
    });
    return (count as num?)?.toInt() ?? 0;
  }

  /// Moves an item between sections without opening the full editor.
  Future<void> setProductCategory(String productId, String? categoryId) =>
      supabase
          .from('products')
          .update({'category_id': categoryId}).eq('id', productId);

  /// Sets a product's stock to an exact count, or moves it by a delta.
  ///
  /// Goes through the RPC rather than an update, because every movement has to
  /// leave a row in `stock_movements` saying why — a stock number nobody can
  /// explain is a stock number nobody trusts.
  Future<int> adjustStock({
    required String productId,
    int? delta,
    int? setTo,
    String reason = 'correction',
    String? note,
  }) async {
    final result = await supabase.rpc(
      'vendor_adjust_stock',
      params: {
        'p_product_id': productId,
        'p_delta': delta,
        'p_set_to': setTo,
        'p_reason': reason,
        'p_note': note,
      },
    );
    return (result as num?)?.toInt() ?? 0;
  }

  /// Products that are out, or close to it.
  Future<List<Map<String, dynamic>>> stockAlerts(String vendorId) async {
    final rows = await supabase.rpc(
      'vendor_stock_alerts',
      params: {'p_vendor_id': vendorId},
    );
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<Product> saveProduct(Map<String, dynamic> values, {String? id}) async {
    final query = id == null
        ? supabase.from('products').insert(values)
        : supabase.from('products').update(values).eq('id', id);
    final data = await query.select().single();
    return Product.fromMap(data);
  }

  Future<void> deleteProduct(String id) =>
      supabase.from('products').delete().eq('id', id);

  Future<void> setProductAvailability(String id, bool isAvailable) =>
      supabase.from('products').update({'is_available': isAvailable}).eq('id', id);

  Future<ProductOptionGroup> saveOptionGroup({
    required String productId,
    required String name,
    required int minSelect,
    required int maxSelect,
  }) async {
    final data = await supabase
        .from('product_option_groups')
        .insert({
          'product_id': productId,
          'name': name,
          'min_select': minSelect,
          'max_select': maxSelect,
        })
        .select()
        .single();
    return ProductOptionGroup.fromMap(data);
  }

  Future<void> deleteOptionGroup(String id) =>
      supabase.from('product_option_groups').delete().eq('id', id);

  Future<ProductOption> saveOption({
    required String groupId,
    required String name,
    required double priceDelta,
  }) async {
    final data = await supabase
        .from('product_options')
        .insert({'group_id': groupId, 'name': name, 'price_delta': priceDelta})
        .select()
        .single();
    return ProductOption.fromMap(data);
  }

  Future<void> deleteOption(String id) =>
      supabase.from('product_options').delete().eq('id', id);

  /// Uploads an image and returns its public URL.
  Future<String> uploadImage({
    required String bucket,
    required String path,
    required Uint8List bytes,
  }) async {
    await supabase.storage.from(bucket).uploadBinary(path, bytes);
    return supabase.storage.from(bucket).getPublicUrl(path);
  }

  Future<Vendor> toggleBusyMode(String vendorId, bool isBusy, {int extraPrepMinutes = 15}) async {
    return updateVendor(vendorId, {
      'is_busy': isBusy,
      'extra_prep_minutes': isBusy ? extraPrepMinutes : 0,
    });
  }

  Future<List<Map<String, dynamic>>> fetchSchedules(String vendorId) async {
    final data = await supabase
        .from('vendor_schedules')
        .select()
        .eq('vendor_id', vendorId)
        .order('day_of_week', ascending: true);
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// One row per (vendor, weekday).
  ///
  /// `onConflict` is required: the row is identified by the unique
  /// (vendor_id, day_of_week) pair, not by `id`, which is never sent. Without
  /// it the upsert conflicts on the primary key instead — never matches, and
  /// so becomes a plain insert that trips the unique index the second time a
  /// day is edited.
  Future<void> updateSchedule(String vendorId, int dayOfWeek, String openTime,
      String closeTime, bool isClosed) async {
    await supabase.from('vendor_schedules').upsert({
      'vendor_id': vendorId,
      'day_of_week': dayOfWeek,
      'open_time': openTime,
      'close_time': closeTime,
      'is_closed': isClosed,
    }, onConflict: 'vendor_id,day_of_week');
  }

  /// What this store sold and what it is owed for the period.
  ///
  /// Server-side and settlement-accurate: the old version pulled every
  /// delivered order the store had ever had and summed `orders.total`, which
  /// includes the delivery fee the store never receives and ignores commission
  /// entirely. The RPC shares `order_commission` with the admin's report, so
  /// the two views of the same store cannot drift apart.
  Future<VendorSettlement> fetchSettlement(
    String vendorId, {
    DateTime? start,
    DateTime? end,
  }) async {
    final data = await supabase.rpc(
      'vendor_settlement',
      params: {
        'p_vendor_id': vendorId,
        'p_start': start?.toUtc().toIso8601String(),
        'p_end': end?.toUtc().toIso8601String(),
      },
    );
    return VendorSettlement.fromMap((data as Map).cast<String, dynamic>());
  }
}


/// One store's commercial position for a period.
class VendorSettlement {
  const VendorSettlement({
    this.deliveredOrders = 0,
    this.itemSales = 0,
    this.vendorDiscounts = 0,
    this.deliveryFeesCollected = 0,
    this.averageOrder = 0,
    this.billingModel = 'commission',
    this.commissionRate = 0,
    this.subscriptionFee = 0,
    this.commission = 0,
    this.netPayout = 0,
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.avgPrepMinutes = 0,
  });

  final int deliveredOrders;

  /// What the store sold, before anything is taken off. Not the order total —
  /// the delivery fee in there was never the store's money.
  final double itemSales;

  /// Discounts from this store's own coupons, which it funds.
  final double vendorDiscounts;

  /// Collected from the customer and passed on to the driver and platform.
  /// Shown only so the store can reconcile against what the customer paid.
  final double deliveryFeesCollected;

  final double averageOrder;

  /// `commission` or `subscription`.
  final String billingModel;
  bool get isSubscription => billingModel == 'subscription';

  /// Zero on the subscription plan, so it always matches [commission].
  final double commissionRate;
  final double subscriptionFee;

  /// The platform's per-order cut. Always zero on the subscription plan.
  final double commission;

  /// What the store is actually owed.
  final double netPayout;

  final double ratingAvg;
  final int ratingCount;
  final int avgPrepMinutes;

  factory VendorSettlement.fromMap(Map<String, dynamic> map) =>
      VendorSettlement(
        deliveredOrders: _num(map['delivered_orders']).toInt(),
        itemSales: _num(map['item_sales']),
        vendorDiscounts: _num(map['vendor_discounts']),
        deliveryFeesCollected: _num(map['delivery_fees_collected']),
        averageOrder: _num(map['average_order']),
        billingModel: (map['billing_model'] as String?) ?? 'commission',
        commissionRate: _num(map['commission_rate']),
        subscriptionFee: _num(map['subscription_fee']),
        commission: _num(map['commission']),
        netPayout: _num(map['net_payout']),
        ratingAvg: _num(map['rating_avg']),
        ratingCount: _num(map['rating_count']).toInt(),
        avgPrepMinutes: _num(map['avg_prep_minutes']).toInt(),
      );
}

/// Postgres `numeric` arrives as a number over PostgREST but as a string from
/// some transports, so neither is assumed.
double _num(Object? value) => switch (value) {
  num n => n.toDouble(),
  String s => double.tryParse(s) ?? 0,
  _ => 0,
};
