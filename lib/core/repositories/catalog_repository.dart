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

  Future<List<Product>> fetchProductsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final data = await supabase
        .from('products')
        .select('*, product_option_groups(*, product_options(*))')
        .inFilter('id', ids);
    return data.map(Product.fromMap).toList();
  }
}
