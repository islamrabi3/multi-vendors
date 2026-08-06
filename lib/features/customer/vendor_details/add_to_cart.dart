import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/cart_item.dart';
import '../../../core/models/product.dart';
import '../../../core/models/vendor.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../cart/cart_cubit.dart';
import 'product_sheet.dart';

/// What the "+" on a product does.
///
/// An item with no choices to make has nothing to ask about, so opening a
/// sheet to confirm a decision the customer has already expressed is a step
/// for its own sake. Those go straight into the cart. An item with option
/// groups still opens the sheet, because the cart line is not decidable
/// without them — a size or a required topping changes what is being bought
/// and what it costs.
///
/// Tapping the row itself always opens the sheet: that is the request to read
/// the description and the options, not to buy.
Future<void> quickAddOrConfigure(
  BuildContext context,
  Vendor vendor,
  Product product,
) async {
  if (product.optionGroups.isNotEmpty) {
    return showProductSheet(context, vendor, product);
  }
  await addCartItem(
    context,
    vendor,
    CartItem(product: product, quantity: 1),
  );
}

/// Puts one line into the cart, asking first when it belongs to another store.
///
/// Shared by the sheet and by quick-add so the cart-conflict rule cannot be
/// enforced in one path and forgotten in the other — a silently dropped item
/// is the worst outcome here, because the customer believes they have ordered.
///
/// Returns true when the item made it into the cart.
Future<bool> addCartItem(
  BuildContext context,
  Vendor vendor,
  CartItem item, {
  bool showConfirmation = true,
}) async {
  final cart = context.read<CartCubit>();
  if (cart.conflictsWithCart(vendor)) {
    // Clearing a cart is destructive, but the customer asked for the new item —
    // `danger` tone, and "Keep cart" is the safe way out.
    final replace = await showConfirmDialog(
      context: context,
      title: context.l10n.startANewCart,
      message: context.l10n.cartFromOtherStore(cart.state.vendor!.name),
      confirmLabel: context.l10n.startNewCart,
      cancelLabel: context.l10n.keepCart,
      tone: AppDialogTone.danger,
      icon: Icons.remove_shopping_cart_rounded,
    );
    if (!replace || !context.mounted) return false;
    cart.startNewCart(vendor, item);
    return true;
  }
  cart.addItem(vendor, item);
  if (showConfirmation && context.mounted) {
    showSnack(context, context.l10n.addedToCart);
  }
  return true;
}
