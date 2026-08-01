import '../models/review.dart';
import '../supabase_client.dart';

class ReviewRepository {
  /// A review covers the whole delivery: the food and, when there was one, the
  /// driver. Both land on the same row, so a customer rates once.
  ///
  /// RLS allows this only for a delivered order the caller placed, and a
  /// unique index keeps it to one per order.
  Future<void> submitReview({
    required String orderId,
    required String vendorId,
    required int rating,
    String? comment,
    String? driverId,
    int? driverRating,
    String? driverComment,
  }) =>
      supabase.from('reviews').insert({
        'order_id': orderId,
        'vendor_id': vendorId,
        'customer_id': supabase.auth.currentUser!.id,
        'rating': rating,
        'comment': _clean(comment),
        // Only stamped when the customer actually rated the driver: a null
        // driver_rating is left out of the driver's average entirely.
        if (driverRating != null) ...{
          'driver_id': driverId,
          'driver_rating': driverRating,
          'driver_comment': _clean(driverComment),
        },
      });

  Future<bool> hasReview(String orderId) async {
    final data = await supabase
        .from('reviews')
        .select('id')
        .eq('order_id', orderId)
        .maybeSingle();
    return data != null;
  }

  /// Public reviews for a store page. Goes through an RPC because the
  /// reviewer's name lives in `profiles`, which a customer cannot read.
  Future<List<Review>> fetchVendorReviews(
    String vendorId, {
    int limit = 20,
    int offset = 0,
  }) async {
    final data = await supabase.rpc('vendor_reviews', params: {
      'p_vendor_id': vendorId,
      'p_limit': limit,
      'p_offset': offset,
    });
    return (data as List)
        .map((e) => Review.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<RatingBreakdown> fetchBreakdown(String vendorId) async {
    final data = await supabase
        .rpc('vendor_rating_breakdown', params: {'p_vendor_id': vendorId});
    if (data == null) return RatingBreakdown.empty;
    return RatingBreakdown.fromMap(data as Map<String, dynamic>);
  }

  /// The store's own inbox — the same rows, plus the order each came from.
  /// Only the owner and admins may call it.
  Future<List<Review>> fetchMyVendorReviews(
    String vendorId, {
    int limit = 30,
    int offset = 0,
  }) async {
    final data = await supabase.rpc('my_vendor_reviews', params: {
      'p_vendor_id': vendorId,
      'p_limit': limit,
      'p_offset': offset,
    });
    return (data as List)
        .map((e) => Review.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  static String? _clean(String? text) {
    final trimmed = text?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
