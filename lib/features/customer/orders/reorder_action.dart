import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/order.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/utils/l10n_extension.dart';
import '../cart/cart_cubit.dart';

/// "Order again", for the orders list and for order details.
///
/// Both used to call a repository method that wrote rows into the `carts`
/// tables and then pushed `/cart` — but the cart screen reads [CartCubit],
/// which is only loaded from the server at sign-in, so the customer arrived at
/// an empty cart. Rebuilding through the cubit is what makes the button do
/// what it says, and doing it here keeps the two entry points identical.
///
/// The whole flow, in order: rebuild against today's menu, refuse if nothing
/// survives, warn if the store is shut, confirm before discarding a cart from
/// somewhere else, then apply, report what was dropped, and navigate.
Future<void> reorderIntoCart(BuildContext context, AppOrder order) async {
  final l10n = context.l10n;
  final cart = context.read<CartCubit>();
  final router = GoRouter.of(context);

  final draft = await showBlockingProgress(
    context,
    () => OrderRepository().buildReorderDraft(order),
  );
  if (draft == null || !context.mounted) return;

  // Nothing on the order is still sold. Saying so beats dropping the customer
  // on an empty cart, which is exactly the bug this replaces.
  if (draft.isEmpty) {
    await showInfoDialog(
      context: context,
      title: l10n.reorderTitle,
      message: draft.vendor.isActive
          ? l10n.reorderNothingAvailable
          : l10n.reorderStoreInactive(draft.vendor.name),
      icon: Icons.remove_shopping_cart_outlined,
      tone: AppDialogTone.danger,
      dismissLabel: l10n.okLabel,
    );
    return;
  }

  // A closed store still lets you fill a cart — the order simply cannot be
  // placed until it opens — so this asks rather than refuses.
  if (!draft.vendor.isOpenNow()) {
    final proceed = await AppDialogs.showConfirmDialog(
      context: context,
      title: draft.vendor.name,
      message: l10n.reorderStoreClosed(draft.vendor.name),
      confirmText: l10n.addAnyway,
      cancelText: l10n.cancel,
      isDestructive: false,
      icon: Icons.schedule_rounded,
    );
    if (proceed != true || !context.mounted) return;
  }

  // Carts are single-store, so this one costs the customer whatever they had.
  if (cart.conflictsWithCart(draft.vendor)) {
    final replace = await AppDialogs.showConfirmDialog(
      context: context,
      title: l10n.reorderTitle,
      message: l10n.reorderReplaceCart(cart.state.vendor?.name ?? ''),
      confirmText: l10n.replaceCart,
      cancelText: l10n.cancel,
      icon: Icons.shopping_cart_outlined,
    );
    if (replace != true || !context.mounted) return;
  }

  cart.replaceWith(draft.vendor, draft.items);

  // What was left out, said once and plainly, before the cart screen opens.
  if (draft.isPartial) {
    showSnack(
      context,
      draft.unavailable.isNotEmpty
          ? l10n.reorderSomeMissing(draft.unavailable.length)
          : l10n.reorderOptionsChanged,
    );
  } else {
    showSnack(context, l10n.reorderAdded);
  }

  router.push('/cart');
}
