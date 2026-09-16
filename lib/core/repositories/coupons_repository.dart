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
    String fundedBy = 'platform',
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
      // Only a store-scoped code can be charged to the store.
      'funded_by': vendorId == null ? 'platform' : fundedBy,
    });
  }

  /// A store's promo codes that a customer can use right now, for that
  /// store's page only. Platform-wide codes are deliberately not included.
  Future<List<Coupon>> fetchStoreOffers(String vendorId) async {
    final data = await supabase
        .from('coupons')
        .select()
        .eq('vendor_id', vendorId)
        .eq('is_active', true)
        .eq('is_public', true)
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => Coupon.fromMap(e))
        // Dates and caps are checked here rather than in the query.
        .where((c) => c.isLive)
        .toList();
  }

  /// Edits a campaign. Mirrors [create] field for field, so anything an admin
  /// could set when making a code they can also correct afterwards — the
  /// screen only offered delete-and-retype before.
  Future<void> edit({
    required String id,
    required String code,
    required String discountType,
    required double value,
    double minOrderAmount = 0,
    double? maxDiscount,
    int? usageLimit,
    int? perUserLimit,
    String? vendorId,
    DateTime? startsAt,
    DateTime? expiresAt,
    bool firstOrderOnly = false,
    bool isPublic = false,
    String? title,
    String fundedBy = 'platform',
  }) async {
    await supabase
        .from('coupons')
        .update({
          'code': code.toUpperCase(),
          'discount_type': discountType,
          'value': discountType == 'free_delivery' ? 0 : value,
          'min_order_amount': minOrderAmount,
          'max_discount': maxDiscount,
          'usage_limit': usageLimit,
          'per_user_limit': perUserLimit,
          'vendor_id': vendorId,
          'starts_at': startsAt?.toUtc().toIso8601String(),
          'expires_at': expiresAt?.toUtc().toIso8601String(),
          'first_order_only': firstOrderOnly,
          'is_public': isPublic,
          'title': title,
          'funded_by': vendorId == null ? 'platform' : fundedBy,
        })
        .eq('id', id);
  }

  /// Codes *this* customer can use right now — the home page's list.
  ///
  /// The server applies the same rules checkout does, including how many times
  /// this customer has already used each code, so a one-per-customer code
  /// disappears once it is spent instead of sitting there to be refused.
  Future<List<Coupon>> fetchPublicCoupons() async {
    final data = await supabase.rpc('my_public_coupons');
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(Coupon.fromMap)
        .toList();
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
