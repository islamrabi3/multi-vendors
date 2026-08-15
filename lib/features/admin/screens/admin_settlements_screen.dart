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
import '../../../core/widgets/responsive_list.dart';
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

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  List<PartyBalance> _drivers = const [];
  List<PartyBalance> _vendors = const [];
  List<Settlement> _pending = const [];
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

    final done = await showFormDialog<bool>(
      context: context,
      title: '${l10n.recordSettlement} · ${party.name}',
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
            decoration: InputDecoration(labelText: l10n.depositAmount),
          ),
          const SizedBox(height: AppSpace.md),
          DropdownButtonFormField<String>(
            initialValue: method,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.depositMethod),
            items: [
              DropdownMenuItem(
                value: 'cash',
                child: Text(l10n.settlementMethodCash),
              ),
              DropdownMenuItem(
                value: 'bank_transfer',
                child: Text(l10n.settlementMethodBank),
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
            decoration: InputDecoration(labelText: l10n.referenceOptional),
          ),
        ],
      ),
      submitLabel: l10n.recordSettlement,
      cancelLabel: l10n.cancel,
      onSubmit: (_) async {
        final amount = double.tryParse(_amountController.text.trim());
        if (amount == null || amount <= 0) {
          throw Exception(l10n.amountRequired);
        }
        await _repository.recordSettlement(
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

  /// Every past hand-over behind [party]'s "total settlements" figure — each
  /// row opens onto [showSettlementDetails] for the full record.
  Future<void> _showHistory(LedgerOwner ownerType, PartyBalance party) async {
    final l10n = context.l10n;
    List<Settlement> history;
    try {
      history = await _repository.settlements(
        ownerType: ownerType,
        ownerId: party.ownerId,
        limit: 50,
      );
    } catch (error) {
      if (mounted) showFailure(context, error);
      return;
    }
    if (!mounted) return;

    await showAdaptiveSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xl,
            0,
            AppSpace.xl,
            AppSpace.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${l10n.settlementsTitle} · ${party.name}',
                style: AppType.heading(18),
              ),
              const SizedBox(height: AppSpace.md),
              if (history.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: EmptyView(
                    message: l10n.noTransactionsYet,
                    icon: Icons.receipt_long_outlined,
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: history.length,
                    itemBuilder: (_, i) =>
                        SettlementTile(settlement: history[i]),
                  ),
                ),
            ],
          ),
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
          text: _pending.isEmpty
              ? l10n.settlementRequestsTab
              : '${l10n.settlementRequestsTab} (${_pending.length})',
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
          : AppBreakpoints.isWebWide(context)
          ? ResponsiveCardList(
              // Natural heights for the same reason as the party grid: an
              // early-payout request carries a fee breakdown that an ordinary
              // one does not, so a single fixed height is wrong for one of
              // the two shapes whichever number is chosen.
              padding: const EdgeInsets.fromLTRB(
                AppSpace.gutter,
                AppSpace.md,
                AppSpace.gutter,
                AppSpace.xxl,
              ),
              itemExtent: 380,
              itemCount: _pending.length,
              itemBuilder: (context, i) => _requestCard(_pending[i]),
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                AppSpace.gutter,
                AppSpace.md,
                AppSpace.gutter,
                AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: _pending.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
              itemBuilder: (context, i) => _requestCard(_pending[i]),
            ),
    );
  }

  Widget _requestCard(Settlement request) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.attentionBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => showSettlementDetails(
              context,
              request,
              partyName: _partyName(request),
            ),
            child: Row(
              children: [
                Icon(
                  request.ownerType == LedgerOwner.driver
                      ? Icons.moped_outlined
                      : Icons.storefront_outlined,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    _partyName(request),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.heading(15),
                  ),
                ),
                const SizedBox(width: 8),
                if (request.isEarly) ...[
                  const Icon(
                    Icons.bolt_rounded,
                    size: 16,
                    color: AppColors.amberInk,
                  ),
                  const SizedBox(width: 2),
                ],
                Text(
                  formatMoney(request.amount),
                  style: AppType.mono(16, weight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.settlementApprovalExternalNotice,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textFaint,
              height: 1.3,
            ),
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
    final query = (isDriver ? _driverQuery : _vendorQuery).trim().toLowerCase();
    final filtered = query.isEmpty
        ? allParties
        : allParties
              .where((p) => p.name.toLowerCase().contains(query))
              .toList();
    // Whoever is owed most, first. Alphabetical order buried the one store
    // waiting on money behind a screen of parties already settled to zero —
    // and settling is the only reason to open this tab.
    final parties = [...filtered]
      ..sort((a, b) {
        final aOut = isDriver ? a.cashDue : a.payable;
        final bOut = isDriver ? b.cashDue : b.payable;
        return bOut.compareTo(aOut);
      });

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: Column(
        children: [
          if (allParties.length > 5)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.gutter,
                AppSpace.md,
                AppSpace.gutter,
                0,
              ),
              child: TextField(
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
          Expanded(
            child: parties.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 100),
                      EmptyView(
                        message: l10n.noReportData,
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                    ],
                  )
                : AppBreakpoints.isWebWide(context)
                ? ResponsiveCardList(
                    // Was a GridView with a hand-set `mainAxisExtent`, which
                    // meant every change to the card had to be paid for in
                    // pixels — and one already shipped as a 10px overflow
                    // because driver cards carry an extra breakdown row.
                    // ResponsiveCardList wraps to natural heights, so the
                    // card can grow without anyone recomputing a constant.
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.gutter,
                      AppSpace.md,
                      AppSpace.gutter,
                      AppSpace.xxl,
                    ),
                    itemExtent: 380,
                    itemCount: parties.length,
                    itemBuilder: (context, i) =>
                        _partyCard(ownerType, isDriver, parties[i]),
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      AppSpace.gutter,
                      AppSpace.md,
                      AppSpace.gutter,
                      AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
                    ),
                    itemCount: parties.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpace.sm),
                    itemBuilder: (context, i) =>
                        _partyCard(ownerType, isDriver, parties[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _partyCard(LedgerOwner ownerType, bool isDriver, PartyBalance party) {
    final l10n = context.l10n;
    final outstanding = isDriver ? party.cashDue : party.payable;
    final settled = outstanding <= 0;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            party.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.heading(14),
          ),
          const SizedBox(height: AppSpace.sm),
          // The outstanding amount is the question this screen answers, so it
          // leads the card instead of sitting at 16px beside the name. A
          // settled party keeps its place in the list but stops competing for
          // attention with the ones still owed money.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatMoney(outstanding),
                style: AppType.mono(
                  settled ? 20 : 26,
                  weight: FontWeight.w800,
                  color: settled
                      ? AppColors.textMuted
                      : (isDriver ? AppColors.amberInk : AppColors.successInk),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  settled
                      ? l10n.statusSettled
                      : (isDriver ? l10n.cashDue : l10n.owedToYou),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          // Every figure here is read straight off the RPC — nothing is
          // subtracted or recomputed on screen, so this can never disagree
          // with the ledger.
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: AppSpace.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Column(
              children: [
                _breakdownRow(
                  l10n.totalEarned,
                  formatMoney(party.totalEarnings),
                ),
                if (isDriver)
                  _breakdownRow(
                    l10n.cashCollectedLabel,
                    formatMoney(party.cashCollected),
                  ),
                _breakdownRow(
                  l10n.alreadySettled,
                  formatMoney(party.totalSettlements),
                ),
                const Divider(height: AppSpace.md, color: AppColors.borderSoft),
                _breakdownRow(
                  l10n.outstandingNow,
                  formatMoney(outstanding),
                  emphasis: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (party.totalSettlements > 0) ...[
                TextButton(
                  onPressed: () => _showHistory(ownerType, party),
                  child: Text(
                    l10n.settlementHistory,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
              ],
              FilledButton.tonal(
                // Nothing to settle is not an error, just nothing to do — so
                // the button rests rather than disappearing.
                onPressed: outstanding <= 0
                    ? null
                    : () => _settle(ownerType, party),
                child: Text(
                  l10n.recordSettlement,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _breakdownRow(String label, String value, {bool emphasis = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: emphasis ? 12.5 : 11.5,
                  fontWeight: emphasis ? FontWeight.w700 : FontWeight.w500,
                  color: emphasis ? AppColors.ink : AppColors.textSecondary,
                ),
              ),
            ),
            Text(
              value,
              style: AppType.mono(
                emphasis ? 13 : 11.5,
                weight: emphasis ? FontWeight.w800 : FontWeight.w600,
                color: emphasis ? AppColors.ink : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
}
