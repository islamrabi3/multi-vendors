import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/models/order.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../admin_orders_cubit.dart';
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

class _OrdersView extends StatelessWidget {
  const _OrdersView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<AdminOrdersCubit, AdminOrdersState>(
          builder: (context, state) {
            final cubit = context.read<AdminOrdersCubit>();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
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
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text('${state.liveCount} ${context.l10n.live}',
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textMuted)),
                        ],
                      ),
                    ],
                  ),
                ),
                _FilterBar(state: state, cubit: cubit),
                if (state.loading)
                  const Expanded(child: LoadingView())
                else if (state.visible.isEmpty)
                  Expanded(
                    child: EmptyView(
                        message: context.l10n.noOrdersInThisView,
                        icon: Icons.receipt_long_outlined),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
                      itemCount: state.visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final o = state.visible[i];
                        return _OrderCard(
                          order: o,
                          label: state.vendorLabels[o.vendorId]?.name,
                        );
                      },
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
          _chip('${context.l10n.flagged} ${state.flaggedCount}', OrderMonitorFilter.flagged,
              danger: true),
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
      child: GestureDetector(
        onTap: () => cubit.setFilter(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(
                color: selected ? Colors.transparent : AppColors.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(
                  color: fg, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, this.label});

  final AppOrder order;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final flagged = AdminOrdersState.isFlagged(order);
    final storeName = label ?? order.vendorName ?? context.l10n.store;
    return InkWell(
      onTap: () => context.push('/admin-app/orders/${order.id}'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(
              color: flagged ? const Color(0xFFF0B9A6) : AppColors.border,
              width: flagged ? 1.5 : 1),
          borderRadius: BorderRadius.circular(16),
          boxShadow: flagged ? AppShadows.card : null,
        ),
        child: flagged
            ? _flaggedBody(context, storeName)
            : _normalBody(context, storeName),
      ),
    );
  }

  Widget _flaggedBody(BuildContext context, String storeName) {
    final mins = DateTime.now().difference(order.createdAt).inMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(order.orderNumber, style: AppType.mono(13)),
            const SizedBox(width: 9),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primaryDark,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${context.l10n.stuck.toUpperCase()} $mins${context.l10n.mShort}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 10)),
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
                TextSpan(children: [
                  TextSpan(
                      text: storeName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
                  TextSpan(text: ' → ${order.customerName ?? context.l10n.customer}'),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF6F2),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              const Icon(Icons.schedule,
                  size: 15, color: AppColors.primaryDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  order.driverId == null
                      ? context.l10n.noDriverAssignedPastSla
                      : context.l10n.runningLatePastSla,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFB4462B)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _normalBody(BuildContext context, String storeName) {
    return Row(
      children: [
        _logo(),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${order.orderNumber} · ${_ago(order.createdAt, context)}',
                  style: AppType.mono(11, color: AppColors.textFaint)),
              Text('$storeName → ${order.customerName ?? context.l10n.customer}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: AppColors.ink)),
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
