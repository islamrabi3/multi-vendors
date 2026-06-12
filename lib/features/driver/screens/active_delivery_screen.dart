import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/repositories/driver_repository.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/supabase_client.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../active_delivery_cubit.dart';

class ActiveDeliveryScreen extends StatelessWidget {
  const ActiveDeliveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ActiveDeliveryCubit(
          OrderRepository(), DriverRepository(), supabase),
      child: const _ActiveDeliveryView(),
    );
  }
}

class _ActiveDeliveryView extends StatelessWidget {
  const _ActiveDeliveryView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ActiveDeliveryCubit, ActiveDeliveryState>(
      listenWhen: (previous, current) =>
          previous.error != current.error && current.error != null,
      listener: (context, state) =>
          showSnack(context, readableError(state.error!), error: true),
      builder: (context, state) {
        if (state.loading) return const LoadingView();
        final order = state.order;
        if (order == null) {
          return const EmptyView(
              message: 'No active delivery.\nClaim one from Available.',
              icon: Icons.delivery_dining_outlined);
        }
        final destination =
            order.deliveryLat != null && order.deliveryLng != null
                ? LatLng(order.deliveryLat!, order.deliveryLng!)
                : null;
        final center = state.myLocation ??
            state.vendorLocation ??
            destination ??
            const LatLng(30.0444, 31.2357);
        return Column(
          children: [
            Expanded(
              child: FlutterMap(
                options: MapOptions(initialCenter: center, initialZoom: 13),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.multi_vendor',
                  ),
                  MarkerLayer(markers: [
                    if (state.vendorLocation != null)
                      Marker(
                        point: state.vendorLocation!,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.storefront,
                            color: Colors.orange, size: 32),
                      ),
                    if (destination != null)
                      Marker(
                        point: destination,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.home,
                            color: Colors.red, size: 32),
                      ),
                    if (state.myLocation != null)
                      Marker(
                        point: state.myLocation!,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.delivery_dining,
                            color: Colors.indigo, size: 36),
                      ),
                  ]),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${order.orderNumber} · '
                      '${state.vendorName ?? 'Store'} → '
                      '${order.customerName ?? 'Customer'}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(order.addressSummary,
                        style: Theme.of(context).textTheme.bodySmall),
                    if (order.customerPhone != null)
                      Text('Phone: ${order.customerPhone}',
                          style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Text(
                      order.isCod
                          ? 'Collect ${formatMoney(order.total)} in cash'
                          : 'Paid online — nothing to collect',
                      style: TextStyle(
                          color: order.isCod ? Colors.orange : Colors.green,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: state.busy
                          ? null
                          : () => context
                              .read<ActiveDeliveryCubit>()
                              .markDelivered(),
                      child: state.busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Mark delivered'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
