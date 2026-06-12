import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import 'cart_cubit.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cart'),
        actions: [
          BlocBuilder<CartCubit, CartState>(
            builder: (context, cart) => cart.isEmpty
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: context.read<CartCubit>().clear,
                    child: const Text('Clear'),
                  ),
          ),
        ],
      ),
      body: BlocBuilder<CartCubit, CartState>(
        builder: (context, cart) {
          if (cart.isEmpty) {
            return const EmptyView(
                message: 'Your cart is empty',
                icon: Icons.shopping_cart_outlined);
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    const Icon(Icons.storefront_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(cart.vendor!.name,
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: cart.items.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final item = cart.items[index];
                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.product.name,
                                  style:
                                      Theme.of(context).textTheme.titleSmall),
                              if (item.selectedOptions.isNotEmpty)
                                Text(
                                  item.selectedOptions
                                      .map((o) => o.name)
                                      .join(', '),
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                              if (item.notes != null)
                                Text('"${item.notes}"',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            fontStyle: FontStyle.italic)),
                              const SizedBox(height: 4),
                              Text(formatMoney(item.lineTotal),
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        QuantityStepper(
                          quantity: item.quantity,
                          min: 0,
                          onChanged: (q) => context
                              .read<CartCubit>()
                              .updateQuantity(item, q),
                        ),
                      ],
                    );
                  },
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Subtotal'),
                          Text(formatMoney(cart.subtotal),
                              style:
                                  Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => context.push('/checkout'),
                        child: const Text('Checkout'),
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
