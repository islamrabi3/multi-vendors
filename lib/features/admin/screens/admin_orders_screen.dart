import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/models/order.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../admin_orders_cubit.dart';
import 'admin_order_detail_screen.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class AdminOrdersScreen extends StatelessWidget {
  const AdminOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AdminOrdersCubit(AdminRepository()),
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
  /// Row selected into the detail pane. Only used on split widths; below that
  /// a tap still pushes the detail route.
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final split = AppBreakpoints.isSplit(constraints.maxWidth);
            return BlocBuilder<AdminOrdersCubit, AdminOrdersState>(
              builder: (context, state) {
                final cubit = context.read<AdminOrdersCubit>();
                final list = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Title(state: state),
                    _FilterBar(state: state, cubit: cubit),
                    Expanded(
                      child: _OrderList(
                        state: state,
                        onLoadMore: cubit.loadMore,
                        selectedId: split ? _selectedId : null,
                        onSelect: split
                            ? (order) => setState(() => _selectedId = order.id)
                            : null,
                      ),
                    ),
                  ],
                );
                if (!split) return list;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 4, child: list),
                    const VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: AppColors.border,
                    ),
                    Expanded(flex: 5, child: _DetailPane(orderId: _selectedId)),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.state});

  final AdminOrdersState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(context.l10n.orders, style: AppType.display(26)),
          const Spacer(),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${state.liveCount} ${context.l10n.live}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Right-hand pane of the wide layout: the selected order, or a hint to pick
/// one.
class _DetailPane extends StatelessWidget {
  const _DetailPane({required this.orderId});

  final String? orderId;

  @override
  Widget build(BuildContext context) {
    if (orderId == null) {
      return Center(
        child: EmptyView(
          message: context.l10n.orderDetails,
          icon: Icons.receipt_long_outlined,
        ),
      );
    }
    return AdminOrderDetailView(
      // Rebuild the view's state when the selection changes.
      key: ValueKey(orderId),
      orderId: orderId!,
      embedded: true,
    );
  }
}

class _OrderList extends StatelessWidget {
  const _OrderList({
    required this.state,
    required this.onLoadMore,
    this.selectedId,
    this.onSelect,
  });

  final AdminOrdersState state;
  final VoidCallback onLoadMore;
  final String? selectedId;
  final ValueChanged<AppOrder>? onSelect;

  @override
  Widget build(BuildContext context) {
    if (state.loading) return const LoadingView();
    final orders = state.visible;
    if (orders.isEmpty) {
      return EmptyView(
        message: context.l10n.noOrdersInThisView,
        icon: Icons.receipt_long_outlined,
      );
    }
    return InfiniteScroll(
      onLoadMore: () {
        if (state.canLoadMore) onLoadMore();
      },
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
        itemCount: orders.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          if (i == orders.length) {
            return PagingFooter(
              loading: state.loadingMore,
              hasMore: state.canLoadMore,
            );
          }
          final o = orders[i];
          return _OrderCard(
            order: o,
            label: state.vendorLabels[o.vendorId]?.name,
            selected: o.id == selectedId,
            onSelect: onSelect,
          );
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.state, required this.cubit});

  final AdminOrdersState state;
  final AdminOrdersCubit cubit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        children: [
          _chip(context.l10n.all, OrderMonitorFilter.all),
          _chip(
            '${context.l10n.flagged} ${state.flaggedCount}',
            OrderMonitorFilter.flagged,
            danger: true,
          ),
          _chip(context.l10n.preparing, OrderMonitorFilter.preparing),
          _chip(context.l10n.onTheWay, OrderMonitorFilter.onTheWay),
        ],
      ),
    );
  }

  Widget _chip(String label, OrderMonitorFilter value, {bool danger = false}) {
    final selected = state.filter == value;
    final bg = selected
        ? (danger ? AppColors.primaryDark : AppColors.ink)
        : AppColors.surface;
    final fg = selected ? Colors.white : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: HoverBuilder(
        builder: (context, hovered) => GestureDetector(
          onTap: () => cubit.setFilter(value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: bg,
              border: Border.all(
                color: selected
                    ? Colors.transparent
                    : hovered
                    ? AppColors.primary
                    : AppColors.border,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    this.label,
    this.selected = false,
    this.onSelect,
  });

  final AppOrder order;
  final String? label;
  final bool selected;

  /// Set on split widths: pick the row into the detail pane instead of
  /// navigating away.
  final ValueChanged<AppOrder>? onSelect;

  @override
  Widget build(BuildContext context) {
    final flagged = AdminOrdersState.isFlagged(order);
    final storeName = label ?? order.vendorName ?? context.l10n.store;
    final pointer = onSelect != null;
    return HoverBuilder(
      builder: (context, hovered) => InkWell(
        onTap: () => onSelect != null
            ? onSelect!(order)
            : context.push('/admin-app/orders/${order.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : hovered
                  ? AppColors.primaryLight
                  : flagged
                  ? AppColors.attentionBorder
                  : AppColors.border,
              width: selected || flagged ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: flagged || hovered || selected ? AppShadows.card : null,
          ),
          child: flagged
              ? _flaggedBody(context, storeName, selectable: pointer)
              : _normalBody(context, storeName, selectable: pointer),
        ),
      ),
    );
  }

  Widget _flaggedBody(
    BuildContext context,
    String storeName, {
    required bool selectable,
  }) {
    final mins = DateTime.now().difference(order.createdAt).inMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SelectableId(
              order.orderNumber,
              style: AppType.mono(13),
              selectable: selectable,
            ),
            const SizedBox(width: 9),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primaryDark,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${context.l10n.stuck.toUpperCase()} $mins${context.l10n.mShort}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
            const Spacer(),
            PriceText(formatMoney(order.total), size: 13.5),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _logo(),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: storeName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    TextSpan(
                      text: ' → ${order.customerName ?? context.l10n.customer}',
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.warmFill,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.schedule,
                size: 15,
                color: AppColors.primaryDark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  order.driverId == null
                      ? context.l10n.noDriverAssignedPastSla
                      : context.l10n.runningLatePastSla,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _normalBody(
    BuildContext context,
    String storeName, {
    required bool selectable,
  }) {
    return Row(
      children: [
        _logo(),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SelectableId(
                    order.orderNumber,
                    style: AppType.mono(11, color: AppColors.textFaint),
                    selectable: selectable,
                  ),
                  Flexible(
                    child: Text(
                      ' · ${_ago(order.createdAt, context)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.mono(11, color: AppColors.textFaint),
                    ),
                  ),
                ],
              ),
              Text(
                '$storeName → ${order.customerName ?? context.l10n.customer}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            OrderStatusChip(status: order.status),
            const SizedBox(height: 3),
            PriceText(formatMoney(order.total), size: 12),
          ],
        ),
      ],
    );
  }

  Widget _logo() => Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: AppColors.warmFill,
      borderRadius: BorderRadius.circular(11),
    ),
    clipBehavior: Clip.antiAlias,
    child: AppNetworkImage(url: order.vendorLogoUrl, width: 38, height: 38),
  );

  String _ago(DateTime t, BuildContext context) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return context.l10n.justNow;
    if (d.inMinutes < 60) return '${d.inMinutes}${context.l10n.minutesAgo}';
    if (d.inHours < 24) return '${d.inHours}${context.l10n.hoursAgo}';
    return '${d.inDays}${context.l10n.daysAgo}';
  }
}
