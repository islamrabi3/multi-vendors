import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/tokens.dart';
import '../../../core/models/order.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/ui_kit.dart';
import 'orders_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => OrdersCubit(OrderRepository()),
      child: const _OrdersView(),
    );
  }
}

class _OrdersView extends StatefulWidget {
  const _OrdersView();

  @override
  State<_OrdersView> createState() => _OrdersViewState();
}

class _OrdersViewState extends State<_OrdersView> {
  bool _active = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_active) {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        context.read<OrdersCubit>().loadNextPastPage();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<OrdersCubit, OrdersState>(
          builder: (context, state) {
            final activeLoading =
                state.loadingActive && state.activeOrders.isEmpty;
            final orders = _active ? state.activeOrders : state.pastOrders;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 6, 22, 6),
                  child: Text(context.l10n.orders, style: AppType.display(26)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                  child: Row(
                    children: [
                      AppFilterChip(
                          label: context.l10n.active2,
                          selected: _active,
                          onTap: () => setState(() => _active = true)),
                      const SizedBox(width: AppSpace.sm),
                      AppFilterChip(
                          label: context.l10n.past,
                          selected: !_active,
                          onTap: () {
                            setState(() => _active = false);
                            if (state.pastOrders.isEmpty && !state.loadingPast) {
                              context.read<OrdersCubit>().loadNextPastPage();
                            }
                          }),
                    ],
                  ),
                ),
                Expanded(
                  child: activeLoading
                      ? const _OrdersSkeleton()
                      : RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () async {
                      if (_active) {
                        // active is streamed, but we can do a refresh
                      } else {
                        await context.read<OrdersCubit>().refresh();
                      }
                    },
                    child: orders.isEmpty && !state.loadingPast
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 120),
                              EmptyView(
                                  message: _active
                                      ? context.l10n.noActiveOrders
                                      : context.l10n.noPastOrders,
                                  icon: Icons.receipt_long_outlined),
                            ],
                          )
                        : ListView.separated(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
                            itemCount: orders.length + (state.loadingPast ? 1 : 0),
                            separatorBuilder: (context, index) => const SizedBox(height: 12),
                            itemBuilder: (context, i) {
                              if (i == orders.length) {
                                // A page in flight is a footer, not a full-size
                                // spinner squatting in a 48px row.
                                return const PagingFooter(
                                    loading: true, hasMore: true);
                              }
                              final order = orders[i];
                              final label = state.vendorLabels[order.vendorId];
                              return _OrderCard(order: order, vendorName: label?.name);
                            },
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, this.vendorName});

  final AppOrder order;
  final String? vendorName;

  double get _progress => switch (order.status) {
        OrderStatus.pending => 0.15,
        OrderStatus.accepted => 0.3,
        OrderStatus.preparing => 0.5,
        OrderStatus.readyForPickup => 0.65,
        OrderStatus.outForDelivery => 0.82,
        _ => 1.0,
      };

  @override
  Widget build(BuildContext context) {
    final active = !order.status.isTerminal;
    final name = vendorName ?? order.vendorName ?? 'Order';
    final itemCount = order.items.length;

    return GestureDetector(
      onTap: () => context.push('/order/${order.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (active) Container(width: 4, color: AppColors.primary),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.warmFill,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.receipt_long_rounded,
                                size: 20, color: AppColors.primary),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.ink)),
                                Text(
                                  active
                                      ? '${order.orderNumber} · $itemCount items'
                                      : '${order.orderNumber} · '
                                          '${DateFormat('d MMM').format(order.createdAt)}',
                                  style: AppType.mono(11.5,
                                      color: AppColors.textMuted,
                                      weight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                          OrderStatusChip(status: order.status),
                        ],
                      ),
                      if (active) ...[
                        const SizedBox(height: 13),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _progress,
                            minHeight: 6,
                            backgroundColor: AppColors.borderSoft,
                            valueColor: const AlwaysStoppedAnimation(
                                AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: 11),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(context.l10n.tapToTrack,
                                style: const TextStyle(
                                    fontSize: 12.5, color: AppColors.textMuted)),
                            Row(
                              children: [
                                Text(context.l10n.track,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary)),
                                DirectionalIcon(Icons.arrow_forward,
                                    size: 14, color: AppColors.primary),
                              ],
                            ),
                          ],
                        ),
                      ] else ...[
                        const SizedBox(height: 13),
                        const Divider(height: 1),
                        const SizedBox(height: 13),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            PriceText(formatMoney(order.total)),
                            Row(
                              children: [
                                _MiniButton(
                                    label: context.l10n.rate,
                                    filled: false,
                                    onTap: () => context.push('/order/${order.id}')),
                                const SizedBox(width: 8),
                                _MiniButton(
                                    label: context.l10n.reorder,
                                    filled: true,
                                    onTap: () async {
                                      await OrderRepository().reorderPastOrder(order);
                                      if (context.mounted) {
                                        context.push('/cart');
                                      }
                                    }),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton(
      {required this.label, required this.filled, required this.onTap});

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: filled ? AppColors.primary : AppColors.surface,
          border: filled ? null : Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: filled ? Colors.white : AppColors.ink)),
      ),
    );
  }
}

/// The orders list while the active stream delivers its first snapshot. Same
/// padding and 12px separation as the real `ListView.separated`, so rows land
/// exactly where their placeholders were.
class _OrdersSkeleton extends StatelessWidget {
  const _OrdersSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonTheme(
      child: SkeletonList(
        itemCount: 4,
        padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter, AppSpace.xs, AppSpace.gutter, AppSpace.xxl),
        separator: const SizedBox(height: AppSpace.md),
        itemBuilder: (_) => const _OrderCardSkeleton(),
      ),
    );
  }
}

/// Mirrors `_OrderCard`: 42px avatar tile, two text lines, status chip, and the
/// progress bar an active order shows.
class _OrderCardSkeleton extends StatelessWidget {
  const _OrderCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Row(
              children: [
                Skeleton(width: 42, height: 42, radius: AppRadii.md),
                SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton.line(widthFactor: 0.5, height: 14),
                      SizedBox(height: 6),
                      Skeleton.line(widthFactor: 0.7, height: 11),
                    ],
                  ),
                ),
                SizedBox(width: AppSpace.sm),
                Skeleton(width: 76, height: 26, shape: SkeletonShape.pill),
              ],
            ),
            SizedBox(height: 13),
            Skeleton(height: 6, radius: AppSpace.xs),
          ],
        ),
      ),
    );
  }
}
