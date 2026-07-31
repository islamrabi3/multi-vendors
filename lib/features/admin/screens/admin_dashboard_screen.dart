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
import 'admin_order_detail_screen.dart';
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

class _DashboardView extends StatefulWidget {
  const _DashboardView();

  @override
  State<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<_DashboardView> {
  /// Live order shown in the side panel. Split widths only; below that a tap
  /// still pushes the detail route.
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final split = AppBreakpoints.isSplit(constraints.maxWidth);
          return BlocBuilder<AdminDashboardCubit, AdminDashboardState>(
            builder: (context, state) {
              final cubit = context.read<AdminDashboardCubit>();
              if (split) {
                return Column(
                  children: [
                    _Header(stats: state.stats),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 15, 22, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _StatGrid(stats: state.stats),
                            const SizedBox(height: 18),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: _LiveOrdersPanel(
                                      state: state,
                                      selectedId: _selectedId,
                                      onSelect: (o) =>
                                          setState(() => _selectedId = o.id),
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  Expanded(
                                    flex: 5,
                                    child: _DetailPanel(orderId: _selectedId),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }
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
          );
        },
      ),
    );
  }
}

/// Wide-screen live feed: its own scroll area beside the detail panel.
class _LiveOrdersPanel extends StatelessWidget {
  const _LiveOrdersPanel({
    required this.state,
    required this.selectedId,
    required this.onSelect,
  });

  final AdminDashboardState state;
  final String? selectedId;
  final ValueChanged<AppOrder> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(context.l10n.liveOrders, style: AppType.heading(17)),
            const Spacer(),
            const _UpdatingDot(),
          ],
        ),
        const SizedBox(height: 11),
        Expanded(
          child: state.loading
              ? const LoadingView()
              : state.liveOrders.isEmpty
                  ? EmptyView(
                      message: context.l10n.noLiveOrdersRightNow,
                      icon: Icons.receipt_long_outlined)
                  : ListView.separated(
                      itemCount: state.liveOrders.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 9),
                      itemBuilder: (_, i) {
                        final o = state.liveOrders[i];
                        return _LiveOrderCard(
                          order: o,
                          label: state.vendorLabels[o.vendorId]?.name,
                          selected: o.id == selectedId,
                          onSelect: onSelect,
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

/// Wide-screen side panel: the selected live order, without leaving the feed.
class _DetailPanel extends StatelessWidget {
  const _DetailPanel({required this.orderId});

  final String? orderId;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
      clipBehavior: Clip.antiAlias,
      child: orderId == null
          ? Center(
              child: EmptyView(
                message: context.l10n.orderDetails,
                icon: Icons.receipt_long_outlined,
              ),
            )
          : AdminOrderDetailView(
              // Rebuild the view's state when the selection changes.
              key: ValueKey(orderId),
              orderId: orderId!,
              embedded: true,
            ),
    );
  }
}

/// Headline counters as a multi-column grid — the wide-screen replacement for
/// the phone layout's two stacked attention cards.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});

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
        const SizedBox(width: 11),
        Expanded(
          child: _AttentionCard(
            count: stats.vendorsOpen,
            label: context.l10n.vendors,
            icon: Icons.store_mall_directory_outlined,
            fill: AppColors.surface,
            border: AppColors.border,
            ink: AppColors.ink,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: _AttentionCard(
            count: stats.driversOnline,
            label: context.l10n.drivers,
            icon: Icons.delivery_dining_outlined,
            fill: AppColors.surface,
            border: AppColors.border,
            ink: AppColors.ink,
          ),
        ),
      ],
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
    // Drivers and menu import used to hide in here because the tab bar was
    // full; they now live in the Manage tab, which leaves this as the account
    // menu it always looked like.
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'manage') {
          context.go('/admin-app/manage');
          return;
        }
        onSignOut();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'manage',
          child: Row(
            children: [
              const Icon(Icons.tune_rounded, size: 18),
              const SizedBox(width: AppSpace.sm),
              Text(context.l10n.manage),
            ],
          ),
        ),
        const PopupMenuDivider(),
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
    this.onTap,
  });

  final int count;
  final String label;
  final IconData icon;
  final Color fill;
  final Color border;
  final Color ink;

  /// Null for read-only counters in the wide stat grid.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      builder: (context, hovered) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(
                color: hovered && onTap != null ? AppColors.primary : border),
            borderRadius: BorderRadius.circular(16),
            boxShadow: hovered && onTap != null ? AppShadows.card : null,
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
  const _LiveOrderCard({
    required this.order,
    this.label,
    this.selected = false,
    this.onSelect,
  });

  final AppOrder order;
  final String? label;
  final bool selected;

  /// Set on split widths: pick the row into the side panel instead of
  /// navigating away.
  final ValueChanged<AppOrder>? onSelect;

  @override
  Widget build(BuildContext context) {
    final flagged = AdminOrdersStuck.isStuck(order);
    return HoverBuilder(
      builder: (context, hovered) => InkWell(
        onTap: () => onSelect != null
            ? onSelect!(order)
            : context.push('/admin-app/orders/${order.id}'),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(
                color: selected
                    ? AppColors.primary
                    : hovered
                        ? AppColors.primaryLight
                        : flagged
                            ? const Color(0xFFF6C7B8)
                            : AppColors.border,
                width: flagged || selected ? 1.5 : 1),
            borderRadius: BorderRadius.circular(14),
            boxShadow: hovered || selected ? AppShadows.card : null,
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
                    SelectableId(order.orderNumber,
                        style: AppType.mono(11, color: AppColors.textFaint),
                        selectable: onSelect != null),
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
