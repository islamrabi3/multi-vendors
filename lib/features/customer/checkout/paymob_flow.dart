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
    extra: checkout.url,
  );

  if (tabResult == PaymobCheckoutResult.cancelled || tabResult == null) {
    return PaymobFlowResult.cancelled;
  }

  final outcome =
      await (payments ?? PaymentRepository()).awaitSettlement(checkout.reference);

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
