import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import 'cart_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  @override
  void initState() {
    super.initState();
    // Checked on every open rather than on a timer: this is the last screen
    // before checkout, and a cart is often hours old by the time it is
    // reopened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<CartCubit>()
          .revalidate(CatalogRepository().fetchProductsByIds);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.ink, size: 22),
          onPressed: () => context.pop(),
        ),
        title: Text(
          context.l10n.yourCart,
          style: AppType.heading(22),
        ),
        centerTitle: false,
        actions: [
          BlocBuilder<CartCubit, CartState>(
            builder: (context, cart) => cart.isEmpty
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: context.read<CartCubit>().clear,
                    child: Text(
                      context.l10n.clear,
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: BlocBuilder<CartCubit, CartState>(
        builder: (context, cart) {
          if (cart.isEmpty) {
            return EmptyView(
              message: context.l10n.yourCartIsEmpty1,
              icon: Icons.shopping_cart_outlined,
            );
          }

          return Column(
            children: [
              if (cart.hasProblems) _CartWarnings(cart: cart),
              // Store Header Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.warmFill,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(context.l10n.emptyString, style: TextStyle(fontSize: 18)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cart.vendor!.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${cart.vendor!.avgPrepMinutes}–${cart.vendor!.avgPrepMinutes + 10} min · Tahrir St',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Items list
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: cart.items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = cart.items[index];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Item cover image (using pattern placeholder style)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: AppNetworkImage(
                              url: item.product.imageUrl,
                              width: 62,
                              height: 62,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.product.displayName(
                                      Localizations.localeOf(context)
                                          .languageCode),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14.5,
                                    color: AppColors.ink,
                                  ),
                                ),
                                if (item.selectedOptions.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    item.selectedOptions.map((o) => o.name).join(', '),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                                if (item.notes != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '"${item.notes}"',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                                // Says which line the banner above is about.
                                if (cart.isUnavailable(item) ||
                                    cart.isRepriced(item)) ...[
                                  const SizedBox(height: 4),
                                  SoftBadge(
                                    label: cart.isUnavailable(item)
                                        ? context.l10n.unavailableNow
                                        : context.l10n.newPrice,
                                    fill: cart.isUnavailable(item)
                                        ? AppColors.dangerFill
                                        : AppColors.amberFill,
                                    ink: cart.isUnavailable(item)
                                        ? AppColors.dangerInk
                                        : AppColors.amberInk,
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    PriceText(formatMoney(item.lineTotal), size: 14),
                                    QuantityStepper(
                                      quantity: item.quantity,
                                      min: 0,
                                      onChanged: (q) => context
                                          .read<CartCubit>()
                                          .updateQuantity(item, q),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Summary & checkout footer
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: AppColors.borderSoft),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            context.l10n.subtotal,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          PriceText(formatMoney(cart.subtotal), size: 14),
                        ],
                      ),
                      // The store minimum is enforced by place_order, the very
                      // last step of checkout. Without this the customer picks
                      // an address and a payment method before being told they
                      // were never eligible to order.
                      if (cart.subtotal < (cart.vendor?.minOrderAmount ?? 0))
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  size: 15, color: AppColors.amberInk),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${context.l10n.addMoreToReachMinimum} '
                                  '${formatMoney((cart.vendor?.minOrderAmount ?? 0) - cart.subtotal)}',
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.amberInk),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 14),
                      InkWell(
                        // An unavailable line would be refused by the server
                        // anyway; stopping here means the customer finds out
                        // before entering an address and a payment method.
                        onTap: !cart.canCheckout ||
                                cart.subtotal <
                                    (cart.vendor?.minOrderAmount ?? 0)
                            ? null
                            : () => context.push('/checkout'),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          height: 54,
                          decoration: BoxDecoration(
                            color: cart.subtotal <
                                    (cart.vendor?.minOrderAmount ?? 0)
                                ? AppColors.borderStrong
                                : AppColors.primary,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: cart.subtotal <
                                    (cart.vendor?.minOrderAmount ?? 0)
                                ? null
                                : AppShadows.primaryGlow,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                cart.subtotal <
                                        (cart.vendor?.minOrderAmount ?? 0)
                                    ? '${context.l10n.minimumOrder} '
                                        '${formatMoney(cart.vendor?.minOrderAmount ?? 0)}'
                                    : context.l10n.goToCheckout,
                                style: TextStyle(
                                  color: cart.subtotal <
                                          (cart.vendor?.minOrderAmount ?? 0)
                                      ? AppColors.textMuted
                                      : Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              if (cart.subtotal >=
                                  (cart.vendor?.minOrderAmount ?? 0)) ...[
                                const SizedBox(width: 8),
                                PriceText(
                                  formatMoney(cart.subtotal),
                                  size: 15,
                                  color: Colors.white,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// What changed since the cart was filled: sold-out lines, and price moves.
class _CartWarnings extends StatelessWidget {
  const _CartWarnings({required this.cart});

  final CartState cart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          if (cart.unavailable.isNotEmpty)
            _banner(
              context,
              icon: Icons.remove_shopping_cart_outlined,
              fill: AppColors.dangerFill,
              ink: AppColors.dangerInk,
              message: l10n.cartItemsUnavailable,
              action: TextButton(
                onPressed: context.read<CartCubit>().removeUnavailable,
                child: Text(l10n.removeUnavailable),
              ),
            ),
          if (cart.repriced.isNotEmpty)
            _banner(
              context,
              icon: Icons.sell_outlined,
              fill: AppColors.amberFill,
              ink: AppColors.amberInk,
              message: l10n.cartPricesChanged,
            ),
        ],
      ),
    );
  }

  Widget _banner(
    BuildContext context, {
    required IconData icon,
    required Color fill,
    required Color ink,
    required String message,
    Widget? action,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: ink),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: ink),
              ),
            ),
            ?action,
          ],
        ),
      );
}
