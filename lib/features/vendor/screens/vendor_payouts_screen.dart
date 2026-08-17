import 'package:flutter/material.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../../app/tokens.dart';
import '../../../core/models/finance.dart';
import '../../../core/repositories/finance_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart' show ButtonSpinner;
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
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

  /// Same request→approve queue as [_requestSettlement], just with the fee
  /// [_quote] quoted up front — nothing moves until an admin approves this
  /// one either, the fee only buys a place in front of the free requests.
  Future<void> _takeEarly() async {
    final quote = _quote!;
    final l10n = context.l10n;
    final due = quote.nextScheduledPayout;

    final confirmed = await showConfirmDialog(
      context: context,
      title: l10n.earlyPayout,
      // Both numbers and the date, so the trade is explicit: this is the one
      // decision on the screen that costs the store money.
      message: l10n.confirmEarlyPayout(
        formatMoney(quote.netPayout),
        formatMoney(quote.payable),
        due == null ? '—' : '${due.day}/${due.month}',
      ),
      confirmLabel: l10n.earlyPayout,
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
  /// admin approves it. Unlike Early Payout there is nothing to weigh — it
  /// costs nothing — so it fires straight from the button, no confirm dialog.
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
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: _loading
            ? const LoadingView()
            : _error != null
            ? ErrorView(message: _error!, onRetry: _load)
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  AppSpace.gutter,
                  AppSpace.md,
                  AppSpace.gutter,
                  AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  // A statement is a column of rows, and a row 1,300px wide
                  // puts its label and its amount at opposite ends of the
                  // monitor. Cap it and centre it; the console's own chrome
                  // fills the rest.
                  _capped(
                    context,
                    children: [
                      WalletHeadline(wallet: _wallet!),
                      const SizedBox(height: AppSpace.md),
                      if (_pendingRequest != null)
                        PendingSettlementTile(pending: _pendingRequest!)
                      else ...[
                        EarlyPayoutCard(quote: _quote!, onTake: _takeEarly),
                        const SizedBox(height: AppSpace.md),
                        SettlementRequestCard(
                          title: l10n.requestSettlement,
                          hint: l10n.requestSettlementHint,
                          payable: _wallet!.payable,
                          busy: _requestingSettlement,
                          onRequest: _requestSettlement,
                        ),
                      ],
                      const SizedBox(height: AppSpace.md),
                      // Two totals that describe one running account, so they read
                      // as consecutive lines rather than as a pair of unrelated
                      // dashboard tiles sitting side by side.
                      _SummaryRows(
                        rows: [
                          (
                            label: l10n.totalEarningsLabel,
                            value: formatMoney(_wallet!.totalEarnings),
                            tone: AppColors.successInk,
                          ),
                          (
                            label: l10n.totalSettlementsLabel,
                            value: formatMoney(_wallet!.cashSettled),
                            tone: null,
                          ),
                        ],
                      ),
                      if (_settlements.isNotEmpty) ...[
                        const SizedBox(height: AppSpace.lg),
                        _SectionHeader(
                          title: l10n.settlementsTitle,
                          count: _settlements.length,
                          hasMore: _hasMoreSettlements,
                        ),
                        const SizedBox(height: AppSpace.xs),
                        _ListCard(
                          children: [
                            for (final settlement in _settlements)
                              SettlementTile(settlement: settlement),
                          ],
                        ),
                        // A button rather than infinite scroll: this list sits in
                        // the middle of a page that continues with the statement
                        // below it, so loading on scroll would fight the section
                        // underneath for the same gesture.
                        if (_hasMoreSettlements)
                          _LoadMore(
                            busy: _loadingMoreSettlements,
                            onPressed: _loadMoreSettlements,
                          ),
                      ],
                      const SizedBox(height: AppSpace.lg),
                      _SectionHeader(
                        title: l10n.statement,
                        count: _entries.length,
                        hasMore: _hasMoreEntries,
                      ),
                      const SizedBox(height: AppSpace.xs),
                      if (_entries.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: EmptyView(
                            message: l10n.noTransactionsYet,
                            icon: Icons.receipt_long_outlined,
                          ),
                        )
                      else ...[
                        _ListCard(
                          children: [
                            for (final entry in _entries)
                              LedgerTile(entry: entry),
                          ],
                        ),
                        if (_hasMoreEntries)
                          _LoadMore(
                            busy: _loadingMoreEntries,
                            onPressed: _loadMoreEntries,
                          ),
                      ],
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  /// One `ListView` child holding the page, so the cap applies to the content
  /// without the scroll view itself being boxed — a `ConstrainedBox` around
  /// the `ListView` would also narrow its scrollbar and its refresh gesture.
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

/// Totals as consecutive rows in one card.
///
/// Replaces a two-cell `GridView`: on a phone those cells were half the width
/// of a figure that can run to `EGP 123,456.78`, and in the web console they
/// stretched to a third of the window each with nothing in them. A money
/// figure wants a label on its left and nothing else on its line.
class _SummaryRows extends StatelessWidget {
  const _SummaryRows({required this.rows});

  final List<({String label, String value, Color? tone})> rows;

  @override
  Widget build(BuildContext context) => _ListCard(
    children: [
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  row.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Text(
                row.value,
                style: AppType.mono(
                  16,
                  weight: FontWeight.w800,
                  color: row.tone ?? AppColors.ink,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// A bordered container that hairlines between its children, so a run of rows
/// reads as one list instead of as loose tiles on the page background.
class _ListCard extends StatelessWidget {
  const _ListCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                color: AppColors.borderSoft,
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
              child: children[i],
            ),
          ],
        ],
      ),
    );
  }
}

/// Section title with how many rows are under it.
///
/// The count carries a `+` while more pages exist, because "10" next to a list
/// of ten is the exact claim the old screen made falsely — it had more and
/// said nothing.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.hasMore,
  });

  final String title;
  final int count;
  final bool hasMore;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(title, style: AppType.heading(16))),
      if (count > 0)
        Text(
          hasMore ? '$count+' : '$count',
          style: AppType.mono(12.5, color: AppColors.textFaint),
        ),
    ],
  );
}

class _LoadMore extends StatelessWidget {
  const _LoadMore({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpace.sm),
    child: Center(
      child: busy
          ? const Padding(
              padding: EdgeInsets.all(AppSpace.sm),
              child: ButtonSpinner(size: 18),
            )
          : TextButton(
              onPressed: onPressed,
              child: Text(context.l10n.loadMore),
            ),
    ),
  );
}
