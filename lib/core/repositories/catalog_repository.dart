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
  /// The home offers strip.
  ///
  /// Goes through `active_ads` rather than reading the table: that applies the
  /// campaign schedule, the audience rule, and — the one that matters most —
  /// drops any ad pointing at a store that is closed or suspended. Sending
  /// customers to a shut restaurant is worse than showing nothing.
  Future<List<BannerItem>> fetchBanners({bool isNewCustomer = false}) async {
    final data = await supabase.rpc(
      'active_ads',
      params: {
        'p_placement': 'home_carousel',
        'p_is_new_customer': isNewCustomer,
      },
    );
    return (data as List)
        .map((e) => BannerItem.fromMap(e as Map<String, dynamic>))
        .toList();
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
  ///
  /// Both levels of the tree arrive in one stream: the home page keeps the
  /// top-level entries and a category page keeps that parent's children, and
  /// neither needs a second subscription to stay live.
  Stream<List<VendorCategory>> vendorCategoriesStream() => supabase
      .from('vendor_categories')
      .stream(primaryKey: ['id'])
      .eq('is_active', true)
      .order('sort_order', ascending: true)
      .map((rows) => rows.map(VendorCategory.fromMap).toList());

  /// Every store's row joined to its opening hours.
  ///
  /// The hours ride along because "closed" is now a question of the timetable
  /// as well as the owner's switch, and a card that had to ask per store would
  /// be one round trip per row. See [Vendor.isOpenNow].
  static const _vendorSelect = '*, vendor_schedules(*)';

  Future<List<Vendor>> fetchVendors({
    String? categoryId,
    String? search,
  }) async {
    var query = supabase
        .from('vendors')
        .select(_vendorSelect)
        .eq('is_active', true);
    if (categoryId != null) query = query.eq('category_id', categoryId);
    if (search != null && search.trim().isNotEmpty) {
      query = query.ilike('name', '%${search.trim()}%');
    }
    final data = await query
        .order('is_open', ascending: false)
        .order('rating_avg', ascending: false);
    return data.map(Vendor.fromMap).toList();
  }

  /// Every store filed under [categoryId], following the tree: a top-level
  /// category returns the stores of all its children too, which is what
  /// tapping "Food" has to mean.
  ///
  /// The RPC ranks; the rows then come from the table so the opening hours can
  /// be joined in — a function returning `setof vendors` cannot carry them.
  Future<List<Vendor>> fetchVendorsInCategory(String categoryId) async {
    final rows =
        await supabase.rpc(
              'vendors_in_category',
              params: {'p_category_id': categoryId},
            )
            as List;
    if (rows.isEmpty) return const [];

    final order = [
      for (final row in rows.cast<Map<String, dynamic>>()) row['id'] as String,
    ];
    final data = await supabase
        .from('vendors')
        .select(_vendorSelect)
        .inFilter('id', order);
    final byId = {
      for (final row in (data as List).cast<Map<String, dynamic>>())
        row['id'] as String: Vendor.fromMap(row),
    };
    // The RPC did the ranking; `in` does not preserve it.
    return [
      for (final id in order)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// The admin's promoted stores for one category, best rank first.
  ///
  /// Separate from `vendors.is_recommended`, which is the home page's single
  /// rail: "our pick for Pizza" is a different answer from "our pick overall".
  Future<List<Vendor>> fetchCategoryRecommendations(String categoryId) async {
    final rows = await supabase
        .from('category_recommendations')
        .select('rank, vendors!inner($_vendorSelect)')
        .eq('category_id', categoryId)
        .order('rank', ascending: true);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map((row) => row['vendors'])
        .whereType<Map<String, dynamic>>()
        .map(Vendor.fromMap)
        .where((vendor) => vendor.isActive && vendor.isApproved)
        .toList();
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
  searchVendors({required String query, String? categoryId}) async {
    final rows =
        await supabase.rpc(
              'search_vendors',
              params: {'p_query': query, 'p_category_id': categoryId},
            )
            as List;
    if (rows.isEmpty) {
      return (vendors: <Vendor>[], matches: const <String, List<String>>{});
    }

    final order = <String>[];
    final matches = <String, List<String>>{};
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final id = row['id'] as String;
      order.add(id);
      final matched = (row['matched_products'] as List?)?.cast<String>();
      if (matched != null && matched.isNotEmpty) matches[id] = matched;
    }

    final data = await supabase
        .from('vendors')
        .select(_vendorSelect)
        .inFilter('id', order);
    final byId = {
      for (final row in (data as List).cast<Map<String, dynamic>>())
        row['id'] as String: Vendor.fromMap(row),
    };
    // The RPC did the ranking; `in` does not preserve it.
    return (
      vendors: [
        for (final id in order)
          if (byId[id] != null) byId[id]!,
      ],
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
    return rows.cast<Map<String, dynamic>>().map(ProductHit.fromMap).toList();
  }

  Future<Vendor> fetchVendor(String vendorId) async {
    final data = await supabase
        .from('vendors')
        .select(_vendorSelect)
        .eq('id', vendorId)
        .single();
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

  /// "Goes well with", for the item sheet.
  ///
  /// Ranked server-side by what people actually order together, falling back
  /// to the same menu section so a store with no order history still has
  /// something to show. Full products are then loaded by id, because tapping a
  /// suggestion has to open its own sheet — which needs its option groups.
  Future<List<Product>> relatedProducts(
    String productId, {
    int limit = 6,
  }) async {
    final rows =
        await supabase.rpc(
              'related_products',
              params: {'p_product_id': productId, 'p_limit': limit},
            )
            as List;
    if (rows.isEmpty) return const [];

    final order = [
      for (final row in rows.cast<Map<String, dynamic>>()) row['id'] as String,
    ];
    final products = await fetchProductsByIds(order);
    final byId = {for (final product in products) product.id: product};
    // The RPC did the ranking; `in` does not preserve it.
    return [
      for (final id in order)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// Suggestions for the cart, ranked against everything already in it and
  /// never repeating what is there.
  ///
  /// Like [relatedProducts], the ids are then loaded in full: a suggestion that
  /// is tapped has to open its own sheet, which needs its option groups.
  Future<List<Product>> cartSuggestions({
    required String vendorId,
    required List<String> inCart,
    int limit = 8,
  }) async {
    final rows =
        await supabase.rpc(
              'cart_suggestions',
              params: {
                'p_vendor_id': vendorId,
                'p_exclude': inCart,
                'p_limit': limit,
              },
            )
            as List;
    if (rows.isEmpty) return const [];

    final order = [
      for (final row in rows.cast<Map<String, dynamic>>()) row['id'] as String,
    ];
    final products = await fetchProductsByIds(order);
    final byId = {for (final product in products) product.id: product};
    // The RPC did the ranking; `in` does not preserve it.
    return [
      for (final id in order)
        if (byId[id] != null) byId[id]!,
    ];
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
