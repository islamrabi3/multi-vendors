import 'package:flutter/material.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../../app/tokens.dart';
import '../../../core/models/finance.dart';
import '../../../core/repositories/finance_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/finance_widgets.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import 'admin_manage_screen.dart' show adminManageWebSections;
import '../admin_shell.dart' show AdminWebNav;

/// The platform's money, and whether the books can be trusted.
///
/// Reconciliation lives here as a second tab rather than on its own screen:
/// it answers a question about the same numbers, and an admin who sees a
/// difference needs the overview in the next tap, not the next menu.
class AdminFinanceScreen extends StatefulWidget {
  const AdminFinanceScreen({super.key, this.embedded = false});

  /// True when a web sidebar is already drawing the shell around this screen
  /// (`_AdminWebShell`) — skips this widget's own [WebPageChrome]/[Scaffold].
  final bool embedded;

  @override
  State<AdminFinanceScreen> createState() => _AdminFinanceScreenState();
}

enum _Period { today, week, month, all }

class _AdminFinanceScreenState extends State<AdminFinanceScreen> {
  final _repository = FinanceRepository();

  FinanceOverview? _overview;
  CashReconciliation? _reconciliation;
  ({bool balanced, double net, int unsettledOrders})? _integrity;
  int _pendingRequests = 0;
  bool _loading = true;
  String? _error;
  _Period _period = _Period.month;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime? get _start {
    final now = DateTime.now();
    return switch (_period) {
      _Period.today => DateTime(now.year, now.month, now.day),
      _Period.week => now.subtract(const Duration(days: 7)),
      _Period.month => now.subtract(const Duration(days: 30)),
      _Period.all => null,
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final start = _start;
      final results = await Future.wait([
        _repository.overview(start: start),
        _repository.reconciliation(start: start),
        _repository.integrityCheck(),
        _repository.pendingSettlementRequests(),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = results[0] as FinanceOverview;
        _reconciliation = results[1] as CashReconciliation;
        _integrity =
            results[2] as ({bool balanced, double net, int unsettledOrders});
        _pendingRequests = (results[3] as List<Settlement>).length;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = errorText(context, error);
        _loading = false;
      });
    }
  }

  Future<void> _backfill() async {
    try {
      final count = await _repository.backfillSettlements();
      if (!mounted) return;
      showSnack(context, context.l10n.pricesUpdated(count));
      await _load();
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tabs = TabBar(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.textMuted,
      indicatorColor: AppColors.primary,
      tabs: [
        Tab(text: l10n.overview),
        Tab(text: l10n.cashReconciliation),
      ],
    );
    final body = _loading
        ? const LoadingView()
        : _error != null
        ? ErrorView(message: _error!, onRetry: _load)
        : TabBarView(children: [_overviewTab(), _reconciliationTab()]);

    if (widget.embedded) {
      return DefaultTabController(
        length: 2,
        child: Column(
          children: [
            ColoredBox(color: AppColors.surface, child: tabs),
            const Divider(height: 1, thickness: 1, color: AppColors.border),
            Expanded(child: body),
          ],
        ),
      );
    }

    if (AppBreakpoints.isWebWide(context)) {
      return DefaultTabController(
        length: 2,
        child: WebPageChrome(
          activeId: 'manage:/admin-app/finance',
          sections: adminManageWebSections(context),
          pageTitle: l10n.financeTitle,
          child: Column(
            children: [
              tabs,
              const Divider(height: 1, thickness: 1, color: AppColors.border),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(title: Text(l10n.financeTitle), bottom: tabs),
        body: body,
      ),
    );
  }

  /// Four columns on a wide screen instead of two — a `MoneyTile` sized for
  /// a phone's half-width column was mostly empty space stretched across a
  /// monitor. `AppBreakpoints.isWebWide` gates it so mobile is untouched.
  Widget _moneyGrid(List<Widget> tiles) {
    final web = AppBreakpoints.isWebWide(context);
    return GridView.count(
      crossAxisCount: web ? 4 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // 2.6 rather than 1.5 on desktop: four tiles across a 1200px pane are
      // ~280px wide, and at 1.5 that made each one 187px tall to hold a
      // number and a caption. Wider-than-tall is the shape a KPI strip wants.
      childAspectRatio: web ? 2.6 : 1.95,
      crossAxisSpacing: AppSpace.md,
      mainAxisSpacing: AppSpace.md,
      children: tiles,
    );
  }

  Widget _periodPicker() {
    final l10n = context.l10n;
    String label(_Period p) => switch (p) {
      _Period.today => l10n.today,
      _Period.week => l10n.last7Days,
      _Period.month => l10n.last30Days,
      _Period.all => l10n.allTime,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final period in _Period.values) ...[
            ChoiceChip(
              selected: period == _period,
              label: Text(label(period)),
              onSelected: (_) {
                setState(() => _period = period);
                _load();
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _overviewTab() {
    final l10n = context.l10n;
    final o = _overview!;
    final integrity = _integrity!;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.md,
          AppSpace.gutter,
          AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          if (_pendingRequests > 0) ...[
            _PendingRequestsBanner(
              count: _pendingRequests,
              onTap: () => AdminWebNav.go(context, '/admin-app/settlements'),
            ),
            const SizedBox(height: AppSpace.md),
          ],
          _periodPicker(),
          const SizedBox(height: AppSpace.md),

          // The health of the ledger, first and unmissable. Money that does
          // not add up is more urgent than any figure below it.
          _IntegrityBanner(
            balanced: integrity.balanced,
            net: integrity.net,
            unsettledOrders: integrity.unsettledOrders,
            onBackfill: _backfill,
          ),
          const SizedBox(height: AppSpace.md),

          _label(l10n.volume),
          _moneyGrid([
            MoneyTile(label: l10n.deliveredOrders, value: '${o.totalOrders}'),
            MoneyTile(
              label: l10n.cashCollectedLabel,
              value: formatMoney(o.cashCollected),
            ),
          ]),

          const SizedBox(height: AppSpace.lg),
          // Counts alone never answered "which half of the money was that?",
          // which is the question this screen exists for. The four rows are
          // built so they sum to the total exactly — every delivered order is
          // on precisely one of them — so the figure can be read as a
          // breakdown rather than four unrelated numbers.
          _MoneyFlow(overview: o),

          const SizedBox(height: AppSpace.lg),
          _label(l10n.platformNet),
          _moneyGrid([
            MoneyTile(
              label: l10n.platformCommission,
              value: formatMoney(o.platformCommission),
              tone: AppColors.successInk,
            ),
            MoneyTile(
              // The share is not in this payload, and "Delivery margin ()"
              // is worse than no parenthetical at all.
              label: l10n.platformShareLabel,
              value: formatMoney(o.platformDeliveryMargin),
              tone: AppColors.successInk,
            ),
            MoneyTile(
              label: l10n.platformFundedDiscounts,
              value: '-${formatMoney(o.platformDiscounts)}',
              tone: AppColors.dangerInk,
            ),
            MoneyTile(label: l10n.refunds, value: formatMoney(o.refunds)),
          ]),

          const SizedBox(height: AppSpace.lg),
          // Positions rather than flows, which is why they ignore the period.
          _label(l10n.owedOut),
          _moneyGrid([
            MoneyTile(
              label: l10n.driverCashDueTotal,
              value: formatMoney(o.driverCashDue),
              emphasis: true,
              tone: AppColors.amberInk,
            ),
            MoneyTile(
              label: l10n.vendorPayableTotal,
              value: formatMoney(o.vendorPayable),
              emphasis: true,
            ),
            MoneyTile(
              label: l10n.driverCost,
              value: formatMoney(o.driverEarnings),
            ),
            MoneyTile(
              label: l10n.vendorPayouts,
              value: formatMoney(o.vendorEarnings),
            ),
          ]),

          const SizedBox(height: AppSpace.lg),
          _label(l10n.settlementsTitle),
          _moneyGrid([
            MoneyTile(
              label: l10n.settlementsTitle,
              value: formatMoney(o.settlements),
            ),
            MoneyTile(
              label: l10n.requestDeposit,
              value: formatMoney(o.deposits),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _reconciliationTab() {
    final l10n = context.l10n;
    final r = _reconciliation!;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.md,
          AppSpace.gutter,
          AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          _periodPicker(),
          const SizedBox(height: AppSpace.md),
          Container(
            padding: const EdgeInsets.all(AppSpace.lg),
            decoration: BoxDecoration(
              color: r.hasException
                  ? AppColors.dangerFill
                  : AppColors.successFill,
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Row(
              children: [
                Icon(
                  r.hasException
                      ? Icons.report_problem_rounded
                      : Icons.verified_rounded,
                  color: r.hasException
                      ? AppColors.dangerInk
                      : AppColors.successInk,
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Text(
                    r.hasException
                        ? l10n.reconciliationException
                        : l10n.reconciliationClean,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: r.hasException
                          ? AppColors.dangerInk
                          : AppColors.successInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          _moneyGrid([
            MoneyTile(
              label: l10n.expectedCash,
              value: formatMoney(r.expectedCash),
            ),
            MoneyTile(
              label: l10n.collectedCash,
              value: formatMoney(r.collectedCash),
            ),
            MoneyTile(
              label: l10n.settledCash,
              value: formatMoney(r.settledCash),
            ),
            MoneyTile(
              label: l10n.outstandingCash,
              value: formatMoney(r.outstandingCash),
              emphasis: true,
              tone: AppColors.amberInk,
            ),
          ]),
          const SizedBox(height: AppSpace.md),
          MoneyTile(
            label: l10n.cashDifference,
            value: formatMoney(r.difference),
            emphasis: true,
            tone: r.hasException ? AppColors.dangerInk : AppColors.successInk,
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.sm),
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

/// The single "here's what needs you" entry point into the four separate
/// money screens (`AdminFinanceScreen`, `AdminSettlementsScreen`,
/// `AdminDepositsScreen`, `AdminReportsScreen`) — none of which otherwise
/// link to each other.
class _PendingRequestsBanner extends StatelessWidget {
  const _PendingRequestsBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          color: AppColors.amberFill,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: AppColors.amberInk.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.hourglass_top_rounded, color: AppColors.amberInk),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                context.l10n.pendingApprovalsBanner(count),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: AppColors.amberInk,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.amberInk),
          ],
        ),
      ),
    );
  }
}

/// Where the period's money came from, and where it went.
///
/// Two deliberately separate blocks rather than one running total. The top
/// block is arithmetic this screen can guarantee: the four routes are drawn
/// from the same delivered-orders set, each order belongs to exactly one, so
/// they sum to the total by construction. The bottom block is the ledger's
/// own figures.
///
/// They are *not* joined into a single "collected minus paid out equals net"
/// equation, tempting as that reads. An order total and the ledger's platform
/// net are not two ends of one subtraction — tips pass straight through,
/// refunds and adjustments land in their own rows, and delivery is split
/// between the driver and the platform. Writing an equals sign between them
/// would produce a number that quietly disagrees with the ledger, which is
/// exactly the kind of figure this screen must never show.
class _MoneyFlow extends StatelessWidget {
  const _MoneyFlow({required this.overview});

  final FinanceOverview overview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final o = overview;

    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(l10n.collectedFromCustomers),
          const SizedBox(height: AppSpace.sm),
          _FlowRow(
            label: l10n.cashOnDelivery,
            amount: o.codRevenue,
            note: l10n.ordersCount(o.cashOrders),
          ),
          _FlowRow(
            label: l10n.card,
            amount: o.cardRevenue,
            note: l10n.ordersCount(o.cardOrders),
          ),
          _FlowRow(
            label: l10n.mobileWallet,
            amount: o.mobileWalletRevenue,
            note: l10n.ordersCount(o.mobileWalletOrders),
          ),
          _FlowRow(
            label: l10n.appWalletLabel,
            amount: o.appWalletRevenue,
            note: l10n.ordersCount(o.appWalletOrders),
          ),
          const Divider(height: AppSpace.lg, color: AppColors.borderSoft),
          _FlowRow(
            label: l10n.grossMerchandiseValue,
            amount: o.grossRevenue,
            emphasis: true,
          ),

          const SizedBox(height: AppSpace.lg),
          _sectionLabel(l10n.whereItGoes),
          const SizedBox(height: AppSpace.sm),
          _FlowRow(
            label: l10n.vendorPayouts,
            amount: -o.vendorEarnings,
            tone: AppColors.dangerInk,
          ),
          _FlowRow(
            label: l10n.driverCost,
            amount: -o.driverEarnings,
            tone: AppColors.dangerInk,
          ),
          _FlowRow(
            label: l10n.platformFundedDiscounts,
            amount: -o.platformDiscounts,
            tone: AppColors.dangerInk,
          ),
          _FlowRow(
            label: l10n.platformCommission,
            amount: o.platformCommission,
            tone: AppColors.successInk,
          ),
          _FlowRow(
            label: l10n.platformShareLabel,
            amount: o.platformDeliveryMargin,
            tone: AppColors.successInk,
          ),
          const Divider(height: AppSpace.lg, color: AppColors.borderSoft),
          // Read straight off the platform's own ledger balance rather than
          // computed from the rows above, so it can never drift from what the
          // ledger says the platform actually holds.
          _FlowRow(
            label: l10n.platformNetLedger,
            amount: o.platformRevenue,
            emphasis: true,
            tone: o.platformRevenue >= 0
                ? AppColors.successInk
                : AppColors.dangerInk,
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.9,
      color: AppColors.textFaint,
    ),
  );
}

class _FlowRow extends StatelessWidget {
  const _FlowRow({
    required this.label,
    required this.amount,
    this.note,
    this.emphasis = false,
    this.tone,
  });

  final String label;
  final double amount;
  final String? note;
  final bool emphasis;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: emphasis ? 13.5 : 13,
                fontWeight: emphasis ? FontWeight.w800 : FontWeight.w500,
                color: emphasis ? AppColors.ink : AppColors.textSecondary,
              ),
            ),
          ),
          if (note != null) ...[
            const SizedBox(width: AppSpace.sm),
            Text(
              note!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textFaint,
              ),
            ),
          ],
          const SizedBox(width: AppSpace.md),
          Text(
            // The minus stays on the number rather than being implied by the
            // colour: red is not readable as a sign to everyone, and these
            // figures get screenshotted into messages that lose it entirely.
            '${amount < 0 ? '-' : ''}${formatMoney(amount.abs())}',
            style: AppType.mono(
              emphasis ? 14 : 12.5,
              weight: emphasis ? FontWeight.w800 : FontWeight.w600,
              color: tone ?? (emphasis ? AppColors.ink : AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Says out loud whether the ledger adds up.
///
/// The invariant is that every signed amount across all three parties sums to
/// zero, because money is only moved between accounts and never created. A
/// non-zero total is a bug, and it is worth more screen space than any revenue
/// figure — a dashboard that quietly renders wrong numbers is worse than one
/// that refuses to.
class _IntegrityBanner extends StatelessWidget {
  const _IntegrityBanner({
    required this.balanced,
    required this.net,
    required this.unsettledOrders,
    required this.onBackfill,
  });

  final bool balanced;
  final double net;
  final int unsettledOrders;
  final VoidCallback onBackfill;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final healthy = balanced && unsettledOrders == 0;

    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: healthy ? AppColors.successFill : AppColors.dangerFill,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                healthy ? Icons.verified_rounded : Icons.report_problem_rounded,
                size: 19,
                color: healthy ? AppColors.successInk : AppColors.dangerInk,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  balanced
                      ? l10n.booksBalanced
                      : l10n.booksNotBalanced(formatMoney(net)),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: healthy ? AppColors.successInk : AppColors.dangerInk,
                  ),
                ),
              ),
            ],
          ),
          if (unsettledOrders > 0) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              l10n.unsettledOrdersWarning(unsettledOrders),
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.dangerInk,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            // Safe to press twice: the split is idempotent per order.
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonal(
                onPressed: onBackfill,
                child: Text(l10n.runBackfill),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
