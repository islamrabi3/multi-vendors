import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/models/product.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../vendor_details/product_sheet.dart';
import '../vendor_details/product_suggestion_card.dart';
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
      context.read<CartCubit>().revalidate(
        CatalogRepository().fetchProductsByIds,
      );
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
        title: Text(context.l10n.yourCart, style: AppType.heading(22)),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
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
                        child: Text(
                          context.l10n.emptyString,
                          style: TextStyle(fontSize: 18),
                        ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
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
                                    Localizations.localeOf(
                                      context,
                                    ).languageCode,
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14.5,
                                    color: AppColors.ink,
                                  ),
                                ),
                                if (item.selectedOptions.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    item.selectedOptions
                                        .map((o) => o.name)
                                        .join(', '),
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    PriceText(
                                      formatMoney(item.lineTotal),
                                      size: 14,
                                    ),
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

              // Above the total rather than below it: once somebody has read
              // the amount they are about to pay, they are leaving, and a
              // suggestion under the button is a suggestion nobody sees.
              if (cart.vendor != null)
                _CartSuggestions(
                  vendor: cart.vendor!,
                  inCart: [for (final item in cart.items) item.product.id],
                ),

              // Summary & checkout footer
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppColors.borderSoft)),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 16,
                ),
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
                              const Icon(
                                Icons.info_outline,
                                size: 15,
                                color: AppColors.amberInk,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${context.l10n.addMoreToReachMinimum} '
                                  '${formatMoney((cart.vendor?.minOrderAmount ?? 0) - cart.subtotal)}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.amberInk,
                                  ),
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
                        onTap:
                            !cart.canCheckout ||
                                cart.subtotal <
                                    (cart.vendor?.minOrderAmount ?? 0)
                            ? null
                            : () => context.push('/checkout'),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          height: 54,
                          // Explicit, because the label no longer stretches it.
                          // The Row inside is mainAxisSize.min so it can be
                          // scaled, which means it no longer forces the button
                          // to full width the way a max-size Row did.
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color:
                                cart.subtotal <
                                    (cart.vendor?.minOrderAmount ?? 0)
                                ? AppColors.borderStrong
                                : AppColors.primary,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow:
                                cart.subtotal <
                                    (cart.vendor?.minOrderAmount ?? 0)
                                ? null
                                : AppShadows.primaryGlow,
                          ),
                          // Scaled rather than clipped, for the same reason as
                          // the add-to-cart button: the minimum-order variant
                          // carries a price inside the label, and in Arabic it
                          // is long enough to overflow a narrow phone.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  cart.subtotal <
                                          (cart.vendor?.minOrderAmount ?? 0)
                                      ? '${context.l10n.minimumOrder} '
                                            '${formatMoney(cart.vendor?.minOrderAmount ?? 0)}'
                                      : context.l10n.goToCheckout,
                                  style: TextStyle(
                                    color:
                                        cart.subtotal <
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
/// "You might also like", under the items and above the total.
///
/// Ranked server-side against everything in the cart, and never suggests
/// something already in it. Adding is one tap: the card carries the same
/// quantity control as the menu, so nobody has to leave the cart to change
/// their mind about a drink.
class _CartSuggestions extends StatefulWidget {
  const _CartSuggestions({required this.vendor, required this.inCart});

  final Vendor vendor;
  final List<String> inCart;

  @override
  State<_CartSuggestions> createState() => _CartSuggestionsState();
}

class _CartSuggestionsState extends State<_CartSuggestions> {
  final _catalog = CatalogRepository();
  late Future<List<Product>> _future = _load();

  Future<List<Product>> _load() => _catalog.cartSuggestions(
    vendorId: widget.vendor.id,
    inCart: widget.inCart,
  );

  @override
  void didUpdateWidget(_CartSuggestions oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Deliberately not refetched when the cart changes.
    //
    // The exclusion list is what was in the cart when the strip loaded, not
    // what is in it now. Refetching on every change meant adding from the strip
    // immediately excluded that item, so the card the customer had just tapped
    // deleted itself a moment later — taking the stepper with it, before they
    // could reach a second one or undo.
    //
    // A card that stays put also stays steppable, which is the whole point of
    // putting the control here. The list is rebuilt the next time the cart is
    // opened, since that is a fresh State.
    if (oldWidget.vendor.id == widget.vendor.id) return;
    final future = _load();
    setState(() {
      _future = future;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Product>>(
      future: _future,
      builder: (context, snap) {
        // A suggestion strip is a bonus, never the point of the screen: it
        // stays invisible while it loads and if it fails.
        final items = snap.data ?? const <Product>[];
        if (items.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
              child: Text(
                context.l10n.youMightAlsoLike,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) => ProductSuggestionCard(
                  vendor: widget.vendor,
                  product: items[i],
                  onTap: () =>
                      showProductSheet(context, widget.vendor, items[i]),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}

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
  }) => Container(
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
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ),
        ?action,
      ],
    ),
  );
}
