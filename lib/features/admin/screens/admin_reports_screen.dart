import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/file_save.dart';
import '../../../core/utils/menu_export.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/web/console.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import '../../../core/widgets/web/web_table.dart';
import 'admin_manage_screen.dart' show adminManageWebSections;
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// `10` and `12.5` both read better without trailing zeros.
String _percent(double rate) =>
    '${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}%';

/// What the platform took, what each store is owed, and what each driver is
/// owed — over one period, from one set of server-side figures.
///
/// The vendor and driver tabs answer "who do I pay"; the platform tab answers
/// "what is left, and how much of it is still cash in a driver's pocket",
/// which is the question a cash-heavy market actually settles on.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key, this.embedded = false});

  /// True when a web sidebar is already drawing the shell around this screen
  /// (`_AdminWebShell`) — skips this widget's own [WebPageChrome]/[Scaffold]
  /// and returns just the content.
  final bool embedded;

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  );
  final _repo = AdminRepository();

  bool _loading = true;
  String? _error;
  PlatformReport _platform = const PlatformReport();
  List<VendorReportItem> _vendorReports = const [];
  List<DriverReportItem> _driverReports = const [];

  String _dateFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  DateTime? get _startDate {
    final now = DateTime.now();
    switch (_dateFilter) {
      case 'today':
        return DateTime(now.year, now.month, now.day);
      case 'week':
        return now.subtract(const Duration(days: 7));
      case 'month':
        return DateTime(now.year, now.month - 1, now.day);
      default:
        return null;
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final start = _startDate;
      // One period, three views — fetched together so the tabs can never
      // disagree about which window they are showing.
      final results = await Future.wait([
        _repo.fetchPlatformReport(startDate: start),
        _repo.fetchVendorSalesReport(startDate: start),
        _repo.fetchDriverEarningsReport(startDate: start),
      ]);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _platform = results[0] as PlatformReport;
        _vendorReports = results[1] as List<VendorReportItem>;
        _driverReports = results[2] as List<DriverReportItem>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final webWide = AppBreakpoints.isWebWide(context);

    final tabBar = TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: [
        Tab(text: l10n.platformTab),
        Tab(text: l10n.vendorSalesTab),
        Tab(text: l10n.driverPayoutsTab),
      ],
    );

    final periodBar = _PeriodBar(
      value: _dateFilter,
      onChanged: (v) {
        setState(() => _dateFilter = v);
        _loadData();
      },
    );

    final tabContent = _loading
        ? const LoadingView()
        : _error != null
        ? FailureView(error: _error!, onRetry: _loadData)
        : TabBarView(
            controller: _tabController,
            children: [_platformTab(), _vendorTab(), _driverTab()],
          );

    if (webWide) {
      final page = _webPage();
      if (widget.embedded) return page;
      return WebPageChrome(
        forStaff: true,
        activeId: 'manage:/admin-app/sales-reports',
        sections: adminManageWebSections(context),
        pageTitle: l10n.salesAndFinancialReports,
        child: page,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.financialReports), bottom: tabBar),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            periodBar,
            Expanded(child: tabContent),
          ],
        ),
      ),
    );
  }

  Widget _platformTab() {
    final l10n = context.l10n;
    if (_platform.deliveredOrders == 0) {
      return _empty(l10n.noReportData, Icons.query_stats_outlined);
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadData,
      child: ListView(
        padding: _listPadding,
        children: [
          _sectionLabel(l10n.volume),
          _StatGrid(
            items: [
              (l10n.deliveredOrders, '${_platform.deliveredOrders}', null),
              (l10n.cancelledOrders, '${_platform.cancelledOrders}', null),
              (l10n.averageOrder, formatMoney(_platform.averageOrder), null),
              (l10n.grossRevenue, formatMoney(_platform.grossRevenue), null),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          _sectionLabel(l10n.settlement),
          _Row(label: l10n.itemSales, value: _platform.itemSales),
          _Row(label: l10n.deliveryFeesTotal, value: _platform.deliveryFees),
          _Row(
            label: l10n.discountsGiven,
            value: -_platform.discounts,
            subtle: true,
          ),
          const Divider(height: AppSpace.xl, color: AppColors.borderSoft),
          // What the platform earns, line by line, so the net below can be
          // checked by adding up the rows above it.
          _Row(label: l10n.platformCommission, value: _platform.commission),
          _Row(
            label: l10n.deliveryMargin(_percent(100 - _platform.driverShare)),
            value: _platform.deliveryMargin,
          ),
          _Row(
            label: l10n.platformFundedDiscounts,
            value: -_platform.platformDiscounts,
            subtle: true,
          ),
          _Row(
            label: l10n.netMargin,
            value: _platform.netMargin,
            emphasis: true,
          ),
          const SizedBox(height: AppSpace.lg),
          // Owed out. Kept apart from the platform's own P&L above: these are
          // other people's money passing through, not platform costs.
          _sectionLabel(l10n.owedOut),
          _Row(label: l10n.vendorPayouts, value: _platform.vendorPayout),
          if (_platform.driverStorePurchases > 0)
            _Row(
              label: l10n.paidToStoresByDrivers,
              value: _platform.driverStorePurchases,
            ),
          _Row(label: l10n.driverCost, value: _platform.driverCost),
          if (_platform.driverTips > 0)
            _Row(
              label: l10n.tipsPassedThrough,
              value: _platform.driverTips,
              subtle: true,
            ),
          if (_platform.subscriptionStores > 0) ...[
            const SizedBox(height: AppSpace.lg),
            _sectionLabel(l10n.subscriptions),
            _Row(
              label: l10n.subscriptionFeesMonthly(_platform.subscriptionStores),
              value: _platform.subscriptionFeesMonthly,
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(
                l10n.subscriptionNotInNet,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                  height: 1.35,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          // The number that decides who owes whom at the end of a shift.
          _sectionLabel(l10n.cashCollected),
          _StatGrid(
            items: [
              (
                l10n.cashCollected,
                formatMoney(_platform.cashCollected),
                AppColors.amberInk,
              ),
              (
                l10n.cardCollected,
                formatMoney(_platform.cardCollected),
                AppColors.successInk,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _vendorTab() {
    final l10n = context.l10n;
    if (_vendorReports.isEmpty) {
      return _empty(l10n.noReportData, Icons.storefront_outlined);
    }
    final payouts = _vendorReports.fold<double>(
      0,
      (sum, i) => sum + i.netPayout,
    );
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadData,
      child: ListView(
        padding: _listPadding,
        children: [
          _TotalBanner(label: l10n.vendorPayouts, value: payouts),
          const SizedBox(height: AppSpace.md),
          for (final item in _vendorReports)
            _PartyCard(
              name: item.vendorName,
              lines: [
                '${l10n.orders}: ${item.totalOrders}',
                '${l10n.itemSales}: ${formatMoney(item.grossSales)}',
                if (item.vendorDiscounts > 0)
                  '${l10n.storeFundedDiscounts}: '
                      '-${formatMoney(item.vendorDiscounts)}',
                // A subscription store pays a flat fee and no per-order cut,
                // so quoting a percentage on its card would be a lie.
                if (item.isSubscription)
                  '${l10n.subscriptionPlan}: '
                      '${formatMoney(item.subscriptionFee)}${l10n.perMonthSuffix}'
                else
                  '${l10n.platformCommission} '
                      '(${_percent(item.commissionRate)}): '
                      '${formatMoney(item.commissionFee)}',
              ],
              payout: item.netPayout,
              payoutColor: AppColors.successInk,
              payoutLabel: l10n.netPayout,
            ),
        ],
      ),
    );
  }

  Widget _driverTab() {
    final l10n = context.l10n;
    if (_driverReports.isEmpty) {
      return _empty(l10n.noReportData, Icons.two_wheeler_outlined);
    }
    final payouts = _driverReports.fold<double>(
      0,
      (sum, i) => sum + i.netDriverPayout,
    );
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadData,
      child: ListView(
        padding: _listPadding,
        children: [
          _TotalBanner(label: l10n.driverCost, value: payouts),
          const SizedBox(height: AppSpace.md),
          for (final item in _driverReports)
            _PartyCard(
              name: item.driverName,
              lines: [
                '${l10n.deliveredOrders}: ${item.deliveredOrders}',
                '${l10n.deliveryFeesTotal}: '
                    '${formatMoney(item.deliveryFeesCollected)}',
                '${l10n.driverShareLabel}: '
                    '${formatMoney(item.driverFeeShare)}',
                // The other side of the same fee. Its absence is what made a
                // 20 fee look like a flat 18 cost with no platform income.
                '${l10n.platformShareLabel}: '
                    '${formatMoney(item.platformFeeShare)}',
                if (item.tipsEarned > 0)
                  '${l10n.tips}: ${formatMoney(item.tipsEarned)}',
              ],
              payout: item.netDriverPayout,
              payoutColor: AppColors.primary,
              payoutLabel: l10n.netPayout,
            ),
        ],
      ),
    );
  }

  // ── Desktop ─────────────────────────────────────────────────────────────

  String _periodLabel(String key) {
    final l10n = context.l10n;
    return switch (key) {
      'today' => l10n.periodToday,
      'week' => l10n.periodWeek,
      'month' => l10n.periodMonth,
      _ => l10n.periodAll,
    };
  }

  /// Tabs, then one toolbar that sets the period for all three and exports
  /// whichever one is showing, then the tab.
  Widget _webPage() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          padding: const EdgeInsetsDirectional.only(start: 4),
          tabs: [
            Tab(text: l10n.platformTab),
            Tab(text: l10n.vendorSalesTab),
            Tab(text: l10n.driverPayoutsTab),
          ],
        ),
        const Divider(height: 1, thickness: 1, color: AppColors.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: ConsoleToolbar(
                  filters: [
                    for (final key in const ['today', 'week', 'month', 'all'])
                      ConsoleFilterChip(
                        label: _periodLabel(key),
                        selected: _dateFilter == key,
                        onSelected: () {
                          if (_dateFilter == key) return;
                          setState(() => _dateFilter = key);
                          _loadData();
                        },
                      ),
                  ],
                ),
              ),
              AnimatedBuilder(
                animation: _tabController,
                builder: (context, _) => _tabController.index == 0
                    ? const SizedBox.shrink()
                    : OutlinedButton.icon(
                        onPressed: _loading ? null : _exportCurrent,
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(l10n.exportCsv),
                      ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const LoadingView()
              : _error != null
              ? FailureView(error: _error!, onRetry: _loadData)
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _webPlatformTab(),
                    _webVendorTab(),
                    _webDriverTab(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _webScroll(List<Widget> children) => RefreshIndicator(
    color: AppColors.primary,
    onRefresh: _loadData,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
      children: children,
    ),
  );

  Widget _webEmpty(IconData icon) => _webScroll([
    ConsolePanel(
      child: ConsoleEmpty(icon: icon, title: context.l10n.noReportData),
    ),
  ]);

  /// Headline figures, then the platform's own money beside the money it
  /// only passes on — two ledgers that each add up on their own.
  Widget _webPlatformTab() {
    final l10n = context.l10n;
    final p = _platform;
    if (p.deliveredOrders == 0) return _webEmpty(Icons.query_stats_outlined);
    final collected = p.cashCollected + p.cardCollected;
    final cashShare = collected <= 0 ? 0.0 : p.cashCollected / collected;

    final earnings = ConsolePanel(
      title: l10n.platformEarnings,
      subtitle: l10n.platformEarningsHint,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        children: [
          _Row(label: l10n.platformCommission, value: p.commission),
          _Row(
            label: l10n.deliveryMargin(_percent(100 - p.driverShare)),
            value: p.deliveryMargin,
          ),
          _Row(
            label: l10n.platformFundedDiscounts,
            value: -p.platformDiscounts,
            subtle: true,
          ),
          const Divider(height: AppSpace.lg, color: AppColors.border),
          _Row(label: l10n.netMargin, value: p.netMargin, emphasis: true),
        ],
      ),
    );

    final orderValue = ConsolePanel(
      title: l10n.orderValueSection,
      subtitle: l10n.orderValueHint,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        children: [
          _Row(label: l10n.itemSales, value: p.itemSales),
          _Row(label: l10n.deliveryFeesTotal, value: p.deliveryFees),
          // Tips are not in gross revenue; they are listed with the money
          // passed on, so this column adds up to the total below it.
          _Row(label: l10n.discountsGiven, value: -p.discounts, subtle: true),
          const Divider(height: AppSpace.lg, color: AppColors.border),
          _Row(label: l10n.grossRevenue, value: p.grossRevenue, strong: true),
        ],
      ),
    );

    final owedOut = ConsolePanel(
      title: l10n.owedOut,
      subtitle: l10n.owedOutHint,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        children: [
          _Row(label: l10n.vendorPayouts, value: p.vendorPayout),
          if (p.driverStorePurchases > 0)
            _Row(
              label: l10n.paidToStoresByDrivers,
              value: p.driverStorePurchases,
            ),
          _Row(label: l10n.driverCost, value: p.driverCost),
          if (p.driverTips > 0)
            _Row(
              label: l10n.tipsPassedThrough,
              value: p.driverTips,
              subtle: true,
            ),
        ],
      ),
    );

    final paymentMix = ConsolePanel(
      title: l10n.paymentMix,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: SizedBox(
              height: 10,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (cashShare > 0)
                    Expanded(
                      flex: (cashShare * 1000).round(),
                      child: const ColoredBox(color: AppColors.amberInk),
                    ),
                  if (cashShare < 1)
                    Expanded(
                      flex: ((1 - cashShare) * 1000).round(),
                      child: const ColoredBox(color: AppColors.successInk),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          _MixRow(
            color: AppColors.amberInk,
            label: l10n.cashCollected,
            value: p.cashCollected,
            share: cashShare,
          ),
          _MixRow(
            color: AppColors.successInk,
            label: l10n.cardCollected,
            value: p.cardCollected,
            share: collected <= 0 ? 0 : 1 - cashShare,
          ),
        ],
      ),
    );

    return _webScroll([
      ConsoleGrid(
        children: [
          ConsoleStat(
            label: l10n.deliveredOrders,
            value: '${p.deliveredOrders}',
            hint: '${l10n.cancelledOrders}: ${p.cancelledOrders}',
            icon: Icons.check_circle_outline_rounded,
          ),
          ConsoleStat(
            label: l10n.grossRevenue,
            value: formatMoney(p.grossRevenue),
            hint: _periodLabel(_dateFilter),
            icon: Icons.receipt_long_outlined,
          ),
          ConsoleStat(
            label: l10n.averageOrder,
            value: formatMoney(p.averageOrder),
            hint: _periodLabel(_dateFilter),
            icon: Icons.shopping_bag_outlined,
          ),
          ConsoleStat(
            label: l10n.netMargin,
            value: formatMoney(p.netMargin),
            hint: _periodLabel(_dateFilter),
            icon: Icons.trending_up_rounded,
            tone: p.netMargin >= 0 ? ConsoleTone.good : ConsoleTone.danger,
          ),
        ],
      ),
      const SizedBox(height: AppSpace.xl),
      LayoutBuilder(
        builder: (context, constraints) {
          final left = [
            earnings,
            const SizedBox(height: AppSpace.lg),
            orderValue,
          ];
          final right = [
            owedOut,
            const SizedBox(height: AppSpace.lg),
            paymentMix,
            if (p.subscriptionStores > 0) ...[
              const SizedBox(height: AppSpace.lg),
              ConsolePanel(
                title: l10n.subscriptions,
                subtitle: l10n.subscriptionNotInNet,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: _Row(
                  label: l10n.subscriptionFeesMonthly(p.subscriptionStores),
                  value: p.subscriptionFeesMonthly,
                ),
              ),
            ],
          ];
          if (constraints.maxWidth < 860) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...left,
                const SizedBox(height: AppSpace.lg),
                ...right,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: left,
                ),
              ),
              const SizedBox(width: AppSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: right,
                ),
              ),
            ],
          );
        },
      ),
    ]);
  }

  static TextStyle _figure({bool strong = false, Color? color}) => AppType.mono(
    13.5,
    weight: strong ? FontWeight.w800 : FontWeight.w600,
    color: color ?? (strong ? AppColors.ink : AppColors.textSecondary),
  );

  static Widget _name(String name) => Text(
    name,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    ),
  );

  Widget _webVendorTab() {
    final l10n = context.l10n;
    if (_vendorReports.isEmpty) return _webEmpty(Icons.storefront_outlined);
    final rows = [..._vendorReports]
      ..sort((a, b) => b.netPayout.compareTo(a.netPayout));
    double sum(double Function(VendorReportItem) f) =>
        rows.fold<double>(0, (total, i) => total + f(i));
    final orders = rows.fold<int>(0, (total, i) => total + i.totalOrders);
    final columns = [
      WebTableColumn(label: l10n.store, flex: 3),
      WebTableColumn(label: l10n.orders, width: 80, numeric: true),
      WebTableColumn(label: l10n.itemSales, flex: 2, numeric: true),
      WebTableColumn(label: l10n.discountsColumn, flex: 2, numeric: true),
      WebTableColumn(label: l10n.commissionColumn, flex: 2, numeric: true),
      WebTableColumn(label: l10n.netPayout, flex: 2, numeric: true),
    ];
    return _webScroll([
      ConsoleGrid(
        maxColumns: 3,
        children: [
          ConsoleStat(
            label: l10n.vendorPayouts,
            value: formatMoney(sum((i) => i.netPayout)),
            hint: _periodLabel(_dateFilter),
            icon: Icons.account_balance_wallet_outlined,
          ),
          ConsoleStat(
            label: l10n.itemSales,
            value: formatMoney(sum((i) => i.grossSales)),
            hint: '${l10n.orders}: $orders',
            icon: Icons.receipt_long_outlined,
          ),
          ConsoleStat(
            label: l10n.platformCommission,
            value: formatMoney(sum((i) => i.commissionFee)),
            icon: Icons.percent_rounded,
          ),
        ],
      ),
      const SizedBox(height: AppSpace.xl),
      WebTable(
        columns: columns,
        trailingWidth: 0,
        rows: [
          for (final item in rows)
            WebTableRow.aligned(
              columns: columns,
              trailingWidth: 0,
              cells: [
                _name(item.vendorName),
                Text('${item.totalOrders}', style: _figure()),
                Text(formatMoney(item.grossSales), style: _figure()),
                Text(
                  item.vendorDiscounts > 0
                      ? '-${formatMoney(item.vendorDiscounts)}'
                      : '—',
                  style: _figure(color: AppColors.textMuted),
                ),
                // A subscription store pays a flat fee and no per-order cut.
                Tooltip(
                  message: item.isSubscription
                      ? '${formatMoney(item.subscriptionFee)}${l10n.perMonthSuffix}'
                      : _percent(item.commissionRate),
                  child: Text(
                    item.isSubscription
                        ? l10n.subscriptionShort
                        : '${formatMoney(item.commissionFee)} · ${_percent(item.commissionRate)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _figure(),
                  ),
                ),
                Text(formatMoney(item.netPayout), style: _figure(strong: true)),
              ],
            ),
        ],
      ),
    ]);
  }

  Widget _webDriverTab() {
    final l10n = context.l10n;
    if (_driverReports.isEmpty) return _webEmpty(Icons.two_wheeler_outlined);
    final rows = [..._driverReports]
      ..sort((a, b) => b.netDriverPayout.compareTo(a.netDriverPayout));
    double sum(double Function(DriverReportItem) f) =>
        rows.fold<double>(0, (total, i) => total + f(i));
    final delivered = rows.fold<int>(
      0,
      (total, i) => total + i.deliveredOrders,
    );
    final columns = [
      WebTableColumn(label: l10n.driverLabel, flex: 3),
      WebTableColumn(label: l10n.deliveredOrders, width: 110, numeric: true),
      WebTableColumn(label: l10n.deliveryFeesTotal, flex: 2, numeric: true),
      WebTableColumn(label: l10n.driverShareLabel, flex: 2, numeric: true),
      WebTableColumn(label: l10n.platformShareLabel, flex: 2, numeric: true),
      WebTableColumn(label: l10n.tips, flex: 1, numeric: true),
      WebTableColumn(label: l10n.netPayout, flex: 2, numeric: true),
    ];
    return _webScroll([
      ConsoleGrid(
        maxColumns: 3,
        children: [
          ConsoleStat(
            label: l10n.driverCost,
            value: formatMoney(sum((i) => i.netDriverPayout)),
            hint: _periodLabel(_dateFilter),
            icon: Icons.two_wheeler_rounded,
          ),
          ConsoleStat(
            label: l10n.deliveredOrders,
            value: '$delivered',
            icon: Icons.check_circle_outline_rounded,
          ),
          ConsoleStat(
            label: l10n.platformShareLabel,
            value: formatMoney(sum((i) => i.platformFeeShare)),
            icon: Icons.percent_rounded,
          ),
        ],
      ),
      const SizedBox(height: AppSpace.xl),
      WebTable(
        columns: columns,
        trailingWidth: 0,
        rows: [
          for (final item in rows)
            WebTableRow.aligned(
              columns: columns,
              trailingWidth: 0,
              cells: [
                _name(item.driverName),
                Text('${item.deliveredOrders}', style: _figure()),
                Text(formatMoney(item.deliveryFeesCollected), style: _figure()),
                Text(formatMoney(item.driverFeeShare), style: _figure()),
                Text(formatMoney(item.platformFeeShare), style: _figure()),
                Text(
                  item.tipsEarned > 0 ? formatMoney(item.tipsEarned) : '—',
                  style: _figure(color: AppColors.textMuted),
                ),
                Text(
                  formatMoney(item.netDriverPayout),
                  style: _figure(strong: true),
                ),
              ],
            ),
        ],
      ),
    ]);
  }

  /// The table on screen, as a spreadsheet: same rows, same columns, plain
  /// numbers so it adds up in Excel.
  Future<void> _exportCurrent() async {
    final l10n = context.l10n;
    String n(double v) => v.toStringAsFixed(2);
    final vendors = _tabController.index == 1;
    final rows = <List<Object>>[
      if (vendors) ...[
        [
          l10n.store,
          l10n.orders,
          l10n.itemSales,
          l10n.discountsColumn,
          l10n.commissionColumn,
          l10n.netPayout,
        ],
        for (final i in _vendorReports)
          [
            i.vendorName,
            i.totalOrders,
            n(i.grossSales),
            n(i.vendorDiscounts),
            n(i.isSubscription ? 0 : i.commissionFee),
            n(i.netPayout),
          ],
      ] else ...[
        [
          l10n.driverLabel,
          l10n.deliveredOrders,
          l10n.deliveryFeesTotal,
          l10n.driverShareLabel,
          l10n.platformShareLabel,
          l10n.tips,
          l10n.netPayout,
        ],
        for (final i in _driverReports)
          [
            i.driverName,
            i.deliveredOrders,
            n(i.deliveryFeesCollected),
            n(i.driverFeeShare),
            n(i.platformFeeShare),
            n(i.tipsEarned),
            n(i.netDriverPayout),
          ],
      ],
    ];
    final day = DateTime.now().toIso8601String().substring(0, 10);
    try {
      final saved = await saveBytesAsFile(
        fileName:
            '${vendors ? 'store-sales' : 'driver-payouts'}-$_dateFilter-$day.csv',
        bytes: MenuExport.csv(rows),
        extensions: const ['csv'],
      );
      if (saved && mounted) showSnack(context, l10n.reportExported);
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  EdgeInsets get _listPadding => EdgeInsets.fromLTRB(
    AppSpace.gutter,
    AppSpace.md,
    AppSpace.gutter,
    AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
  );

  Widget _empty(String message, IconData icon) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 100),
      EmptyView(message: message, icon: icon),
    ],
  );

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpace.xs,
      AppSpace.sm,
      AppSpace.xs,
      AppSpace.sm,
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
      ),
    ),
  );
}

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.md,
        AppSpace.gutter,
        AppSpace.xs,
      ),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final (key, label) in [
              ('today', l10n.periodToday),
              ('week', l10n.periodWeek),
              ('month', l10n.periodMonth),
              ('all', l10n.periodAll),
            ])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
                child: ChoiceChip(
                  label: Text(label),
                  selected: value == key,
                  onSelected: (_) => onChanged(key),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tile grid for headline figures: two across on a phone, more as the space
/// allows.
///
/// Sized from the grid's own width rather than the window's. Inside the web
/// shell those differ by the sidebar and the page's own margins, so tiles
/// measured against the window were wider than the box holding them — and on
/// a desktop two tiles across a whole monitor is not a grid, it is two very
/// long labels.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.items});

  /// (label, value, accent colour or null)
  final List<(String, String, Color?)> items;

  /// Narrow enough to read at a glance, wide enough for a long money figure.
  static const _minTile = 190.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final columns = (available / _minTile).floor().clamp(2, 4);
        final tile = (available - AppSpace.sm * (columns - 1)) / columns;
        return _grid(tile);
      },
    );
  }

  Widget _grid(double tile) {
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: [
        for (final (label, value, accent) in items)
          SizedBox(
            width: tile,
            child: Container(
              padding: const EdgeInsets.all(AppSpace.lg),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      value,
                      style: AppType.mono(
                        17,
                        color: accent ?? AppColors.ink,
                        weight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One line of the settlement ledger.
class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.subtle = false,
    this.emphasis = false,
    this.strong = false,
  });

  final String label;
  final double value;

  /// A subtotal: bold, but not the page's one green number.
  final bool strong;

  /// Money leaving the platform, shown muted and signed.
  final bool subtle;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: emphasis ? 14.5 : 13.5,
                fontWeight: emphasis || strong
                    ? FontWeight.w800
                    : FontWeight.w600,
                color: emphasis || strong
                    ? AppColors.ink
                    : AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            formatMoney(value),
            style: AppType.mono(
              emphasis ? 15 : 13.5,
              color: emphasis
                  ? AppColors.successInk
                  : subtle
                  ? AppColors.textMuted
                  : AppColors.ink,
              weight: emphasis || strong ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalBanner extends StatelessWidget {
  const _TotalBanner({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formatMoney(value),
            style: AppType.mono(
              22,
              color: Colors.white,
              weight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// One store or driver in the payout list.
class _PartyCard extends StatelessWidget {
  const _PartyCard({
    required this.name,
    required this.lines,
    required this.payout,
    required this.payoutColor,
    required this.payoutLabel,
  });

  final String name;
  final List<String> lines;
  final double payout;
  final Color payoutColor;

  /// What [payout] actually is. Every card on both the vendor and the driver
  /// tab used to print "Net to platform" underneath a number that was neither
  /// — a vendor's payout and a driver's payout are money leaving the
  /// platform, the opposite of what the caption claimed.
  final String payoutLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 5),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatMoney(payout),
                style: AppType.mono(
                  15,
                  color: payoutColor,
                  weight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                payoutLabel,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textFaint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One side of the payment mix: its colour key, what it is, how much, and
/// its share.
class _MixRow extends StatelessWidget {
  const _MixRow({
    required this.color,
    required this.label,
    required this.value,
    required this.share,
  });

  final Color color;
  final String label;
  final double value;
  final double share;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            context.l10n.shareOfTotal(_percent(share * 100)),
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
          const SizedBox(width: AppSpace.lg),
          Text(
            formatMoney(value),
            style: AppType.mono(13.5, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
