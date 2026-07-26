import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/models/order.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_cubit.dart';
import '../admin_dashboard_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AdminDashboardCubit(AdminRepository()),
      child: const _DashboardView(),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: BlocBuilder<AdminDashboardCubit, AdminDashboardState>(
        builder: (context, state) {
          final cubit = context.read<AdminDashboardCubit>();
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: cubit.refreshStats,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _Header(stats: state.stats),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 15, 22, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AttentionRow(stats: state.stats),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Text(context.l10n.liveOrders,
                              style: AppType.heading(17)),
                          const Spacer(),
                          const _UpdatingDot(),
                        ],
                      ),
                      const SizedBox(height: 11),
                      if (state.loading)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: LoadingView(),
                        )
                      else if (state.liveOrders.isEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 30),
                          child: EmptyView(
                              message: context.l10n.noLiveOrdersRightNow,
                              icon: Icons.receipt_long_outlined),
                        )
                      else
                        ...state.liveOrders.map((o) => Padding(
                              padding: const EdgeInsets.only(bottom: 9),
                              child: _LiveOrderCard(
                                order: o,
                                label: state.vendorLabels[o.vendorId]?.name,
                              ),
                            )),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.stats});

  final AdminStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.ink,
      padding: EdgeInsets.fromLTRB(
          22, MediaQuery.of(context).padding.top + 14, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.eatyPlatformToday,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            letterSpacing: 1)),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                              color: Color(0xFF5FE39B),
                              shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(context.l10n.liveOverview,
                            style: AppType.heading(21, color: Colors.white)),
                      ],
                    ),
                  ],
                ),
              ),
              _AvatarButton(
                onSignOut: () => context.read<AuthCubit>().signOut(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(context.l10n.grossMerchandiseValue,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(formatMoney(stats.gmvToday),
                style: AppType.display(38, color: Colors.white)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _DarkStat(value: '${stats.ordersToday}', label: context.l10n.orders),
              const SizedBox(width: 9),
              _DarkStat(
                  value: '${stats.vendorsOpen}',
                  suffix: 'on',
                  label: context.l10n.vendors),
              const SizedBox(width: 9),
              _DarkStat(
                  value: '${stats.driversOnline}',
                  suffix: 'on',
                  label: context.l10n.drivers),
            ],
          ),
        ],
      ),
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (_) => onSignOut(),
      itemBuilder: (_) => [
        PopupMenuItem(value: 'signout', child: Text(context.l10n.signOut)),
      ],
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF243029),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(context.l10n.a,
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16)),
      ),
    );
  }
}

class _DarkStat extends StatelessWidget {
  const _DarkStat({required this.value, required this.label, this.suffix});

  final String value;
  final String label;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 13),
        decoration: BoxDecoration(
          color: const Color(0xFF243029),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value,
                    style: AppType.display(19, color: Colors.white)),
                if (suffix != null) ...[
                  const SizedBox(width: 3),
                  Text(context.l10n.on,
                      style: TextStyle(
                          color: Color(0xFF5FE39B),
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ],
              ],
            ),
            const SizedBox(height: 1),
            Text(label,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 10.5)),
          ],
        ),
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.stats});

  final AdminStats stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _AttentionCard(
            count: stats.ordersAttention,
            label: context.l10n.ordersNeedAttention,
            icon: Icons.warning_amber_rounded,
            fill: AppColors.warmFill,
            border: const Color(0xFFFAD9CC),
            ink: AppColors.primaryDark,
            onTap: () => context.go('/admin-app/orders'),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: _AttentionCard(
            count: stats.vendorsPending,
            label: context.l10n.vendorsToApprove,
            icon: Icons.storefront_outlined,
            fill: AppColors.surface,
            border: AppColors.border,
            ink: AppColors.ink,
            onTap: () => context.go('/admin-app/vendors'),
          ),
        ),
      ],
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({
    required this.count,
    required this.label,
    required this.icon,
    required this.fill,
    required this.border,
    required this.ink,
    required this.onTap,
  });

  final int count;
  final String label;
  final IconData icon;
  final Color fill;
  final Color border;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('$count', style: AppType.display(26, color: ink)),
                const Spacer(),
                Icon(icon, size: 18, color: ink),
              ],
            ),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: ink)),
          ],
        ),
      ),
    );
  }
}

class _UpdatingDot extends StatelessWidget {
  const _UpdatingDot();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
              color: AppColors.success, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(context.l10n.updating,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted)),
      ],
    );
  }
}

class _LiveOrderCard extends StatelessWidget {
  const _LiveOrderCard({required this.order, this.label});

  final AppOrder order;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final flagged = AdminOrdersStuck.isStuck(order);
    return InkWell(
      onTap: () => context.push('/admin-app/orders/${order.id}'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(
              color: flagged ? const Color(0xFFF6C7B8) : AppColors.border,
              width: flagged ? 1.5 : 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.warmFill,
                borderRadius: BorderRadius.circular(11),
              ),
              clipBehavior: Clip.antiAlias,
              child: AppNetworkImage(
                  url: order.vendorLogoUrl, width: 38, height: 38),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.orderNumber,
                      style: AppType.mono(11, color: AppColors.textFaint)),
                  Text(
                    '${label ?? order.vendorName ?? context.l10n.store} → '
                    '${order.customerName ?? context.l10n.customer}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.ink),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (flagged)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryDark,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                        '${context.l10n.stuck} ${DateTime.now().difference(order.createdAt).inMinutes}${context.l10n.mShort}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5)),
                  )
                else
                  OrderStatusChip(status: order.status),
                const SizedBox(height: 3),
                PriceText(formatMoney(order.total), size: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared "stuck" heuristic so the dashboard and monitor agree.
class AdminOrdersStuck {
  static bool isStuck(AppOrder o) =>
      !o.status.isTerminal &&
      o.status != OrderStatus.outForDelivery &&
      DateTime.now().difference(o.createdAt) > const Duration(minutes: 20);
}
