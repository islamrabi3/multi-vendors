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
          AddressRepository(), OrderRepository(), PaymentRepository()),
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
      checkout = await PaymentRepository().createOrderCheckout(orderId);
    } catch (error) {
      await discard(readableError(error.toString()));
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
        await discard(
            'Payment cancelled. The order was not sent to the restaurant.');
      case PaymobFlowResult.failed:
        await discard(
            'Payment failed. The order was not sent to the restaurant.');
      case PaymobFlowResult.unresolved:
        // Keep the order: it is still unpaid and invisible to the restaurant,
        // and the customer can retry or watch it settle from order details.
        cartCubit.clear();
        router.pushReplacement('/order/$orderId');
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
                'Still confirming your payment with the bank. The restaurant '
                'is notified only once it is confirmed.'),
          ),
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
            showSnack(context, readableError(state.error!), error: true);
          }
        },
        builder: (context, state) {
          if (state.loading) return const _CheckoutSkeleton();
          if (cart.isEmpty) {
            return EmptyView(
                message: context.l10n.yourCartIsEmpty,
                icon: Icons.shopping_cart_outlined);
          }
          final cubit = context.read<CheckoutCubit>();
          final discount = state.couponDiscount ?? 0;
          final total =
              cart.subtotal - discount + cart.vendor!.deliveryFee;
          return ListView(
            // The place-order button is the last item, so the list has to
            // clear Android's gesture bar itself — this screen has no
            // bottomNavigationBar for Scaffold to inset.
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
            children: [
              // Address section with mini map
              if (state.addresses.isEmpty)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.add_location_alt_outlined, color: AppColors.primary),
                    title: Text(context.l10n.addADeliveryAddress),
                    onTap: () async {
                      await context.push('/addresses');
                      cubit.loadAddresses();
                    },
                  ),
                )
              else
                _AddressCard(
                  address: state.selectedAddress ?? state.addresses.first,
                  onChange: () async {
                    await context.push('/addresses');
                    cubit.loadAddresses();
                  },
                ),

              const SizedBox(height: AppSpace.md),
              _EtaCard(prepMinutes: cart.vendor!.totalPrepMinutes),

              // Payment Section
              const SizedBox(height: 18),
              Text(
                context.l10n.payment,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 11),
              _PaymentSelectorCard(
                emoji: '👛',
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
                emoji: '💵',
                title: context.l10n.cashOnDelivery,
                subtitle: context.l10n.payTheDriverInEgp,
                selected: state.paymentMethod == 'cod',
                onTap: () => cubit.selectPaymentMethod('cod'),
              ),
              const SizedBox(height: 9),
              _PaymentSelectorCard(
                emoji: '💳',
                title: context.l10n.cardPaymob,
                subtitle: context.l10n.visaMastercardMeeza,
                selected: state.paymentMethod == 'paymob',
                onTap: () => cubit.selectPaymentMethod('paymob'),
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
                      horizontal: 15, vertical: 13),
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
                        child: const Icon(Icons.local_offer_rounded,
                            size: 16, color: AppColors.primaryDark),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.couponApplied(state.couponCode),
                              style: AppType.mono(13.5, color: AppColors.ink, weight: FontWeight.w700),
                            ),
                            Text(
                              context.l10n.youSavedAmount(formatMoney(state.couponDiscount!)),
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
                        icon: const Icon(Icons.close, color: AppColors.textFaint, size: 18),
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
                              ? readableError(state.couponError!)
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
                        padding: const EdgeInsets.symmetric(horizontal: 20),
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
                    _SummaryRow(label: context.l10n.subtotal, value: cart.subtotal),
                    _SummaryRow(
                        label: context.l10n.deliveryFee,
                        value: cart.vendor!.deliveryFee),
                    if (discount > 0)
                      _SummaryRow(
                          label: context.l10n.discount,
                          value: -discount,
                          highlight: true),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(context.l10n.total,
                            style: Theme.of(context).textTheme.titleLarge),
                        PriceText(formatMoney(total), size: 18),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: state.step == CheckoutStep.placing ||
                          state.selectedAddressId == null
                      ? null
                      : () => context.read<CheckoutCubit>().placeOrder(
                            notes: _notes.text.trim().isEmpty
                                ? null
                                : _notes.text.trim()),
                  child: state.step == CheckoutStep.placing
                      ? const ButtonSpinner()
                      : Text(state.paymentMethod == 'cod'
                          ? context.l10n.placeOrder
                          : context.l10n.placeOrderAndPay),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
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
                  interactionOptions:
                      const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.multi_vendor',
                  ),
                  MarkerLayer(markers: [
                    Marker(
                      point: point,
                      width: 34,
                      height: 34,
                      child: const Icon(Icons.location_on_rounded,
                          color: AppColors.primary, size: 30),
                    ),
                  ]),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            child: Row(
              children: [
                const Icon(Icons.location_on,
                    color: AppColors.primary, size: 18),
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
  const _EtaCard({required this.prepMinutes});

  final int prepMinutes;

  @override
  Widget build(BuildContext context) {
    // Prep, plus a delivery leg. The spread is the honest part of an estimate.
    final earliest = prepMinutes;
    final latest = prepMinutes + 10;
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
                  style: AppType.mono(12,
                      color: AppColors.textMuted, weight: FontWeight.w500),
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

class _PaymentSelectorCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  const _PaymentSelectorCard({
    required this.emoji,
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
            color: disabled ? AppColors.neutralFill : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2.0 : 1.0,
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
              child: Text(emoji, style: const TextStyle(fontSize: 18)),
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
                  color: selected ? AppColors.primary : AppColors.borderStrong,
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: selected
                  ? const Icon(
                      Icons.check,
                      size: 12,
                      color: Colors.white,
                    )
                  : null,
            ),
          ],
        ),
      ),
    ),
    );
  }
}
