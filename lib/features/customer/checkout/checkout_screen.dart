import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/tokens.dart';
import '../../../core/models/address.dart';
import '../../../core/repositories/address_repository.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/repositories/payment_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/ui_kit.dart';
import '../cart/cart_cubit.dart';
import 'checkout_cubit.dart';
import 'paymob_flow.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class CheckoutScreen extends StatelessWidget {
  const CheckoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => CheckoutCubit(
        AddressRepository(),
        OrderRepository(),
        PaymentRepository(),
      ),
      child: const _CheckoutView(),
    );
  }
}

class _CheckoutView extends StatefulWidget {
  const _CheckoutView();

  @override
  State<_CheckoutView> createState() => _CheckoutViewState();
}

class _CheckoutViewState extends State<_CheckoutView> {
  final _coupon = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _coupon.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Card orders are held as unpaid until Paymob's webhook confirms payment;
  /// RLS keeps an unpaid card order invisible to the restaurant, and anything
  /// that does not settle is deleted outright.
  Future<void> _onPlaced(CheckoutState state) async {
    final orderId = state.placedOrderId!;
    // Held before the first await: everything below runs after a round trip to
    // Paymob, and reading the context for a string at that point is exactly
    // what `use_build_context_synchronously` warns about.
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final cartCubit = context.read<CartCubit>();
    final checkoutCubit = context.read<CheckoutCubit>();

    if (state.paymentMethod != 'paymob') {
      cartCubit.clear();
      router.pushReplacement('/order/$orderId');
      return;
    }

    Future<void> discard(String message) async {
      await OrderRepository().discardUnpaidOrder(orderId);
      if (!mounted) return;
      checkoutCubit.resetAfterFailedPayment();
      showSnack(context, message, error: true);
    }

    PaymobCheckout checkout;
    try {
      checkout = await PaymentRepository().createOrderCheckout(
        orderId,
        channel: state.paymobChannel,
      );
    } catch (error) {
      await discard(AppFailure.from(error).message(l10n));
      return;
    }
    if (!mounted) return;

    final result = await runPaymobCheckout(router, checkout);
    if (!mounted) return;

    switch (result) {
      case PaymobFlowResult.paid:
        cartCubit.clear();
        router.pushReplacement('/order/$orderId');
      case PaymobFlowResult.cancelled:
        await discard(l10n.paymentCancelledNotice);
      case PaymobFlowResult.failed:
        await discard(l10n.paymentFailedNotice);
      case PaymobFlowResult.unresolved:
        // Keep the order: it is still unpaid and invisible to the restaurant,
        // and the customer can retry or watch it settle from order details.
        cartCubit.clear();
        router.pushReplacement('/order/$orderId');
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.paymentPendingNotice)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartCubit>().state;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.checkout)),
      body: BlocConsumer<CheckoutCubit, CheckoutState>(
        listenWhen: (previous, current) =>
            previous.step != current.step || previous.error != current.error,
        listener: (context, state) {
          if (state.step == CheckoutStep.placed) {
            _onPlaced(state);
          } else if (state.error != null) {
            showFailure(context, state.error!);
          }
        },
        builder: (context, state) {
          if (state.loading) return const _CheckoutSkeleton();
          if (cart.isEmpty) {
            return EmptyView(
              message: context.l10n.yourCartIsEmpty,
              icon: Icons.shopping_cart_outlined,
            );
          }
          final cubit = context.read<CheckoutCubit>();
          final discount = state.couponDiscount ?? 0;
          // Collection has nothing to deliver, so nothing to charge for it.
          // The server recomputes this; the screen must not promise otherwise.
          final deliveryFee = state.chargesDelivery
              ? cart.vendor!.deliveryFee
              : 0.0;
          final total = cart.subtotal - discount + deliveryFee;
          final placing = state.step == CheckoutStep.placing;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  // Bottom padding is the pay bar's job now, not the list's.
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  children: [
                    // What is actually being paid for, before anything else:
                    // the customer should never commit to a total without
                    // seeing the items behind it.
                    _OrderItemsCard(cart: cart),
                    const SizedBox(height: AppSpace.md),
                    // Address section with mini map
                    // Pickup collects at the store, so there is nothing to
                    // deliver to and no address to pick. Requiring one anyway
                    // is why a pickup order used to be blocked at Place Order
                    // with no visible reason.
                    if (!state.isPickup) ...[
                      if (state.addresses.isEmpty)
                        Card(
                          child: ListTile(
                            leading: const Icon(
                              Icons.add_location_alt_outlined,
                              color: AppColors.primary,
                            ),
                            title: Text(context.l10n.addADeliveryAddress),
                            onTap: () => _pickAddress(context, cubit, state),
                          ),
                        )
                      else
                        _AddressCard(
                          address:
                              state.selectedAddress ?? state.addresses.first,
                          onChange: () => _pickAddress(context, cubit, state),
                        ),
                    ],

                    const SizedBox(height: AppSpace.md),
                    _OrderTypePicker(
                      state: state,
                      storeName: cart.vendor!.name,
                      onChanged: cubit.setOrderType,
                      onSchedule: cubit.setScheduledAt,
                    ),
                    const SizedBox(height: AppSpace.md),
                    // A scheduled order has a slot rather than an estimate, so the
                    // estimate would only contradict it.
                    if (!state.isScheduled)
                      _EtaCard(
                        prepMinutes: cart.vendor!.totalPrepMinutes,
                        isPickup: state.isPickup,
                      ),

                    // Payment Section
                    const SizedBox(height: 18),
                    Text(
                      context.l10n.payment,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 11),
                    _PaymentSelectorCard(
                      icon: Icons.account_balance_wallet_rounded,
                      title: context.l10n.payWithWallet,
                      subtitle: state.walletBalance >= total
                          ? '${formatMoney(state.walletBalance)} ${context.l10n.currentBalance}'
                          : '${formatMoney(state.walletBalance)} (${context.l10n.insufficientWalletBalance})',
                      selected: state.paymentMethod == 'wallet',
                      disabled: state.walletBalance < total,
                      onTap: state.walletBalance >= total
                          ? () => cubit.selectPaymentMethod('wallet')
                          : null,
                    ),
                    const SizedBox(height: 9),
                    _PaymentSelectorCard(
                      icon: Icons.payments_rounded,
                      title: context.l10n.cashOnDelivery,
                      subtitle: state.isPickup
                          ? context.l10n.payAtPickup
                          : context.l10n.payTheDriverInEgp,
                      selected: state.paymentMethod == 'cod',
                      onTap: () => cubit.selectPaymentMethod('cod'),
                    ),
                    const SizedBox(height: 9),
                    _PaymentSelectorCard(
                      icon: Icons.credit_card_rounded,
                      title: context.l10n.cardPaymob,
                      subtitle: context.l10n.visaMastercardMeeza,
                      // Both cards below are 'paymob'; the channel is what
                      // separates them, so neither may key its highlight off the
                      // method alone or the two would light up together.
                      selected:
                          state.paymentMethod == 'paymob' &&
                          state.paymobChannel == PaymobChannel.card,
                      onTap: () => cubit.selectPaymentMethod(
                        'paymob',
                        channel: PaymobChannel.card,
                      ),
                    ),
                    const SizedBox(height: 9),
                    _PaymentSelectorCard(
                      icon: Icons.smartphone_rounded,
                      title: context.l10n.mobileWallet,
                      subtitle: context.l10n.mobileWalletProviders,
                      selected:
                          state.paymentMethod == 'paymob' &&
                          state.paymobChannel == PaymobChannel.wallet,
                      onTap: () => cubit.selectPaymentMethod(
                        'paymob',
                        channel: PaymobChannel.wallet,
                      ),
                    ),

                    // Coupon section
                    const SizedBox(height: 18),
                    Text(
                      context.l10n.coupon,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 11),
                    if (state.couponDiscount != null)
                      // Applied Coupon Card
                      AppCard(
                        attention: true,
                        radius: AppRadii.md,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 13,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: AppColors.warmFill,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              alignment: Alignment.center,
                              // Was `l10n.emptyString` — a literal "••••••••" glyph
                              // standing in for an icon that was never drawn.
                              child: const Icon(
                                Icons.local_offer_rounded,
                                size: 16,
                                color: AppColors.primaryDark,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.l10n.couponApplied(
                                      state.couponCode,
                                    ),
                                    style: AppType.mono(
                                      13.5,
                                      color: AppColors.ink,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    context.l10n.youSavedAmount(
                                      formatMoney(state.couponDiscount!),
                                    ),
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.successInk,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: cubit.clearCoupon,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: const Icon(
                                Icons.close,
                                color: AppColors.textFaint,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      // Coupon Entry Form
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _coupon,
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(
                                hintText: context.l10n.couponCode,
                                fillColor: AppColors.surface,
                                errorText: state.couponError != null
                                    ? errorText(context, state.couponError!)
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () => cubit.applyCoupon(
                              _coupon.text,
                              cart.vendor!.id,
                              cart.subtotal,
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              minimumSize: const Size(0, 54),
                            ),
                            child: Text(context.l10n.apply),
                          ),
                        ],
                      ),

                    const Divider(height: 32),
                    TextField(
                      controller: _notes,
                      decoration: InputDecoration(
                        labelText: context.l10n.orderNotesOptional,
                        fillColor: AppColors.surface,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(AppRadii.xl),
                      ),
                      child: Column(
                        children: [
                          _SummaryRow(
                            label: context.l10n.subtotal,
                            value: cart.subtotal,
                          ),
                          if (state.chargesDelivery)
                            _SummaryRow(
                              label: context.l10n.deliveryFee,
                              value: cart.vendor!.deliveryFee,
                            ),
                          if (discount > 0)
                            _SummaryRow(
                              label: context.l10n.discount,
                              value: -discount,
                              highlight: true,
                            ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Divider(),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                context.l10n.total,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              PriceText(formatMoney(total), size: 18),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              // Pinned rather than the last item in the list. Paying was the
              // one action on the screen you had to scroll to the very end to
              // reach, past the coupon box and the summary — and the total it
              // commits you to was down there with it.
              _PayBar(
                total: total,
                placing: placing,
                enabled:
                    !placing &&
                    (state.isPickup || state.selectedAddressId != null) &&
                    (!state.isScheduled || state.scheduledAt != null),
                payNow: state.paymentMethod != 'cod',
                onPressed: () => context.read<CheckoutCubit>().placeOrder(
                  notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OrderItemsCard extends StatefulWidget {
  const _OrderItemsCard({required this.cart});

  final CartState cart;

  @override
  State<_OrderItemsCard> createState() => _OrderItemsCardState();
}

class _OrderItemsCardState extends State<_OrderItemsCard> {
  static const _collapsedCount = 3;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final cart = widget.cart;
    final vendor = cart.vendor!;
    final items = cart.items;
    final visible = _expanded || items.length <= _collapsedCount
        ? items
        : items.take(_collapsedCount).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 6, 12),
            child: Row(
              children: [
                AppNetworkImage(
                  url: vendor.logoUrl,
                  width: 40,
                  height: 40,
                  borderRadius: BorderRadius.circular(12),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.yourOrderFrom(vendor.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.heading(15),
                      ),
                      Text(
                        l10n.itemsCount(cart.itemCount),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  // Checkout is opened from the cart; editing is going back.
                  onPressed: () =>
                      context.canPop() ? context.pop() : context.go('/cart'),
                  child: Text(l10n.edit),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.borderSoft),
          for (final item in visible)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    constraints: const BoxConstraints(minWidth: 30),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warmFill,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${item.quantity}×',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.product.displayName(language),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                        if (item.selectedOptions.isNotEmpty)
                          Text(
                            item.selectedOptions.map((o) => o.name).join('، '),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        if (item.notes?.isNotEmpty ?? false)
                          Text(
                            '"${item.notes!}"',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: AppColors.textFaint,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  PriceText(formatMoney(item.lineTotal), size: 13.5),
                ],
              ),
            ),
          if (items.length > _collapsedCount)
            TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
              ),
              label: Text(
                _expanded ? l10n.showLess : l10n.showAllItems(items.length),
              ),
            )
          else
            const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final double value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? AppColors.successInk : AppColors.ink;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          PriceText(formatMoney(value), color: color, weight: FontWeight.w600),
        ],
      ),
    );
  }
}

/// Where the order is going.
///
/// The map header is the user's REAL pin on real tiles, and only appears when
/// the address actually carries coordinates. The previous version painted three
/// grey lines and a pin at fixed pixel offsets — identical for every address in
/// the country, which made "check your address" impossible to actually do.
/// Opens the address list in pick mode, pre-marking whatever is already
/// selected, and applies the result — either an existing address the
/// customer tapped, or a brand-new one they just drew on the map.
///
/// Previously "Change" reopened the same manage-addresses list with no way
/// to report a choice back, so the delivery address on checkout could never
/// actually be changed once one existed.
Future<void> _pickAddress(
  BuildContext context,
  CheckoutCubit cubit,
  CheckoutState state,
) async {
  final pickedId = await context.push<String>(
    '/addresses',
    extra: state.selectedAddressId,
  );
  if (pickedId != null) {
    cubit.selectAddress(pickedId);
  } else {
    // Nothing picked, but an address may have been edited or deleted while
    // the list was open — refresh so the card reflects that.
    cubit.loadAddresses();
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.address, required this.onChange});

  final Address address;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final lat = address.lat;
    final lng = address.lng;
    final point = lat != null && lng != null ? LatLng(lat, lng) : null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (point != null)
            SizedBox(
              height: 84,
              // Non-interactive: this is a confirmation glance, not a picker —
              // moving the pin lives behind "Change".
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: point,
                  initialZoom: 15,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.multi_vendor',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: point,
                        width: 34,
                        height: 34,
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: AppColors.primary,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on,
                  color: AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        address.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        address.summary,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: onChange,
                  child: Text(
                    context.l10n.change,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The delivery window, computed from this store's prep time and the clock.
///
/// Was a hardcoded "Standard · 25–35 min / Arrives by 9:35 PM" beside a radio
/// that was always checked and could not be unchecked — a fake estimate next to
/// a fake choice. There is no scheduled-delivery feature to choose between, so
/// the radio is gone and the numbers are now real.
class _EtaCard extends StatelessWidget {
  const _EtaCard({required this.prepMinutes, required this.isPickup});

  final int prepMinutes;

  /// Pickup has no delivery leg to add, and the arrival time below is the
  /// customer's own trip, not the store's — the estimate over-promised by the
  /// delivery buffer and then contradicted itself with a driver-shaped label.
  final bool isPickup;

  @override
  Widget build(BuildContext context) {
    final earliest = prepMinutes;
    // Prep, plus a delivery leg — skipped for pickup. The spread is the
    // honest part of an estimate.
    final latest = isPickup ? prepMinutes : prepMinutes + 10;
    final arrival = DateTime.now().add(Duration(minutes: latest));

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.access_time_filled, color: AppColors.ink, size: 19),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$earliest–$latest ${context.l10n.minShort}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  DateFormat.jm().format(arrival),
                  style: AppType.mono(
                    12,
                    color: AppColors.textMuted,
                    weight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Checkout while addresses and the wallet balance load. Shaped like the real
/// page: address block, ETA row, three payment rows, totals, CTA.
class _CheckoutSkeleton extends StatelessWidget {
  const _CheckoutSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonTheme(
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: const [
          Skeleton.box(height: 140, radius: AppRadii.lg),
          SizedBox(height: AppSpace.md),
          Skeleton.box(height: 62, radius: AppRadii.md),
          SizedBox(height: AppSpace.lg + 2),
          Skeleton.line(widthFactor: 0.3, height: 16),
          SizedBox(height: 11),
          Skeleton.box(height: 68, radius: AppRadii.md),
          SizedBox(height: 9),
          Skeleton.box(height: 68, radius: AppRadii.md),
          SizedBox(height: 9),
          Skeleton.box(height: 68, radius: AppRadii.md),
          SizedBox(height: AppSpace.lg + 2),
          Skeleton.line(widthFactor: 0.25, height: 16),
          SizedBox(height: 11),
          Skeleton.box(height: 54, radius: AppRadii.md),
          SizedBox(height: AppSpace.xxl),
          Skeleton.box(height: 128, radius: AppRadii.xl),
          SizedBox(height: AppSpace.lg),
          Skeleton.box(height: 54, radius: AppRadii.lg),
        ],
      ),
    );
  }
}

/// The total and the one action, always on screen.
class _PayBar extends StatelessWidget {
  const _PayBar({
    required this.total,
    required this.placing,
    required this.enabled,
    required this.payNow,
    required this.onPressed,
  });

  final double total;
  final bool placing;
  final bool enabled;

  /// Cash on delivery places the order and stops; every other method hands
  /// over to a payment page, and the button should say which is about to
  /// happen before it is pressed.
  final bool payNow;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.total,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                ),
              ),
              PriceText(formatMoney(total), size: 19),
            ],
          ),
          const SizedBox(width: AppSpace.lg),
          Expanded(
            child: FilledButton(
              onPressed: enabled ? onPressed : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: placing
                  ? const ButtonSpinner()
                  : Text(payNow ? l10n.placeOrderAndPay : l10n.placeOrder),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentSelectorCard extends StatelessWidget {
  /// A real icon rather than an emoji. Emoji render differently on every
  /// platform and font, so the payment picker — the one place a customer
  /// decides whether to trust the screen with their money — looked different
  /// on each device and matched nothing else in the app.
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  const _PaymentSelectorCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.disabled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            // Tinted rather than thickened. A border that grows from 1px to
            // 2px on selection nudges the row's contents by a pixel, so the
            // list twitches every time the choice changes.
            color: disabled
                ? AppColors.neutralFill
                : selected
                ? AppColors.warmFill
                : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected ? AppColors.warmFill : AppColors.neutralFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 19,
                  color: selected ? AppColors.primary : AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : AppColors.borderStrong,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: selected
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Delivery, collection, or a slot for later.
///
/// The screen previously carried a single always-checked radio next to a
/// hardcoded estimate — a fake choice beside a fake number. These are the
/// three the server actually supports, and each changes what the order costs
/// or when it is made.
class _OrderTypePicker extends StatelessWidget {
  const _OrderTypePicker({
    required this.state,
    required this.storeName,
    required this.onChanged,
    required this.onSchedule,
  });

  final CheckoutState state;
  final String storeName;
  final ValueChanged<String> onChanged;
  final ValueChanged<DateTime?> onSchedule;

  /// [fallbackType] is where to land if the customer backs out of either
  /// picker. Cancelling used to leave the segmented control on "Scheduled"
  /// with no time chosen — Place Order stayed enabled, and the order would
  /// have gone to the server as scheduled for nothing.
  Future<void> _pickSlot(BuildContext context, String fallbackType) async {
    final now = DateTime.now();
    // The server refuses anything sooner than 45 minutes, so the picker does
    // not offer it — a rejection the customer could have been spared.
    final earliest = now.add(const Duration(minutes: 45));
    final date = await showDatePicker(
      context: context,
      initialDate: earliest,
      firstDate: earliest,
      lastDate: now.add(const Duration(days: 7)),
    );
    if (date == null) {
      if (context.mounted) onChanged(fallbackType);
      return;
    }
    if (!context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(earliest),
    );
    if (time == null) {
      onChanged(fallbackType);
      return;
    }

    final slot = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    // Picking today plus an early hour would land before the floor.
    onSchedule(slot.isBefore(earliest) ? earliest : slot);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: 'delivery',
              icon: const Icon(Icons.delivery_dining_outlined, size: 18),
              label: Text(l10n.orderTypeDelivery),
            ),
            ButtonSegment(
              value: 'pickup',
              icon: const Icon(Icons.storefront_outlined, size: 18),
              label: Text(l10n.orderTypePickup),
            ),
            ButtonSegment(
              value: 'scheduled',
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: Text(l10n.orderTypeScheduled),
            ),
          ],
          selected: {state.orderType},
          onSelectionChanged: (selection) {
            final type = selection.first;
            final previousType = state.orderType;
            onChanged(type);
            if (type == 'scheduled') _pickSlot(context, previousType);
          },
        ),
        if (state.isPickup) ...[
          const SizedBox(height: AppSpace.sm),
          _Note(
            icon: Icons.storefront_outlined,
            text: '${l10n.pickupCollectAt(storeName)} · ${l10n.pickupNoFee}',
          ),
        ],
        if (state.isScheduled) ...[
          const SizedBox(height: AppSpace.sm),
          InkWell(
            // Re-tapping the note has nothing sensible to fall back to but
            // staying scheduled — the customer is already committed to this
            // order type and is only here to fix or confirm the time.
            onTap: () => _pickSlot(context, 'scheduled'),
            borderRadius: BorderRadius.circular(AppRadii.lg),
            child: _Note(
              icon: Icons.schedule_rounded,
              text: state.scheduledAt == null
                  ? '${l10n.scheduleForLater} · ${l10n.scheduleHint}'
                  : l10n.scheduledFor(
                      DateFormat.MMMEd().add_jm().format(state.scheduledAt!),
                    ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.warmFill,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.primaryDark),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
