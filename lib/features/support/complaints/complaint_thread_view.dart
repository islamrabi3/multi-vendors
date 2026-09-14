import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/models/customer_report.dart';
import '../../../core/repositories/report_repository.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart' show ButtonSpinner;

/// One complaint and its follow-up conversation.
///
/// The customer and the admin see the same thread; [asAdmin] only decides
/// which side "mine" is and whether resolve/reopen are offered. The original
/// complaint sits at the top as a card, then the replies, then the composer.
class ComplaintThreadView extends StatefulWidget {
  const ComplaintThreadView({
    super.key,
    required this.reportId,
    this.asAdmin = false,
    this.onChanged,
    this.showHeaderActions = false,
  });

  final String reportId;
  final bool asAdmin;

  /// Called after this side changed the complaint (sent, resolved, reopened),
  /// so a list beside or behind the thread can refresh.
  final VoidCallback? onChanged;

  /// Draws a slim bar with the resolve/reopen action — for the web split
  /// view, which has no AppBar to put it in.
  final bool showHeaderActions;

  @override
  State<ComplaintThreadView> createState() => _ComplaintThreadViewState();
}

class _ComplaintThreadViewState extends State<ComplaintThreadView> {
  final _repo = ReportRepository();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final Stream<CustomerReport?> _report = _repo.watchReport(
    widget.reportId,
  );
  late final Stream<List<ReportMessage>> _messages = _repo.messagesStream(
    widget.reportId,
  );

  bool _sending = false;
  String? _lastSeenMessageId;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.asAdmin) _markRead();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _markRead() => _repo.markRead(widget.reportId).catchError((_) {});

  Future<void> _send({bool resolve = false}) async {
    final text = _input.text.trim();
    if (_sending || (text.isEmpty && !resolve)) return;
    setState(() => _sending = true);
    try {
      await _repo.sendMessage(
        reportId: widget.reportId,
        message: text,
        resolve: resolve,
      );
      _input.clear();
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleResolved(CustomerReport report) async {
    try {
      await _repo.setStatus(
        report.id,
        report.isResolved ? 'pending' : 'resolved',
      );
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  void _scrollToEnd(int count) {
    if (count == _lastCount) return;
    _lastCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CustomerReport?>(
      stream: _report,
      builder: (context, reportSnap) {
        if (reportSnap.hasError && !reportSnap.hasData) {
          return FailureView(error: reportSnap.error!);
        }
        if (reportSnap.connectionState == ConnectionState.waiting) {
          return const LoadingView();
        }
        final report = reportSnap.data;
        if (report == null) {
          return EmptyView(
            message: context.l10n.complaintNotFound,
            icon: Icons.report_problem_outlined,
          );
        }
        return Column(
          children: [
            if (widget.showHeaderActions && widget.asAdmin)
              ComplaintAdminBar(
                report: report,
                onToggle: () => _toggleResolved(report),
              ),
            Expanded(child: _thread(context, report)),
            _Composer(
              controller: _input,
              sending: _sending,
              asAdmin: widget.asAdmin,
              resolved: report.isResolved,
              onSend: () => _send(),
              onSendAndResolve: () => _send(resolve: true),
            ),
          ],
        );
      },
    );
  }

  Widget _thread(BuildContext context, CustomerReport report) {
    final l10n = context.l10n;
    return StreamBuilder<List<ReportMessage>>(
      stream: _messages,
      builder: (context, snap) {
        final messages = snap.data ?? const <ReportMessage>[];
        if (messages.isNotEmpty) {
          _scrollToEnd(messages.length);
          final last = messages.last;
          // A reply arriving while the customer has the thread open is read.
          if (!widget.asAdmin &&
              last.isFromAdmin &&
              last.id != _lastSeenMessageId) {
            _lastSeenMessageId = last.id;
            _markRead();
          }
        }
        final otherName = widget.asAdmin
            ? (report.customerName?.trim().isNotEmpty ?? false)
                  ? report.customerName!
                  : l10n.customer
            : l10n.complaintSupportTeam;

        return ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.md,
          ),
          children: [
            ComplaintSummaryCard(report: report, asAdmin: widget.asAdmin),
            const SizedBox(height: AppSpace.lg),
            if (snap.connectionState == ConnectionState.waiting &&
                messages.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpace.xl),
                child: LoadingView(),
              )
            else if (messages.isEmpty)
              _ThreadHint(
                icon: Icons.forum_outlined,
                text: widget.asAdmin
                    ? l10n.complaintThreadEmptyAdmin
                    : l10n.complaintThreadEmpty,
              ),
            for (var i = 0; i < messages.length; i++)
              _Bubble(
                message: messages[i],
                mine: messages[i].isFromAdmin == widget.asAdmin,
                senderLabel: messages[i].isFromAdmin == widget.asAdmin
                    ? null
                    : otherName,
                // One name per run of messages from the same side.
                showSender:
                    i == 0 ||
                    messages[i - 1].isFromAdmin != messages[i].isFromAdmin,
              ),
            if (report.isResolved) ...[
              const SizedBox(height: AppSpace.sm),
              _ThreadHint(
                icon: Icons.check_circle_rounded,
                tone: _HintTone.success,
                text: widget.asAdmin
                    ? l10n.complaintResolvedNoticeAdmin
                    : l10n.complaintResolvedNotice,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Resolve / reopen, with the customer's name, above an embedded thread.
class ComplaintAdminBar extends StatelessWidget {
  const ComplaintAdminBar({
    super.key,
    required this.report,
    required this.onToggle,
  });

  final CustomerReport report;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.sm,
        AppSpace.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.person_outline_rounded,
            size: 18,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              (report.customerName?.trim().isNotEmpty ?? false)
                  ? report.customerName!
                  : l10n.customer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.heading(15),
            ),
          ),
          ComplaintStatusToggle(report: report, onToggle: onToggle),
        ],
      ),
    );
  }
}

/// "Mark resolved" on an open complaint, "Reopen" on a closed one.
class ComplaintStatusToggle extends StatelessWidget {
  const ComplaintStatusToggle({
    super.key,
    required this.report,
    required this.onToggle,
  });

  final CustomerReport report;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextButton.icon(
      onPressed: onToggle,
      icon: Icon(
        report.isResolved ? Icons.replay_rounded : Icons.check_circle_outline,
        size: 18,
      ),
      label: Text(report.isResolved ? l10n.reopen : l10n.markResolved),
      style: TextButton.styleFrom(
        foregroundColor: report.isResolved
            ? AppColors.textSecondary
            : AppColors.successInk,
      ),
    );
  }
}

/// The complaint as filed: status, what it is about, and the description.
class ComplaintSummaryCard extends StatelessWidget {
  const ComplaintSummaryCard({
    super.key,
    required this.report,
    this.asAdmin = false,
  });

  final CustomerReport report;
  final bool asAdmin;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final refs = [
      if (report.orderNumber != null) l10n.orderRef(report.orderNumber!),
      if (report.vendorName != null) report.vendorName!,
    ];
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.dangerFill,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: const Icon(
                  Icons.report_problem_rounded,
                  size: 20,
                  color: AppColors.dangerInk,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.subject.isEmpty
                          ? l10n.complaintFallback
                          : report.subject,
                      style: AppType.heading(16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.complaintFiledAt(
                        formatDateTime(context, report.createdAt),
                      ),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              ComplaintStatusBadge(report: report),
            ],
          ),
          if (refs.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final ref in refs)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(color: AppColors.borderSoft),
                    ),
                    child: Text(
                      ref,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpace.md),
          const Divider(height: 1, color: AppColors.borderSoft),
          const SizedBox(height: AppSpace.md),
          Text(
            asAdmin ? l10n.complaintCustomerWrote : l10n.complaintYouWrote,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            report.description,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Status in one badge. An open complaint says whose turn it is.
class ComplaintStatusBadge extends StatelessWidget {
  const ComplaintStatusBadge({
    super.key,
    required this.report,
    this.forAdmin = false,
  });

  final CustomerReport report;
  final bool forAdmin;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (label, fill, ink) = report.isResolved
        ? (l10n.resolvedLabel, AppColors.successFill, AppColors.successInk)
        : forAdmin && report.awaitsSupport && report.lastMessageAt != null
        ? (
            l10n.complaintCustomerReplied,
            AppColors.dangerFill,
            AppColors.dangerInk,
          )
        : !forAdmin && report.lastMessageFromAdmin
        ? (l10n.complaintSupportReplied, AppColors.warmFill, AppColors.primary)
        : (l10n.complaintInReview, AppColors.amberFill, AppColors.amberInk);
    return SoftBadge(label: label, fill: fill, ink: ink);
  }
}

enum _HintTone { neutral, success }

class _ThreadHint extends StatelessWidget {
  const _ThreadHint({
    required this.icon,
    required this.text,
    this.tone = _HintTone.neutral,
  });

  final IconData icon;
  final String text;
  final _HintTone tone;

  @override
  Widget build(BuildContext context) {
    final success = tone == _HintTone.success;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.md - 2,
      ),
      decoration: BoxDecoration(
        color: success ? AppColors.successFill : AppColors.neutralFill,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: success ? AppColors.successInk : AppColors.textMuted,
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: success ? AppColors.successInk : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.senderLabel,
    required this.showSender,
  });

  final ReportMessage message;
  final bool mine;
  final String? senderLabel;
  final bool showSender;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final at = message.createdAt;
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    final time = sameDay
        ? formatClock(context, at)
        : formatDateTime(context, at);
    final maxWidth = (MediaQuery.sizeOf(context).width * 0.75).clamp(
      200.0,
      520.0,
    );

    return Align(
      alignment: mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (showSender && senderLabel != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 6, bottom: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.support_agent_rounded,
                    size: 13,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    senderLabel!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            margin: const EdgeInsets.only(bottom: AppSpace.sm),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.lg,
              vertical: AppSpace.md - 2,
            ),
            constraints: BoxConstraints(maxWidth: maxWidth),
            decoration: BoxDecoration(
              color: mine ? AppColors.primary : AppColors.surface,
              border: Border.all(
                color: mine ? AppColors.primary : AppColors.border,
              ),
              borderRadius: BorderRadiusDirectional.only(
                topStart: const Radius.circular(AppRadii.lg),
                topEnd: const Radius.circular(AppRadii.lg),
                bottomStart: Radius.circular(mine ? AppRadii.lg : AppRadii.xs),
                bottomEnd: Radius.circular(mine ? AppRadii.xs : AppRadii.lg),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.message,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: mine ? Colors.white : AppColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 10,
                    color: mine
                        ? Colors.white.withValues(alpha: 0.75)
                        : AppColors.textFaint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.asAdmin,
    required this.resolved,
    required this.onSend,
    required this.onSendAndResolve,
  });

  final TextEditingController controller;
  final bool sending;
  final bool asAdmin;
  final bool resolved;
  final VoidCallback onSend;
  final VoidCallback onSendAndResolve;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.md,
            AppSpace.sm,
            AppSpace.md,
            AppSpace.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: asAdmin
                        ? l10n.complaintReplyHint
                        : resolved
                        ? l10n.complaintReplyReopens
                        : l10n.complaintAddDetails,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.xl),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg,
                      vertical: AppSpace.md,
                    ),
                  ),
                ),
              ),
              if (asAdmin && !resolved) ...[
                const SizedBox(width: AppSpace.sm),
                SizedBox(
                  width: 46,
                  height: 46,
                  child: Tooltip(
                    message: l10n.sendAndResolve,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                        foregroundColor: AppColors.successInk,
                        side: const BorderSide(color: AppColors.successInk),
                      ),
                      onPressed: sending ? null : onSendAndResolve,
                      child: const Icon(Icons.done_all_rounded, size: 20),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: AppSpace.sm),
              SizedBox(
                width: 46,
                height: 46,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: const CircleBorder(),
                  ),
                  onPressed: sending ? null : onSend,
                  child: sending
                      ? const ButtonSpinner(size: 16)
                      : const Directionality(
                          textDirection: TextDirection.ltr,
                          child: Icon(Icons.send_rounded, size: 19),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
