import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/tokens.dart';
import '../../../core/models/cart_item.dart';
import '../../../core/models/product.dart';
import '../../../core/models/vendor.dart';
import '../cart/cart_cubit.dart';
import 'add_to_cart.dart';
import 'product_sheet.dart';

/// The "+" on a product, which becomes a stepper once the item is in the cart.
///
/// Collapsed it is a single +. After the first tap it expands to `− n +`, and
/// stepping back down to zero collapses it again — so the whole quantity can be
/// set from the menu without opening anything.
///
/// Two cases do not get a stepper:
///
/// * An item with option groups. Its + opens the sheet every time, because a
///   second one is not necessarily the same thing — a different size or topping
///   is a different line at a different price.
/// * An item already in the cart as more than one configured line. The count is
///   shown, but − is hidden: there is no answer to which of "large, extra
///   cheese" and "small, no onions" a minus was meant to remove, and picking
///   one silently is worse than not offering it.
class ProductQuantityControl extends StatelessWidget {
  const ProductQuantityControl({
    super.key,
    required this.vendor,
    required this.product,
    this.compact = false,
    this.onConfigure,
  });

  final Vendor vendor;
  final Product product;

  /// Smaller geometry for the related-products carousel.
  final bool compact;

  /// What to run when the product needs the sheet. Defaults to opening it.
  /// The related-products carousel overrides this: it must close its own sheet
  /// and let the caller reopen, rather than stack a second one.
  final VoidCallback? onConfigure;

  double get _size => compact ? 28 : 32;
  double get _iconSize => compact ? 16 : 18;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CartCubit, CartState>(
      builder: (context, cart) {
        // Only lines from this store count. A cart belonging to another vendor
        // is about to be replaced, so its contents say nothing about this item.
        final lines = cart.vendor?.id == vendor.id
            ? cart.items.where((i) => i.product.id == product.id).toList()
            : const <CartItem>[];
        final quantity = lines.fold<int>(0, (sum, i) => sum + i.quantity);

        final needsSheet = product.optionGroups.isNotEmpty;
        final canStep = lines.length == 1 && !needsSheet;

        void onPlus() {
          if (needsSheet) {
            (onConfigure ?? () => showProductSheet(context, vendor, product))();
            return;
          }
          if (canStep) {
            context.read<CartCubit>().updateQuantity(
              lines.first,
              lines.first.quantity + 1,
            );
            return;
          }
          addCartItem(
            context,
            vendor,
            CartItem(product: product, quantity: 1),
            // The stepper appearing in place of the + is the confirmation.
            showConfirmation: false,
          );
        }

        void onMinus() {
          final line = lines.first;
          // updateQuantity removes the line at zero, which collapses this back
          // to a plain +.
          context.read<CartCubit>().updateQuantity(line, line.quantity - 1);
        }

        return AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: AlignmentDirectional.centerEnd,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_size / 2),
              boxShadow: AppShadows.primaryGlow,
            ),
            child: Material(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(_size / 2),
              clipBehavior: Clip.antiAlias,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (quantity > 0 && canStep)
                    _TapIcon(
                      icon: quantity == 1
                          ? Icons.delete_outline_rounded
                          : Icons.remove,
                      size: _size,
                      iconSize: _iconSize,
                      onTap: onMinus,
                    ),
                  if (quantity > 0)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: canStep ? 0 : 8,
                      ),
                      child: SizedBox(
                        width: canStep ? 22 : null,
                        child: Text(
                          '$quantity',
                          textAlign: TextAlign.center,
                          style: AppType.mono(
                            compact ? 13 : 14,
                            weight: FontWeight.w700,
                          ).copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  _TapIcon(
                    icon: Icons.add,
                    size: _size,
                    iconSize: _iconSize,
                    onTap: onPlus,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TapIcon extends StatelessWidget {
  const _TapIcon({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, size: iconSize, color: Colors.white),
      ),
    );
  }
}
