import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  const PaymobCheckoutScreen({super.key, required this.checkoutUrl});

  final String checkoutUrl;

  @override
  State<PaymobCheckoutScreen> createState() => _PaymobCheckoutScreenState();
}

class _PaymobCheckoutScreenState extends State<PaymobCheckoutScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _finished = false;

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
            _finish(result);
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
            if (_loading) const LoadingView(),
          ],
        ),
      ),
    );
  }
}
