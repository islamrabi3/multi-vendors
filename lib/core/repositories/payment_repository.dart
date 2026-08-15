import '../supabase_client.dart';

/// A unified-checkout session created by the paymob-create-intention function.
class PaymobCheckout {
  const PaymobCheckout({
    required this.url,
    required this.reference,
    required this.amount,
  });

  final String url;

  /// Paymob's `special_reference`; also the key of the `payment_intents` row
  /// the webhook settles.
  final String reference;
  final double amount;
}

/// How a payment ended, as recorded server-side by the Paymob webhook.
enum PaymentOutcome { paid, failed, pending }

/// Which Paymob integration to open the checkout against.
///
/// Both settle identically — same unified-checkout page, same webhook, same
/// `payment_intents` row — so this only decides which methods Paymob offers
/// once the customer is there.
///
/// [wallet] is an Egyptian *mobile* wallet (Vodafone Cash, Etisalat, Orange).
/// It is not this app's own stored balance: paying from that is a ledger
/// debit that never reaches the gateway and never comes through here.
enum PaymobChannel { card, wallet }

class PaymentException implements Exception {
  const PaymentException(this.code);
  final String code;

  @override
  String toString() => code;
}

class PaymentRepository {
  /// How long to wait for Paymob's webhook after the customer finishes the
  /// checkout. Settlement is normally a second or two.
  static const _settleTimeout = Duration(seconds: 45);
  static const _pollInterval = Duration(seconds: 2);

  /// Unified checkout for an existing order. The amount is taken from the
  /// order row server-side.
  Future<PaymobCheckout> createOrderCheckout(
    String orderId, {
    PaymobChannel channel = PaymobChannel.card,
  }) => _createIntention({
    'kind': 'order',
    'order_id': orderId,
    'channel': channel.name,
  });

  /// Unified checkout for a wallet top-up.
  Future<PaymobCheckout> createTopUpCheckout(
    double amount, {
    PaymobChannel channel = PaymobChannel.card,
  }) => _createIntention({
    'kind': 'topup',
    'amount': amount,
    'channel': channel.name,
  });

  Future<PaymobCheckout> _createIntention(Map<String, dynamic> body) async {
    final response = await supabase.functions.invoke(
      'paymob-create-intention',
      body: body,
    );

    final data = response.data;
    if (data is! Map) {
      throw const PaymentException('PAYMENT_GATEWAY_UNAVAILABLE');
    }
    if (data['error'] != null) {
      throw PaymentException(data['error'].toString());
    }

    final url = data['checkout_url'] as String?;
    final reference = data['reference'] as String?;
    if (url == null || url.isEmpty || reference == null || reference.isEmpty) {
      throw const PaymentException('PAYMENT_GATEWAY_UNAVAILABLE');
    }

    return PaymobCheckout(
      url: url,
      reference: reference,
      amount: ((data['amount'] as num?) ?? 0).toDouble(),
    );
  }

  /// Blocks until the webhook has settled [reference], or the wait times out.
  ///
  /// The redirect back from Paymob is only a hint — the transaction is not
  /// trusted until the HMAC-verified webhook has written the intent's status.
  Future<PaymentOutcome> awaitSettlement(String reference) async {
    final deadline = DateTime.now().add(_settleTimeout);

    while (DateTime.now().isBefore(deadline)) {
      final status = await _fetchStatus(reference);
      if (status == 'paid') return PaymentOutcome.paid;
      if (status == 'failed') return PaymentOutcome.failed;
      await Future<void>.delayed(_pollInterval);
    }

    // Still pending: treat as unresolved, not as success.
    return PaymentOutcome.pending;
  }

  Future<String?> _fetchStatus(String reference) async {
    try {
      final row = await supabase
          .from('payment_intents')
          .select('status')
          .eq('reference', reference)
          .maybeSingle();
      return row?['status'] as String?;
    } catch (_) {
      return null;
    }
  }
}
