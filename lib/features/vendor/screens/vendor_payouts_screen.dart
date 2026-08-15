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

class _VendorPayoutsScreenState extends State<VendorPayoutsScreen> {
  final _repository = FinanceRepository();

  WalletSummary? _wallet;
  EarlySettlementQuote? _quote;
  List<LedgerEntry> _entries = const [];
  List<Settlement> _settlements = const [];
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
          limit: 40,
        ),
        _repository.settlements(
          ownerType: LedgerOwner.vendor,
          ownerId: widget.vendorId,
          limit: 10,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _wallet = results[0] as WalletSummary;
        _quote = results[1] as EarlySettlementQuote;
        _entries = results[2] as List<LedgerEntry>;
        _settlements = results[3] as List<Settlement>;
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
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.95,
                    crossAxisSpacing: AppSpace.md,
                    mainAxisSpacing: AppSpace.md,
                    children: [
                      MoneyTile(
                        label: l10n.totalEarningsLabel,
                        value: formatMoney(_wallet!.totalEarnings),
                        tone: AppColors.successInk,
                      ),
                      MoneyTile(
                        label: l10n.totalSettlementsLabel,
                        value: formatMoney(_wallet!.cashSettled),
                      ),
                    ],
                  ),
                  if (_settlements.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.lg),
                    Text(l10n.settlementsTitle, style: AppType.heading(16)),
                    for (final settlement in _settlements)
                      SettlementTile(settlement: settlement),
                  ],
                  const SizedBox(height: AppSpace.lg),
                  Text(l10n.statement, style: AppType.heading(16)),
                  const SizedBox(height: AppSpace.xs),
                  if (_entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: EmptyView(
                        message: l10n.noTransactionsYet,
                        icon: Icons.receipt_long_outlined,
                      ),
                    )
                  else
                    for (final entry in _entries) LedgerTile(entry: entry),
                ],
              ),
      ),
    );
  }
}
