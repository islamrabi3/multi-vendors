import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/models/order.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/repositories/payment_repository.dart';
import '../../../core/repositories/review_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import 'order_details_cubit.dart';

class OrderDetailsScreen extends StatelessWidget {
  const OrderDetailsScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => OrderDetailsCubit(
          OrderRepository(), ReviewRepository(), PaymentRepository(), orderId),
      child: const _OrderDetailsView(),
    );
  }
}

class _OrderDetailsView extends StatelessWidget {
  const _OrderDetailsView();

  static const _trackedStatuses = [
    OrderStatus.pending,
    OrderStatus.accepted,
    OrderStatus.preparing,
    OrderStatus.readyForPickup,
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order details')),
      body: BlocConsumer<OrderDetailsCubit, OrderDetailsState>(
        listenWhen: (previous, current) =>
            previous.error != current.error && current.error != null,
        listener: (context, state) =>
            showSnack(context, readableError(state.error!), error: true),
        builder: (context, state) {
          if (state.loading) return const LoadingView();
          final order = state.order;
          if (order == null) {
            return const ErrorView(message: 'Order not found.');
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(order.orderNumber,
                      style: Theme.of(context).textTheme.titleLarge),
                  OrderStatusChip(status: order.status),
                ],
              ),
              if (order.vendorName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(order.vendorName!,
                      style: Theme.of(context).textTheme.bodyLarge),
                ),
              const SizedBox(height: 16),
              if (order.status == OrderStatus.rejected ||
                  order.status == OrderStatus.cancelled)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(order.status == OrderStatus.rejected
                        ? 'Rejected by store'
                            '${order.rejectionReason != null ? ': ${order.rejectionReason}' : ''}'
                        : 'This order was cancelled.'),
                  ),
                )
              else
                _StatusStepper(order: order),
              if (order.status == OrderStatus.outForDelivery) ...[
                const SizedBox(height: 16),
                _TrackingMap(order: order, driverLocation: state.driverLocation),
              ],
              const Divider(height: 32),
              _PaymentCard(order: order, busy: state.busy),
              const SizedBox(height: 8),
              Text('Items', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              for (final item in state.items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Text('${item.quantity}x',
                      style: Theme.of(context).textTheme.titleSmall),
                  title: Text(item.productName),
                  subtitle: item.optionNames.isEmpty
                      ? null
                      : Text(item.optionNames.join(', ')),
                  trailing: Text(formatMoney(item.lineTotal)),
                ),
              const Divider(),
              _Row(label: 'Subtotal', value: formatMoney(order.subtotal)),
              _Row(label: 'Delivery fee', value: formatMoney(order.deliveryFee)),
              if (order.discount > 0)
                _Row(label: 'Discount', value: '-${formatMoney(order.discount)}'),
              _Row(label: 'Total', value: formatMoney(order.total), bold: true),
              const SizedBox(height: 16),
              Text('Delivering to ${order.addressSummary}',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 24),
              if (order.status == OrderStatus.pending)
                OutlinedButton(
                  onPressed: state.busy
                      ? null
                      : () => context.read<OrderDetailsCubit>().cancelOrder(),
                  child: const Text('Cancel order'),
                ),
              if (order.status == OrderStatus.delivered && !state.hasReview)
                FilledButton.icon(
                  onPressed: () => _showReviewSheet(context),
                  icon: const Icon(Icons.star_outline),
                  label: const Text('Rate this order'),
                ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  void _showReviewSheet(BuildContext context) {
    final cubit = context.read<OrderDetailsCubit>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReviewSheet(cubit: cubit),
    );
  }
}

class _StatusStepper extends StatelessWidget {
  const _StatusStepper({required this.order});

  final AppOrder order;

  @override
  Widget build(BuildContext context) {
    final steps = _OrderDetailsView._trackedStatuses;
    final currentIndex = steps.indexOf(order.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (var i = 0; i < steps.length; i++)
              Row(
                children: [
                  Icon(
                    i <= currentIndex
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: i <= currentIndex
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    steps[i].label,
                    style: TextStyle(
                      fontWeight:
                          i == currentIndex ? FontWeight.bold : FontWeight.normal,
                      color: i <= currentIndex ? null : Colors.grey,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _TrackingMap extends StatelessWidget {
  const _TrackingMap({required this.order, required this.driverLocation});

  final AppOrder order;
  final LatLng? driverLocation;

  @override
  Widget build(BuildContext context) {
    final destination = order.deliveryLat != null && order.deliveryLng != null
        ? LatLng(order.deliveryLat!, order.deliveryLng!)
        : null;
    final center = driverLocation ?? destination;
    if (center == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Your rider is on the way!'),
        ),
      );
    }
    return SizedBox(
      height: 220,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FlutterMap(
          options: MapOptions(initialCenter: center, initialZoom: 14),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.multi_vendor',
            ),
            MarkerLayer(markers: [
              if (destination != null)
                Marker(
                  point: destination,
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.home, color: Colors.red, size: 32),
                ),
              if (driverLocation != null)
                Marker(
                  point: driverLocation!,
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.delivery_dining,
                      color: Colors.indigo, size: 36),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.order, required this.busy});

  final AppOrder order;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final needsPayment = !order.isCod && !order.isPaid && !order.status.isTerminal;
    return Card(
      child: ListTile(
        leading: Icon(
            order.isCod ? Icons.payments_outlined : Icons.credit_card),
        title: Text(order.isCod ? 'Cash on delivery' : 'Card / wallet'),
        subtitle: Text('Payment: ${order.paymentStatus}'),
        trailing: needsPayment
            ? FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final cubit = context.read<OrderDetailsCubit>();
                        final router = GoRouter.of(context);
                        final url = await cubit.retryPayment();
                        if (url != null) {
                          router.push('/paymob-checkout',
                              extra: {'url': url, 'orderId': order.id});
                        }
                      },
                child: const Text('Pay now'),
              )
            : order.isPaid
                ? const Icon(Icons.check_circle, color: Colors.green)
                : null,
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.cubit});

  final OrderDetailsCubit cubit;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _rating = 5;
  final _comment = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('How was your order?',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var star = 1; star <= 5; star++)
                IconButton(
                  onPressed: () => setState(() => _rating = star),
                  icon: Icon(
                    star <= _rating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 32,
                  ),
                ),
            ],
          ),
          TextField(
            controller: _comment,
            maxLines: 3,
            decoration:
                const InputDecoration(labelText: 'Comment (optional)'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting
                ? null
                : () async {
                    setState(() => _submitting = true);
                    final ok = await widget.cubit
                        .submitReview(_rating, _comment.text);
                    if (!context.mounted) return;
                    if (ok) {
                      Navigator.pop(context);
                      showSnack(context, 'Thanks for your review!');
                    } else {
                      setState(() => _submitting = false);
                    }
                  },
            child: const Text('Submit review'),
          ),
        ],
      ),
    );
  }
}
