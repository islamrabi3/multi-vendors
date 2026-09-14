import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/models/customer_report.dart';
import '../../../core/repositories/report_repository.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/widgets/common.dart';
import 'complaint_thread_view.dart';

/// A complaint thread as its own page — the customer's follow-up screen, and
/// the admin's on a phone. `/complaints/:id` opens it from a notification.
class ComplaintThreadScreen extends StatefulWidget {
  const ComplaintThreadScreen({
    super.key,
    required this.reportId,
    this.asAdmin = false,
  });

  final String reportId;
  final bool asAdmin;

  @override
  State<ComplaintThreadScreen> createState() => _ComplaintThreadScreenState();
}

class _ComplaintThreadScreenState extends State<ComplaintThreadScreen> {
  final _repo = ReportRepository();
  late final Stream<CustomerReport?> _report = _repo.watchReport(
    widget.reportId,
  );

  Future<void> _toggle(CustomerReport report) async {
    try {
      await _repo.setStatus(
        report.id,
        report.isResolved ? 'pending' : 'resolved',
      );
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(l10n.complaintDetails),
        actions: [
          if (widget.asAdmin)
            StreamBuilder<CustomerReport?>(
              stream: _report,
              builder: (context, snap) {
                final report = snap.data;
                if (report == null) return const SizedBox.shrink();
                return ComplaintStatusToggle(
                  report: report,
                  onToggle: () => _toggle(report),
                );
              },
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ComplaintThreadView(
            reportId: widget.reportId,
            asAdmin: widget.asAdmin,
          ),
        ),
      ),
    );
  }
}
