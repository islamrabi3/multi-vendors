import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// Hosts Paymob's unified checkout in a WebView. The Edge Function sets the
/// intention's redirection_url to https://payment-complete.local/ — when the
/// checkout navigates there we close the WebView and land on the order, whose
/// realtime stream reflects the webhook-confirmed payment status.
class PaymobCheckoutScreen extends StatefulWidget {
  const PaymobCheckoutScreen({
    super.key,
    required this.checkoutUrl,
    required this.orderId,
  });

  final String checkoutUrl;
  final String orderId;

  @override
  State<PaymobCheckoutScreen> createState() => _PaymobCheckoutScreenState();
}

class _PaymobCheckoutScreenState extends State<PaymobCheckoutScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onNavigationRequest: (request) {
          if (Uri.parse(request.url).host == 'payment-complete.local') {
            _finish();
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  void _finish() {
    if (!mounted) return;
    context.pushReplacement('/order/${widget.orderId}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.payment),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _finish,
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
