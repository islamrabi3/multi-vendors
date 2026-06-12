import 'dart:typed_data';

import '../models/product.dart';
import '../models/vendor.dart';
import '../supabase_client.dart';

/// Menu management and store settings for the vendor role.
class VendorAdminRepository {
  Future<Vendor> updateVendor(String vendorId, Map<String, dynamic> values) async {
    final data = await supabase
        .from('vendors')
        .update(values)
        .eq('id', vendorId)
        .select()
        .single();
    return Vendor.fromMap(data);
  }

  Future<ProductCategory> saveCategory({
    required String vendorId,
    required String name,
    String? id,
  }) async {
    final query = id == null
        ? supabase
            .from('product_categories')
            .insert({'vendor_id': vendorId, 'name': name})
        : supabase.from('product_categories').update({'name': name}).eq('id', id);
    final data = await query.select().single();
    return ProductCategory.fromMap(data);
  }

  Future<void> deleteCategory(String id) =>
      supabase.from('product_categories').delete().eq('id', id);

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
}
