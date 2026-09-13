import 'package:flutter/material.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../../app/tokens.dart';
import '../../../core/models/finance.dart';
import '../../../core/repositories/finance_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/finance_widgets.dart';

/// What the store is owed, after the platform's cut, and when it arrives.
///
/// The figure at the top is the settled one — commission already deducted —
/// because that is the number the store is actually paid. The gross and the
/// commission are shown underneath so it reconciles rather than having to be
/// taken on trust.
class VendorPayoutsScreen extends StatefulWidget {
  const VendorPayoutsScreen({
    super.key,
    required this.vendorId,
    this.embedded = false,
  });

  final String vendorId;
  final bool embedded;

  @override
  State<VendorPayoutsScreen> createState() => _VendorPayoutsScreenState();
}

enum _ActivityTab { statement, payouts }

class _VendorPayoutsScreenState extends State<VendorPayoutsScreen> {
  final _repository = FinanceRepository();

  WalletSummary? _wallet;
  EarlySettlementQuote? _quote;
  List<LedgerEntry> _entries = const [];
  List<Settlement> _settlements = const [];

  /// The settlements list was capped at 10 with no way past it, so a store
  /// more than a couple of months old simply could not see its older
  /// payouts — the screen looked complete while quietly hiding history.
  static const _settlementsPage = 10;
  bool _loadingMoreSettlements = false;
  bool _hasMoreSettlements = false;

  /// The statement had the same problem one section further down and no fix:
  /// 40 rows, then nothing, with no indication that anything was missing. A
  /// busy store passes 40 ledger rows inside a week.
  static const _entriesPage = 25;
  bool _loadingMoreEntries = false;
  bool _hasMoreEntries = false;

  bool _loading = true;
  bool _requestingSettlement = false;
  String? _error;
  _ActivityTab _tab = _ActivityTab.statement;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _wallet == null;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repository.vendorWallet(widget.vendorId),
        _repository.earlySettlementQuote(widget.vendorId),
        _repository.ledger(
          ownerType: LedgerOwner.vendor,
          ownerId: widget.vendorId,
          limit: _entriesPage,
        ),
        _repository.settlements(
          ownerType: LedgerOwner.vendor,
          ownerId: widget.vendorId,
          limit: _settlementsPage,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _wallet = results[0] as WalletSummary;
        _quote = results[1] as EarlySettlementQuote;
        _entries = results[2] as List<LedgerEntry>;
        _settlements = results[3] as List<Settlement>;
        // A full page means there is probably another; the next fetch
        // settles it either way.
        _hasMoreSettlements = _settlements.length == _settlementsPage;
        _hasMoreEntries = _entries.length == _entriesPage;
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

  Future<void> _loadMoreSettlements() async {
    if (_loadingMoreSettlements || !_hasMoreSettlements) return;
    setState(() => _loadingMoreSettlements = true);
    try {
      final page = await _repository.settlements(
        ownerType: LedgerOwner.vendor,
        ownerId: widget.vendorId,
        limit: _settlementsPage,
        offset: _settlements.length,
      );
      if (!mounted) return;
      setState(() {
        _settlements = [..._settlements, ...page];
        _hasMoreSettlements = page.length == _settlementsPage;
        _loadingMoreSettlements = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingMoreSettlements = false);
      showFailure(context, error, onRetry: _loadMoreSettlements);
    }
  }

  Future<void> _loadMoreEntries() async {
    if (_loadingMoreEntries || !_hasMoreEntries) return;
    setState(() => _loadingMoreEntries = true);
    try {
      final page = await _repository.ledger(
        ownerType: LedgerOwner.vendor,
        ownerId: widget.vendorId,
        limit: _entriesPage,
        offset: _entries.length,
      );
      if (!mounted) return;
      setState(() {
        _entries = [..._entries, ...page];
        _hasMoreEntries = page.length == _entriesPage;
        _loadingMoreEntries = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingMoreEntries = false);
      showFailure(context, error, onRetry: _loadMoreEntries);
    }
  }

  /// Withdraw: pick free/standard or paid/faster, then run it.
  Future<void> _withdraw() async {
    final choice = await showWithdrawSheet(
      context,
      payable: _wallet!.payable,
      quote: _quote!,
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case WithdrawChoice.standard:
        await _requestSettlement();
      case WithdrawChoice.faster:
        await _takeEarly();
    }
  }

  /// Same request→approve queue as [_requestSettlement], just with the fee
  /// [_quote] quoted up front — confirmed once more, because this is the one
  /// decision on the screen that costs the store money.
  Future<void> _takeEarly() async {
    final quote = _quote!;
    final l10n = context.l10n;
    final due = quote.nextScheduledPayout;

    final confirmed = await showConfirmDialog(
      context: context,
      title: l10n.fasterPayout,
      message: l10n.confirmEarlyPayout(
        formatMoney(quote.netPayout),
        formatMoney(quote.payable),
        due == null ? '—' : '${due.day}/${due.month}',
      ),
      confirmLabel: l10n.fasterPayout,
      cancelLabel: l10n.cancel,
      icon: Icons.bolt_rounded,
      onConfirm: () async {
        await _repository.requestEarlySettlement(vendorId: widget.vendorId);
      },
    );
    if (!confirmed || !mounted) return;
    showSnack(context, l10n.settlementRequested);
    await _load();
  }

  /// The free alternative to [_takeEarly]: no fee, but nothing moves until an
  /// admin approves it.
  Future<void> _requestSettlement() async {
    setState(() => _requestingSettlement = true);
    try {
      await _repository.requestVendorSettlement(vendorId: widget.vendorId);
      if (mounted) showSnack(context, context.l10n.settlementRequested);
      await _load();
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _requestingSettlement = false);
    }
  }

  Settlement? get _pendingRequest =>
      _settlements.where((s) => s.status == 'pending').firstOrNull;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: widget.embedded ? null : AppBar(title: Text(l10n.payouts)),
      body: _loading
          ? const LoadingView()
          : _error != null && _wallet == null
          ? ErrorView(message: _error!, onRetry: _load)
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  AppSpace.lg,
                  AppSpace.md,
                  AppSpace.lg,
                  AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
                ),
                // A statement is a column of rows, and a row 1,300px wide
                // puts its label and its amount at opposite ends of the
                // monitor. Cap it and centre it.
                children: [_capped(context, children: _sections(context))],
              ),
            ),
    );
  }

  List<Widget> _sections(BuildContext context) {
    final l10n = context.l10n;
    final wallet = _wallet!;
    final pending = _pendingRequest;

    return [
      WalletHero(
        wallet: wallet,
        // One open request at a time — the server refuses a second.
        onWithdraw: pending == null ? _withdraw : null,
        withdrawBusy: _requestingSettlement,
      ),
      if (pending != null)
        InReviewCard(
          children: [
            InReviewRow(
              icon: pending.isEarly
                  ? Icons.bolt_rounded
                  : Icons.account_balance_rounded,
              title: pending.isEarly ? l10n.fasterPayout : l10n.standardPayout,
              subtitle: financeDayLabel(context, pending.createdAt),
              amount: formatMoney(pending.amount),
              onTap: () => showSettlementDetails(context, pending),
            ),
          ],
        ),
      FinanceSection(
        title: l10n.summaryLabel,
        child: FinanceCard(
          children: [
            FinanceRow(
              icon: Icons.storefront_rounded,
              label: l10n.totalEarningsLabel,
              value: formatMoney(wallet.totalEarnings),
              tone: AppColors.successInk,
            ),
            FinanceRow(
              icon: Icons.account_balance_rounded,
              label: l10n.settlementsPaidOut,
              value: formatMoney(wallet.cashSettled),
            ),
          ],
        ),
      ),
      FinanceSection(
        title: l10n.activityLabel,
        child: FinanceSegments<_ActivityTab>(
          values: _ActivityTab.values,
          selected: _tab,
          labelOf: (t) => switch (t) {
            _ActivityTab.statement => l10n.statement,
            _ActivityTab.payouts => l10n.payouts,
          },
          onChanged: (t) => setState(() => _tab = t),
        ),
      ),
      if (_tab == _ActivityTab.statement) ...[
        LedgerActivity(entries: _entries),
        if (_hasMoreEntries)
          FinanceLoadMore(
            busy: _loadingMoreEntries,
            onPressed: _loadMoreEntries,
          ),
      ] else ...[
        if (_settlements.isEmpty)
          FinanceEmpty(
            message: l10n.noTransactionsYet,
            icon: Icons.account_balance_outlined,
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.md),
            child: FinanceCard(
              children: [
                for (final settlement in _settlements)
                  SettlementTile(settlement: settlement),
              ],
            ),
          ),
        if (_hasMoreSettlements)
          FinanceLoadMore(
            busy: _loadingMoreSettlements,
            onPressed: _loadMoreSettlements,
          ),
      ],
    ];
  }

  /// One `ListView` child holding the page, so the cap applies to the content
  /// without the scroll view itself being boxed.
  Widget _capped(BuildContext context, {required List<Widget> children}) {
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
}
