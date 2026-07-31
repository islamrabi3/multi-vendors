import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/tokens.dart';
import '../models/order.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

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
      color: const Color(0xFFF3E7DE),
      child: const Icon(Icons.restaurant, color: Color(0xFFB9A492)),
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

/// Page-level loader. Brand-coloured, because an uncoloured
/// CircularProgressIndicator renders in the Material default and the app then
/// shows two different spinner colours depending on the screen.
///
/// Prefer a shape-matched skeleton (`lib/core/widgets/skeleton.dart`) where the
/// layout is known ahead of the data; this is for screens whose shape is not
/// predictable, such as the driver's live map.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
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
            const Icon(Icons.error_outline,
                size: 48, color: AppColors.textFaint),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: Text(context.l10n.retry)),
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
          Icon(icon, size: 56, color: AppColors.textFaint),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// Rebuilds its child with a hover flag and a pointer cursor — the desktop
/// affordance for rows and cards. Inert on touch: `MouseRegion` never fires.
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({
    super.key,
    required this.builder,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;

  void _set(bool value) {
    if (_hovered != value) setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => _set(true),
      onExit: (_) => _set(false),
      child: widget.builder(context, _hovered),
    );
  }
}

/// An id / order number / phone number an operator needs to copy.
///
/// Selection is opt-out because inside a tappable row a `SelectableText` eats
/// the tap that opens the record — list rows keep plain text on touch layouts
/// and only turn selectable on pointer widths.
class SelectableId extends StatelessWidget {
  const SelectableId(
    this.text, {
    super.key,
    this.style,
    this.selectable = true,
  });

  final String text;
  final TextStyle? style;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    if (!selectable) {
      return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return SelectableText(text, style: style, maxLines: 1);
  }
}

/// Footer of an infinite list: a spinner while a page is in flight, and
/// nothing at all once the list is exhausted.
class PagingFooter extends StatelessWidget {
  const PagingFooter({super.key, required this.loading, required this.hasMore});

  final bool loading;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          ),
        ),
      );
    }
    return const SizedBox(height: 8);
  }
}

/// Calls [onLoadMore] as the wrapped scroll view nears its end. The callee is
/// expected to ignore the call while a page is in flight or the list is done.
class InfiniteScroll extends StatelessWidget {
  const InfiniteScroll({
    super.key,
    required this.onLoadMore,
    required this.child,
    this.threshold = 320,
  });

  final VoidCallback onLoadMore;
  final Widget child;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final m = notification.metrics;
        if (m.axis == Axis.vertical &&
            m.maxScrollExtent - m.pixels <= threshold) {
          onLoadMore();
        }
        return false;
      },
      child: child,
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            icon: Icons.remove,
            onTap: quantity > min ? () => onChanged(quantity - 1) : null,
          ),
          SizedBox(
            width: 30,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: AppType.mono(15, weight: FontWeight.w700),
            ),
          ),
          _StepButton(icon: Icons.add, onTap: () => onChanged(quantity + 1)),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? AppColors.primary : AppColors.textFaint,
        ),
      ),
    );
  }
}

/// Pill badge with a soft fill — used for ratings, statuses, tags.
class SoftBadge extends StatelessWidget {
  const SoftBadge({
    super.key,
    required this.label,
    required this.fill,
    required this.ink,
    this.icon,
    this.leading,
  });

  final String label;
  final Color fill;
  final Color ink;
  final IconData? icon;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 4)],
          if (icon != null) ...[
            Icon(icon, size: 13, color: ink),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
                color: ink, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Star + score chip on amber fill (`★ 4.8`).
class RatingChip extends StatelessWidget {
  const RatingChip({super.key, required this.rating, this.count});

  final double rating;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final isNew = count != null && count == 0;
    return SoftBadge(
      label: isNew ? 'New' : rating.toStringAsFixed(1),
      fill: AppColors.amberFill,
      ink: AppColors.amberInk,
      leading: const Icon(Icons.star_rounded, size: 15, color: AppColors.rating),
    );
  }
}

/// Mono price text (`EGP 84.00`).
class PriceText extends StatelessWidget {
  const PriceText(
    this.text, {
    super.key,
    this.size = 14,
    this.color = AppColors.ink,
    this.weight = FontWeight.w700,
  });

  final String text;
  final double size;
  final Color color;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: AppType.mono(size, color: color, weight: weight));
}

class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.status});

  final OrderStatus status;

  (Color, Color) get _palette => switch (status) {
        OrderStatus.pending => (AppColors.amberFill, AppColors.amberInk),
        OrderStatus.accepted ||
        OrderStatus.preparing =>
          (AppColors.warmFill, AppColors.primaryDark),
        OrderStatus.readyForPickup ||
        OrderStatus.outForDelivery =>
          (AppColors.successFill, AppColors.successInk),
        OrderStatus.delivered => (AppColors.successFill, AppColors.successInk),
        OrderStatus.cancelled ||
        OrderStatus.rejected =>
          (const Color(0xFFFBE7E4), const Color(0xFFC0392B)),
      };

  @override
  Widget build(BuildContext context) {
    final (fill, ink) = _palette;
    return SoftBadge(label: status.localizedLabel(context), fill: fill, ink: ink);
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
    'OUTSIDE_SERVICE_AREA':
        "We don't deliver to this address yet. Pick another address inside "
        'our delivery area.',
    'ROLE_ALREADY_SET': 'Your account type has already been set.',
    'ROLE_CHANGE_NOT_ALLOWED': 'Account type cannot be changed here.',
    'COUPON_INVALID': 'This coupon code is not valid.',
    'NOT_AN_ONLINE_DRIVER':
        'Go online to claim orders. A new driver account needs admin '
        'approval first.',
    'INSUFFICIENT_WALLET_BALANCE':
        'Your wallet balance is not enough for this order.',
    'PAYMOB_NOT_CONFIGURED':
        'Card payments are unavailable right now. Please try another method.',
    'PAYMOB_INTENTION_FAILED':
        'The payment page could not be opened. Please try again.',
    'PAYMENT_GATEWAY_UNAVAILABLE':
        'The payment page could not be opened. Please try again.',
    'ALREADY_PAID': 'This order has already been paid.',
    'ALREADY_REFUNDED': 'This order has already been refunded.',
    'DRIVER_NOT_APPROVED':
        'Your driver account is awaiting admin approval. You can go online '
        'once it is approved.',
    'ORDER_NOT_PAID': 'This order was never paid, nothing to refund.',
    'ORDER_NOT_CANCELLED': 'Only cancelled or rejected orders can be refunded.',
    'NOT_A_CARD_ORDER': 'Only card-paid orders can be refunded to the wallet.',
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
