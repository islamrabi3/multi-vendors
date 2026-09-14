import 'dart:async';

import 'package:flutter/material.dart';
import 'package:multi_vendor/features/admin/admin_action_badges.dart';
import 'package:multi_vendor/core/widgets/count_badge.dart';
import '../../../app/tokens.dart';
import '../../../core/models/customer_report.dart';
import '../../../core/repositories/report_repository.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';
import '../../support/complaints/complaint_thread_screen.dart';
import '../../support/complaints/complaint_thread_view.dart';
import '../../support/complaints/my_complaints_screen.dart' show ComplaintTile;
import 'admin_manage_screen.dart' show adminManageWebSections;

/// The complaints queue. Each complaint is a conversation with the customer:
/// the admin replies, the customer can answer back, and either resolving or a
/// new customer message moves it between the tabs.
class AdminComplaintsScreen extends StatefulWidget {
  const AdminComplaintsScreen({
    super.key,
    this.embedded = false,
    this.initialReportId,
  });

  /// True when a web sidebar is already drawing the shell around this screen
  /// (`_AdminWebShell`) — skips this widget's own [WebPageChrome]/[Scaffold]
  /// and returns just the filter bar + split view.
  final bool embedded;

  /// Opened from a notification: select (web) or open (phone) this complaint.
  final String? initialReportId;

  @override
  State<AdminComplaintsScreen> createState() => _AdminComplaintsScreenState();
}

class _AdminComplaintsScreenState extends State<AdminComplaintsScreen> {
  final _repo = ReportRepository();
  bool _loading = true;
  String? _error;
  List<CustomerReport> _reports = const [];
  String _filterStatus = 'all'; // 'all', 'pending', 'resolved'

  /// Selected complaint for the web split view.
  String? _selectedId;
  StreamSubscription<void>? _changes;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialReportId;
    _load();
    // A customer reply or another admin's resolve reorders the queue live.
    _changes = _repo.watchAll().listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), _load);
    });
    final initial = widget.initialReportId;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !AppBreakpoints.isWebWide(context)) {
          _openOnPhone(initial);
        }
      });
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
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

  Future<void> _openOnPhone(String reportId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ComplaintThreadScreen(reportId: reportId, asAdmin: true),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final webWide = AppBreakpoints.isWebWide(context);

    // [expanded] fills a phone's width with equal segments. Without it the
    // Arabic labels plus the selected check ran past a 358px screen.
    Widget buildFilterBar({bool expanded = false}) {
      Text label(String text) =>
          Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
      return SegmentedButton<String>(
        expandedInsets: expanded ? EdgeInsets.zero : null,
        showSelectedIcon: !expanded,
        segments: [
          ButtonSegment(value: 'all', label: label(l10n.all)),
          ButtonSegment(
            value: 'pending',
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: label(l10n.pendingLabel)),
                const SizedBox(width: 4),
                CountBadge(
                  compact: true,
                  count: AdminActionBadges.instance.countFor(
                    AdminActionBadges.reportsPending,
                  ),
                ),
              ],
            ),
          ),
          ButtonSegment(value: 'resolved', label: label(l10n.resolvedLabel)),
        ],
        selected: {_filterStatus},
        onSelectionChanged: (set) {
          setState(() => _filterStatus = set.first);
          _load();
        },
      );
    }

    final filterBar = buildFilterBar();

    final body = _loading && _reports.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? ErrorView(message: _error!, onRetry: _load)
        : webWide
        ? _WebSplitView(
            reports: _reports,
            selectedId: _selectedId,
            onSelect: (id) => setState(() => _selectedId = id),
            onChanged: _load,
            onRefresh: _load,
          )
        : _MobileList(
            reports: _reports,
            onOpen: _openOnPhone,
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
              child: buildFilterBar(expanded: true),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// Mobile/narrow: the queue as tiles; a tap opens the thread full screen.
class _MobileList extends StatelessWidget {
  const _MobileList({
    required this.reports,
    required this.onOpen,
    required this.onRefresh,
  });

  final List<CustomerReport> reports;
  final ValueChanged<String> onOpen;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
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
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpace.gutter),
              itemCount: reports.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
              itemBuilder: (context, i) => ComplaintTile(
                report: reports[i],
                forAdmin: true,
                onTap: () => onOpen(reports[i].id),
              ),
            ),
    );
  }
}

/// Web/wide: the queue beside the open conversation.
class _WebSplitView extends StatelessWidget {
  const _WebSplitView({
    required this.reports,
    required this.selectedId,
    required this.onSelect,
    required this.onChanged,
    required this.onRefresh,
  });

  final List<CustomerReport> reports;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onChanged;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final id = selectedId;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 4,
          child: reports.isEmpty
              ? Center(
                  child: EmptyView(
                    message: context.l10n.noComplaints,
                    icon: Icons.report_problem_outlined,
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: onRefresh,
                  child: ListView.separated(
                    itemCount: reports.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpace.sm),
                    itemBuilder: (context, i) => ComplaintTile(
                      report: reports[i],
                      forAdmin: true,
                      selected: reports[i].id == id,
                      onTap: () => onSelect(reports[i].id),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: AppSpace.lg),
        Expanded(
          flex: 6,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.canvas,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppRadii.xl),
            ),
            clipBehavior: Clip.antiAlias,
            // Kept even when the filter hides the selected complaint, so
            // resolving it does not yank the conversation away mid-reply.
            child: id == null
                ? Center(
                    child: EmptyView(
                      message: context.l10n.complaintSelectHint,
                      icon: Icons.forum_outlined,
                    ),
                  )
                : ComplaintThreadView(
                    key: ValueKey(id),
                    reportId: id,
                    asAdmin: true,
                    showHeaderActions: true,
                    onChanged: onChanged,
                  ),
          ),
        ),
      ],
    );
  }
}
