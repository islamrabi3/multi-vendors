import 'package:flutter/material.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../../app/tokens.dart';
import '../../../core/models/finance.dart';
import '../../../core/repositories/finance_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import '../../../core/widgets/web/web_table.dart';
import 'admin_manage_screen.dart' show adminManageWebSections;

/// Drivers claiming to have paid money in, and the decision on each.
///
/// Approving is the only thing that creates money here, which is why it is a
/// deliberate act with a confirmation rather than a swipe: the request is the
/// driver's word, and the transfer has to be checked against the bank before
/// anyone's balance moves.
class AdminDepositsScreen extends StatefulWidget {
  const AdminDepositsScreen({super.key, this.embedded = false});

  /// True when a web sidebar is already drawing the shell around this screen
  /// (`_AdminWebShell`) — skips this widget's own [WebPageChrome]/[Scaffold].
  final bool embedded;

  @override
  State<AdminDepositsScreen> createState() => _AdminDepositsScreenState();
}

class _AdminDepositsScreenState extends State<AdminDepositsScreen> {
  final _repository = FinanceRepository();

  List<DepositRequest> _requests = const [];
  bool _loading = true;
  bool _pendingOnly = true;
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
      final rows = await _repository.depositRequests(
        status: _pendingOnly ? 'pending' : null,
      );
      if (!mounted) return;
      setState(() {
        _requests = rows;
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

  Future<void> _review(DepositRequest request, bool approve) async {
    final l10n = context.l10n;
    final confirmed = await showConfirmDialog(
      context: context,
      title: approve ? l10n.approve : l10n.reject,
      message: approve
          ? '${formatMoney(request.amount)} · ${request.driverName ?? ''}'
          : l10n.depositRejected,
      confirmLabel: approve ? l10n.approve : l10n.reject,
      cancelLabel: l10n.cancel,
      tone: approve ? AppDialogTone.primary : AppDialogTone.danger,
      icon: approve ? Icons.check_rounded : Icons.close_rounded,
      onConfirm: () =>
          _repository.reviewDeposit(requestId: request.id, approve: approve),
    );
    if (!confirmed || !mounted) return;
    showSnack(context, approve ? l10n.depositApproved : l10n.depositRejected);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final webWide = AppBreakpoints.isWebWide(context);

    // A stock `FilterChip` here rendered as an unlabeled dark pill — its
    // selected-state text colour collided with this app's chip theme. A
    // small explicit toggle sidesteps that theme entirely instead of
    // fighting it, and reads more deliberately "designed" either way.
    final filter = _PendingToggle(
      selected: _pendingOnly,
      label: l10n.pending,
      onChanged: (value) {
        setState(() => _pendingOnly = value);
        _load();
      },
    );

    final body = _loading
        ? const LoadingView()
        : _error != null
        ? ErrorView(message: _error!, onRetry: _load)
        : webWide
        ? _WebDepositsTable(requests: _requests, onReview: _review)
        : _MobileList(requests: _requests, onReview: _review);

    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            filter,
            const SizedBox(height: AppSpace.lg),
            Expanded(child: body),
          ],
        ),
      );
    }

    if (webWide) {
      return WebPageChrome(
        activeId: 'manage:/admin-app/deposits',
        sections: adminManageWebSections(context),
        pageTitle: l10n.depositsAwaitingReview,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              filter,
              const SizedBox(height: AppSpace.lg),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.depositsAwaitingReview)),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.gutter,
                AppSpace.sm,
                AppSpace.gutter,
                0,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: filter,
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _PendingToggle extends StatelessWidget {
  const _PendingToggle({
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final bool selected;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.ink : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        onTap: () => onChanged(!selected),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
              color: selected ? AppColors.ink : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded, size: 15, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebDepositsTable extends StatelessWidget {
  const _WebDepositsTable({required this.requests, required this.onReview});

  final List<DepositRequest> requests;
  final void Function(DepositRequest request, bool approve) onReview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      child: WebTable(
        trailingWidth: 190,
        emptyState: EmptyView(
          message: l10n.noDepositsPending,
          icon: Icons.account_balance_outlined,
        ),
        columns: [
          WebTableColumn(label: l10n.driversTab, flex: 3),
          WebTableColumn(label: l10n.depositMethod, flex: 2),
          WebTableColumn(label: l10n.dateLabel, width: 90),
          const WebTableColumn(label: '', width: 110),
        ],
        rows: [
          for (final request in requests)
            WebTableRow.aligned(
              trailingWidth: 190,
              columns: [
                WebTableColumn(label: '', flex: 3),
                WebTableColumn(label: '', flex: 2),
                const WebTableColumn(label: '', width: 90),
                const WebTableColumn(label: '', width: 110),
              ],
              cells: [
                Text(
                  request.driverName ?? l10n.driversTab,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  request.paymentMethod == 'cash'
                      ? l10n.settlementMethodCash
                      : l10n.settlementMethodBank,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  '${request.createdAt.day}/${request.createdAt.month}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  formatMoney(request.amount),
                  textAlign: TextAlign.right,
                  style: AppType.mono(14, weight: FontWeight.w800),
                ),
              ],
              trailing: request.isPending
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MiniButton(
                          label: l10n.reject,
                          tone: AppColors.dangerInk,
                          onTap: () => onReview(request, false),
                        ),
                        const SizedBox(width: 6),
                        _MiniButton(
                          label: l10n.approve,
                          tone: AppColors.primary,
                          filled: true,
                          onTap: () => onReview(request, true),
                        ),
                      ],
                    )
                  : SoftBadge(
                      label: request.isApproved ? l10n.approve : l10n.reject,
                      fill: request.isApproved
                          ? AppColors.successFill
                          : AppColors.dangerFill,
                      ink: request.isApproved
                          ? AppColors.successInk
                          : AppColors.dangerInk,
                    ),
            ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.label,
    required this.tone,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final Color tone;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? tone : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: filled ? null : Border.all(color: tone),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: filled ? Colors.white : tone,
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileList extends StatelessWidget {
  const _MobileList({required this.requests, required this.onReview});

  final List<DepositRequest> requests;
  final void Function(DepositRequest request, bool approve) onReview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (requests.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 100),
          EmptyView(
            message: l10n.noDepositsPending,
            icon: Icons.account_balance_outlined,
          ),
        ],
      );
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.md,
        AppSpace.gutter,
        AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: requests.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
      itemBuilder: (context, i) => _card(context, requests[i]),
    );
  }

  Widget _card(BuildContext context, DepositRequest request) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: request.isPending
              ? AppColors.attentionBorder
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.moped_outlined,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  request.driverName ?? l10n.driversTab,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.heading(15),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatMoney(request.amount),
                style: AppType.mono(16, weight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              request.paymentMethod == 'cash'
                  ? l10n.settlementMethodCash
                  : l10n.settlementMethodBank,
              if (request.reference != null && request.reference!.isNotEmpty)
                request.reference!,
              '${request.createdAt.day}/${request.createdAt.month}',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
          if (!request.isPending) ...[
            const SizedBox(height: AppSpace.sm),
            SoftBadge(
              label: request.isApproved ? l10n.approve : l10n.reject,
              fill: request.isApproved
                  ? AppColors.successFill
                  : AppColors.dangerFill,
              ink: request.isApproved
                  ? AppColors.successInk
                  : AppColors.dangerInk,
            ),
          ],
          if (request.isPending) ...[
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onReview(request, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.dangerInk,
                      side: const BorderSide(color: AppColors.dangerInk),
                    ),
                    child: Text(
                      l10n.reject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: FilledButton(
                    onPressed: () => onReview(request, true),
                    child: Text(
                      l10n.approve,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
