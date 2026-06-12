import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/order.dart';

class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.storefront_outlined, color: Colors.grey),
    );
    final child = url == null || url!.isEmpty
        ? placeholder
        : CachedNetworkImage(
            imageUrl: url!,
            width: width,
            height: height,
            fit: fit,
            placeholder: (_, _) => placeholder,
            errorWidget: (_, _, _) => placeholder,
          );
    if (borderRadius == null) return child;
    return ClipRRect(borderRadius: borderRadius!, child: child);
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.onChanged,
    this.min = 1,
  });

  final int quantity;
  final ValueChanged<int> onChanged;
  final int min;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          visualDensity: VisualDensity.compact,
          onPressed: quantity > min ? () => onChanged(quantity - 1) : null,
          icon: const Icon(Icons.remove, size: 18),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('$quantity',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        IconButton.outlined(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(quantity + 1),
          icon: const Icon(Icons.add, size: 18),
        ),
      ],
    );
  }
}

class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.status});

  final OrderStatus status;

  Color get _color => switch (status) {
        OrderStatus.pending => Colors.orange,
        OrderStatus.accepted || OrderStatus.preparing => Colors.blue,
        OrderStatus.readyForPickup => Colors.teal,
        OrderStatus.outForDelivery => Colors.indigo,
        OrderStatus.delivered => Colors.green,
        OrderStatus.cancelled || OrderStatus.rejected => Colors.red,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
            color: _color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? Theme.of(context).colorScheme.error : null,
  ));
}

/// Strips PostgrestException noise down to a readable message.
String readableError(Object error) {
  final text = error.toString();
  final known = {
    'CART_EMPTY': 'Your cart is empty.',
    'VENDOR_CLOSED': 'This store is currently closed.',
    'ADDRESS_NOT_FOUND': 'Please choose a delivery address.',
    'COUPON_INVALID': 'This coupon code is not valid.',
    'NOT_AN_ONLINE_DRIVER': 'Go online to claim orders.',
  };
  for (final entry in known.entries) {
    if (text.contains(entry.key)) return entry.value;
  }
  if (text.contains('MIN_ORDER_NOT_MET')) {
    return 'Order total is below the store minimum.';
  }
  if (text.contains('COUPON_MIN_ORDER')) {
    return 'Order total is below the coupon minimum.';
  }
  if (text.contains('PRODUCT_UNAVAILABLE')) {
    return 'An item in your cart is no longer available.';
  }
  if (text.contains('TRANSITION_NOT_ALLOWED')) {
    return 'This order was already updated. Refreshing…';
  }
  if (text.contains('Invalid login credentials')) {
    return 'Incorrect email or password.';
  }
  return 'Something went wrong. Please try again.';
}
