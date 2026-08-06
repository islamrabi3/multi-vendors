import 'package:flutter/material.dart';
import '../../../app/tokens.dart';
import '../../../core/repositories/report_repository.dart';
import '../../../core/widgets/common.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class AdminComplaintsScreen extends StatefulWidget {
  const AdminComplaintsScreen({super.key});

  @override
  State<AdminComplaintsScreen> createState() => _AdminComplaintsScreenState();
}

class _AdminComplaintsScreenState extends State<AdminComplaintsScreen> {
  final _repo = ReportRepository();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _reports = const [];
  String _filterStatus = 'all'; // 'all', 'pending', 'resolved'

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
      final list = await _repo.fetchReports(status: _filterStatus);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _reports = list;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _resolveReport(Map<String, dynamic> report) async {
    final controller = TextEditingController();
    final reply = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.resolveComplaint),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.subjectLine(
                (report['subject'] as String?) ??
                    context.l10n.complaintFallback,
              ),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              report['description'] ?? '',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: context.l10n.complaintReplyHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(context.l10n.sendAndResolve),
          ),
        ],
      ),
    );

    if (reply == null || reply.isEmpty) return;

    try {
      await _repo.resolveReport(
        reportId: report['id'] as String,
        userId: report['user_id'] as String,
        replyMessage: reply,
      );
      if (!mounted) return;
      showSnack(context, 'Complaint resolved and customer notified! 💬');
      await _load();
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(context.l10n.customerReports),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Status filter chips
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.gutter,
                vertical: AppSpace.sm,
              ),
              child: Row(
                children: [
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'all',
                        label: Text(context.l10n.all),
                      ),
                      ButtonSegment(
                        value: 'pending',
                        label: Text(context.l10n.pendingLabel),
                      ),
                      ButtonSegment(
                        value: 'resolved',
                        label: Text(context.l10n.resolvedLabel),
                      ),
                    ],
                    selected: {_filterStatus},
                    onSelectionChanged: (set) {
                      setState(() => _filterStatus = set.first);
                      _load();
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? ErrorView(message: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _reports.isEmpty
                          ? ListView(
                              children: [
                                const SizedBox(height: 80),
                                EmptyView(
                                  message: context.l10n.noComplaints,
                                  icon: Icons.report_problem_outlined,
                                ),
                              ],
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(AppSpace.gutter),
                              itemCount: _reports.length,
                              itemBuilder: (context, index) {
                                final report = _reports[index];
                                final isResolved =
                                    report['status'] == 'resolved';
                                final vendorName =
                                    (report['vendors'] as Map?)?['name'];

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                report['subject'] ??
                                                    'Customer Complaint',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isResolved
                                                    ? AppColors.successFill
                                                    : AppColors.amberFill,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                (report['status'] ?? 'pending')
                                                    .toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: isResolved
                                                      ? AppColors.successInk
                                                      : AppColors.amberInk,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (vendorName != null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'Store: $vendorName',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                        Text(
                                          report['description'] ?? '',
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            height: 1.4,
                                          ),
                                        ),
                                        if (isResolved &&
                                            report['admin_reply'] != null) ...[
                                          const SizedBox(height: 12),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'Resolution Reply:\n${report['admin_reply']}',
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 12),
                                        if (!isResolved)
                                          SizedBox(
                                            width: double.infinity,
                                            child: OutlinedButton.icon(
                                              onPressed: () =>
                                                  _resolveReport(report),
                                              icon: const Icon(
                                                Icons.check_circle_outline,
                                                size: 18,
                                              ),
                                              label: const Text(
                                                'Reply & Resolve',
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
