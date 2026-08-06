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

  /// Creates a campaign.
  ///
  /// [perUserLimit] is the one that stops a code being spent repeatedly by the
  /// same customer; null means unlimited and is almost never what an admin
  /// wants, so the form defaults it to 1.
  Future<void> create({
    required String code,
    required String discountType,
    required double value,
    double minOrderAmount = 0,
    double? maxDiscount,
    int? usageLimit,
    int? perUserLimit = 1,
    String? vendorId,
    DateTime? startsAt,
    DateTime? expiresAt,
    bool firstOrderOnly = false,
    bool isPublic = false,
    String? title,
  }) async {
    await supabase.from('coupons').insert({
      'code': code.toUpperCase(),
      'discount_type': discountType,
      // A free-delivery code has no value of its own: the discount is whatever
      // the store charges for delivery, resolved when the code is applied.
      'value': discountType == 'free_delivery' ? 0 : value,
      'min_order_amount': minOrderAmount,
      'max_discount': ?maxDiscount,
      'usage_limit': ?usageLimit,
      'per_user_limit': perUserLimit,
      'vendor_id': ?vendorId,
      'starts_at': startsAt?.toUtc().toIso8601String(),
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      'first_order_only': firstOrderOnly,
      'is_public': isPublic,
      'title': ?title,
      'is_active': true,
    });
  }

  Future<void> update(String id, Map<String, dynamic> values) async {
    await supabase.from('coupons').update(values).eq('id', id);
  }

  /// Who has redeemed a campaign, newest first — the answer to "why has this
  /// cost us so much" and the only place a per-customer abuse shows up.
  Future<List<Map<String, dynamic>>> redemptions(String couponId) async {
    final data = await supabase
        .from('coupon_redemptions')
        .select('id, user_id, order_id, discount, created_at')
        .eq('coupon_id', couponId)
        .order('created_at', ascending: false)
        .limit(100);
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<void> setActive(String id, bool active) async {
    await supabase.from('coupons').update({'is_active': active}).eq('id', id);
  }

  Future<void> delete(String id) async {
    await supabase.from('coupons').delete().eq('id', id);
  }
}
