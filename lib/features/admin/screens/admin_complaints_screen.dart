import 'package:flutter/material.dart';
import '../../../app/tokens.dart';
import '../../../core/repositories/report_repository.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';
import 'admin_manage_screen.dart' show adminManageWebSections;

class AdminComplaintsScreen extends StatefulWidget {
  const AdminComplaintsScreen({super.key, this.embedded = false});

  /// True when a web sidebar is already drawing the shell around this screen
  /// (`_AdminWebShell`) — skips this widget's own [WebPageChrome]/[Scaffold]
  /// and returns just the filter bar + split view.
  final bool embedded;

  @override
  State<AdminComplaintsScreen> createState() => _AdminComplaintsScreenState();
}

class _AdminComplaintsScreenState extends State<AdminComplaintsScreen> {
  final _repo = ReportRepository();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _reports = const [];
  String _filterStatus = 'all'; // 'all', 'pending', 'resolved'

  /// Selected complaint for the web split view. Mobile never sets this — it
  /// resolves inline via a dialog instead, same as before this screen grew a
  /// desktop layout.
  String? _selectedId;

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
        if (_selectedId != null && !list.any((r) => r['id'] == _selectedId)) {
          _selectedId = null;
        }
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
      showSnack(context, context.l10n.complaintResolvedAndNotified);
      await _load();
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  /// Resolves inline from the web detail pane — same repository call as the
  /// mobile dialog, just with the reply box already on screen instead of
  /// popped over it.
  Future<void> _resolveInline(Map<String, dynamic> report, String reply) async {
    if (reply.trim().isEmpty) return;
    try {
      await _repo.resolveReport(
        reportId: report['id'] as String,
        userId: report['user_id'] as String,
        replyMessage: reply.trim(),
      );
      if (!mounted) return;
      showSnack(context, context.l10n.complaintResolvedAndNotified);
      await _load();
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final webWide = AppBreakpoints.isWebWide(context);

    final filterBar = SegmentedButton<String>(
      segments: [
        ButtonSegment(value: 'all', label: Text(l10n.all)),
        ButtonSegment(value: 'pending', label: Text(l10n.pendingLabel)),
        ButtonSegment(value: 'resolved', label: Text(l10n.resolvedLabel)),
      ],
      selected: {_filterStatus},
      onSelectionChanged: (set) {
        setState(() => _filterStatus = set.first);
        _load();
      },
    );

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? ErrorView(message: _error!, onRetry: _load)
        : webWide
        ? _WebSplitView(
            reports: _reports,
            selectedId: _selectedId,
            onSelect: (id) => setState(() => _selectedId = id),
            onResolve: _resolveInline,
            onRefresh: _load,
          )
        : _MobileList(
            reports: _reports,
            onResolve: _resolveReport,
            onRefresh: _load,
          );

    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            filterBar,
            const SizedBox(height: AppSpace.lg),
            Expanded(child: body),
          ],
        ),
      );
    }

    if (webWide) {
      return WebPageChrome(
        forStaff: true,
        activeId: 'manage:/admin-app/complaints',
        sections: adminManageWebSections(context),
        pageTitle: l10n.customerReports,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              filterBar,
              const SizedBox(height: AppSpace.lg),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(l10n.customerReports),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.gutter,
                vertical: AppSpace.sm,
              ),
              child: Row(children: [filterBar]),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// Mobile/narrow: the original vertical stack of full cards, resolve via a
/// dialog. Unchanged behaviour from before this screen grew a web layout.
class _MobileList extends StatelessWidget {
  const _MobileList({
    required this.reports,
    required this.onResolve,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> reports;
  final ValueChanged<Map<String, dynamic>> onResolve;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: reports.isEmpty
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
              itemCount: reports.length,
              itemBuilder: (context, index) {
                final report = reports[index];
                final isResolved = report['status'] == 'resolved';
                final vendorName = (report['vendors'] as Map?)?['name'];

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                report['subject'] ??
                                    context.l10n.complaintFallback,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            _StatusPill(isResolved: isResolved),
                          ],
                        ),
                        if (vendorName != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${context.l10n.storeLabel}: $vendorName',
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
                          style: const TextStyle(fontSize: 13.5, height: 1.4),
                        ),
                        if (isResolved && report['admin_reply'] != null) ...[
                          const SizedBox(height: 12),
                          _ReplyBlock(reply: report['admin_reply'] as String),
                        ],
                        const SizedBox(height: 12),
                        if (!isResolved)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => onResolve(report),
                              icon: const Icon(
                                Icons.check_circle_outline,
                                size: 18,
                              ),
                              label: Text(context.l10n.replyAndResolve),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Web/wide: a list (subject, store, status) beside a reading pane — the
/// same list+detail shape [admin_dashboard_screen.dart] already uses for
/// live orders, since a complaint is free-text content that doesn't fit a
/// spreadsheet row any better than an order does.
class _WebSplitView extends StatelessWidget {
  const _WebSplitView({
    required this.reports,
    required this.selectedId,
    required this.onSelect,
    required this.onResolve,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> reports;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final void Function(Map<String, dynamic> report, String reply) onResolve;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return Center(
        child: EmptyView(
          message: context.l10n.noComplaints,
          icon: Icons.report_problem_outlined,
        ),
      );
    }

    final selected = reports.cast<Map<String, dynamic>?>().firstWhere(
      (r) => r?['id'] == selectedId,
      orElse: () => null,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 4,
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: onRefresh,
            child: ListView.separated(
              itemCount: reports.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
              itemBuilder: (context, i) {
                final report = reports[i];
                final isResolved = report['status'] == 'resolved';
                final vendorName = (report['vendors'] as Map?)?['name'];
                final isSelected = report['id'] == selectedId;
                return Material(
                  color: isSelected ? AppColors.warmFill : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    onTap: () => onSelect(report['id'] as String),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpace.md),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: 0.3)
                              : AppColors.border,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  report['subject'] ??
                                      context.l10n.complaintFallback,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              _StatusPill(isResolved: isResolved),
                            ],
                          ),
                          if (vendorName != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              vendorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: AppSpace.lg),
        Expanded(
          flex: 5,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppRadii.xl),
            ),
            clipBehavior: Clip.antiAlias,
            child: selected == null
                ? Center(
                    child: EmptyView(
                      message: context.l10n.complaintFallback,
                      icon: Icons.report_problem_outlined,
                    ),
                  )
                : _ComplaintDetail(
                    key: ValueKey(selected['id']),
                    report: selected,
                    onResolve: onResolve,
                  ),
          ),
        ),
      ],
    );
  }
}

class _ComplaintDetail extends StatefulWidget {
  const _ComplaintDetail({
    super.key,
    required this.report,
    required this.onResolve,
  });

  final Map<String, dynamic> report;
  final void Function(Map<String, dynamic> report, String reply) onResolve;

  @override
  State<_ComplaintDetail> createState() => _ComplaintDetailState();
}

class _ComplaintDetailState extends State<_ComplaintDetail> {
  final _replyController = TextEditingController();

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final report = widget.report;
    final isResolved = report['status'] == 'resolved';
    final vendorName = (report['vendors'] as Map?)?['name'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  report['subject'] ?? l10n.complaintFallback,
                  style: AppType.heading(18),
                ),
              ),
              _StatusPill(isResolved: isResolved),
            ],
          ),
          if (vendorName != null) ...[
            const SizedBox(height: 4),
            Text(
              '${l10n.storeLabel}: $vendorName',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          Text(
            report['description'] ?? '',
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          if (isResolved && report['admin_reply'] != null) ...[
            const SizedBox(height: AppSpace.xl),
            _ReplyBlock(reply: report['admin_reply'] as String),
          ],
          if (!isResolved) ...[
            const SizedBox(height: AppSpace.xl),
            const Divider(color: AppColors.borderSoft),
            const SizedBox(height: AppSpace.lg),
            TextField(
              controller: _replyController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: l10n.complaintReplyHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () =>
                    widget.onResolve(report, _replyController.text),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(l10n.sendAndResolve),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.isResolved});

  final bool isResolved;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isResolved ? AppColors.successFill : AppColors.amberFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        (isResolved ? context.l10n.resolvedLabel : context.l10n.pendingLabel)
            .toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isResolved ? AppColors.successInk : AppColors.amberInk,
        ),
      ),
    );
  }
}

class _ReplyBlock extends StatelessWidget {
  const _ReplyBlock({required this.reply});

  final String reply;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${context.l10n.resolutionReply}:\n$reply',
        style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic),
      ),
    );
  }
}
