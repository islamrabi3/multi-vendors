import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/cart_item.dart';
import '../../../core/models/product.dart';
import '../../../core/models/vendor.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../cart/cart_cubit.dart';

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
          title: const Text('Start a new cart?'),
          content: Text(
              'Your cart has items from ${cart.state.vendor!.name}. '
              'Adding this item will clear it.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Keep cart')),
            FilledButton(
              onPressed: () {
                cart.startNewCart(widget.vendor, item);
                Navigator.pop(dialogContext);
                Navigator.pop(context);
              },
              child: const Text('Start new cart'),
            ),
          ],
        ),
      );
      return;
    }
    cart.addItem(widget.vendor, item);
    Navigator.pop(context);
    showSnack(context, 'Added to cart');
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
                Row(
                  children: [
                    Expanded(
                      child: Text(product.name,
                          style: Theme.of(context).textTheme.headlineSmall),
                    ),
                    Text(formatMoney(product.price),
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                if (product.description?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 8),
                  Text(product.description!),
                ],
                for (final group in product.optionGroups) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(group.name,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(width: 8),
                      if (group.isRequired)
                        const Text('Required',
                            style: TextStyle(color: Colors.red, fontSize: 12))
                      else
                        Text('Up to ${group.maxSelect}',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  if (group.isSingleChoice)
                    RadioGroup<ProductOption>(
                      groupValue: (_selections[group.id] ?? {}).firstOrNull,
                      onChanged: (option) {
                        if (option != null) _toggleOption(group, option);
                      },
                      child: Column(
                        children: [
                          for (final option
                              in group.options.where((o) => o.isAvailable))
                            RadioListTile<ProductOption>(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(option.name),
                              secondary: option.priceDelta != 0
                                  ? Text('+${formatMoney(option.priceDelta)}')
                                  : null,
                              value: option,
                            ),
                        ],
                      ),
                    )
                  else
                    for (final option
                        in group.options.where((o) => o.isAvailable))
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(option.name),
                        secondary: option.priceDelta != 0
                            ? Text('+${formatMoney(option.priceDelta)}')
                            : null,
                        value: (_selections[group.id] ?? {}).contains(option),
                        onChanged: (_) => _toggleOption(group, option),
                      ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _notes,
                  decoration: const InputDecoration(
                      labelText: 'Notes (e.g. no onions)'),
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
                      child: Text(
                          'Add · ${formatMoney(_unitPrice * _quantity)}'),
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
