import 'package:flutter/material.dart';
import 'package:multi_vendor/features/admin/admin_action_badges.dart';
import 'package:intl/intl.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../../app/tokens.dart';
import '../../../core/models/finance.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/repositories/finance_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/utils/settlement_format.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/finance_widgets.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import '../../../core/widgets/web/web_table.dart';
import '../../../core/widgets/web/adaptive_sheet.dart';
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

  /// Approving moves money on the driver's word alone — the transfer itself
  /// happens outside the app — so this is the one place that decision can be
  /// made, and it always shows whatever proof the driver attached first.
  /// There is no separate one-tap approve; every review opens here.
  Future<void> _review(DepositRequest request) async {
    final l10n = context.l10n;
    // Receipts live in a private bucket; the row holds its path.
    final proofUrl = await AdminRepository().signedDriverDocumentUrl(
      request.proofUrl,
    );
    if (!mounted) return;
    final reasonController = TextEditingController();

    Future<void> confirm(bool approve) async {
      final confirmed = await showConfirmDialog(
        context: context,
        title: approve ? l10n.approve : l10n.reject,
        message: approve
            ? '${formatMoney(request.amount)} · ${request.driverName ?? ''}'
            : (reasonController.text.trim().isEmpty
                  ? l10n.depositRejected
                  : reasonController.text.trim()),
        confirmLabel: approve ? l10n.approve : l10n.reject,
        cancelLabel: l10n.cancel,
        tone: approve ? AppDialogTone.primary : AppDialogTone.danger,
        icon: approve ? Icons.check_rounded : Icons.close_rounded,
        onConfirm: () => _repository.reviewDeposit(
          requestId: request.id,
          approve: approve,
          notes: approve ? null : reasonController.text.trim(),
        ),
      );
      if (!confirmed || !mounted) return;
      Navigator.of(context).pop(); // close the details sheet
      showSnack(context, approve ? l10n.depositApproved : l10n.depositRejected);
      await _load();
    }

    final webWide = AppBreakpoints.isWebWide(context);
    // Centered dialog on web: a phone-style sheet pinned to the bottom of a
    // desktop window hid most of the review below the fold.
    await showAdaptiveSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      maxWidth: 520,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpace.xl,
            webWide ? AppSpace.xl : 0,
            AppSpace.xl,
            AppSpace.xl + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      request.driverName ?? l10n.driverLabel,
                      style: AppType.heading(18),
                    ),
                  ),
                  Text(
                    formatMoney(request.amount),
                    style: AppType.mono(20, weight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                [
                  settlementMethodLabel(context, request.paymentMethod),
                  financeDayLabel(context, request.createdAt),
                ].join(' · '),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              Text(
                l10n.proofPhoto,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textFaint,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              if (proofUrl == null || proofUrl.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpace.lg),
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Text(
                    l10n.noProofAttached,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  child: GestureDetector(
                    onTap: () => showDialog<void>(
                      context: sheetContext,
                      builder: (_) => Dialog(
                        insetPadding: const EdgeInsets.all(AppSpace.lg),
                        child: InteractiveViewer(
                          child: AppNetworkImage(url: proofUrl),
                        ),
                      ),
                    ),
                    child: AppNetworkImage(
                      url: proofUrl,
                      height: 220,
                      width: double.infinity,
                    ),
                  ),
                ),
              if (request.reference != null &&
                  request.reference!.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                _detail(l10n.settlementReference, request.reference!),
              ],
              if (request.notes != null && request.notes!.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                _detail(l10n.settlementNotes, request.notes!),
              ],
              if (request.isPending) ...[
                const SizedBox(height: AppSpace.lg),
                TextField(
                  controller: reasonController,
                  decoration: InputDecoration(
                    labelText: l10n.rejectReasonOptional,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: AppSpace.lg),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => confirm(false),
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
                        onPressed: () => confirm(true),
                        child: Text(l10n.approve),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: AppSpace.lg),
                _StatusBadge(request: request),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppColors.textFaint,
        ),
      ),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(fontSize: 13, color: AppColors.ink)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final webWide = AppBreakpoints.isWebWide(context);

    final filter = FinanceSegments<bool>(
      values: const [true, false],
      selected: _pendingOnly,
      labelOf: (pendingOnly) {
        if (!pendingOnly) return l10n.all;
        final waiting = AdminActionBadges.instance
            .countFor(AdminActionBadges.depositsPending)
            .value;
        return waiting > 0 ? '${l10n.pending} ($waiting)' : l10n.pending;
      },
      onChanged: (value) {
        if (value == _pendingOnly) return;
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
        forStaff: true,
        activeId: 'manage:/admin-app/deposits',
        sections: adminManageWebSections(context),
        pageTitle: l10n.depositsAwaitingReview,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: filter,
              ),
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
                AppSpace.md,
                AppSpace.gutter,
                0,
              ),
              child: filter,
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _WebDepositsTable extends StatelessWidget {
  const _WebDepositsTable({required this.requests, required this.onReview});

  final List<DepositRequest> requests;
  final void Function(DepositRequest request) onReview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    // One list for header and rows, so every column has a label and the
    // body can never drift out of line with it.
    final columns = [
      WebTableColumn(label: l10n.driverLabel, flex: 3),
      WebTableColumn(label: l10n.settlementMethod, flex: 2),
      WebTableColumn(label: l10n.dateLabel, width: 130),
      WebTableColumn(label: l10n.amountValue, width: 130),
      WebTableColumn(label: l10n.statusLabel, width: 120),
    ];
    return SingleChildScrollView(
      child: WebTable(
        trailingWidth: 90,
        emptyState: EmptyView(
          message: l10n.noDepositsPending,
          icon: Icons.account_balance_outlined,
        ),
        columns: columns,
        rows: [
          for (final request in requests)
            WebTableRow.aligned(
              trailingWidth: 90,
              // A tap opens the review sheet — proof photo and notes first,
              // approve/reject inside it — rather than a one-tap approve on
              // the driver's word alone right here in the row.
              onTap: () => onReview(request),
              columns: columns,
              cells: [
                Text(
                  request.driverName ?? l10n.driversTab,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  settlementMethodLabel(context, request.paymentMethod),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  DateFormat.yMMMd(language).format(request.createdAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  formatMoney(request.amount),
                  maxLines: 1,
                  style: AppType.mono(14, weight: FontWeight.w800),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _StatusBadge(request: request),
                ),
              ],
              trailing: request.isPending
                  ? _MiniButton(
                      label: l10n.review,
                      tone: AppColors.primary,
                      filled: true,
                      onTap: () => onReview(request),
                    )
                  : const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textFaint,
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
  final void Function(DepositRequest request) onReview;

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
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: () => onReview(request),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(
              color: request.isPending
                  ? AppColors.attentionBorder
                  : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.amberInk.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.move_to_inbox_rounded,
                      size: 20,
                      color: AppColors.amberInk,
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.driverName ?? l10n.driverLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.heading(15),
                        ),
                        Text(
                          [
                            settlementMethodLabel(
                              context,
                              request.paymentMethod,
                            ),
                            financeDayLabel(context, request.createdAt),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                          if (!request.isPending)
                            _StatusBadge(request: request),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (request.reference != null &&
                  request.reference!.isNotEmpty) ...[
                const SizedBox(height: AppSpace.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                    vertical: AppSpace.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: Text(
                    '${l10n.settlementReference}: ${request.reference}',
                    style: AppType.mono(12, color: AppColors.textSecondary),
                  ),
                ),
              ],
              if (request.isPending) ...[
                const SizedBox(height: AppSpace.md),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    l10n.review,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Approved / rejected — the outcome, not the verb that produced it.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.request});

  final DepositRequest request;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (request.isPending) {
      return SoftBadge(
        label: l10n.statusPending,
        fill: AppColors.amberFill,
        ink: AppColors.amberInk,
      );
    }
    return SoftBadge(
      label: request.isApproved ? l10n.statusApproved : l10n.rejected,
      fill: request.isApproved ? AppColors.successFill : AppColors.dangerFill,
      ink: request.isApproved ? AppColors.successInk : AppColors.dangerInk,
    );
  }
}
