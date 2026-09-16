import 'package:flutter/material.dart';
import 'package:multi_vendor/core/widgets/proof_photo_field.dart'
    show pickProofPhoto;
import 'package:multi_vendor/core/errors/app_failure.dart' show UserMessage;

import 'package:flutter/services.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../../app/tokens.dart';
import '../../../core/models/finance.dart';
import '../../../core/repositories/finance_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/settlement_format.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/finance_widgets.dart';

/// The driver's own money.
///
/// Read-only by construction: the tables grant `SELECT` and nothing else, so
/// the only things this screen can write are *requests* — a cash hand-over,
/// which clears nothing until an admin confirms receiving the money, and a
/// payout request, which an admin still has to approve.
///
/// Layout, top to bottom: where the driver stands and the one action that
/// matches (hand over cash / withdraw), anything waiting on an admin, a short
/// summary, then activity.
class DriverWalletScreen extends StatefulWidget {
  const DriverWalletScreen({super.key});

  @override
  State<DriverWalletScreen> createState() => _DriverWalletScreenState();
}

enum _ActivityTab { statement, payouts }

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
  List<DepositRequest> _handOvers = const [];
  List<Settlement> _settlements = const [];
  double _tips = 0;
  bool _loading = true;
  bool _requestingPayout = false;
  String? _error;
  _ActivityTab _tab = _ActivityTab.statement;

  Settlement? get _pendingPayout =>
      _settlements.where((s) => s.status == 'pending').firstOrNull;

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
        _handOvers = results[2] as List<DepositRequest>;
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

  /// Withdraw: pick free/standard or paid/faster, then run it.
  Future<void> _withdraw() async {
    final wallet = _wallet!;
    final choice = await showWithdrawSheet(
      context,
      payable: wallet.payable,
      quote: _quote!,
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case WithdrawChoice.standard:
        await _requestPayout();
      case WithdrawChoice.faster:
        await _takeEarly();
    }
  }

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

  /// The paid, faster-review alternative — same queue, same "an admin still
  /// has to approve it" reality, with the fee confirmed before it is taken.
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
        await _repository.requestDriverEarlySettlement();
      },
    );
    if (!confirmed || !mounted) return;
    showSnack(context, l10n.settlementRequested);
    await _load();
  }

  /// Hand over the cash collected from customers. Pre-filled with everything
  /// the driver is holding, which is what is handed over almost every time.
  Future<void> _handOverCash() async {
    final l10n = context.l10n;
    final due = _wallet?.cashDue ?? 0;
    _amountController.text = due > 0 ? trimZeros(due) : '';
    _referenceController.clear();
    var method = 'cash';
    String? photoName;
    Uint8List? photoBytes;

    Future<void> pickPhoto(void Function() rebuild) async {
      final picked = await pickProofPhoto(context);
      if (picked == null) return;
      photoName = picked.name;
      photoBytes = picked.bytes;
      rebuild();
    }

    final created = await showFormSheet<bool>(
      context: context,
      title: l10n.requestDeposit,
      subtitle: l10n.handOverCashHint,
      icon: Icons.move_to_inbox_rounded,
      contentBuilder: (rebuild) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _amountController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: AppType.mono(18, weight: FontWeight.w800),
            decoration: InputDecoration(
              labelText: l10n.depositAmount,
              suffixText: l10n.egp,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Text(
            l10n.depositMethod,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          SegmentedButton<String>(
            expandedInsets: EdgeInsets.zero,
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: 'cash',
                icon: const Icon(Icons.payments_outlined, size: 17),
                label: Text(
                  l10n.settlementMethodCash,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ButtonSegment(
                value: 'bank_transfer',
                icon: const Icon(Icons.account_balance_outlined, size: 17),
                label: Text(
                  l10n.settlementMethodBank,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            selected: {method},
            onSelectionChanged: (value) {
              method = value.first;
              rebuild();
            },
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _referenceController,
            decoration: InputDecoration(labelText: l10n.referenceOptional),
          ),
          const SizedBox(height: AppSpace.md),
          // The receipt is what an admin checks the claim against, so it sits
          // in the form rather than being something to send separately.
          InkWell(
            onTap: () => pickPhoto(rebuild),
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Container(
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: photoBytes == null
                    ? AppColors.canvas
                    : AppColors.successFill,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(
                  color: photoBytes == null
                      ? AppColors.border
                      : AppColors.successInk.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: photoBytes == null
                          ? const ColoredBox(
                              color: AppColors.warmFill,
                              child: Icon(
                                Icons.add_a_photo_rounded,
                                color: AppColors.primary,
                              ),
                            )
                          : Image.memory(photoBytes!, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          photoBytes == null
                              ? l10n.attachProofPhoto
                              : l10n.changePhoto,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.attachProofHint,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (photoBytes != null)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        photoName = null;
                        photoBytes = null;
                        rebuild();
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      submitLabel: l10n.requestDeposit,
      cancelLabel: l10n.cancel,
      onSubmit: (_) async {
        final amount = double.tryParse(_amountController.text.trim());
        if (amount == null || amount <= 0) {
          // Thrown rather than returned: the form shows it inline and keeps
          // everything the driver typed.
          throw UserMessage(l10n.amountRequired);
        }
        // A bank transfer is only verifiable against its receipt.
        if (method == 'bank_transfer' && photoBytes == null) {
          throw UserMessage(l10n.proofRequiredForBank);
        }
        final proofPath = photoBytes == null
            ? null
            : await _repository.uploadDepositProof(
                photoBytes!,
                photoName ?? 'receipt.jpg',
              );
        await _repository.createDepositRequest(
          amount: amount,
          paymentMethod: method,
          proofUrl: proofPath,
          reference: _referenceController.text.trim().isEmpty
              ? null
              : _referenceController.text.trim(),
        );
        return true;
      },
    );

    if (created == true && mounted) {
      showSnack(context, l10n.depositRequested);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.wallet)),
      body: _loading
          ? const LoadingView()
          : _error != null && _wallet == null
          ? ErrorView(message: _error!, onRetry: _load)
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: _content(context),
            ),
    );
  }

  Widget _content(BuildContext context) {
    final l10n = context.l10n;
    final wallet = _wallet!;
    final pendingHandOvers = _handOvers.where((d) => d.isPending).toList();
    final pendingPayout = _pendingPayout;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.lg,
        AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        WalletHero(
          wallet: wallet,
          onHandOver: _handOverCash,
          // One open payout at a time — the server refuses a second.
          onWithdraw: pendingPayout == null ? _withdraw : null,
          withdrawBusy: _requestingPayout,
        ),

        if (pendingHandOvers.isNotEmpty || pendingPayout != null)
          InReviewCard(
            children: [
              for (final handOver in pendingHandOvers)
                InReviewRow(
                  icon: Icons.move_to_inbox_rounded,
                  title: l10n.requestDeposit,
                  subtitle: [
                    settlementMethodLabel(context, handOver.paymentMethod),
                    financeDayLabel(context, handOver.createdAt),
                  ].join(' · '),
                  amount: formatMoney(handOver.amount),
                ),
              if (pendingPayout != null)
                InReviewRow(
                  icon: pendingPayout.isEarly
                      ? Icons.bolt_rounded
                      : Icons.account_balance_rounded,
                  title: pendingPayout.isEarly
                      ? l10n.fasterPayout
                      : l10n.standardPayout,
                  subtitle: financeDayLabel(context, pendingPayout.createdAt),
                  amount: formatMoney(pendingPayout.amount),
                  onTap: () => showSettlementDetails(context, pendingPayout),
                ),
            ],
          ),

        FinanceSection(
          title: l10n.summaryLabel,
          child: FinanceCard(
            children: [
              FinanceRow(
                icon: Icons.two_wheeler_rounded,
                label: l10n.totalEarningsLabel,
                value: formatMoney(wallet.totalEarnings),
                tone: AppColors.successInk,
              ),
              // Paid into the in-app wallet by the customer, not owed by the
              // platform — so it sits beside the balance rather than in it.
              FinanceRow(
                icon: Icons.volunteer_activism_rounded,
                label: l10n.tips,
                value: formatMoney(_tips),
                tone: AppColors.successInk,
              ),
              FinanceRow(
                icon: Icons.payments_rounded,
                label: l10n.cashCollectedLabel,
                value: formatMoney(wallet.cashCollected),
              ),
              FinanceRow(
                icon: Icons.move_to_inbox_rounded,
                label: l10n.cashHandedOver,
                value: formatMoney(wallet.totalDeposited),
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
        switch (_tab) {
          _ActivityTab.statement => LedgerActivity(entries: _entries),
          _ActivityTab.payouts =>
            _settlements.isEmpty
                ? FinanceEmpty(
                    message: l10n.noTransactionsYet,
                    icon: Icons.account_balance_outlined,
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpace.md),
                    child: FinanceCard(
                      children: [
                        for (final settlement in _settlements)
                          SettlementTile(settlement: settlement),
                      ],
                    ),
                  ),
        },
      ],
    );
  }
}
