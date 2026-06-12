import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/repositories/driver_repository.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../driver_pool_cubit.dart';

class DriverPoolScreen extends StatelessWidget {
  const DriverPoolScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DriverPoolCubit(OrderRepository(), DriverRepository()),
      child: const _PoolView(),
    );
  }
}

class _PoolView extends StatelessWidget {
  const _PoolView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DriverPoolCubit, DriverPoolState>(
      listenWhen: (previous, current) =>
          current.claimedOrderId != null || current.error != null,
      listener: (context, state) {
        if (state.claimedOrderId != null) {
          showSnack(context, 'Order claimed — head to the store!');
          context.go('/driver-app/active');
        } else if (state.error != null) {
          showSnack(context, readableError(state.error!), error: true);
        }
      },
      builder: (context, state) {
        if (state.loading) return const LoadingView();
        final cubit = context.read<DriverPoolCubit>();
        return Column(
          children: [
            Card(
              margin: const EdgeInsets.all(12),
              child: SwitchListTile(
                title: Text(state.isOnline
                    ? 'Online — receiving orders'
                    : 'Offline'),
                value: state.isOnline,
                onChanged: cubit.setOnline,
              ),
            ),
            Expanded(
              child: !state.isOnline
                  ? const EmptyView(
                      message: 'Go online to see available orders',
                      icon: Icons.power_settings_new)
                  : state.orders.isEmpty
                      ? const EmptyView(
                          message: 'No orders waiting for pickup',
                          icon: Icons.hourglass_empty)
                      : ListView.builder(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: state.orders.length,
                          itemBuilder: (context, index) {
                            final order = state.orders[index];
                            final label =
                                state.vendorLabels[order.vendorId];
                            return Card(
                              margin:
                                  const EdgeInsets.symmetric(vertical: 6),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        AppNetworkImage(
                                            url: label?.logoUrl,
                                            height: 40,
                                            width: 40,
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                  label?.name ??
                                                      order.orderNumber,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall),
                                              Text(
                                                'Deliver to '
                                                '${order.addressSummary}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                                maxLines: 2,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(formatMoney(order.total)),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                          minimumSize:
                                              const Size.fromHeight(40)),
                                      onPressed: () => cubit.claim(order),
                                      child: Text(order.isCod
                                          ? 'Claim · collect '
                                              '${formatMoney(order.total)} cash'
                                          : 'Claim (paid online)'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }
}
