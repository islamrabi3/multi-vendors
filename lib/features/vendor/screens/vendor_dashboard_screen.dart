import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/tokens.dart';
import '../../../core/models/order.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/repositories/vendor_admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart' show ButtonSpinner;
import '../../auth/auth_cubit.dart';
import '../vendor_orders_cubit.dart';
import 'vendor_analytics_screen.dart';
import 'vendor_order_details_screen.dart';
import 'vendor_schedule_screen.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

enum _OrderFilter { incoming, preparing, ready, past }

/// The vendor's working screen.
///
/// Laid out around the one question a busy kitchen asks every few minutes —
/// "what needs me right now?" — so the answer is readable without scrolling:
/// a live count in the header, an escalating age chip per order, and a banner
/// whenever the store is in a state that stops or slows new orders.
///
/// Everything occasional (busy mode, analytics, opening hours) lives behind one
/// labelled sheet rather than a row of unlabeled icons in the header.
class VendorDashboardScreen extends StatelessWidget {
  const VendorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vendor = context.read<AuthCubit>().state.vendor;
    if (vendor == null) return const LoadingView();
    return BlocProvider(
      create: (_) => VendorOrdersCubit(
        OrderRepository(),
        vendor.id,
        autoAccept: vendor.autoAccept,
      ),
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
  final _admin = VendorAdminRepository();
  _OrderFilter _filter = _OrderFilter.incoming;
  bool _togglingOpen = false;
  bool _togglingBusy = false;

  /// Order shown in the detail pane. Split widths only; below that a tap still
  /// pushes the detail route.
  String? _selectedId;

  Future<void> _toggleOpen(bool open) async {
    final auth = context.read<AuthCubit>();
    final vendor = auth.state.vendor;
    if (vendor == null) return;
    setState(() => _togglingOpen = true);
    try {
      final updated = await _admin.updateVendor(vendor.id, {'is_open': open});
      auth.vendorUpdated(updated);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _togglingOpen = false);
    }
  }

  /// Busy mode used to fire bare, with no spinner and no catch — a failed
  /// write left the switch showing the old value and said nothing.
  Future<void> _toggleBusy(bool busy) async {
    final auth = context.read<AuthCubit>();
    final vendor = auth.state.vendor;
    if (vendor == null) return;
    setState(() => _togglingBusy = true);
    try {
      final updated = await _admin.toggleBusyMode(vendor.id, busy);
      auth.vendorUpdated(updated);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _togglingBusy = false);
    }
  }

  void _openStoreControls(Vendor vendor) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
      ),
      builder: (sheetContext) => _StoreControlsSheet(
        onToggleBusy: (value) {
          Navigator.pop(sheetContext);
          _toggleBusy(value);
        },
        onAnalytics: () {
          Navigator.pop(sheetContext);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VendorAnalyticsScreen(vendorId: vendor.id),
            ),
          );
        },
        onSchedule: () {
          Navigator.pop(sheetContext);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VendorScheduleScreen(vendorId: vendor.id),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vendor = context.select((AuthCubit c) => c.state.vendor);
    if (vendor == null) return const LoadingView();

    // Keep the cubit's auto-accept flag in sync with settings changes.
    context.read<VendorOrdersCubit>().autoAccept = vendor.autoAccept;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final split = AppBreakpoints.isSplit(constraints.maxWidth);
          return BlocConsumer<VendorOrdersCubit, VendorOrdersState>(
            listenWhen: (p, c) => c.newOrderArrived || c.error != null,
            listener: (context, state) {
              if (state.newOrderArrived) {
                showSnack(context, context.l10n.newOrderReceived);
              } else if (state.error != null) {
                showFailure(context, state.error!);
              }
            },
            builder: (context, state) {
              final cubit = context.read<VendorOrdersCubit>();
              final tabs = _FilterTabs(
                filter: _filter,
                incoming: state.pending.length,
                preparing: state.preparing.length,
                ready: state.ready.length,
                onChanged: _selectFilter,
              );
              final list = RefreshIndicator(
                color: AppColors.primary,
                onRefresh: cubit.refresh,
                child: _OrderList(
                  orders: _visibleOrders(state),
                  // Only the history tab pages; the live tabs are streamed.
                  paged: _filter == _OrderFilter.past,
                  loadingMore: state.loadingHistory,
                  hasMore: state.hasMoreHistory,
                  onLoadMore: cubit.loadMoreHistory,
                  selectedId: split ? _selectedId : null,
                  onSelect: split
                      ? (o) => setState(() => _selectedId = o.id)
                      : null,
                ),
              );
              return Column(
                children: [
                  _VerificationNotice(vendor: vendor),
                  _Header(
                    vendor: vendor,
                    actionable: state.pending.length + state.preparing.length,
                    togglingOpen: _togglingOpen,
                    onToggleOpen: _toggleOpen,
                    onOpenControls: () => _openStoreControls(vendor),
                  ),
                  _StatusBanner(
                    vendor: vendor,
                    busyPending: _togglingBusy,
                    onClearBusy: () => _toggleBusy(false),
                    onOpenStore: () => _toggleOpen(true),
                    onEditHours: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            VendorScheduleScreen(vendorId: vendor.id),
                      ),
                    ),
                  ),
                  if (state.loading)
                    const Expanded(child: LoadingView())
                  else ...[
                    _KpiBar(
                      revenue: state.todayRevenue,
                      orders: state.todayOrderCount,
                      avgPrep: vendor.totalPrepMinutes,
                    ),
                    if (!split) ...[
                      tabs,
                      Expanded(child: list),
                    ] else
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 16, bottom: 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 4,
                                child: Column(
                                  children: [
                                    tabs,
                                    Expanded(child: list),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 5,
                                child: _DetailPane(orderId: _selectedId),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _selectFilter(_OrderFilter filter) {
    setState(() => _filter = filter);
    if (filter == _OrderFilter.past) {
      // First visit to the history tab: pull its first page.
      final state = context.read<VendorOrdersCubit>().state;
      if (state.history.isEmpty) {
        context.read<VendorOrdersCubit>().loadMoreHistory();
      }
    }
  }

  List<AppOrder> _visibleOrders(VendorOrdersState state) => switch (_filter) {
    _OrderFilter.incoming => state.pending,
    _OrderFilter.preparing => state.preparing,
    _OrderFilter.ready => state.ready,
    _OrderFilter.past => state.history,
  };
}

/// Right-hand pane of the wide layout: the selected order, or a hint to pick
/// one.
class _DetailPane extends StatelessWidget {
  const _DetailPane({required this.orderId});

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
          : VendorOrderDetailsView(
              // Rebuild the view's state when the selection changes.
              key: ValueKey(orderId),
              orderId: orderId!,
              embedded: true,
            ),
    );
  }
}

/// Identity, workload, and the one switch that matters.
///
/// The three unlabeled icons that used to live here (busy / analytics /
/// schedule) squeezed the store name to nothing on a phone and were guesswork
/// on a touch device, where tooltips never appear. They moved into a labelled
/// sheet behind a single button.
class _Header extends StatelessWidget {
  const _Header({
    required this.vendor,
    required this.actionable,
    required this.togglingOpen,
    required this.onToggleOpen,
    required this.onOpenControls,
  });

  final Vendor vendor;

  /// Orders that are still the vendor's move — the workload line.
  final int actionable;
  final bool togglingOpen;
  final ValueChanged<bool> onToggleOpen;
  final VoidCallback onOpenControls;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      color: AppColors.ink,
      padding: EdgeInsets.fromLTRB(
        AppSpace.xl,
        MediaQuery.paddingOf(context).top + AppSpace.md,
        AppSpace.md,
        AppSpace.lg,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.warmFill,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                clipBehavior: Clip.antiAlias,
                child: vendor.logoUrl != null
                    ? AppNetworkImage(
                        url: vendor.logoUrl,
                        width: 44,
                        height: 44,
                      )
                    : const Icon(
                        Icons.storefront_rounded,
                        color: AppColors.primary,
                      ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vendor.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.heading(18, color: Colors.white),
                    ),
                    const SizedBox(height: 3),
                    // Replaces the address, which the vendor already knows, with
                    // the number they actually need off this screen.
                    Text(
                      actionable == 0
                          ? l10n.allCaughtUp
                          : '$actionable ${l10n.needsYourAttention}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: actionable == 0
                            ? Colors.white.withValues(alpha: 0.55)
                            : AppColors.onDarkSuccess,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              IconButton(
                onPressed: onOpenControls,
                tooltip: l10n.storeControls,
                icon: const Icon(Icons.tune_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          _OpenToggle(
            isOpen: vendor.isOpen,
            // The switch says "we are trading"; the timetable can still have
            // the store shut. Showing only the switch let an owner sit there
            // believing they were open at 2am.
            outsideHours: vendor.isOpen && !vendor.isOpenNow(),
            closingTime: vendor.closingTime(),
            busy: togglingOpen,
            onChanged: onToggleOpen,
          ),
        ],
      ),
    );
  }
}

/// Full-width so the store's own state is never a detail in the corner.
class _OpenToggle extends StatelessWidget {
  const _OpenToggle({
    required this.isOpen,
    required this.busy,
    required this.onChanged,
    this.outsideHours = false,
    this.closingTime,
  });

  /// The owner's own switch. Left as-is when the timetable closes the store, so
  /// tomorrow's opening does not need anyone to come back and flip it.
  final bool isOpen;

  /// The switch is on but today's hours have it shut anyway.
  final bool outsideHours;

  /// Today's closing time, `HH:MM`, when there is one.
  final String? closingTime;

  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final trading = isOpen && !outsideHours;
    final accent = trading
        ? AppColors.onDarkSuccess
        : outsideHours
        ? AppColors.amberInk
        : AppColors.navInactive;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.sm,
        AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.inkElevated,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              outsideHours
                  ? l10n.closedOutsideHours
                  : trading && closingTime != null
                  ? l10n.openUntil(closingTime!)
                  : isOpen
                  ? l10n.open
                  : l10n.closed,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            height: 26,
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(5),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Transform.scale(
                    scale: 0.85,
                    child: Switch(
                      value: isOpen,
                      onChanged: onChanged,
                      activeThumbColor: Colors.white,
                      activeTrackColor: AppColors.success,
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor: AppColors.onDarkTrack,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Says out loud when the store is in a state that stops or slows orders.
///
/// Closed and busy were previously only visible as a switch position and an
/// icon tint, so a store could sit closed all morning without anyone noticing
/// why nothing was coming in.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.vendor,
    required this.busyPending,
    required this.onClearBusy,
    required this.onOpenStore,
    required this.onEditHours,
  });

  final Vendor vendor;
  final bool busyPending;
  final VoidCallback onClearBusy;
  final VoidCallback onOpenStore;

  /// Opens the weekly hours — the only thing that fixes an out-of-hours store,
  /// since the switch is already on.
  final VoidCallback onEditHours;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Closed outranks busy: it is the one that stops orders outright.
    if (!vendor.isOpen) {
      return _banner(
        icon: Icons.do_not_disturb_on_outlined,
        fill: AppColors.dangerFill,
        ink: AppColors.dangerInk,
        message: l10n.storeClosedNotice,
        actionLabel: l10n.open,
        onAction: onOpenStore,
        pending: false,
      );
    }
    // The switch is on and the store still takes nothing, which is the state
    // most likely to be mistaken for a dead app. Flipping the switch would not
    // help, so the action goes to the timetable instead.
    if (!vendor.isOpenNow()) {
      return _banner(
        icon: Icons.schedule_rounded,
        fill: AppColors.amberFill,
        ink: AppColors.amberInk,
        message: l10n.outsideOpeningHoursNotice,
        actionLabel: l10n.editHours,
        onAction: onEditHours,
        pending: false,
      );
    }
    if (vendor.isBusy) {
      return _banner(
        icon: Icons.local_fire_department_outlined,
        fill: AppColors.amberFill,
        ink: AppColors.amberInk,
        message: l10n.busyStoreNotice,
        actionLabel: l10n.off,
        onAction: onClearBusy,
        pending: busyPending,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _banner({
    required IconData icon,
    required Color fill,
    required Color ink,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
    required bool pending,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.sm,
        AppSpace.md,
      ),
      color: fill,
      child: Row(
        children: [
          Icon(icon, size: 18, color: ink),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
          if (pending)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: ButtonSpinner(size: 16),
            )
          else
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: ink),
              child: Text(
                actionLabel,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }
}

/// Today's numbers as one flat rail.
///
/// This was three elevated cards costing ~110pt of height on a phone. The
/// numbers are reference, not the job, so they now read as a single line and
/// hand the reclaimed space to the order list.
class _KpiBar extends StatelessWidget {
  const _KpiBar({
    required this.revenue,
    required this.orders,
    required this.avgPrep,
  });

  final double revenue;
  final int orders;
  final int avgPrep;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.lg,
        AppSpace.xs,
      ),
      padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(
        children: [
          _stat(formatMoney(revenue), l10n.itemSales),
          _divider(),
          _stat('$orders', l10n.orders),
          _divider(),
          _stat('$avgPrep ${l10n.min}', l10n.avgPrep),
        ],
      ),
    );
  }

  Widget _divider() =>
      Container(width: 1, height: 26, color: AppColors.borderSoft);

  Widget _stat(String value, String label) => Expanded(
    child: Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: AppType.mono(
              15,
              color: AppColors.ink,
              weight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
          ),
        ),
      ],
    ),
  );
}

/// Busy mode, analytics and opening hours — labelled, with the consequence of
/// each spelled out.
class _StoreControlsSheet extends StatelessWidget {
  const _StoreControlsSheet({
    required this.onToggleBusy,
    required this.onAnalytics,
    required this.onSchedule,
  });

  final ValueChanged<bool> onToggleBusy;
  final VoidCallback onAnalytics;
  final VoidCallback onSchedule;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final vendor = context.select((AuthCubit c) => c.state.vendor);
    if (vendor == null) return const SizedBox.shrink();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.xl,
              0,
              AppSpace.xl,
              AppSpace.md,
            ),
            child: Text(l10n.storeControls, style: AppType.heading(17)),
          ),
          SwitchListTile(
            value: vendor.isBusy,
            onChanged: onToggleBusy,
            secondary: Icon(
              Icons.local_fire_department_outlined,
              color: vendor.isBusy ? AppColors.amberInk : AppColors.textMuted,
            ),
            title: Text(
              l10n.busyStore,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              l10n.busyMode,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          const Divider(height: 1, color: AppColors.borderSoft),
          ListTile(
            onTap: onAnalytics,
            leading: const Icon(
              Icons.insights_rounded,
              color: AppColors.textSecondary,
            ),
            title: Text(
              l10n.vendorAnalytics,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textFaint,
            ),
          ),
          const Divider(height: 1, color: AppColors.borderSoft),
          ListTile(
            onTap: onSchedule,
            leading: const Icon(
              Icons.schedule_rounded,
              color: AppColors.textSecondary,
            ),
            title: Text(
              l10n.operatingSchedule,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textFaint,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
      ),
    );
  }
}

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({
    required this.filter,
    required this.incoming,
    required this.preparing,
    required this.ready,
    required this.onChanged,
  });

  final _OrderFilter filter;
  final int incoming;
  final int preparing;
  final int ready;
  final ValueChanged<_OrderFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          _tab(context.l10n.newText, incoming, _OrderFilter.incoming, context),
          const SizedBox(width: 10),
          _tab(
            context.l10n.preparing,
            preparing,
            _OrderFilter.preparing,
            context,
          ),
          const SizedBox(width: 10),
          _tab(context.l10n.ready, ready, _OrderFilter.ready, context),
          const SizedBox(width: 10),
          // History is paged, so it carries no count badge.
          _tab(context.l10n.past, null, _OrderFilter.past, context),
        ],
      ),
    );
  }

  Widget _tab(
    String label,
    int? count,
    _OrderFilter value,
    BuildContext context,
  ) {
    final selected = filter == value;
    // A zero count is noise on a filter chip — the tab is still reachable.
    final showCount = count != null && count > 0;
    return HoverBuilder(
      builder: (context, hovered) => GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.ink : AppColors.surface,
            border: Border.all(
              color: selected
                  ? AppColors.ink
                  : hovered
                  ? AppColors.primary
                  : AppColors.border,
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(AppRadii.pill),
            boxShadow: selected || hovered ? AppShadows.card : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              if (showCount) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : AppColors.warmFill,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: selected ? Colors.white : AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  const _OrderList({
    required this.orders,
    required this.paged,
    required this.loadingMore,
    required this.hasMore,
    required this.onLoadMore,
    this.selectedId,
    this.onSelect,
  });

  final List<AppOrder> orders;

  /// True on the history tab, which loads a page at a time.
  final bool paged;
  final bool loadingMore;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final String? selectedId;
  final ValueChanged<AppOrder>? onSelect;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          if (paged && loadingMore)
            const LoadingView()
          else
            EmptyView(
              message: context.l10n.nothingHereRightNow,
              icon: Icons.receipt_long_outlined,
            ),
        ],
      );
    }
    final list = ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: orders.length + (paged ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == orders.length) {
          return PagingFooter(loading: loadingMore, hasMore: hasMore);
        }
        return _OrderCard(
          order: orders[i],
          selected: orders[i].id == selectedId,
          onSelect: onSelect,
        );
      },
    );
    if (!paged) return list;
    return InfiniteScroll(onLoadMore: onLoadMore, child: list);
  }
}

/// How long the order has been sitting, escalating as it ages.
///
/// The card previously showed only the time it was placed, leaving the vendor
/// to do the arithmetic on the busiest screen in the app. Colour carries the
/// urgency so a late order is findable by scanning, not reading.
class _OrderAgeChip extends StatelessWidget {
  const _OrderAgeChip({required this.placedAt});

  final DateTime placedAt;

  @override
  Widget build(BuildContext context) {
    final minutes = DateTime.now().difference(placedAt).inMinutes;

    // Past an hour the elapsed figure stops being actionable, so the card falls
    // back to the wall-clock time it was placed.
    if (minutes >= 60) {
      return Text(
        DateFormat('h:mm a').format(placedAt),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
        ),
      );
    }

    final (fill, ink) = switch (minutes) {
      < 5 => (AppColors.successFill, AppColors.successInk),
      < 10 => (AppColors.amberFill, AppColors.amberInk),
      _ => (AppColors.dangerFill, AppColors.dangerInk),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadii.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, size: 12, color: ink),
          const SizedBox(width: 4),
          Text(
            '$minutes${context.l10n.minutesAgo}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, this.selected = false, this.onSelect});

  final AppOrder order;
  final bool selected;

  /// Set on split widths: pick the row into the detail pane instead of
  /// navigating away.
  final ValueChanged<AppOrder>? onSelect;

  String _payLabel(BuildContext context) => order.isCod
      ? context.l10n.cod
      : order.isPaid
      ? context.l10n.cardPaid
      : context.l10n.cardUnpaid;

  @override
  Widget build(BuildContext context) =>
      HoverBuilder(builder: (context, hovered) => _card(context, hovered));

  Widget _card(BuildContext context, bool hovered) {
    final cubit = context.read<VendorOrdersCubit>();
    final isNew = order.status == OrderStatus.pending;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(
          color: selected
              ? AppColors.primary
              : hovered
              ? AppColors.primaryLight
              : isNew
              ? AppColors.attentionBorder
              : AppColors.border,
          width: isNew || selected ? 1.6 : 1.0,
        ),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: isNew ? AppShadows.raised : AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onSelect != null
                ? onSelect!(order)
                : context.push('/vendor-app/orders/${order.id}'),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Line 1: which order, and how long it has been waiting.
                  Row(
                    children: [
                      SelectableId(
                        order.orderNumber,
                        style: AppType.mono(
                          14.5,
                          color: AppColors.ink,
                          weight: FontWeight.w700,
                        ),
                        selectable: onSelect != null,
                      ),
                      const SizedBox(width: AppSpace.sm),
                      _OrderAgeChip(placedAt: order.createdAt),
                      const Spacer(),
                      OrderStatusChip(status: order.status),
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  // Line 2: how it leaves the kitchen. A collection order and a
                  // slot booked for tonight need different handling from a
                  // rider job, and the card said nothing about either.
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OrderTypeChip(order: order),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  // Line 3: who it is for, what it is worth, how it is paid.
                  // Three facts on one row replaces the old divider plus
                  // "TOTAL AMOUNT" caps label, which cost height and said
                  // nothing the number did not.
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          order.customerName ?? context.l10n.customer,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: order.isCod
                              ? AppColors.amberFill
                              : AppColors.successFill,
                          borderRadius: BorderRadius.circular(AppRadii.xs),
                        ),
                        child: Text(
                          _payLabel(context).toUpperCase(),
                          style: TextStyle(
                            color: order.isCod
                                ? AppColors.amberInk
                                : AppColors.successInk,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      PriceText(formatMoney(order.total), size: 15),
                    ],
                  ),
                  _ActionRow(order: order, cubit: cubit),
                ],
              ),
            ),
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
    final localUnavailable = context.l10n.unavailable;
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.rejectOrder),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: context.l10n.reason),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.back),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(context.l10n.reject),
          ),
        ],
      ),
    );
    if (reason != null) {
      await cubit.reject(order, reason.isEmpty ? localUnavailable : reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = switch (order.status) {
      OrderStatus.pending => Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
              ),
              onPressed: () => _rejectWithReason(context),
              child: Text(context.l10n.reject),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.success,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
              ),
              onPressed: () => cubit.accept(order),
              child: Text(context.l10n.acceptOrder),
            ),
          ),
        ],
      ),
      OrderStatus.accepted => FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
        ),
        onPressed: () => cubit.startPreparing(order),
        child: Text(context.l10n.startPreparing),
      ),
      OrderStatus.preparing => FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
        ),
        onPressed: () => cubit.markReady(order),
        child: Text(context.l10n.markReadyForPickup),
      ),
      // Nobody is coming for a collection order, so "waiting for a driver"
      // would be a lie the store could never act on.
      OrderStatus.readyForPickup when order.isPickup => FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
        ),
        onPressed: () => cubit.markCollected(order),
        icon: const Icon(Icons.shopping_bag_outlined, size: 18),
        label: Text(context.l10n.markCollected),
      ),
      OrderStatus.readyForPickup => Padding(
        padding: const EdgeInsets.only(top: AppSpace.sm),
        child: Row(
          children: [
            const Icon(
              Icons.hourglass_empty_rounded,
              color: AppColors.success,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              context.l10n.waitingForADriver,
              style: const TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
      _ => const SizedBox.shrink(),
    };
    if (child is SizedBox) return child;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md),
      child: child,
    );
  }
}


/// Why an unapproved store sees orders it cannot act on.
///
/// Accepting is refused server-side by is_vendor_owner(), which requires
/// approval_status = 'active'. Without this the vendor met a bare
/// TRANSITION_NOT_ALLOWED and no explanation.
class _VerificationNotice extends StatelessWidget {
  const _VerificationNotice({required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    if (vendor.isApproved) return const SizedBox.shrink();
    final suspended = vendor.approvalStatus == 'suspended';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.lg,
        0,
      ),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: suspended ? AppColors.dangerFill : AppColors.warmFill,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            suspended ? Icons.block_rounded : Icons.hourglass_top_rounded,
            size: 20,
            color: suspended ? AppColors.dangerInk : AppColors.primaryDark,
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              suspended
                  ? context.l10n.suspendedVendorNotice
                  : context.l10n.unverifiedVendorNotice,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: suspended ? AppColors.dangerInk : AppColors.primaryDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
