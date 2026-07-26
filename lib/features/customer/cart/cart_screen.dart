import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import 'cart_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.ink, size: 20),
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
                                  item.product.name,
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
                      const SizedBox(height: 14),
                      InkWell(
                        onTap: () => context.push('/checkout'),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          height: 54,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: AppShadows.primaryGlow,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                context.l10n.goToCheckout,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              PriceText(
                                formatMoney(cart.subtotal),
                                size: 15,
                                color: Colors.white,
                              ),
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

