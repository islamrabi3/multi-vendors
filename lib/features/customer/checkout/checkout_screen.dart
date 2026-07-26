import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/repositories/address_repository.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/repositories/payment_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../cart/cart_cubit.dart';
import 'checkout_cubit.dart';
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

  void _onPlaced(BuildContext context, CheckoutState state) {
    final orderId = state.placedOrderId!;
    context.read<CartCubit>().clear();
    if (state.paymobCheckoutUrl != null) {
      context.pushReplacement('/paymob-checkout',
          extra: {'url': state.paymobCheckoutUrl!, 'orderId': orderId});
    } else {
      context.pushReplacement('/order/$orderId');
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
            _onPlaced(context, state);
          } else if (state.error != null) {
            showSnack(context, readableError(state.error!), error: true);
          }
        },
        builder: (context, state) {
          if (state.loading) return const LoadingView();
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
            padding: const EdgeInsets.all(16),
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
              else ...[
                Builder(
                  builder: (context) {
                    final selectedAddress = state.selectedAddress ?? state.addresses.first;
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          // Abstract mini map
                          Container(
                            height: 84,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFFEDEAE4), Color(0xFFE4DFD7)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _MiniMapPainter(),
                                  ),
                                ),
                                // Location Pin
                                Positioned(
                                  left: 52,
                                  top: 34,
                                  child: Transform.rotate(
                                    angle: -0.785, // -45 degrees
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: const BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius: BorderRadius.only(
                                          topLeft: Radius.circular(10),
                                          topRight: Radius.circular(10),
                                          bottomRight: Radius.circular(10),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Color(0x66FF5A2C),
                                            blurRadius: 8,
                                            offset: Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Address Details Row
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                            child: Row(
                              children: [
                                const Icon(Icons.location_on, color: AppColors.primary, size: 18),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        selectedAddress.label,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                      Text(
                                        selectedAddress.summary,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    await context.push('/addresses');
                                    cubit.loadAddresses();
                                  },
                                  child: Text(
                                    context.l10n.change,
                                    style: TextStyle(
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
                ),
              ],

              // Delivery Time Card
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(14),
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
                            context.l10n.standard2535Min,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            context.l10n.arrivesBy935Pm,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.check, size: 12, color: Colors.white),
                    ),
                  ],
                ),
              ),

              // Payment Section
              const SizedBox(height: 18),
              Text(
                context.l10n.payment,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 11),
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFFFC2AC), width: 1.5),
                    borderRadius: BorderRadius.circular(14),
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
                        child: Text(context.l10n.emptyString, style: TextStyle(fontSize: 16)),
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
                          fillColor: Colors.white,
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
                  fillColor: Colors.white,
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
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
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

class _MiniMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD6CFC4)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Draw horizontal road
    canvas.drawLine(Offset(0, size.height * 0.5), Offset(size.width, size.height * 0.5), paint);
    // Draw vertical roads
    canvas.drawLine(Offset(size.width * 0.25, 0), Offset(size.width * 0.25, size.height), paint);
    canvas.drawLine(Offset(size.width * 0.75, 0), Offset(size.width * 0.75, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PaymentSelectorCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentSelectorCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
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
                color: selected ? AppColors.warmFill : const Color(0xFFF3EEE8),
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
                  color: selected ? AppColors.primary : const Color(0xFFDDD4CB),
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
    );
  }
}
