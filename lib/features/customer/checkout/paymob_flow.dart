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
    // Closing the page is not proof that nothing was paid. Paymob's success
    // page counts down for five seconds before it redirects, and a customer
    // who has just seen "payment successful" closes it — which left no signed
    // redirect to confirm with, so the app believed the webhook or nothing.
    //
    // So ask Paymob itself what became of this checkout. Its answer is
    // final; only when it has no transaction to report does the wait for the
    // webhook decide, and only then is this a genuine cancellation.
    final answer = await repository.inquire(checkout.reference);
    if (answer == 'paid') return PaymobFlowResult.paid;
    if (answer == 'failed') return PaymobFlowResult.failed;

    final settled = await repository.awaitSettlement(
      checkout.reference,
      timeout: const Duration(seconds: 12),
    );
    return switch (settled) {
      PaymentOutcome.paid => PaymobFlowResult.paid,
      PaymentOutcome.failed => PaymobFlowResult.failed,
      // One last ask: a 3-D Secure step that was still pending when the page
      // closed has had a quarter of a minute to resolve by now.
      PaymentOutcome.pending =>
        await repository.inquire(checkout.reference) == 'paid'
            ? PaymobFlowResult.paid
            : PaymobFlowResult.cancelled,
    };
  }

  final outcome = await repository.awaitSettlement(checkout.reference);

  switch (outcome) {
    case PaymentOutcome.paid:
      return PaymobFlowResult.paid;
    case PaymentOutcome.failed:
      return PaymobFlowResult.failed;
    case PaymentOutcome.pending:
      // The webhook never came. Paymob knows either way.
      final answer = await repository.inquire(checkout.reference);
      if (answer == 'paid') return PaymobFlowResult.paid;
      if (answer == 'failed') return PaymobFlowResult.failed;
      return tabResult == PaymobCheckoutResult.declined
          ? PaymobFlowResult.failed
          : PaymobFlowResult.unresolved;
  }
}
