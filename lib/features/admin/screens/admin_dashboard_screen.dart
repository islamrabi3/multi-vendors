import 'package:flutter/material.dart';
import 'package:multi_vendor/core/widgets/count_badge.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/models/finance.dart';
import '../../../core/models/order.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/messages_button.dart';
import '../../../core/widgets/notification_bell.dart';
import '../../auth/auth_cubit.dart';
import '../admin_dashboard_cubit.dart';
import 'admin_order_detail_screen.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';
import '../admin_shell.dart' show AdminWebNav;
import '../admin_action_badges.dart';
import '../../../core/widgets/web/console.dart';
import 'admin_manage_screen.dart' show adminManageGroups;

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
          final webWide = AppBreakpoints.isWebWide(context);
          return BlocBuilder<AdminDashboardCubit, AdminDashboardState>(
            builder: (context, state) {
              final cubit = context.read<AdminDashboardCubit>();
              // The desktop console gets a page of its own rather than the
              // tablet's split view: an action queue, the day's money, and
              // the live board beside who is owed.
              if (webWide) {
                return _WebOverview(
                  state: state,
                  onRefresh: cubit.refreshStats,
                );
              }
              if (split) {
                return Column(
                  children: [
                    // The mobile hero is a full-bleed dark block sized to be
                    // the first thing seen scrolling on a phone — on web,
                    // where the sidebar already carries the brand and "Live
                    // overview" repeats the top bar's page title, that same
                    // block is 300px of a monitor spent on five numbers. A
                    // slim strip says the same thing in a fifth of the height.
                    webWide
                        ? _WebStatStrip(stats: state.stats)
                        : _Header(stats: state.stats),
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
                          const SizedBox(height: 14),
                          const _ManageGrid(),
                          if (!state.moneyDenied) ...[
                            const SizedBox(height: 18),
                            _MoneyPanel(state: state),
                          ],
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Text(
                                context.l10n.liveOrders,
                                style: AppType.heading(17),
                              ),
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
                                icon: Icons.receipt_long_outlined,
                              ),
                            )
                          else
                            ...state.liveOrders.map(
                              (o) => Padding(
                                padding: const EdgeInsets.only(bottom: 9),
                                child: _LiveOrderCard(
                                  order: o,
                                  label: state.vendorLabels[o.vendorId]?.name,
                                ),
                              ),
                            ),
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

/// The handful of places an admin goes several times a day.
///
/// Everything occasional lives behind Manage, which is right — but it made the
/// four or five daily destinations cost two taps and a scan of a long list.
/// These are the ones worth a shortcut, gated by permission so a scoped role
/// is not shown a door it cannot open.
/// Every occasional admin tool, grouped and shown as a grid right on
/// Overview.
///
/// Previously a full bottom-tab of its own ("Manage") plus a smaller,
/// hand-duplicated shortcuts strip up here that only ever covered six of the
/// admin's ~17 tools and kept its own separate permission list to stay in
/// sync with. One phone tab bar slot goes back to something daily (there
/// were only four to begin with), and one list — [adminManageGroups], the
/// same one the desktop sidebar already builds from — instead of two that
/// could disagree.
class _ManageGrid extends StatelessWidget {
  const _ManageGrid();

  @override
  Widget build(BuildContext context) {
    final groups = adminManageGroups(context);
    if (groups.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (title, items) in groups) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Text(
              title,
              style: AppType.heading(14, color: AppColors.textSecondary),
            ),
          ),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.98,
            children: [
              for (final item in items)
                Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  child: InkWell(
                    onTap: () => AdminWebNav.go(context, item.route),
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          WithCountBadge(
                            count: item.badge,
                            top: -8,
                            end: -14,
                            child: Icon(
                              item.icon,
                              size: 22,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Flexible(
                            child: Text(
                              item.label,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
        ],
      ],
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
        if (!state.moneyDenied) ...[
          _MoneyPanel(state: state),
          const SizedBox(height: 18),
        ],
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
                  icon: Icons.receipt_long_outlined,
                )
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

/// What the day took, and who is waiting to be paid out of it.
///
/// Two different kinds of number, kept visibly apart. The day's figures are a
/// period — what was sold since midnight and what the platform kept of it.
/// What a store or a rider is *owed* is a running balance that has nothing to
/// do with today: settle a shop its lunchtime share and the account is still
/// not clear. An operator reading one as the other pays the wrong amount.
class _MoneyPanel extends StatelessWidget {
  const _MoneyPanel({required this.state});

  final AdminDashboardState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = state.today;
    final stores = state.vendorBalances
        .where((party) => party.payable > 0)
        .toList();
    final riders = state.driverBalances
        .where((party) => party.payable > 0)
        .toList();
    final cashOut = state.driverBalances.fold<double>(
      0,
      (sum, party) => sum + party.cashDue,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(l10n.todaysMoney, style: AppType.heading(16)),
            ],
          ),
          const SizedBox(height: 12),
          if (today == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                _MoneyStat(
                  label: l10n.salesToday,
                  value: today.grossRevenue,
                  tone: AppColors.ink,
                ),
                _MoneyStat(
                  label: l10n.profitToday,
                  value: today.platformEarnings,
                  tone: AppColors.successInk,
                ),
                _MoneyStat(
                  label: l10n.storesShareToday,
                  value: today.vendorEarnings,
                ),
                _MoneyStat(
                  label: l10n.driversShareToday,
                  value: today.driverEarnings,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _OwedList(
              title: l10n.owedToStores,
              icon: Icons.storefront_rounded,
              parties: stores,
            ),
            const SizedBox(height: 14),
            _OwedList(
              title: l10n.owedToDrivers,
              icon: Icons.two_wheeler_rounded,
              parties: riders,
            ),
            if (cashOut > 0) ...[
              const SizedBox(height: 12),
              // Money the platform is owed rather than owes: cash a rider
              // took from a customer and has not handed in.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.amberFill,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.payments_outlined,
                      size: 16,
                      color: AppColors.amberInk,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.cashHeldByDrivers,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.amberInk,
                        ),
                      ),
                    ),
                    Text(
                      formatMoney(cashOut),
                      style: AppType.mono(13, color: AppColors.amberInk),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _MoneyStat extends StatelessWidget {
  const _MoneyStat({required this.label, required this.value, this.tone});

  final String label;
  final double value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        border: Border.all(color: AppColors.borderSoft),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              formatMoney(value),
              style: AppType.mono(15, color: tone ?? AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Who is owed what, by name, biggest first — the order an operator settles
/// in. Capped at five with the rest counted, because this is the overview and
/// the finance screen is where the whole list lives.
class _OwedList extends StatelessWidget {
  const _OwedList({
    required this.title,
    required this.icon,
    required this.parties,
  });

  final String title;
  final IconData icon;
  final List<PartyBalance> parties;

  static const _shown = 5;

  @override
  Widget build(BuildContext context) {
    final sorted = [...parties]..sort((a, b) => b.payable.compareTo(a.payable));
    final total = sorted.fold<double>(0, (sum, p) => sum + p.payable);
    final visible = sorted.take(_shown).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: AppColors.textMuted),
            const SizedBox(width: 7),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              formatMoney(total),
              style: AppType.mono(13, color: AppColors.primaryDark),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (visible.isEmpty)
          Text(
            context.l10n.nothingOwed,
            style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
          )
        else
          for (final party in visible)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      party.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatMoney(party.payable),
                    style: AppType.mono(12.5, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
        if (sorted.length > _shown)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              context.l10n.andNMore(sorted.length - _shown),
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textFaint,
              ),
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
            border: AppColors.attentionBorder,
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
            count: stats.driversPending,
            label: context.l10n.driversToApprove,
            icon: Icons.delivery_dining_outlined,
            fill: AppColors.surface,
            border: AppColors.border,
            ink: AppColors.ink,
            onTap: () => AdminWebNav.go(context, '/admin-app/drivers'),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          // Support was two taps behind the Manage tab, so a waiting customer
          // was only found by someone who went looking. An unanswered thread
          // is the same kind of debt as an order nobody has moved, so it sits
          // with them — and turns amber once there is one.
          child: _AttentionCard(
            count: stats.supportOpen,
            label: context.l10n.openSupportThreads,
            icon: Icons.support_agent_rounded,
            fill: stats.supportOpen > 0
                ? AppColors.warmFill
                : AppColors.surface,
            border: stats.supportOpen > 0
                ? AppColors.attentionBorder
                : AppColors.border,
            ink: stats.supportOpen > 0 ? AppColors.primaryDark : AppColors.ink,
            onTap: () => AdminWebNav.go(context, '/admin-app/support'),
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
        22,
        MediaQuery.of(context).padding.top + 14,
        22,
        20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.platformToday,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: AppColors.onDarkSuccess,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          context.l10n.liveOverview,
                          style: AppType.heading(21, color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const MessagesButton.staff(compact: true, dark: true),
              const SizedBox(width: 5),
              const NotificationBell(compact: true, dark: true),
              const SizedBox(width: 5),
              _AvatarButton(
                onSignOut: () => context.read<AuthCubit>().signOut(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.grossMerchandiseValue,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoney(stats.gmvToday),
              style: AppType.display(38, color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _DarkStat(
                value: '${stats.ordersToday}',
                label: context.l10n.orders,
              ),
              const SizedBox(width: 9),
              _DarkStat(
                value: '${stats.vendorsOpen}',
                suffix: 'on',
                label: context.l10n.vendors,
              ),
              const SizedBox(width: 9),
              _DarkStat(
                value: '${stats.driversOnline}',
                suffix: 'on',
                label: context.l10n.drivers,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The web-width replacement for [_Header]: the same five numbers, one row,
/// on the ordinary surface rather than a dark hero — the sidebar already
/// carries the brand and the top bar already carries the page title, so
/// this only needs to say what's true right now.
class _WebStatStrip extends StatelessWidget {
  const _WebStatStrip({required this.stats});

  final AdminStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      // Every item here is a fixed width, so at 900px — the narrowest window
      // that still gets the web layout — a large currency value or a longer
      // translation runs the row past the edge. Scrolling beats a striped
      // overflow bar drawn across the day's numbers.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          // Required inside a horizontal scroll: the default `max` demands an
          // unbounded width and fails outright rather than overflowing.
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.grossMerchandiseValue,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(width: 8),
            Text(
              formatMoney(stats.gmvToday),
              style: AppType.mono(20, weight: FontWeight.w800),
            ),
            const SizedBox(width: 28),
            Container(width: 1, height: 24, color: AppColors.border),
            const SizedBox(width: 28),
            _InlineStat(value: '${stats.ordersToday}', label: l10n.orders),
            const SizedBox(width: 24),
            _InlineStat(
              value: '${stats.vendorsOpen}',
              label: l10n.vendors,
              tone: AppColors.successInk,
            ),
            const SizedBox(width: 24),
            _InlineStat(
              value: '${stats.driversOnline}',
              label: l10n.drivers,
              tone: AppColors.successInk,
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat({required this.value, required this.label, this.tone});

  final String value;
  final String label;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: AppType.mono(
            16,
            weight: FontWeight.w800,
            color: tone ?? AppColors.ink,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    // Every management tool now lives on Overview as a grid — this is the
    // plain account menu it always looked like.
    return PopupMenuButton<String>(
      onSelected: (value) =>
          value == 'password' ? context.push('/change-password') : onSignOut(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'password',
          child: Row(
            children: [
              const Icon(
                Icons.key_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpace.sm),
              Text(context.l10n.changePassword),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'signout',
          child: Row(
            children: [
              const Icon(
                Icons.logout_rounded,
                size: 18,
                color: AppColors.dangerInk,
              ),
              const SizedBox(width: AppSpace.sm),
              Text(
                context.l10n.signOut,
                style: const TextStyle(color: AppColors.dangerInk),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.inkElevated,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(
          context.l10n.a,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
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
          color: AppColors.inkElevated,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: AppType.display(19, color: Colors.white)),
                if (suffix != null) ...[
                  const SizedBox(width: 3),
                  Text(
                    context.l10n.on,
                    style: TextStyle(
                      color: AppColors.onDarkSuccess,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 10.5,
              ),
            ),
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
            border: AppColors.attentionBorder,
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
              color: hovered && onTap != null ? AppColors.primary : border,
            ),
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
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
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
            color: AppColors.success,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          context.l10n.updating,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
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
                  ? AppColors.attentionBorder
                  : AppColors.border,
              width: flagged || selected ? 1.5 : 1,
            ),
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
                  url: order.vendorLogoUrl,
                  width: 38,
                  height: 38,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableId(
                      order.orderNumber,
                      style: AppType.mono(11, color: AppColors.textFaint),
                      selectable: onSelect != null,
                    ),
                    Text(
                      '${label ?? order.vendorName ?? context.l10n.store} → '
                      '${order.customerName ?? context.l10n.customer}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
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
                  if (flagged)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryDark,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${context.l10n.stuck} ${DateTime.now().difference(order.createdAt).inMinutes}${context.l10n.mShort}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 10.5,
                        ),
                      ),
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

/// The admin's desktop Overview.
///
/// One question first — "does anything need me?" — answered by the action
/// queue, which is the only loud thing on the page. Then the day's money, then
/// the live board beside the balances an operator settles from.
class _WebOverview extends StatelessWidget {
  const _WebOverview({required this.state, required this.onRefresh});

  final AdminDashboardState state;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = context.watch<AuthCubit>().state;
    final name = auth.profile?.fullName.trim().split(RegExp(r'\s+')).first;
    final today = state.today;
    final stats = state.stats;

    return ConsolePage(
      title: name == null || name.isEmpty
          ? l10n.overview
          : l10n.helloName(name),
      description: l10n.overviewDescription,
      onRefresh: onRefresh,
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go('/admin-app/orders'),
          icon: const Icon(Icons.receipt_long_rounded, size: 18),
          label: Text(l10n.openOrderBoard),
        ),
      ],
      children: [
        const _ActionQueue(),
        const SizedBox(height: AppSpace.xxl),
        Text(l10n.today, style: AppType.heading(17)),
        const SizedBox(height: AppSpace.md),
        ConsoleGrid(
          minTileWidth: 170,
          maxColumns: 5,
          children: [
            ConsoleStat(
              label: l10n.grossMerchandiseValue,
              value: formatMoney(stats.gmvToday),
              icon: Icons.shopping_bag_outlined,
            ),
            ConsoleStat(
              label: l10n.orders,
              value: '${stats.ordersToday}',
              icon: Icons.receipt_long_outlined,
              onTap: () => context.go('/admin-app/orders'),
            ),
            if (!state.moneyDenied && today != null) ...[
              ConsoleStat(
                label: l10n.profitToday,
                value: formatMoney(today.platformEarnings),
                icon: Icons.trending_up_rounded,
                tone: today.platformEarnings > 0
                    ? ConsoleTone.good
                    : ConsoleTone.plain,
                onTap: () => AdminWebNav.go(context, '/admin-app/finance'),
              ),
            ],
            ConsoleStat(
              label: l10n.storesOpenNow,
              value: '${stats.vendorsOpen} / ${stats.vendorsActive}',
              icon: Icons.store_mall_directory_outlined,
              onTap: () => context.go('/admin-app/vendors'),
            ),
            ConsoleStat(
              label: l10n.driversOnlineNow,
              value: '${stats.driversOnline}',
              icon: Icons.two_wheeler_rounded,
              tone: stats.driversOnline == 0 && stats.ordersToday > 0
                  ? ConsoleTone.warn
                  : ConsoleTone.plain,
              hint: stats.driversOnline == 0 ? l10n.noDriversOnlineHint : null,
              onTap: () => AdminWebNav.go(context, '/admin-app/drivers'),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xxl),
        LayoutBuilder(
          builder: (context, constraints) {
            final board = _LiveBoard(state: state);
            final money = state.moneyDenied
                ? null
                : _BalancesPanel(state: state);
            if (constraints.maxWidth < 980 || money == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  board,
                  if (money != null) ...[
                    const SizedBox(height: AppSpace.lg),
                    money,
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: board),
                const SizedBox(width: AppSpace.lg),
                Expanded(flex: 2, child: money),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Everything waiting on staff, from the same live counts as the sidebar
/// badges. Each item is a door to where it is dealt with; when nothing is
/// waiting, the queue says so in one calm line instead of a row of zeros.
class _ActionQueue extends StatelessWidget {
  const _ActionQueue();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final badges = AdminActionBadges.instance;
    final items =
        <({String key, IconData icon, String label, VoidCallback go})>[
          (
            key: AdminActionBadges.ordersAttention,
            icon: Icons.receipt_long_rounded,
            label: l10n.ordersNeedAttention,
            go: () => context.go('/admin-app/orders'),
          ),
          (
            key: AdminActionBadges.supportAwaiting,
            icon: Icons.support_agent_rounded,
            label: l10n.openSupportThreads,
            go: () => AdminWebNav.go(context, '/admin-app/support'),
          ),
          (
            key: AdminActionBadges.reportsPending,
            icon: Icons.report_problem_outlined,
            label: l10n.customerReports,
            go: () => AdminWebNav.go(context, '/admin-app/complaints'),
          ),
          (
            key: AdminActionBadges.vendorsPending,
            icon: Icons.storefront_rounded,
            label: l10n.vendorsToApprove,
            go: () => context.go('/admin-app/vendors'),
          ),
          (
            key: AdminActionBadges.driversPending,
            icon: Icons.delivery_dining_rounded,
            label: l10n.driversToApprove,
            go: () => AdminWebNav.go(context, '/admin-app/drivers'),
          ),
          (
            key: AdminActionBadges.settlementRequests,
            icon: Icons.handshake_outlined,
            label: l10n.settlementsTitle,
            go: () => AdminWebNav.go(context, '/admin-app/settlements'),
          ),
          (
            key: AdminActionBadges.depositsPending,
            icon: Icons.account_balance_outlined,
            label: l10n.depositsAwaitingReview,
            go: () => AdminWebNav.go(context, '/admin-app/deposits'),
          ),
        ];
    final listenables = [for (final i in items) badges.countFor(i.key)];

    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) {
        final waiting = [
          for (var i = 0; i < items.length; i++)
            if (listenables[i].value > 0)
              (item: items[i], count: listenables[i].value),
        ];
        final total = waiting.fold<int>(0, (sum, w) => sum + w.count);
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: waiting.isEmpty ? AppColors.surface : AppColors.ink,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(
              color: waiting.isEmpty ? AppColors.border : AppColors.ink,
            ),
          ),
          child: waiting.isEmpty
              ? Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: AppColors.successFill,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: AppColors.successInk,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.allClear, style: AppType.heading(16)),
                          Text(
                            l10n.allClearDescription,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          l10n.needsYouNow,
                          style: AppType.heading(17, color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.onDarkPistachio,
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                          ),
                          child: Text(
                            '$total',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final w in waiting)
                          _QueueItem(
                            icon: w.item.icon,
                            label: w.item.label,
                            count: w.count,
                            onTap: w.item.go,
                          ),
                      ],
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _QueueItem extends StatelessWidget {
  const _QueueItem({
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.inkElevated,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        hoverColor: Colors.white.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppColors.onDarkPistachio),
              const SizedBox(width: 10),
              Text('$count', style: AppType.display(20, color: Colors.white)),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  label,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The orders still moving, newest first, as a dense list. A row opens the
/// order beside the board rather than taking the operator away from it.
class _LiveBoard extends StatelessWidget {
  const _LiveBoard({required this.state});

  final AdminDashboardState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final orders = state.liveOrders;
    return ConsolePanel(
      title: l10n.liveOrders,
      subtitle: l10n.liveOrdersCount(orders.length),
      trailing: const Padding(
        padding: EdgeInsets.only(top: 4, right: 8),
        child: _UpdatingDot(),
      ),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      child: state.loading
          ? const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          : orders.isEmpty
          ? ConsoleEmpty(
              icon: Icons.receipt_long_outlined,
              title: l10n.noLiveOrdersRightNow,
              message: l10n.noLiveOrdersHint,
            )
          : Column(
              children: [
                for (final order in orders.take(12))
                  _LiveRow(
                    order: order,
                    store:
                        state.vendorLabels[order.vendorId]?.name ??
                        order.vendorName ??
                        l10n.store,
                  ),
                if (orders.length > 12)
                  TextButton(
                    onPressed: () => context.go('/admin-app/orders'),
                    child: Text(l10n.andNMore(orders.length - 12)),
                  ),
              ],
            ),
    );
  }
}

class _LiveRow extends StatelessWidget {
  const _LiveRow({required this.order, required this.store});

  final AppOrder order;
  final String store;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final minutes = DateTime.now().difference(order.createdAt).inMinutes;
    final stuck = AdminOrdersStuck.isStuck(order);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.sm),
      onTap: () => showConsoleSidePanel<void>(
        context,
        title: l10n.orderRef(order.orderNumber),
        child: AdminOrderDetailView(orderId: order.id, embedded: true),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(
                order.orderNumber,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.mono(12.5, color: AppColors.textSecondary),
              ),
            ),
            Expanded(
              child: Text(
                '$store → ${order.customerName ?? l10n.customer}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 70,
              child: Text(
                l10n.minutesAgoShort(minutes),
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: stuck ? FontWeight.w800 : FontWeight.w500,
                  color: stuck ? AppColors.dangerInk : AppColors.textMuted,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 130,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: OrderStatusChip(status: order.status),
              ),
            ),
            SizedBox(
              width: 100,
              child: Text(
                formatMoney(order.total),
                textAlign: TextAlign.end,
                style: AppType.mono(13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Who is owed money right now, and cash the platform is owed back. Running
/// balances, not today's figures — those are in the stat row above.
class _BalancesPanel extends StatelessWidget {
  const _BalancesPanel({required this.state});

  final AdminDashboardState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final stores = state.vendorBalances.where((p) => p.payable > 0).toList();
    final riders = state.driverBalances.where((p) => p.payable > 0).toList();
    final cashOut = state.driverBalances.fold<double>(
      0,
      (sum, party) => sum + party.cashDue,
    );
    return ConsolePanel(
      title: l10n.balances,
      subtitle: l10n.balancesHint,
      trailing: TextButton(
        onPressed: () => AdminWebNav.go(context, '/admin-app/settlements'),
        child: Text(l10n.settle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OwedList(
            title: l10n.owedToStores,
            icon: Icons.storefront_rounded,
            parties: stores,
          ),
          const Divider(height: 28, color: AppColors.borderSoft),
          _OwedList(
            title: l10n.owedToDrivers,
            icon: Icons.two_wheeler_rounded,
            parties: riders,
          ),
          if (cashOut > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.amberFill,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.payments_outlined,
                    size: 16,
                    color: AppColors.amberInk,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.cashHeldByDrivers,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.amberInk,
                      ),
                    ),
                  ),
                  Text(
                    formatMoney(cashOut),
                    style: AppType.mono(13, color: AppColors.amberInk),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
