import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/models/order.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_cubit.dart';
import '../vendor_orders_cubit.dart';

class VendorDashboardScreen extends StatelessWidget {
  const VendorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vendor = context.read<AuthCubit>().state.vendor;
    if (vendor == null) return const LoadingView();
    return BlocProvider(
      create: (_) => VendorOrdersCubit(OrderRepository(), vendor.id),
      child: const _DashboardView(),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context) {
    final vendorName =
        context.select((AuthCubit cubit) => cubit.state.vendor?.name);
    return Scaffold(
      appBar: AppBar(title: Text(vendorName ?? 'Orders')),
      body: BlocConsumer<VendorOrdersCubit, VendorOrdersState>(
        listenWhen: (previous, current) =>
            current.newOrderArrived || current.error != null,
        listener: (context, state) {
          if (state.newOrderArrived) {
            showSnack(context, '🔔 New order received!');
          } else if (state.error != null) {
            showSnack(context, readableError(state.error!), error: true);
          }
        },
        builder: (context, state) {
          if (state.loading) return const LoadingView();
          if (state.orders.isEmpty) {
            return const EmptyView(
                message: 'No orders yet', icon: Icons.receipt_long_outlined);
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (state.pending.isNotEmpty) ...[
                _SectionTitle('New orders (${state.pending.length})'),
                for (final order in state.pending)
                  _OrderCard(order: order, highlight: true),
              ],
              if (state.active.isNotEmpty) ...[
                const _SectionTitle('In progress'),
                for (final order in state.active) _OrderCard(order: order),
              ],
              if (state.past.isNotEmpty) ...[
                const _SectionTitle('History'),
                for (final order in state.past.take(20))
                  _OrderCard(order: order),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, this.highlight = false});

  final AppOrder order;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<VendorOrdersCubit>();
    return Card(
      color: highlight
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
          : null,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: () => context.push('/vendor-app/orders/${order.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(order.orderNumber,
                      style: Theme.of(context).textTheme.titleSmall),
                  OrderStatusChip(status: order.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${order.customerName ?? 'Customer'} · '
                '${DateFormat('h:mm a').format(order.createdAt)} · '
                '${formatMoney(order.total)}'
                '${order.isCod ? ' (COD)' : order.isPaid ? ' (paid)' : ' (unpaid)'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              _ActionRow(order: order, cubit: cubit),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.order, required this.cubit});

  final AppOrder order;
  final VendorOrdersCubit cubit;

  Future<void> _rejectWithReason(BuildContext context) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject order'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Back')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (reason != null) {
      await cubit.reject(order, reason.isEmpty ? 'Unavailable' : reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (order.status) {
      OrderStatus.pending => Row(
          children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(40)),
                onPressed: () => cubit.accept(order),
                child: const Text('Accept'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _rejectWithReason(context),
                child: const Text('Reject'),
              ),
            ),
          ],
        ),
      OrderStatus.accepted => FilledButton.tonal(
          style:
              FilledButton.styleFrom(minimumSize: const Size.fromHeight(40)),
          onPressed: () => cubit.startPreparing(order),
          child: const Text('Start preparing'),
        ),
      OrderStatus.preparing => FilledButton.tonal(
          style:
              FilledButton.styleFrom(minimumSize: const Size.fromHeight(40)),
          onPressed: () => cubit.markReady(order),
          child: const Text('Ready for pickup'),
        ),
      OrderStatus.readyForPickup => const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Waiting for a driver…',
              style: TextStyle(color: Colors.teal)),
        ),
      _ => const SizedBox.shrink(),
    };
  }
}
