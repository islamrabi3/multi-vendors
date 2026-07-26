
import '../models/coupon.dart';
import '../supabase_client.dart';

/// Admin CRUD for promo codes (the `coupons` table). Writes are gated by the
/// `coupons_admin_all` RLS policy (requires `is_admin()`).
class CouponsRepository {
  Future<List<Coupon>> fetchAll() async {
    final data = await supabase
        .from('coupons')
        .select()
        .order('created_at', ascending: false);
    return (data as List).map((e) => Coupon.fromMap(e)).toList();
  }

  Future<void> create({
    required String code,
    required String discountType,
    required double value,
    double minOrderAmount = 0,
    double? maxDiscount,
    int? usageLimit,
    String? vendorId,
  }) async {
    await supabase.from('coupons').insert({
      'code': code.toUpperCase(),
      'discount_type': discountType,
      'value': value,
      'min_order_amount': minOrderAmount,
      'max_discount': ?maxDiscount,
      'usage_limit': ?usageLimit,
      'vendor_id': ?vendorId,
      'is_active': true,
    });
  }

  Future<void> setActive(String id, bool active) async {
    await supabase.from('coupons').update({'is_active': active}).eq('id', id);
  }

  Future<void> delete(String id) async {
    await supabase.from('coupons').delete().eq('id', id);
  }
}
