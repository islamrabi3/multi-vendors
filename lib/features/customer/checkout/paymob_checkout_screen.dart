import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app/tokens.dart';
import '../../../core/repositories/payment_repository.dart';
import '../../../core/widgets/common.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// What the customer did in the unified checkout. `completed` only means the
/// gateway redirected back claiming success — the payment is not considered
/// real until the webhook has settled the intent.
enum PaymobCheckoutResult { completed, declined, cancelled }

/// Hosts Paymob's unified checkout in a WebView. The Edge Function sets the
/// intention's redirection_url to https://payment-complete.local/ — when the
/// checkout navigates there we close the tab and hand the outcome back to the
/// caller. This screen never navigates anywhere itself.
class PaymobCheckoutScreen extends StatefulWidget {
  const PaymobCheckoutScreen({
    super.key,
    required this.checkoutUrl,
    this.reference,
  });

  final String checkoutUrl;

  /// The intent this checkout settles. With it, the screen confirms the
  /// payment itself from Paymob's signed redirect before closing, instead of
  /// relying on the webhook alone.
  final String? reference;

  @override
  State<PaymobCheckoutScreen> createState() => _PaymobCheckoutScreenState();
}

class _PaymobCheckoutScreenState extends State<PaymobCheckoutScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _finished = false;

  /// Paymob has redirected back; the server is confirming the payment.
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            final result = _resultFor(request.url);
            if (result == null) return NavigationDecision.navigate;
            _confirmAndFinish(result, Uri.parse(request.url));
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  /// Returns null while the customer is still inside the gateway.
  PaymobCheckoutResult? _resultFor(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return null;
    if (uri.host != 'payment-complete.local') return null;

    final params = uri.queryParameters;
    final success = params['success']?.toLowerCase();
    final responseCode = params['txn_response_code']?.toUpperCase();
    final pending = params['pending']?.toLowerCase();

    // Paymob marks a 3-D Secure step as pending; the webhook resolves it.
    if (success == 'true' && pending != 'true') {
      return PaymobCheckoutResult.completed;
    }
    if (responseCode == 'APPROVED') return PaymobCheckoutResult.completed;
    if (success == 'false' || responseCode != null) {
      return PaymobCheckoutResult.declined;
    }
    // Redirected home with no verdict — let the caller confirm with the server.
    return PaymobCheckoutResult.completed;
  }

  /// The redirect carries the whole transaction, signed. Passing it to the
  /// server settles the payment even when Paymob's webhook never arrives —
  /// which is how a paid order used to stay unpaid and invisible.
  Future<void> _confirmAndFinish(PaymobCheckoutResult result, Uri uri) async {
    final reference = widget.reference;
    if (_confirming || _finished) return;
    if (reference == null || result == PaymobCheckoutResult.cancelled) {
      _finish(result);
      return;
    }
    setState(() => _confirming = true);
    final repo = PaymentRepository();
    final status = await repo.confirmFromRedirect(
      reference,
      uri.queryParameters,
    );
    if (status == null || status == 'pending') {
      // Give the webhook a moment before handing back to the caller, which
      // keeps polling on its own.
      await repo.awaitSettlement(
        reference,
        timeout: const Duration(seconds: 20),
      );
    }
    _finish(result);
  }

  void _finish(PaymobCheckoutResult result) {
    if (_finished || !mounted) return;
    _finished = true;
    context.pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish(PaymobCheckoutResult.cancelled);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.payment),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => _finish(PaymobCheckoutResult.cancelled),
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading && !_confirming) const LoadingView(),
            if (_confirming) const _ConfirmingOverlay(),
          ],
        ),
      ),
    );
  }
}

/// Covers the gateway page while the payment is confirmed, so the customer is
/// not left looking at a finished checkout with nothing happening.
class _ConfirmingOverlay extends StatelessWidget {
  const _ConfirmingOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: AppColors.canvas,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.5,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                Text(
                  context.l10n.paymentConfirmingTitle,
                  textAlign: TextAlign.center,
                  style: AppType.heading(17),
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  context.l10n.paymentConfirmingBody,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
