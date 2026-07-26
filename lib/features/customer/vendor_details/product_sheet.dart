import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/tokens.dart';
import '../../../core/models/cart_item.dart';
import '../../../core/models/product.dart';
import '../../../core/models/vendor.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../cart/cart_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

Future<void> showProductSheet(
    BuildContext context, Vendor vendor, Product product) {
  final cartCubit = context.read<CartCubit>();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BlocProvider.value(
      value: cartCubit,
      child: _ProductSheet(vendor: vendor, product: product),
    ),
  );
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

  List<ProductOption> get _selectedOptions =>
      [for (final set in _selections.values) ...set];

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

  void _addToCart() {
    final cart = context.read<CartCubit>();
    final item = CartItem(
      product: product,
      quantity: _quantity,
      selectedOptions: _selectedOptions,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    if (cart.conflictsWithCart(widget.vendor)) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.l10n.startANewCart),
          content: Text(
              'Your cart has items from ${cart.state.vendor!.name}. '
              'Adding this item will clear it.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(context.l10n.keepCart)),
            FilledButton(
              onPressed: () {
                cart.startNewCart(widget.vendor, item);
                Navigator.pop(dialogContext);
                Navigator.pop(context);
              },
              child: Text(context.l10n.startNewCart),
            ),
          ],
        ),
      );
      return;
    }
    cart.addItem(widget.vendor, item);
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
                      borderRadius: BorderRadius.circular(16)),
                const SizedBox(height: 12),
                Text(product.name,
                    style: Theme.of(context).textTheme.displaySmall),
                if (product.description?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 6),
                  Text(product.description!,
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
                const SizedBox(height: 12),
                PriceText(formatMoney(product.price), size: 18),
                for (final group in product.optionGroups) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(group.name,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(width: 8),
                      if (group.isRequired)
                        SoftBadge(
                            label: context.l10n.required,
                            fill: AppColors.warmFill,
                            ink: AppColors.primaryDark)
                      else
                        Text('Optional · up to ${group.maxSelect}',
                            style: const TextStyle(
                                color: AppColors.textFaint, fontSize: 12)),
                    ],
                  ),
                  Column(
                    children: [
                      for (final option in group.options.where((o) => o.isAvailable))
                        _OptionTile(
                          name: option.name,
                          priceDelta: option.priceDelta,
                          selected: (_selections[group.id] ?? {}).contains(option),
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
                      labelText: context.l10n.notesEgNoOnions),
                ),
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
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(context.l10n.addToCart),
                          const SizedBox(width: 8),
                          PriceText(formatMoney(_unitPrice * _quantity),
                              size: 15, color: Colors.white),
                        ],
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
          color: Colors.white,
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
              priceDelta != 0
                  ? '$name · +${formatMoney(priceDelta)}'
                  : name,
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
                  color: selected ? AppColors.primary : const Color(0xFFDDD4CB),
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: selected
                  ? const Icon(
                      Icons.check,
                      size: 13,
                      color: Colors.white,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
