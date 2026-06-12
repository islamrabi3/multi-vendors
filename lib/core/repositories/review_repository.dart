import '../supabase_client.dart';

class ReviewRepository {
  Future<void> submitReview({
    required String orderId,
    required String vendorId,
    required int rating,
    String? comment,
  }) =>
      supabase.from('reviews').insert({
        'order_id': orderId,
        'vendor_id': vendorId,
        'customer_id': supabase.auth.currentUser!.id,
        'rating': rating,
        'comment': (comment?.trim().isEmpty ?? true) ? null : comment!.trim(),
      });

  Future<bool> hasReview(String orderId) async {
    final data = await supabase
        .from('reviews')
        .select('id')
        .eq('order_id', orderId)
        .maybeSingle();
    return data != null;
  }
}
