import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/repositories/address_repository.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/repositories/payment_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../cart/cart_cubit.dart';
import 'checkout_cubit.dart';

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
      appBar: AppBar(title: const Text('Checkout')),
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
            return const EmptyView(
                message: 'Your cart is empty',
                icon: Icons.shopping_cart_outlined);
          }
          final cubit = context.read<CheckoutCubit>();
          final discount = state.couponDiscount ?? 0;
          final total =
              cart.subtotal - discount + cart.vendor!.deliveryFee;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Deliver to',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (state.addresses.isEmpty)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.add_location_alt_outlined),
                    title: const Text('Add a delivery address'),
                    onTap: () async {
                      await context.push('/addresses');
                      cubit.loadAddresses();
                    },
                  ),
                )
              else ...[
                RadioGroup<String>(
                  groupValue: state.selectedAddressId,
                  onChanged: (id) => cubit.selectAddress(id!),
                  child: Column(
                    children: [
                      for (final address in state.addresses)
                        RadioListTile<String>(
                          value: address.id,
                          title: Text(address.label),
                          subtitle: Text(address.summary),
                        ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await context.push('/addresses');
                    cubit.loadAddresses();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Manage addresses'),
                ),
              ],
              const Divider(height: 32),
              Text('Payment', style: Theme.of(context).textTheme.titleMedium),
              RadioGroup<String>(
                groupValue: state.paymentMethod,
                onChanged: (m) => cubit.selectPaymentMethod(m!),
                child: const Column(
                  children: [
                    RadioListTile<String>(
                      value: 'cod',
                      title: Text('Cash on delivery'),
                      secondary: Icon(Icons.payments_outlined),
                    ),
                    RadioListTile<String>(
                      value: 'paymob',
                      title: Text('Card / wallet (Paymob)'),
                      secondary: Icon(Icons.credit_card),
                    ),
                  ],
                ),
              ),
              const Divider(height: 32),
              Text('Coupon', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _coupon,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'Coupon code',
                        errorText: state.couponError != null
                            ? readableError(state.couponError!)
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => cubit.applyCoupon(
                        _coupon.text, cart.vendor!.id, cart.subtotal),
                    child: const Text('Apply'),
                  ),
                ],
              ),
              if (state.couponDiscount != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 18),
                      const SizedBox(width: 6),
                      Text(
                          '${state.couponCode} applied: '
                          '-${formatMoney(state.couponDiscount!)}'),
                      const Spacer(),
                      TextButton(
                          onPressed: cubit.clearCoupon,
                          child: const Text('Remove')),
                    ],
                  ),
                ),
              const Divider(height: 32),
              TextField(
                controller: _notes,
                decoration:
                    const InputDecoration(labelText: 'Order notes (optional)'),
              ),
              const SizedBox(height: 24),
              _SummaryRow(label: 'Subtotal', value: cart.subtotal),
              _SummaryRow(
                  label: 'Delivery fee', value: cart.vendor!.deliveryFee),
              if (discount > 0)
                _SummaryRow(label: 'Discount', value: -discount),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total',
                      style: Theme.of(context).textTheme.titleLarge),
                  Text(formatMoney(total),
                      style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
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
                        ? 'Place order'
                        : 'Place order & pay'),
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
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label), Text(formatMoney(value))],
      ),
    );
  }
}
