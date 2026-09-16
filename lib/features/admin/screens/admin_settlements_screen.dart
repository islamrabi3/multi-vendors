import 'package:flutter/material.dart';
import 'package:multi_vendor/core/errors/app_failure.dart' show UserMessage;
import 'package:multi_vendor/features/admin/admin_action_badges.dart';
import 'package:multi_vendor/core/widgets/count_badge.dart';
import 'package:flutter/services.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../../app/tokens.dart';
import '../../../core/models/finance.dart';
import '../../../core/repositories/finance_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/finance_widgets.dart';
import '../../../core/widgets/proof_photo_field.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import 'admin_manage_screen.dart' show adminManageWebSections;
import '../../../core/widgets/web/adaptive_sheet.dart';

/// Who owes what, and the one action that changes it.
///
/// Drivers are listed by how much cash they are holding and stores by how much
/// they are owed — the two questions an operator actually opens this screen to
/// answer. Recording a settlement never edits a balance: it writes a ledger row
/// and the balance follows.
class AdminSettlementsScreen extends StatefulWidget {
  const AdminSettlementsScreen({super.key, this.embedded = false});

  /// True when a web sidebar is already drawing the shell around this screen
  /// (`_AdminWebShell`) — skips this widget's own [WebPageChrome]/[Scaffold].
  final bool embedded;

  @override
  State<AdminSettlementsScreen> createState() => _AdminSettlementsScreenState();
}

class _AdminSettlementsScreenState extends State<AdminSettlementsScreen> {
  final _repository = FinanceRepository();

  // Owned by the screen, not by each dialog. Disposing them when
  // `showFormDialog` returned killed them while the dialog was still animating
  // out and its TextFields were still listening — "A TextEditingController was
  // used after being disposed", which then took the whole render pass with it.
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _feePercentController = TextEditingController();
  final _feeMinController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _feePercentController.dispose();
    _feeMinController.dispose();
    super.dispose();
  }

  List<PartyBalance> _drivers = const [];
  List<PartyBalance> _vendors = const [];
  List<Settlement> _pending = const [];
  ({double percent, double min})? _fee;
  bool _loading = true;
  String? _error;
  String _driverQuery = '';
  String _vendorQuery = '';

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
        _repository.driverBalances(),
        _repository.vendorBalances(),
        _repository.pendingSettlementRequests(),
      ]);
      // Not in the batch above: an admin who can settle but whose role
      // predates `finance.settle` still gets a working screen, just without
      // the fee control, rather than an error page over the whole tab.
      final fee = await _repository
          .earlySettlementFeeConfig()
          .then<({double percent, double min})?>(
            (v) => v,
            onError: (_) => null,
          );
      if (!mounted) return;
      // Early ones cost the party a fee specifically for faster review, so
      // they lead the queue rather than sitting wherever their timestamp
      // happens to place them.
      final pending = results[2] as List<Settlement>
        ..sort((a, b) => b.isEarly == a.isEarly ? 0 : (b.isEarly ? 1 : -1));
      setState(() {
        _drivers = results[0] as List<PartyBalance>;
        _vendors = results[1] as List<PartyBalance>;
        _pending = pending;
        _fee = fee;
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

  /// Looks the requester's name up in whichever balances list already has
  /// it, rather than a second query — the pending row and the party card
  /// come from the same admin read, just two different shapes of it.
  String _partyName(Settlement settlement) {
    final list = settlement.ownerType == LedgerOwner.driver
        ? _drivers
        : _vendors;
    for (final party in list) {
      if (party.ownerId == settlement.ownerId) return party.name;
    }
    return '—';
  }

  Future<void> _settle(LedgerOwner ownerType, PartyBalance party) async {
    final l10n = context.l10n;
    // Pre-filled with the whole outstanding amount, which is what is being
    // handed over the overwhelming majority of the time.
    final outstanding = ownerType == LedgerOwner.driver
        ? party.cashDue
        : party.payable;
    _amountController.text = outstanding > 0
        ? outstanding.toStringAsFixed(2)
        : '';
    _referenceController.clear();
    var method = 'cash';
    PickedProof? proof;

    final done = await showFormDialog<bool>(
      context: context,
      title: l10n.recordSettlement,
      subtitle: party.name,
      icon: Icons.handshake_outlined,
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
            style: AppType.mono(18, weight: FontWeight.w800),
            decoration: InputDecoration(
              labelText: l10n.depositAmount,
              suffixText: l10n.egp,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
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
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _referenceController,
            decoration: InputDecoration(labelText: l10n.referenceOptional),
          ),
          const SizedBox(height: AppSpace.md),
          // Required: this is the record the store or driver sees of being
          // paid, and what support checks against in a dispute.
          ProofPhotoField(
            proof: proof,
            required: true,
            title: l10n.attachPaymentProof,
            hint: l10n.attachPaymentProofHint,
            onPick: () async {
              final picked = await pickProofPhoto(context);
              if (picked == null) return;
              proof = picked;
              rebuild();
            },
            onClear: () {
              proof = null;
              rebuild();
            },
          ),
        ],
      ),
      submitLabel: l10n.recordSettlement,
      cancelLabel: l10n.cancel,
      onSubmit: (_) async {
        final amount = double.tryParse(_amountController.text.trim());
        if (amount == null || amount <= 0) {
          throw UserMessage(l10n.amountRequired);
        }
        final picked = proof;
        if (picked == null) throw UserMessage(l10n.paymentProofRequired);
        final proofPath = await _repository.uploadSettlementProof(
          ownerType: ownerType,
          ownerId: party.ownerId,
          bytes: picked.bytes,
          fileName: picked.name,
        );
        await _repository.recordSettlement(
          proofPath: proofPath,
          ownerType: ownerType,
          ownerId: party.ownerId,
          amount: amount,
          method: method,
          reference: _referenceController.text.trim().isEmpty
              ? null
              : _referenceController.text.trim(),
          // A double-submitted dialog must not record the hand-over twice.
          idempotencyKey:
              'settle:${party.ownerId}:${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
        );
        return true;
      },
    );

    if (done == true && mounted) {
      showSnack(context, l10n.settlementRecorded);
      await _load();
    }
  }

  /// Approving only records that the money already moved — there is no
  /// payout API behind this button. Paymob here is collection-only (it takes
  /// a customer's card); sending a store or driver their money is always a
  /// manual transfer the admin makes outside the app, same as
  /// [_settle]/`admin_record_settlement`. This just marks that it happened.
  Future<void> _reviewRequest(Settlement request, bool approve) async {
    final l10n = context.l10n;
    if (approve) {
      PickedProof? proof;
      final approved = await showFormDialog<bool>(
        context: context,
        title: l10n.approve,
        subtitle:
            '${formatMoney(request.amount)} · ${_partyName(request)}'
            '\n\n${l10n.settlementApprovalExternalNotice}',
        icon: Icons.check_rounded,
        contentBuilder: (rebuild) => ProofPhotoField(
          proof: proof,
          required: true,
          title: l10n.attachPaymentProof,
          hint: l10n.attachPaymentProofHint,
          onPick: () async {
            final picked = await pickProofPhoto(context);
            if (picked == null) return;
            proof = picked;
            rebuild();
          },
          onClear: () {
            proof = null;
            rebuild();
          },
        ),
        submitLabel: l10n.approve,
        cancelLabel: l10n.cancel,
        onSubmit: (_) async {
          final picked = proof;
          if (picked == null) throw UserMessage(l10n.paymentProofRequired);
          final path = await _repository.uploadSettlementProof(
            ownerType: request.ownerType,
            ownerId: request.ownerId,
            bytes: picked.bytes,
            fileName: picked.name,
          );
          await _repository.reviewSettlementRequest(
            settlementId: request.id,
            approve: true,
          );
          await _repository.attachSettlementProof(request.id, path);
          return true;
        },
      );
      if (approved != true || !mounted) return;
      showSnack(context, l10n.settlementApproved);
      await _load();
      return;
    }
    final confirmed = await showConfirmDialog(
      context: context,
      title: approve ? l10n.approve : l10n.reject,
      message: approve
          ? '${formatMoney(request.amount)} · ${_partyName(request)}'
                '\n\n${l10n.settlementApprovalExternalNotice}'
          : '${formatMoney(request.amount)} · ${_partyName(request)}',
      confirmLabel: approve ? l10n.approve : l10n.reject,
      cancelLabel: l10n.cancel,
      tone: approve ? AppDialogTone.primary : AppDialogTone.danger,
      icon: approve ? Icons.check_rounded : Icons.close_rounded,
      onConfirm: () => _repository.reviewSettlementRequest(
        settlementId: request.id,
        approve: approve,
      ),
    );
    if (!confirmed || !mounted) return;
    showSnack(
      context,
      approve ? l10n.settlementApproved : l10n.settlementRejected,
    );
    await _load();
  }

  /// Everything about one party in a sheet: how the outstanding figure is
  /// made up, the action, and past settlements. Keeps the list itself to one
  /// line per party.
  Future<void> _showParty(LedgerOwner ownerType, PartyBalance party) async {
    final l10n = context.l10n;
    final isDriver = ownerType == LedgerOwner.driver;
    final outstanding = isDriver ? party.cashDue : party.payable;

    // Errors are shown by showBlockingProgress; the sheet still opens with
    // the balance breakdown, which needs no extra fetch.
    final history = party.totalSettlements > 0
        ? await showBlockingProgress(
                context,
                () => _repository.settlements(
                  ownerType: ownerType,
                  ownerId: party.ownerId,
                  limit: 50,
                ),
              ) ??
              const <Settlement>[]
        : const <Settlement>[];
    if (!mounted) return;

    await showAdaptiveSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              0,
              AppSpace.lg,
              AppSpace.xl,
            ),
            children: [
              Row(
                children: [
                  _PartyAvatar(isDriver: isDriver),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Text(
                      party.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.heading(18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              // Every figure is read straight off the RPC — nothing is
              // recomputed on screen, so this can never disagree with the
              // ledger.
              FinanceCard(
                children: [
                  FinanceRow(
                    label: l10n.totalEarned,
                    value: formatMoney(party.totalEarnings),
                  ),
                  if (isDriver)
                    FinanceRow(
                      label: l10n.cashCollectedLabel,
                      value: formatMoney(party.cashCollected),
                    ),
                  FinanceRow(
                    label: l10n.alreadySettled,
                    value: formatMoney(party.totalSettlements),
                  ),
                  FinanceRow(
                    label: isDriver ? l10n.driverHolds : l10n.owedToStore,
                    value: formatMoney(outstanding),
                    emphasis: true,
                    tone: outstanding > 0
                        ? (isDriver ? AppColors.amberInk : AppColors.primary)
                        : AppColors.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              FilledButton.icon(
                onPressed: outstanding <= 0
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        _settle(ownerType, party);
                      },
                icon: const Icon(Icons.handshake_outlined, size: 19),
                label: Text(l10n.recordSettlement),
              ),
              if (history.isNotEmpty)
                FinanceSection(
                  title: l10n.settlementHistory,
                  child: FinanceCard(
                    children: [
                      for (final settlement in history)
                        SettlementTile(
                          settlement: settlement,
                          partyName: party.name,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sets what an early payout costs, for stores and drivers alike.
  ///
  /// Both fields matter together, so they are edited together: the fee is
  /// `percent` of the payable but never less than `min`, which is what stops a
  /// 1.5% cut of EGP 40 from being worth less than the transfer that carries
  /// it. The preview line exists because those two rules interact — on small
  /// balances the floor is the fee, and the percent is doing nothing.
  Future<void> _editFee() async {
    final l10n = context.l10n;
    final current = _fee;
    if (current == null) return;

    _feePercentController.text = trimZeros(current.percent);
    _feeMinController.text = trimZeros(current.min);

    final saved = await showFormDialog<bool>(
      context: context,
      title: l10n.earlyPayoutFeeTitle,
      subtitle: l10n.earlyPayoutFeeScope,
      icon: Icons.bolt_rounded,
      contentBuilder: (rebuild) {
        final percent = double.tryParse(_feePercentController.text.trim());
        final min = double.tryParse(_feeMinController.text.trim());
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _feePercentController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => rebuild(),
              decoration: InputDecoration(
                labelText: l10n.feePercentLabel,
                suffixText: '%',
              ),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _feeMinController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => rebuild(),
              decoration: InputDecoration(labelText: l10n.feeMinLabel),
            ),
            if (percent != null && min != null && percent >= 0 && min >= 0) ...[
              const SizedBox(height: AppSpace.md),
              _FeePreview(percent: percent, min: min),
            ],
          ],
        );
      },
      submitLabel: l10n.save,
      cancelLabel: l10n.cancel,
      onSubmit: (_) async {
        final percent = double.tryParse(_feePercentController.text.trim());
        final min = double.tryParse(_feeMinController.text.trim());
        if (percent == null || percent < 0 || percent > 100) {
          throw UserMessage(l10n.invalidFeePercent);
        }
        if (min == null || min < 0) throw UserMessage(l10n.invalidFeeMin);
        final updated = await _repository.setEarlySettlementFee(
          percent: percent,
          min: min,
        );
        if (mounted) setState(() => _fee = updated);
        return true;
      },
    );

    if (saved == true && mounted) showSnack(context, l10n.feeUpdated);
  }

  Widget _feeStrip() {
    final l10n = context.l10n;
    final fee = _fee;
    if (fee == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.lg,
        0,
      ),
      child: _centered(
        FinanceCard(
          children: [
            FinanceRow(
              icon: Icons.bolt_rounded,
              tone: AppColors.amberInk,
              label: l10n.earlyPayoutFeeTitle,
              note: l10n.earlyPayoutFeeSummary(
                trimZeros(fee.percent),
                formatMoneyCompact(fee.min),
              ),
              value: '${trimZeros(fee.percent)}%',
              onTap: _editFee,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tabs = TabBar(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.textMuted,
      indicatorColor: AppColors.primary,
      tabs: [
        Tab(text: l10n.driversTab),
        Tab(text: l10n.storesLabel),
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  l10n.settlementRequestsTab,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              CountBadge(
                compact: true,
                count: AdminActionBadges.instance.countFor(
                  AdminActionBadges.settlementRequests,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final body = _loading
        ? const LoadingView()
        : _error != null
        ? ErrorView(message: _error!, onRetry: _load)
        : TabBarView(
            children: [
              _list(LedgerOwner.driver, _drivers),
              _list(LedgerOwner.vendor, _vendors),
              _requestsList(),
            ],
          );

    if (widget.embedded) {
      return DefaultTabController(
        length: 3,
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
        length: 3,
        child: WebPageChrome(
          forStaff: true,
          activeId: 'manage:/admin-app/settlements',
          sections: adminManageWebSections(context),
          pageTitle: l10n.settlementsTitle,
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
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(title: Text(l10n.settlementsTitle), bottom: tabs),
        body: body,
      ),
    );
  }

  Widget _requestsList() {
    // The fee sits above the queue it prices, not on a settings screen three
    // clicks away: this is where an operator sees what early payouts are
    // costing people and is therefore where they would think to change it.
    return Column(
      children: [
        _feeStrip(),
        Expanded(child: _requestsQueue()),
      ],
    );
  }

  Widget _requestsQueue() {
    final l10n = context.l10n;
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: _pending.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 100),
                EmptyView(
                  message: l10n.noSettlementRequests,
                  icon: Icons.inbox_outlined,
                ),
              ],
            )
          // A single column at every width, on request: a request queue is
          // read top to bottom in priority order (early payouts first — see
          // the sort in `_load`), which a multi-column grid breaks by
          // scattering that order across rows. Capped and centred on wide
          // windows so a 380px card is not stretched across a 1300px monitor.
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                AppSpace.gutter,
                AppSpace.md,
                AppSpace.gutter,
                AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: _pending.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
              itemBuilder: (context, i) => _centered(_requestCard(_pending[i])),
            ),
    );
  }

  /// Caps a list row at a readable card width and centres it, so a single
  /// column stays a column of cards rather than one card stretched full width
  /// on a wide console window.
  Widget _centered(Widget child) {
    if (!AppBreakpoints.isWebWide(context)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: child,
      ),
    );
  }

  Widget _requestCard(Settlement request) {
    final l10n = context.l10n;
    final isDriver = request.ownerType == LedgerOwner.driver;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: request.isEarly
              ? AppColors.amberInk.withValues(alpha: 0.35)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => showSettlementDetails(
              context,
              request,
              partyName: _partyName(request),
            ),
            child: Row(
              children: [
                _PartyAvatar(isDriver: isDriver),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _partyName(request),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.heading(15),
                      ),
                      Text(
                        [
                          isDriver ? l10n.driverLabel : l10n.storeLabel,
                          financeDayLabel(context, request.createdAt),
                        ].join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerEnd,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatMoney(request.amount),
                          style: AppType.mono(17, weight: FontWeight.w800),
                        ),
                        if (request.isEarly)
                          SoftBadge(
                            label: l10n.earlySettlementTag,
                            icon: Icons.bolt_rounded,
                            fill: AppColors.amberFill,
                            ink: AppColors.amberInk,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (request.isEarly) ...[
            const SizedBox(height: AppSpace.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md,
                vertical: AppSpace.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: settlementFeeBreakdown(context, request),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: AppColors.textFaint,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.settlementApprovalExternalNotice,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _reviewRequest(request, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dangerInk,
                    side: const BorderSide(color: AppColors.dangerInk),
                  ),
                  child: Text(l10n.reject),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () => _reviewRequest(request, true),
                  child: Text(l10n.approve),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _list(LedgerOwner ownerType, List<PartyBalance> allParties) {
    final l10n = context.l10n;
    final isDriver = ownerType == LedgerOwner.driver;
    double outstandingOf(PartyBalance p) => isDriver ? p.cashDue : p.payable;

    final query = (isDriver ? _driverQuery : _vendorQuery).trim().toLowerCase();
    final filtered = query.isEmpty
        ? allParties
        : allParties
              .where((p) => p.name.toLowerCase().contains(query))
              .toList();
    // Whoever is owed most, first — settling is the only reason to open this
    // tab.
    final parties = [...filtered]
      ..sort((a, b) => outstandingOf(b).compareTo(outstandingOf(a)));
    final open = allParties.where((p) => outstandingOf(p) > 0).toList();
    final total = open.fold<double>(0, (sum, p) => sum + outstandingOf(p));

    return RefreshIndicator(
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
        children: [
          _centered(
            FinanceHero(
              tone: isDriver ? FinanceHeroTone.warning : FinanceHeroTone.brand,
              eyebrow: isDriver
                  ? l10n.driverCashDueTotal
                  : l10n.vendorPayableTotal,
              amount: formatMoney(total),
              caption: l10n.partiesWithBalance(open.length),
            ),
          ),
          if (allParties.length > 5) ...[
            const SizedBox(height: AppSpace.md),
            _centered(
              TextField(
                onChanged: (v) => setState(
                  () => isDriver ? _driverQuery = v : _vendorQuery = v,
                ),
                decoration: InputDecoration(
                  hintText: l10n.searchByName,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          if (parties.isEmpty)
            _centered(
              FinanceEmpty(
                message: l10n.noReportData,
                icon: Icons.account_balance_wallet_outlined,
              ),
            )
          else
            // A single column at every width: whoever is owed most leads,
            // which a multi-column grid would scramble.
            _centered(
              FinanceCard(
                children: [
                  for (final party in parties)
                    _partyRow(ownerType, isDriver, party),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _partyRow(LedgerOwner ownerType, bool isDriver, PartyBalance party) {
    final l10n = context.l10n;
    final outstanding = isDriver ? party.cashDue : party.payable;
    final settled = outstanding <= 0;
    return InkWell(
      onTap: () => _showParty(ownerType, party),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.md,
        ),
        child: Row(
          children: [
            _PartyAvatar(isDriver: isDriver, muted: settled),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    party.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    settled
                        ? l10n.statusSettled
                        : (isDriver ? l10n.driverHolds : l10n.owedToStore),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  formatMoney(outstanding),
                  style: AppType.mono(
                    15,
                    weight: FontWeight.w800,
                    color: settled
                        ? AppColors.textFaint
                        : (isDriver ? AppColors.amberInk : AppColors.primary),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            // The action is one tap from the list — no need to open the
            // party first for the common case.
            if (!settled)
              IconButton.filledTonal(
                tooltip: l10n.recordSettlement,
                onPressed: () => _settle(ownerType, party),
                icon: const Icon(Icons.handshake_outlined, size: 19),
              )
            else
              const Padding(
                padding: EdgeInsets.all(AppSpace.sm),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textFaint,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PartyAvatar extends StatelessWidget {
  const _PartyAvatar({required this.isDriver, this.muted = false});

  final bool isDriver;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final tone = muted
        ? AppColors.textFaint
        : (isDriver ? AppColors.amberInk : AppColors.primary);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        isDriver ? Icons.two_wheeler_rounded : Icons.storefront_rounded,
        size: 20,
        color: tone,
      ),
    );
  }
}

/// What the entered fee schedule would actually cost, at three sizes.
///
/// The percent and the floor interact, and the interaction is the whole point
/// of having two fields: on a small balance the floor is the fee and the
/// percent is irrelevant, on a large one the reverse. Three worked examples
/// show where the crossover falls without the operator doing the arithmetic —
/// and show it before they save, not after a store complains.
class _FeePreview extends StatelessWidget {
  const _FeePreview({required this.percent, required this.min});

  final double percent;
  final double min;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.neutralFill,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final payable in const [500.0, 2000.0, 10000.0])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Builder(
                builder: (_) {
                  final q = EarlySettlementQuote.preview(
                    payable: payable,
                    percent: percent,
                    min: min,
                  );
                  return Text(
                    q.available
                        ? l10n.feePreview(
                            formatMoneyCompact(payable),
                            formatMoneyCompact(q.fee),
                            formatMoneyCompact(q.netPayout),
                          )
                        // Not an error: the floor simply exceeds the balance,
                        // so nobody with this little owed is offered the deal.
                        : '${formatMoneyCompact(payable)} — ${l10n.unavailable}',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: q.available
                          ? AppColors.textSecondary
                          : AppColors.textFaint,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
