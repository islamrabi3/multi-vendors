import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../../app/tokens.dart';
import '../../../core/models/finance.dart';
import '../../../core/repositories/finance_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
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
  double? _driverShare;
  bool _loading = true;
  String? _error;
  _Period _period = _Period.month;
  BuildContext? _tabContext;
  final _driverShareController = TextEditingController();

  @override
  void dispose() {
    _driverShareController.dispose();
    super.dispose();
  }

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
      // A separate, non-fatal fetch: an admin whose role can view reports but
      // not adjust finance still gets a working screen, just without the
      // driver-share card, rather than an error over the whole tab.
      final driverShare = await _repository.driverShareConfig().then<double?>(
        (v) => v,
        onError: (_) => null,
      );
      if (!mounted) return;
      setState(() {
        _overview = results[0] as FinanceOverview;
        _reconciliation = results[1] as CashReconciliation;
        _integrity =
            results[2] as ({bool balanced, double net, int unsettledOrders});
        _pendingRequests = (results[3] as List<Settlement>).length;
        _driverShare = driverShare;
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

  /// Sets what a driver keeps out of every delivery fee, platform-wide.
  ///
  /// One field, not two: the driver's percent and the platform's are the same
  /// number twice, and a form that let them be edited separately could be
  /// saved not summing to 100.
  Future<void> _editDriverShare() async {
    final l10n = context.l10n;
    final current = _driverShare;
    if (current == null) return;
    _driverShareController.text = trimZeros(current);

    final saved = await showFormDialog<bool>(
      context: context,
      title: l10n.driverShareTitle,
      subtitle: l10n.driverShareScope,
      icon: Icons.two_wheeler_rounded,
      contentBuilder: (rebuild) {
        final driverPercent = double.tryParse(
          _driverShareController.text.trim(),
        );
        final platformPercent = driverPercent == null
            ? null
            : (100 - driverPercent).clamp(0, 100).toDouble();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _driverShareController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => rebuild(),
              decoration: InputDecoration(
                labelText: l10n.driverShareLabel,
                suffixText: '%',
              ),
            ),
            if (platformPercent != null) ...[
              const SizedBox(height: AppSpace.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: AppColors.neutralFill,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Text(
                  l10n.platformShareResult(trimZeros(platformPercent)),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        );
      },
      submitLabel: l10n.save,
      cancelLabel: l10n.cancel,
      onSubmit: (_) async {
        final percent = double.tryParse(_driverShareController.text.trim());
        if (percent == null || percent < 0 || percent > 100) {
          throw Exception(l10n.invalidFeePercent);
        }
        final updated = await _repository.setDriverShare(percent);
        if (mounted) setState(() => _driverShare = updated);
        return true;
      },
    );

    if (saved == true && mounted) showSnack(context, l10n.driverShareUpdated);
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
        : Builder(
            builder: (tabContext) {
              _tabContext = tabContext;
              return TabBarView(
                children: [_overviewTab(), _reconciliationTab()],
              );
            },
          );

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
          forStaff: true,
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

  /// Caps content on wide windows so rows keep label and amount close.
  Widget _capped(List<Widget> children) {
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    if (!AppBreakpoints.isWebWide(context)) return column;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: column,
      ),
    );
  }

  EdgeInsets get _listPadding => EdgeInsets.fromLTRB(
    AppSpace.lg,
    AppSpace.md,
    AppSpace.lg,
    AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
  );

  Widget _periodPicker() {
    final l10n = context.l10n;
    return FinanceSegments<_Period>(
      values: _Period.values,
      selected: _period,
      labelOf: (p) => switch (p) {
        _Period.today => l10n.today,
        _Period.week => l10n.last7Days,
        _Period.month => l10n.last30Days,
        _Period.all => l10n.allTime,
      },
      onChanged: (p) {
        if (p == _period) return;
        setState(() => _period = p);
        _load();
      },
    );
  }

  Widget _overviewTab() {
    final l10n = context.l10n;
    final o = _overview!;
    final integrity = _integrity!;
    final reconciliation = _reconciliation!;

    final attention = <Widget>[
      if (!integrity.balanced)
        _AttentionRow(
          icon: Icons.report_problem_rounded,
          tone: AppColors.dangerInk,
          text: l10n.booksNotBalanced(formatMoney(integrity.net)),
        ),
      if (integrity.unsettledOrders > 0)
        _AttentionRow(
          icon: Icons.sync_problem_rounded,
          tone: AppColors.dangerInk,
          text: l10n.unsettledOrdersWarning(integrity.unsettledOrders),
          // Safe to press twice: the split is idempotent per order.
          actionLabel: l10n.runBackfill,
          onTap: _backfill,
        ),
      if (reconciliation.hasException)
        _AttentionRow(
          icon: Icons.money_off_rounded,
          tone: AppColors.dangerInk,
          text: l10n.reconciliationException,
          // The State's own context sits above the tab controller.
          onTap: () => DefaultTabController.maybeOf(
            _tabContext ?? context,
          )?.animateTo(1),
        ),
      if (_pendingRequests > 0)
        _AttentionRow(
          icon: Icons.account_balance_rounded,
          tone: AppColors.amberInk,
          text: l10n.pendingApprovalsBanner(_pendingRequests),
          onTap: () => AdminWebNav.go(context, '/admin-app/settlements'),
        ),
      if (o.pendingDeposits > 0)
        _AttentionRow(
          icon: Icons.move_to_inbox_rounded,
          tone: AppColors.amberInk,
          text: l10n.pendingHandOversBanner(o.pendingDeposits),
          onTap: () => AdminWebNav.go(context, '/admin-app/deposits'),
        ),
    ];

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _listPadding,
        children: [
          _capped([
            _periodPicker(),
            const SizedBox(height: AppSpace.md),

            // What the business kept — the bottom line. Deliberately *not*
            // the platform ledger account's balance: that account is a
            // clearing account and trends to zero.
            FinanceHero(
              tone: o.platformEarnings >= 0
                  ? FinanceHeroTone.brand
                  : FinanceHeroTone.warning,
              eyebrow: l10n.platformEarnings,
              amount: formatMoney(o.platformEarnings),
              caption:
                  '${l10n.grossMerchandiseValue}: ${formatMoney(o.grossRevenue)}'
                  ' · ${l10n.ordersCount(o.totalOrders)}',
            ),

            // Money that does not add up is more urgent than any figure
            // below it, so problems sit right under the headline.
            FinanceSection(
              title: l10n.needsAttention,
              child: FinanceCard(
                children: attention.isEmpty
                    ? [
                        _AttentionRow(
                          icon: Icons.verified_rounded,
                          tone: AppColors.successInk,
                          text:
                              '${l10n.booksBalanced} · ${l10n.nothingNeedsAttention}',
                        ),
                      ]
                    : attention,
              ),
            ),

            // The four routes are drawn from the same delivered-orders set and
            // each order belongs to exactly one, so they sum to the total.
            FinanceSection(
              title: l10n.collectedFromCustomers,
              child: FinanceCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.lg,
                      AppSpace.lg,
                      AppSpace.lg,
                      AppSpace.sm,
                    ),
                    child: _SplitBar(
                      parts: [
                        (o.codRevenue, _inColors[0]),
                        (o.cardRevenue, _inColors[1]),
                        (o.mobileWalletRevenue, _inColors[2]),
                        (o.appWalletRevenue, _inColors[3]),
                      ],
                    ),
                  ),
                  FinanceRow(
                    icon: Icons.payments_rounded,
                    tone: _inColors[0],
                    label: l10n.cashOnDelivery,
                    note: l10n.ordersCount(o.cashOrders),
                    value: formatMoney(o.codRevenue),
                  ),
                  FinanceRow(
                    icon: Icons.credit_card_rounded,
                    tone: _inColors[1],
                    label: l10n.card,
                    note: l10n.ordersCount(o.cardOrders),
                    value: formatMoney(o.cardRevenue),
                  ),
                  FinanceRow(
                    icon: Icons.smartphone_rounded,
                    tone: _inColors[2],
                    label: l10n.mobileWallet,
                    note: l10n.ordersCount(o.mobileWalletOrders),
                    value: formatMoney(o.mobileWalletRevenue),
                  ),
                  FinanceRow(
                    icon: Icons.account_balance_wallet_rounded,
                    tone: _inColors[3],
                    label: l10n.appWalletLabel,
                    note: l10n.ordersCount(o.appWalletOrders),
                    value: formatMoney(o.appWalletRevenue),
                  ),
                  FinanceRow(
                    label: l10n.grossMerchandiseValue,
                    value: formatMoney(o.grossRevenue),
                    emphasis: true,
                  ),
                ],
              ),
            ),

            // The ledger's own figures. Not joined to the block above with an
            // equals sign: tips pass straight through and refunds and
            // adjustments land in their own rows.
            FinanceSection(
              title: l10n.whereItGoes,
              child: FinanceCard(
                children: [
                  _signedRow(l10n.vendorPayouts, -o.vendorEarnings),
                  _signedRow(l10n.driverCost, -o.driverEarnings),
                  _signedRow(
                    l10n.platformFundedDiscounts,
                    -o.platformDiscounts,
                  ),
                  _signedRow(l10n.platformCommission, o.platformCommission),
                  _signedRow(l10n.platformShareLabel, o.platformDeliveryMargin),
                  if (o.earlySettlementFees != 0)
                    _signedRow(l10n.earlySettlementFees, o.earlySettlementFees),
                  FinanceRow(
                    label: l10n.platformEarnings,
                    value: _signed(o.platformEarnings),
                    emphasis: true,
                    tone: o.platformEarnings >= 0
                        ? AppColors.successInk
                        : AppColors.dangerInk,
                  ),
                ],
              ),
            ),

            // Positions rather than flows, which is why they ignore the period.
            FinanceSection(
              title: l10n.openBalances,
              child: FinanceCard(
                children: [
                  FinanceRow(
                    icon: Icons.two_wheeler_rounded,
                    tone: AppColors.amberInk,
                    label: l10n.driverCashDueTotal,
                    value: formatMoney(o.driverCashDue),
                    onTap: () =>
                        AdminWebNav.go(context, '/admin-app/settlements'),
                  ),
                  FinanceRow(
                    icon: Icons.storefront_rounded,
                    tone: AppColors.primary,
                    label: l10n.vendorPayableTotal,
                    value: formatMoney(o.vendorPayable),
                    onTap: () =>
                        AdminWebNav.go(context, '/admin-app/settlements'),
                  ),
                ],
              ),
            ),

            FinanceSection(
              title: l10n.moneyMovements,
              child: FinanceCard(
                children: [
                  FinanceRow(
                    icon: Icons.payments_rounded,
                    label: l10n.cashCollectedLabel,
                    value: formatMoney(o.cashCollected),
                  ),
                  FinanceRow(
                    icon: Icons.move_to_inbox_rounded,
                    label: l10n.cashHandedOver,
                    value: formatMoney(o.deposits),
                    onTap: () => AdminWebNav.go(context, '/admin-app/deposits'),
                  ),
                  FinanceRow(
                    icon: Icons.account_balance_rounded,
                    label: l10n.settlementsPaidOut,
                    value: formatMoney(o.settlements),
                  ),
                  FinanceRow(
                    icon: Icons.undo_rounded,
                    label: l10n.refunds,
                    value: formatMoney(o.refunds),
                  ),
                ],
              ),
            ),

            // The number that decides the driver-cost and delivery-share rows
            // above, so its control sits on the same page.
            if (_driverShare != null)
              FinanceSection(
                title: l10n.driverShareTitle,
                child: FinanceCard(
                  children: [
                    FinanceRow(
                      icon: Icons.tune_rounded,
                      label: l10n.driverShareSummary(
                        trimZeros(_driverShare!),
                        trimZeros(100 - _driverShare!),
                      ),
                      value: '${trimZeros(_driverShare!)}%',
                      onTap: _editDriverShare,
                    ),
                  ],
                ),
              ),
          ]),
        ],
      ),
    );
  }

  static const _inColors = [
    AppColors.amberInk,
    AppColors.primary,
    AppColors.pistachioInk,
    AppColors.primaryLight,
  ];

  /// The minus stays on the number rather than being implied by colour: red
  /// is not readable as a sign to everyone, and screenshots lose it.
  String _signed(double amount) =>
      '${amount < 0
          ? '-'
          : amount > 0
          ? '+'
          : ''}${formatMoney(amount.abs())}';

  Widget _signedRow(String label, double amount) => FinanceRow(
    label: label,
    value: _signed(amount),
    tone: amount < 0
        ? AppColors.dangerInk
        : amount > 0
        ? AppColors.successInk
        : AppColors.textMuted,
  );

  Widget _reconciliationTab() {
    final l10n = context.l10n;
    final r = _reconciliation!;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _listPadding,
        children: [
          _capped([
            _periodPicker(),
            const SizedBox(height: AppSpace.md),
            FinanceHero(
              tone: r.hasException
                  ? FinanceHeroTone.warning
                  : FinanceHeroTone.calm,
              eyebrow: l10n.cashDifference,
              amount: formatMoney(r.difference),
              caption: r.hasException
                  ? l10n.reconciliationException
                  : l10n.reconciliationClean,
            ),
            FinanceSection(
              title: l10n.cashReconciliation,
              child: FinanceCard(
                children: [
                  FinanceRow(
                    icon: Icons.receipt_long_rounded,
                    label: l10n.expectedCash,
                    value: formatMoney(r.expectedCash),
                  ),
                  FinanceRow(
                    icon: Icons.payments_rounded,
                    label: l10n.collectedCash,
                    value: formatMoney(r.collectedCash),
                  ),
                  FinanceRow(
                    icon: Icons.move_to_inbox_rounded,
                    label: l10n.settledCash,
                    value: formatMoney(r.settledCash),
                  ),
                  FinanceRow(
                    icon: Icons.two_wheeler_rounded,
                    tone: AppColors.amberInk,
                    label: l10n.outstandingCash,
                    value: formatMoney(r.outstandingCash),
                    onTap: () =>
                        AdminWebNav.go(context, '/admin-app/settlements'),
                  ),
                  FinanceRow(
                    label: l10n.cashDifference,
                    value: formatMoney(r.difference),
                    emphasis: true,
                    tone: r.hasException
                        ? AppColors.dangerInk
                        : AppColors.successInk,
                  ),
                ],
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

/// One line in the "needs attention" list.
class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.icon,
    required this.tone,
    required this.text,
    this.actionLabel,
    this.onTap,
  });

  final IconData icon;
  final Color tone;
  final String text;
  final String? actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.md,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: tone),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: tone,
              ),
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: AppSpace.sm),
            FilledButton.tonal(onPressed: onTap, child: Text(actionLabel!)),
          ] else if (onTap != null) ...[
            const SizedBox(width: AppSpace.xs),
            Icon(Icons.chevron_right_rounded, color: tone),
          ],
        ],
      ),
    );
    if (onTap == null || actionLabel != null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// A single horizontal bar split in proportion to [parts] — how the period's
/// money divides between payment routes, readable at a glance.
class _SplitBar extends StatelessWidget {
  const _SplitBar({required this.parts});

  final List<(double, Color)> parts;

  @override
  Widget build(BuildContext context) {
    final visible = parts.where((p) => p.$1 > 0).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: SizedBox(
        height: 12,
        child: visible.isEmpty
            ? const ColoredBox(color: AppColors.neutralFill)
            : Row(
                children: [
                  for (var i = 0; i < visible.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      // Flex needs an int; per-mille keeps small routes visible
                      // without distorting the large ones.
                      flex:
                          (visible[i].$1 *
                                  1000 /
                                  visible.fold<double>(0, (a, p) => a + p.$1))
                              .round()
                              .clamp(8, 1000),
                      child: ColoredBox(color: visible[i].$2),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
