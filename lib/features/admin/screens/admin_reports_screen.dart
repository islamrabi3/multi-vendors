import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
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
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 3, vsync: this);
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
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(l10n.financialReports),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: l10n.platformTab),
            Tab(text: l10n.vendorSalesTab),
            Tab(text: l10n.driverPayoutsTab),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _PeriodBar(
              value: _dateFilter,
              onChanged: (v) {
                setState(() => _dateFilter = v);
                _loadData();
              },
            ),
            Expanded(
              child: _loading
                  ? const LoadingView()
                  : _error != null
                      ? FailureView(error: _error!, onRetry: _loadData)
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _platformTab(),
                            _vendorTab(),
                            _driverTab(),
                          ],
                        ),
            ),
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
          _StatGrid(items: [
            (l10n.deliveredOrders, '${_platform.deliveredOrders}', null),
            (l10n.cancelledOrders, '${_platform.cancelledOrders}', null),
            (l10n.averageOrder, formatMoney(_platform.averageOrder), null),
            (l10n.grossRevenue, formatMoney(_platform.grossRevenue), null),
          ]),
          const SizedBox(height: AppSpace.lg),
          _sectionLabel(l10n.settlement),
          _Row(label: l10n.itemSales, value: _platform.itemSales),
          _Row(label: l10n.deliveryFeesTotal, value: _platform.deliveryFees),
          _Row(
              label: l10n.discountsGiven,
              value: -_platform.discounts,
              subtle: true),
          const Divider(height: AppSpace.xl, color: AppColors.borderSoft),
          // What the platform earns, line by line, so the net below can be
          // checked by adding up the rows above it.
          _Row(label: l10n.platformCommission, value: _platform.commission),
          _Row(
              label: l10n.deliveryMargin(_percent(100 - _platform.driverShare)),
              value: _platform.deliveryMargin),
          _Row(
              label: l10n.platformFundedDiscounts,
              value: -_platform.platformDiscounts,
              subtle: true),
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
          _Row(label: l10n.driverCost, value: _platform.driverCost),
          if (_platform.driverTips > 0)
            _Row(
                label: l10n.tipsPassedThrough,
                value: _platform.driverTips,
                subtle: true),
          if (_platform.subscriptionStores > 0) ...[
            const SizedBox(height: AppSpace.lg),
            _sectionLabel(l10n.subscriptions),
            _Row(
              label: l10n.subscriptionFeesMonthly(
                  _platform.subscriptionStores),
              value: _platform.subscriptionFeesMonthly,
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(
                l10n.subscriptionNotInNet,
                style: const TextStyle(
                    fontSize: 11.5, color: AppColors.textMuted, height: 1.35),
              ),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          // The number that decides who owes whom at the end of a shift.
          _sectionLabel(l10n.cashCollected),
          _StatGrid(items: [
            (
              l10n.cashCollected,
              formatMoney(_platform.cashCollected),
              AppColors.amberInk
            ),
            (
              l10n.cardCollected,
              formatMoney(_platform.cardCollected),
              AppColors.successInk
            ),
          ]),
        ],
      ),
    );
  }

  Widget _vendorTab() {
    final l10n = context.l10n;
    if (_vendorReports.isEmpty) {
      return _empty(l10n.noReportData, Icons.storefront_outlined);
    }
    final payouts =
        _vendorReports.fold<double>(0, (sum, i) => sum + i.netPayout);
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
    final payouts =
        _driverReports.fold<double>(0, (sum, i) => sum + i.netDriverPayout);
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
            ),
        ],
      ),
    );
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
            AppSpace.xs, AppSpace.sm, AppSpace.xs, AppSpace.sm),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: AppColors.textMuted,
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
          AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.xs),
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

/// Two-column tile grid for headline figures.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.items});

  /// (label, value, accent colour or null)
  final List<(String, String, Color?)> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: [
        for (final (label, value, accent) in items)
          SizedBox(
            width: (MediaQuery.sizeOf(context).width -
                    AppSpace.gutter * 2 -
                    AppSpace.sm) /
                2,
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
                    child: Text(value,
                        style: AppType.mono(17,
                            color: accent ?? AppColors.ink,
                            weight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 3),
                  Text(label,
                      maxLines: 2,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted)),
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
  });

  final String label;
  final double value;

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
                fontWeight: emphasis ? FontWeight.w800 : FontWeight.w600,
                color: emphasis ? AppColors.ink : AppColors.textSecondary,
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
              weight: emphasis ? FontWeight.w800 : FontWeight.w600,
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
          Text(label.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Colors.white.withValues(alpha: 0.6),
              )),
          const SizedBox(height: 6),
          Text(formatMoney(value),
              style: AppType.mono(22,
                  color: Colors.white, weight: FontWeight.w800)),
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
  });

  final String name;
  final List<String> lines;
  final double payout;
  final Color payoutColor;

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
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 5),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(line,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textMuted)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatMoney(payout),
                  style: AppType.mono(15,
                      color: payoutColor, weight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(context.l10n.netMargin,
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textFaint)),
            ],
          ),
        ],
      ),
    );
  }
}
