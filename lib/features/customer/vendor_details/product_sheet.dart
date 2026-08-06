import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/tokens.dart';
import '../../../core/models/cart_item.dart';
import '../../../core/models/product.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../cart/cart_cubit.dart';
import 'add_to_cart.dart';
import 'product_suggestion_card.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

Future<void> showProductSheet(
  BuildContext context,
  Vendor vendor,
  Product product,
) async {
  final cartCubit = context.read<CartCubit>();
  // A related item pops this sheet and hands its product back, rather than
  // opening the next sheet itself. It cannot open it: by the time it would,
  // its own context has been unmounted by the pop, so the call reaches a dead
  // element and nothing happens. Reopening from here uses the caller's
  // context — the screen, which is still there.
  final next = await showModalBottomSheet<Product>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BlocProvider.value(
      value: cartCubit,
      child: _ProductSheet(vendor: vendor, product: product),
    ),
  );
  if (next != null && context.mounted) {
    await showProductSheet(context, vendor, next);
  }
}

class _ProductSheet extends StatefulWidget {
  const _ProductSheet({required this.vendor, required this.product});

  final Vendor vendor;
  final Product product;

  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  final _notes = TextEditingController();
  final Map<String, Set<ProductOption>> _selections = {};
  int _quantity = 1;

  Product get product => widget.product;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  List<ProductOption> get _selectedOptions => [
    for (final set in _selections.values) ...set,
  ];

  double get _unitPrice =>
      product.price +
      _selectedOptions.fold<double>(0, (sum, o) => sum + o.priceDelta);

  bool get _selectionValid => product.optionGroups.every((group) {
    final count = _selections[group.id]?.length ?? 0;
    return count >= group.minSelect && count <= group.maxSelect;
  });

  void _toggleOption(ProductOptionGroup group, ProductOption option) {
    setState(() {
      final selected = _selections.putIfAbsent(group.id, () => {});
      if (group.isSingleChoice) {
        selected
          ..clear()
          ..add(option);
      } else if (selected.contains(option)) {
        selected.remove(option);
      } else if (selected.length < group.maxSelect) {
        selected.add(option);
      }
    });
  }

  Future<void> _addToCart() async {
    final item = CartItem(
      product: product,
      quantity: _quantity,
      selectedOptions: _selectedOptions,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    // The snack is raised after this sheet closes, not from under it.
    final added = await addCartItem(
      context,
      widget.vendor,
      item,
      showConfirmation: false,
    );
    if (!added || !mounted) return;
    Navigator.pop(context);
    showSnack(context, context.l10n.addedToCart);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                if (product.imageUrl != null)
                  AppNetworkImage(
                    url: product.imageUrl,
                    height: 180,
                    width: double.infinity,
                    borderRadius: BorderRadius.circular(16),
                  ),
                const SizedBox(height: 12),
                Text(
                  product.displayName(
                    Localizations.localeOf(context).languageCode,
                  ),
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                if (product.displayDescription(
                      Localizations.localeOf(context).languageCode,
                    )
                    case final description?) ...[
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 12),
                PriceText(formatMoney(product.price), size: 18),
                for (final group in product.optionGroups) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        group.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 8),
                      if (group.isRequired)
                        SoftBadge(
                          label: context.l10n.required,
                          fill: AppColors.warmFill,
                          ink: AppColors.primaryDark,
                        )
                      else
                        Text(
                          context.l10n.optionalUpTo(group.maxSelect),
                          style: const TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  Column(
                    children: [
                      for (final option in group.options.where(
                        (o) => o.isAvailable,
                      ))
                        _OptionTile(
                          name: option.name,
                          priceDelta: option.priceDelta,
                          selected: (_selections[group.id] ?? {}).contains(
                            option,
                          ),
                          isRadio: group.isSingleChoice,
                          onTap: () => _toggleOption(group, option),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _notes,
                  decoration: InputDecoration(
                    labelText: context.l10n.notesEgNoOnions,
                  ),
                ),
                // Under the note field rather than above the price: the
                // customer has decided on this item by the time they get here,
                // so a suggestion reads as "anything else" instead of
                // competing with what they came for.
                _RelatedProducts(vendor: widget.vendor, product: product),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  QuantityStepper(
                    quantity: _quantity,
                    onChanged: (q) => setState(() => _quantity = q),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: _selectionValid ? _addToCart : null,
                      // Scaled rather than ellipsised: neither half of this
                      // label can be cut. A truncated price is the number the
                      // customer is about to be charged, and the Arabic label
                      // ("أضف إلى السلة") loses a whole word before it loses a
                      // letter. It runs out of room on narrow phones once the
                      // quantity pushes the total into four digits.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(context.l10n.addToCart),
                            const SizedBox(width: 8),
                            PriceText(
                              formatMoney(_unitPrice * _quantity),
                              size: 15,
                              color: Colors.white,
                            ),
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
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String name;
  final double priceDelta;
  final bool selected;
  final bool isRadio;
  final VoidCallback onTap;

  const _OptionTile({
    required this.name,
    required this.priceDelta,
    required this.selected,
    required this.isRadio,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2.0 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              priceDelta != 0 ? '$name · +${formatMoney(priceDelta)}' : name,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 14,
                color: AppColors.ink,
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: isRadio ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: isRadio ? null : BorderRadius.circular(7),
                color: selected ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.borderStrong,
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: selected
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Goes well with" — what people who ordered this also ordered.
///
/// Loaded per sheet rather than with the menu: most customers never open an
/// item sheet at all, and the ranking needs the whole platform's order history
/// behind it, which is not something to ship down with a store page.
class _RelatedProducts extends StatefulWidget {
  const _RelatedProducts({required this.vendor, required this.product});

  final Vendor vendor;
  final Product product;

  @override
  State<_RelatedProducts> createState() => _RelatedProductsState();
}

class _RelatedProductsState extends State<_RelatedProducts> {
  late final Future<List<Product>> _future = CatalogRepository()
      .relatedProducts(widget.product.id);

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
            const SizedBox(height: 22),
            Text(
              context.l10n.goesWellWith,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final item = items[i];
                  // Both taps replace this sheet instead of stacking a second
                  // one on top: two half-open item sheets is a trap the back
                  // button has to be pressed twice to escape. The caller
                  // reopens it — see showProductSheet.
                  return ProductSuggestionCard(
                    vendor: widget.vendor,
                    product: item,
                    onTap: () => Navigator.pop(context, item),
                    onConfigure: () => Navigator.pop(context, item),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
