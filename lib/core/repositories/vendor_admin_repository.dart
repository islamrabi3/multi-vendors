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
        .select()
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

  Future<Map<String, dynamic>> fetchAnalytics(String vendorId) async {
    final orders = await supabase
        .from('orders')
        .select('id, total, created_at, status')
        .eq('vendor_id', vendorId)
        .eq('status', 'delivered');

    double totalRevenue = 0.0;
    int totalDelivered = (orders as List).length;

    for (final row in orders) {
      totalRevenue += ((row['total'] as num?) ?? 0).toDouble();
    }

    return {
      'total_revenue': totalRevenue,
      'total_delivered': totalDelivered,
    };
  }
}

