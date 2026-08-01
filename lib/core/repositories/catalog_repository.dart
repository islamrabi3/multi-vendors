import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart'
    show
        PostgresChangeEvent,
        PostgresChangeFilter,
        PostgresChangeFilterType,
        PostgresChangePayload;

import '../models/banner_item.dart';
import '../models/product.dart';
import '../models/vendor.dart';
import '../supabase_client.dart';

class CatalogRepository {
  Future<List<BannerItem>> fetchBanners() async {
    final data = await supabase
        .from('banners')
        .select()
        .eq('is_active', true)
        .order('sort_order', ascending: true);
    return data.map(BannerItem.fromMap).toList();
  }

  Future<List<VendorCategory>> fetchVendorCategories() async {
    final data = await supabase
        .from('vendor_categories')
        .select()
        .eq('is_active', true)
        .order('sort_order', ascending: true);
    return data.map(VendorCategory.fromMap).toList();
  }

  /// Stream of active vendor categories for real-time customer updates.
  Stream<List<VendorCategory>> vendorCategoriesStream() => supabase
      .from('vendor_categories')
      .stream(primaryKey: ['id'])
      .eq('is_active', true)
      .order('sort_order', ascending: true)
      .map((rows) => rows.map(VendorCategory.fromMap).toList());

  Future<List<Vendor>> fetchVendors({String? categoryId, String? search}) async {
    var query = supabase.from('vendors').select().eq('is_active', true);
    if (categoryId != null) query = query.eq('category_id', categoryId);
    if (search != null && search.trim().isNotEmpty) {
      query = query.ilike('name', '%${search.trim()}%');
    }
    final data = await query
        .order('is_open', ascending: false)
        .order('rating_avg', ascending: false);
    return data.map(Vendor.fromMap).toList();
  }

  /// Stores matching a query by their own name *or* by something on their
  /// menu, with up to three matching item names each.
  ///
  /// The old search was an ILIKE on the store name alone, so "burger" found
  /// the shop called Burger Lab and missed every restaurant that sells one.
  /// Two round trips — the RPC returns ids and the rows come from the table —
  /// because a function cannot return `vendors` rows without duplicating the
  /// whole shape here and drifting from it later.
  Future<({List<Vendor> vendors, Map<String, List<String>> matches})>
      searchVendors({
    required String query,
    String? categoryId,
  }) async {
    final rows = await supabase.rpc('search_vendors', params: {
      'p_query': query,
      'p_category_id': categoryId,
    }) as List;
    if (rows.isEmpty) return (vendors: <Vendor>[], matches: const <String, List<String>>{});

    final order = <String>[];
    final matches = <String, List<String>>{};
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final id = row['id'] as String;
      order.add(id);
      final matched = (row['matched_products'] as List?)?.cast<String>();
      if (matched != null && matched.isNotEmpty) matches[id] = matched;
    }

    final data =
        await supabase.from('vendors').select().inFilter('id', order);
    final byId = {
      for (final row in (data as List).cast<Map<String, dynamic>>())
        row['id'] as String: Vendor.fromMap(row),
    };
    // The RPC did the ranking; `in` does not preserve it.
    return (
      vendors: [for (final id in order) if (byId[id] != null) byId[id]!],
      matches: matches,
    );
  }

  /// Individual dishes across every open store, for the "items" half of a
  /// search result.
  Future<List<ProductHit>> searchProducts(String query) async {
    if (query.trim().isEmpty) return const [];
    final rows =
        await supabase.rpc('search_products', params: {'p_query': query})
            as List;
    return rows
        .cast<Map<String, dynamic>>()
        .map(ProductHit.fromMap)
        .toList();
  }

  Future<Vendor> fetchVendor(String vendorId) async {
    final data =
        await supabase.from('vendors').select().eq('id', vendorId).single();
    return Vendor.fromMap(data);
  }

  Future<List<ProductCategory>> fetchMenuCategories(String vendorId) async {
    final data = await supabase
        .from('product_categories')
        .select()
        .eq('vendor_id', vendorId)
        .order('sort_order', ascending: true);
    return data.map(ProductCategory.fromMap).toList();
  }

  Future<List<Product>> fetchProducts(
    String vendorId, {
    bool includeUnavailable = false,
  }) async {
    var query = supabase
        .from('products')
        .select('*, product_option_groups(*, product_options(*))')
        .eq('vendor_id', vendorId);
    if (!includeUnavailable) query = query.eq('is_available', true);
    final data = await query.order('sort_order', ascending: true);
    return data.map(Product.fromMap).toList();
  }

  /// Fires whenever anything about one store's catalogue changes: the store
  /// row itself, its sections, or its items.
  ///
  /// The payload is deliberately dropped. A product carries its option groups
  /// through a join that a row-level change event cannot express, so this is a
  /// signal to re-read rather than a source of data. Before it existed, a
  /// customer sitting on a store page held whatever the menu looked like when
  /// they opened it — an item the vendor had just marked sold out still went
  /// into the cart and only failed at checkout.
  Stream<void> catalogChanges(String vendorId) {
    final channel = supabase.channel('catalog:$vendorId');
    final controller = StreamController<void>.broadcast();

    void onChange(PostgresChangePayload _) => controller.add(null);

    PostgresChangeFilter equals(String column, String value) =>
        PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: column,
          value: value,
        );

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'products',
          filter: equals('vendor_id', vendorId),
          callback: onChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'product_categories',
          filter: equals('vendor_id', vendorId),
          callback: onChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'vendors',
          filter: equals('id', vendorId),
          callback: onChange,
        )
        .subscribe();

    controller.onCancel = () => supabase.removeChannel(channel);
    return controller.stream;
  }

  Future<List<Product>> fetchProductsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final data = await supabase
        .from('products')
        .select('*, product_option_groups(*, product_options(*))')
        .inFilter('id', ids);
    return data.map(Product.fromMap).toList();
  }
}
