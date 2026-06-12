import '../supabase_client.dart';

class PaymentRepository {
  /// Asks the paymob-create-intention Edge Function for a unified checkout
  /// URL for the given order.
  Future<String> createPaymobCheckout(String orderId) async {
    final response = await supabase.functions.invoke(
      'paymob-create-intention',
      body: {'order_id': orderId},
    );
    final data = response.data as Map<String, dynamic>;
    final url = data['checkout_url'] as String?;
    if (url == null) {
      throw Exception(data['error'] ?? 'Could not start payment');
    }
    return url;
  }
}
