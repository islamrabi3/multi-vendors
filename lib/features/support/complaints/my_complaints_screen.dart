import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/models/customer_report.dart';
import '../../../core/repositories/report_repository.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/common.dart';
import 'complaint_thread_view.dart' show ComplaintStatusBadge;

/// The customer's complaints, each opening its follow-up thread.
class MyComplaintsScreen extends StatefulWidget {
  const MyComplaintsScreen({super.key});

  @override
  State<MyComplaintsScreen> createState() => _MyComplaintsScreenState();
}

class _MyComplaintsScreenState extends State<MyComplaintsScreen> {
  final _repo = ReportRepository();
  late Future<List<CustomerReport>> _future = _repo.fetchMyReports();
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    // A reply or a resolve lands while the list is open.
    _changes = _repo.watchAll().listen((_) => _reload());
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _reload() {
    final future = _repo.fetchMyReports();
    if (mounted) {
      setState(() {
        _future = future;
      });
    }
    return future;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.myComplaints)),
      body: FutureBuilder<List<CustomerReport>>(
        future: _future,
        builder: (context, snap) {
          final reports = snap.data;
          if (reports == null) {
            if (snap.hasError) {
              return FailureView(error: snap.error!, onRetry: _reload);
            }
            return const LoadingView();
          }
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _reload,
            child: reports.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 120),
                      EmptyView(
                        message: l10n.myComplaintsEmpty,
                        icon: Icons.report_problem_outlined,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.xl * 2,
                          vertical: AppSpace.md,
                        ),
                        child: Text(
                          l10n.myComplaintsEmptyHint,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(AppSpace.gutter),
                        itemCount: reports.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpace.sm),
                        itemBuilder: (context, i) => ComplaintTile(
                          report: reports[i],
                          onTap: () async {
                            await context.push('/complaints/${reports[i].id}');
                            _reload();
                          },
                        ),
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }
}

/// One complaint in a list: subject, what it is about, status, last activity.
/// Shared by the customer list and the admin queue.
class ComplaintTile extends StatelessWidget {
  const ComplaintTile({
    super.key,
    required this.report,
    required this.onTap,
    this.forAdmin = false,
    this.selected = false,
  });

  final CustomerReport report;
  final VoidCallback onTap;
  final bool forAdmin;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final highlight = forAdmin ? report.awaitsSupport : report.hasUnreadReply;
    final refs = [
      if (forAdmin && (report.customerName?.trim().isNotEmpty ?? false))
        report.customerName!,
      if (report.orderNumber != null) l10n.orderRef(report.orderNumber!),
      if (report.vendorName != null) report.vendorName!,
    ].join(' · ');

    return Material(
      color: selected ? AppColors.warmFill : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.35)
                  : AppColors.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: report.isResolved
                      ? AppColors.successFill
                      : AppColors.amberFill,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Icon(
                  report.isResolved
                      ? Icons.task_alt_rounded
                      : Icons.report_problem_rounded,
                  size: 20,
                  color: report.isResolved
                      ? AppColors.successInk
                      : AppColors.amberInk,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            report.subject.isEmpty
                                ? l10n.complaintFallback
                                : report.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: highlight
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        if (highlight)
                          Container(
                            width: 9,
                            height: 9,
                            margin: const EdgeInsetsDirectional.only(start: 6),
                            decoration: const BoxDecoration(
                              color: AppColors.dangerInk,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (refs.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        refs,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpace.sm),
                    Row(
                      children: [
                        ComplaintStatusBadge(
                          report: report,
                          forAdmin: forAdmin,
                        ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            formatDateTime(context, report.lastActivity),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textFaint,
                            ),
                          ),
                        ),
                      ],
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
}
