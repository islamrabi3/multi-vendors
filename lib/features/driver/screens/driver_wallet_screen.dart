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

/// The driver's own money.
///
/// Read-only by construction: the tables grant `SELECT` and nothing else, so
/// the only thing this screen can write is a *request* to deposit, which
/// credits nothing until an admin confirms the payment. A driver cannot move
/// their own balance from here, and there is no code path that would let them.
class DriverWalletScreen extends StatefulWidget {
  const DriverWalletScreen({super.key});

  @override
  State<DriverWalletScreen> createState() => _DriverWalletScreenState();
}

class _DriverWalletScreenState extends State<DriverWalletScreen> {
  final _repository = FinanceRepository();

  // Owned by the screen: disposing them the moment the dialog future resolved
  // destroyed them while the exit animation was still rendering the fields.
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  WalletSummary? _wallet;
  EarlySettlementQuote? _quote;
  List<LedgerEntry> _entries = const [];
  List<DepositRequest> _deposits = const [];
  List<Settlement> _settlements = const [];
  double _tips = 0;
  bool _loading = true;
  bool _requestingPayout = false;
  String? _error;

  Settlement? get _pendingRequest =>
      _settlements.where((s) => s.status == 'pending').firstOrNull;

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
        _repository.myDriverWallet(),
        _repository.myDriverLedger(limit: 40),
        _repository.depositRequests(limit: 10),
        _repository.myTipsTotal(),
        _repository.myDriverSettlements(limit: 10),
        _repository.driverEarlySettlementQuote(),
      ]);
      if (!mounted) return;
      setState(() {
        _wallet = results[0] as WalletSummary;
        _entries = results[1] as List<LedgerEntry>;
        _deposits = results[2] as List<DepositRequest>;
        _tips = results[3] as double;
        _settlements = results[4] as List<Settlement>;
        _quote = results[5] as EarlySettlementQuote;
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

  /// Asking to be paid out the balance the platform owes — the opposite
  /// direction of [_requestDeposit], which is cash the driver hands in.
  Future<void> _requestPayout() async {
    setState(() => _requestingPayout = true);
    try {
      await _repository.requestDriverSettlement();
      if (mounted) showSnack(context, context.l10n.settlementRequested);
      await _load();
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _requestingPayout = false);
    }
  }

  /// The paid, faster-review alternative to [_requestPayout] — same queue,
  /// same "an admin still has to approve it" reality, just with the fee
  /// [_quote] spells out up front.
  Future<void> _takeEarly() async {
    final quote = _quote!;
    final l10n = context.l10n;
    final due = quote.nextScheduledPayout;

    final confirmed = await showConfirmDialog(
      context: context,
      title: l10n.earlyPayout,
      message: l10n.confirmEarlyPayout(
        formatMoney(quote.netPayout),
        formatMoney(quote.payable),
        due == null ? '—' : '${due.day}/${due.month}',
      ),
      confirmLabel: l10n.earlyPayout,
      cancelLabel: l10n.cancel,
      icon: Icons.bolt_rounded,
      onConfirm: () async {
        await _repository.requestDriverEarlySettlement();
      },
    );
    if (!confirmed || !mounted) return;
    showSnack(context, l10n.settlementRequested);
    await _load();
  }

  Future<void> _requestDeposit() async {
    _amountController.clear();
    _referenceController.clear();
    var method = 'bank_transfer';

    final created = await showFormDialog<bool>(
      context: context,
      title: context.l10n.requestDeposit,
      icon: Icons.account_balance_outlined,
      contentBuilder: (rebuild) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amountController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(labelText: context.l10n.depositAmount),
          ),
          const SizedBox(height: AppSpace.md),
          DropdownButtonFormField<String>(
            initialValue: method,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.l10n.depositMethod),
            items: [
              DropdownMenuItem(
                value: 'bank_transfer',
                child: Text(context.l10n.settlementMethodBank),
              ),
              DropdownMenuItem(
                value: 'cash',
                child: Text(context.l10n.settlementMethodCash),
              ),
            ],
            onChanged: (value) {
              method = value ?? method;
              rebuild();
            },
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _referenceController,
            decoration: InputDecoration(
              labelText: context.l10n.referenceOptional,
            ),
          ),
        ],
      ),
      submitLabel: context.l10n.submitRequest,
      cancelLabel: context.l10n.cancel,
      onSubmit: (_) async {
        final amount = double.tryParse(_amountController.text.trim());
        if (amount == null || amount <= 0) {
          // Thrown rather than returned: the dialog shows it inline and keeps
          // everything the driver typed.
          throw Exception(context.l10n.amountRequired);
        }
        await _repository.createDepositRequest(
          amount: amount,
          paymentMethod: method,
          reference: _referenceController.text.trim().isEmpty
              ? null
              : _referenceController.text.trim(),
        );
        return true;
      },
    );

    if (created == true && mounted) {
      showSnack(context, context.l10n.depositRequested);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final wallet = _wallet;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.wallet)),
      floatingActionButton: wallet == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _requestDeposit,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                l10n.requestDeposit,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
                  96 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  WalletHeadline(wallet: wallet!),
                  const SizedBox(height: AppSpace.md),
                  if (_pendingRequest != null)
                    PendingSettlementTile(pending: _pendingRequest!)
                  else ...[
                    EarlyPayoutCard(quote: _quote!, onTake: _takeEarly),
                    const SizedBox(height: AppSpace.md),
                    SettlementRequestCard(
                      title: l10n.requestPayout,
                      hint: l10n.requestPayoutHint,
                      payable: wallet.payable,
                      busy: _requestingPayout,
                      onRequest: _requestPayout,
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
                        value: formatMoney(wallet.totalEarnings),
                        tone: AppColors.successInk,
                      ),
                      MoneyTile(
                        label: l10n.cashCollectedLabel,
                        value: formatMoney(wallet.cashCollected),
                      ),
                      MoneyTile(
                        label: l10n.totalSettlementsLabel,
                        value: formatMoney(wallet.cashSettled),
                      ),
                      MoneyTile(
                        label: l10n.requestDeposit,
                        value: formatMoney(wallet.totalDeposited),
                      ),
                      // Paid into the in-app wallet by the customer, not owed
                      // by the platform — so it sits beside the balance rather
                      // than inside it.
                      MoneyTile(
                        label: l10n.tips,
                        value: formatMoney(_tips),
                        tone: AppColors.successInk,
                      ),
                    ],
                  ),
                  if (_deposits.any((d) => d.isPending)) ...[
                    const SizedBox(height: AppSpace.lg),
                    Text(
                      l10n.depositsAwaitingReview,
                      style: AppType.heading(16),
                    ),
                    for (final deposit in _deposits.where((d) => d.isPending))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.hourglass_top_rounded,
                          color: AppColors.amberInk,
                        ),
                        title: Text(formatMoney(deposit.amount)),
                        subtitle: Text(
                          l10n.depositRequested,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                  ],
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
