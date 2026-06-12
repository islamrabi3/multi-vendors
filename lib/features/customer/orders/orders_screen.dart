import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/repositories/order_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import 'orders_cubit.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => OrdersCubit(OrderRepository()),
      child: Scaffold(
        appBar: AppBar(title: const Text('My orders')),
        body: BlocBuilder<OrdersCubit, OrdersState>(
          builder: (context, state) {
            if (state.loading) return const LoadingView();
            if (state.orders.isEmpty) {
              return const EmptyView(
                  message: 'No orders yet',
                  icon: Icons.receipt_long_outlined);
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: state.orders.length,
              itemBuilder: (context, index) {
                final order = state.orders[index];
                final label = state.vendorLabels[order.vendorId];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    onTap: () => context.push('/order/${order.id}'),
                    leading: AppNetworkImage(
                        url: label?.logoUrl,
                        height: 44,
                        width: 44,
                        borderRadius: BorderRadius.circular(8)),
                    title: Text(label?.name ?? order.orderNumber),
                    subtitle: Text(
                      '${order.orderNumber} · '
                      '${DateFormat('d MMM, h:mm a').format(order.createdAt)}',
                    ),
                    trailing: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OrderStatusChip(status: order.status),
                        const SizedBox(height: 4),
                        Text(formatMoney(order.total)),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
