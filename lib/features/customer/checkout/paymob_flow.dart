import 'package:go_router/go_router.dart';

import '../../../core/repositories/payment_repository.dart';
import 'paymob_checkout_screen.dart';

/// Outcome of a full card payment: open the gateway, then confirm with the
/// server what actually happened.
enum PaymobFlowResult {
  /// Webhook confirmed the money arrived.
  paid,

  /// Gateway declined, or the webhook recorded a failure.
  failed,

  /// Customer closed the tab without paying.
  cancelled,

  /// Customer finished but the webhook has not settled yet. Nothing has been
  /// credited or fulfilled; the payment may still land.
  unresolved,
}

/// Opens Paymob's unified checkout and waits for server-side settlement.
///
/// The gateway's redirect is never treated as proof of payment — only the
/// HMAC-verified webhook can move the intent to `paid`. Takes the router
/// rather than a BuildContext so callers can await it across async gaps.
Future<PaymobFlowResult> runPaymobCheckout(
  GoRouter router,
  PaymobCheckout checkout, {
  PaymentRepository? payments,
}) async {
  final tabResult = await router.push<PaymobCheckoutResult>(
    '/paymob-checkout',
    extra: checkout,
  );

  final repository = payments ?? PaymentRepository();

  if (tabResult == PaymobCheckoutResult.cancelled || tabResult == null) {
    // Closing the page is not proof that nothing was paid: a customer who
    // paid and then shut the tab a second early would otherwise be told the
    // payment failed while the webhook was busy settling it. A short wait
    // costs nothing and turns that into the truth.
    final late = await repository.awaitSettlement(
      checkout.reference,
      timeout: const Duration(seconds: 12),
    );
    return switch (late) {
      PaymentOutcome.paid => PaymobFlowResult.paid,
      PaymentOutcome.failed => PaymobFlowResult.failed,
      PaymentOutcome.pending => PaymobFlowResult.cancelled,
    };
  }

  final outcome = await repository.awaitSettlement(checkout.reference);

  switch (outcome) {
    case PaymentOutcome.paid:
      return PaymobFlowResult.paid;
    case PaymentOutcome.failed:
      return PaymobFlowResult.failed;
    case PaymentOutcome.pending:
      return tabResult == PaymobCheckoutResult.declined
          ? PaymobFlowResult.failed
          : PaymobFlowResult.unresolved;
  }
}
