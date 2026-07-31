import '../models/banner_item.dart';
import '../supabase_client.dart';

/// Admin CRUD for promotional offers (the `banners` table).
/// Writes are gated server-side by the `banners_admin_all` RLS policy
/// (requires `is_admin()`), so non-admins simply get a permission error.
class OffersRepository {
  /// All offers including inactive — admins only (RLS).
  Future<List<BannerItem>> fetchAll() async {
    final data = await supabase
        .from('banners')
        .select()
        .order('sort_order', ascending: true);
    return (data as List).map((e) => BannerItem.fromMap(e)).toList();
  }

  Future<void> create({
    required String imageUrl,
    required BannerType type,
    String? title,
    String? subtitle,
    String? code,
    String? vendorId,
    int sortOrder = 0,
  }) async {
    await supabase.from('banners').insert({
      'image_url': imageUrl,
      'banner_type': type.name,
      if (title != null && title.isNotEmpty) 'title': title,
      if (subtitle != null && subtitle.isNotEmpty) 'subtitle': subtitle,
      if (code != null && code.isNotEmpty) 'code': code,
      if (vendorId != null && vendorId.isNotEmpty) 'vendor_id': vendorId,
      'sort_order': sortOrder,
      'is_active': true,
    });
  }

  Future<void> setActive(String id, bool active) async {
    await supabase.from('banners').update({'is_active': active}).eq('id', id);
  }

  Future<void> delete(String id) async {
    await supabase.from('banners').delete().eq('id', id);
  }
}
