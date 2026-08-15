import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../app/tokens.dart';
import '../../../core/widgets/web/web_table.dart';
import '../../../core/repositories/campaigns_repository.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/responsive_list.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import '../../auth/auth_cubit.dart';
import 'admin_manage_screen.dart' show adminManageWebSections;
import '../../../core/widgets/web/adaptive_sheet.dart';

/// Platform-wide announcements.
///
/// Every push before this was one event to one person, fired by a trigger.
/// This is the other shape — one message to a whole audience — so it is
/// composed as a row first and sent second: a send that leaves no record is
/// impossible to answer questions about afterwards.
/// Platform-wide announcements: what has gone out, and what has not.
///
/// Split in two because they are read for different reasons — drafts are a
/// to-do list, sent ones are a record — and paged because a campaign list only
/// ever grows.
class AdminAnnouncementsScreen extends StatefulWidget {
  const AdminAnnouncementsScreen({super.key, this.embedded = false});

  /// True when a web sidebar is already drawing the shell around this screen
  /// (`_AdminWebShell`) — skips this widget's own [WebPageChrome]/[Scaffold]
  /// and returns just the content.
  final bool embedded;

  @override
  State<AdminAnnouncementsScreen> createState() =>
      _AdminAnnouncementsScreenState();
}

class _AdminAnnouncementsScreenState extends State<AdminAnnouncementsScreen> {
  final _repo = CampaignsRepository();

  /// Bumped after anything that changes the data. Both lists key off it, so
  /// sending from one tab refreshes the other — a sent campaign leaves the
  /// drafts tab and appears in the sent one.
  int _revision = 0;

  void _reload() => setState(() => _revision++);

  Future<void> _compose() async {
    final outcome = await showAdaptiveSheet<_ComposeOutcome>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _Composer(repo: _repo),
    );
    if (outcome == null || !mounted) return;
    _reload();
    // The composer sends; this only reports. Splitting it that way keeps the
    // "cannot be unsent" confirmation next to the button that does it.
    final result = outcome.result;
    showSnack(
      context,
      result == null
          ? context.l10n.draftSaved
          : context.l10n.campaignSent(
              ((result['delivered'] as num?) ?? 0).toInt(),
              ((result['recipients'] as num?) ?? 0).toInt(),
            ),
    );
  }

  /// Sends a draft, or sends an already-sent one again as a fresh copy.
  Future<void> _send(
    NotificationCampaign campaign, {
    bool asCopy = false,
  }) async {
    final l10n = context.l10n;
    // Fetched fresh rather than reused: an audience grows, and "cannot be
    // unsent" deserves an accurate number.
    final reach = await _repo.audienceSize(campaign.audience);
    if (!mounted) return;
    if (reach == 0) {
      showSnack(context, l10n.campaignNothingToReach, error: true);
      return;
    }

    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: campaign.title,
      message: asCopy
          ? l10n.resendConfirm(reach)
          : l10n.campaignSendConfirm(reach),
      confirmText: asCopy ? l10n.resend : l10n.sendNow,
      cancelText: l10n.cancel,
      isDestructive: false,
      icon: Icons.campaign_outlined,
    );
    if (confirmed != true || !mounted) return;

    final result = await showBlockingProgress(context, () async {
      // A resend is a new row. Resetting the original's status would overwrite
      // the record of the first send, leaving its counts meaningless.
      final target = asCopy ? await _repo.duplicate(campaign) : campaign;
      return _repo.send(target.id);
    });
    if (result == null || !mounted) return;
    _reload();
    showSnack(
      context,
      l10n.campaignSent(
        ((result['delivered'] as num?) ?? 0).toInt(),
        ((result['recipients'] as num?) ?? 0).toInt(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final webWide = AppBreakpoints.isWebWide(context);
    final canSend = context.select(
      (AuthCubit c) => c.state.can('notifications.send'),
    );

    final tabs = TabBar(
      tabs: [
        Tab(text: l10n.statusSent),
        Tab(text: l10n.drafts),
      ],
    );

    final body = TabBarView(
      children: [
        _CampaignList(
          key: ValueKey('sent-$_revision'),
          repo: _repo,
          sent: true,
          canSend: canSend,
          onSend: _send,
        ),
        _CampaignList(
          key: ValueKey('drafts-$_revision'),
          repo: _repo,
          sent: false,
          canSend: canSend,
          onSend: _send,
        ),
      ],
    );

    // Wide/embedded layouts have no floating action button to hang this off,
    // so it surfaces as a button above the tabs instead.
    final header = ColoredBox(
      color: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canSend)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                0,
              ),
              child: Row(
                children: [
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _compose,
                    icon: const Icon(Icons.campaign_outlined, size: 18),
                    label: Text(l10n.newAnnouncement),
                  ),
                ],
              ),
            ),
          tabs,
        ],
      ),
    );

    if (widget.embedded) {
      return DefaultTabController(
        length: 2,
        child: Column(
          children: [
            header,
            const Divider(height: 1, thickness: 1, color: AppColors.border),
            Expanded(child: body),
          ],
        ),
      );
    }

    if (webWide) {
      return DefaultTabController(
        length: 2,
        child: WebPageChrome(
          activeId: 'manage:/admin-app/announcements',
          sections: adminManageWebSections(context),
          pageTitle: l10n.announcements,
          child: Column(
            children: [
              header,
              const Divider(height: 1, thickness: 1, color: AppColors.border),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(title: Text(l10n.announcements), bottom: tabs),
        floatingActionButton: canSend
            ? FloatingActionButton.extended(
                onPressed: _compose,
                icon: const Icon(Icons.campaign_outlined),
                label: Text(l10n.newAnnouncement),
              )
            : null,
        body: body,
      ),
    );
  }
}

/// One page-at-a-time list of campaigns.
class _CampaignList extends StatefulWidget {
  const _CampaignList({
    super.key,
    required this.repo,
    required this.sent,
    required this.canSend,
    required this.onSend,
  });

  final CampaignsRepository repo;

  /// true = the sent record, false = drafts, failures and anything mid-send.
  final bool sent;
  final bool canSend;
  final void Function(NotificationCampaign campaign, {bool asCopy}) onSend;

  @override
  State<_CampaignList> createState() => _CampaignListState();
}

class _CampaignListState extends State<_CampaignList> {
  static const _pageSize = 20;

  final _scroll = ScrollController();
  final _campaigns = <NotificationCampaign>[];

  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repo.fetchAll(
        limit: _pageSize,
        sent: widget.sent,
      );
      if (!mounted) return;
      setState(() {
        _campaigns
          ..clear()
          ..addAll(page);
        _hasMore = page.length == _pageSize;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final page = await widget.repo.fetchAll(
        limit: _pageSize,
        offset: _campaigns.length,
        sent: widget.sent,
      );
      if (!mounted) return;
      setState(() {
        _campaigns.addAll(page);
        _hasMore = page.length == _pageSize;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      // The page already has content; a failed *next* page is a message, not
      // an error screen replacing what is on screen.
      showFailure(context, error, onRetry: _loadMore);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_loading) return const LoadingView();
    if (_error != null) {
      return FailureView(error: _error!, onRetry: _load);
    }
    if (_campaigns.isEmpty) {
      return EmptyView(
        message: l10n.noCampaignsYet,
        icon: Icons.campaign_outlined,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: AppBreakpoints.isWebWide(context)
          ? _CampaignTable(
              campaigns: _campaigns,
              controller: _scroll,
              canSend: widget.canSend,
              onSend: widget.onSend,
              loadingMore: _loadingMore,
              hasMore: _hasMore,
            )
          : ResponsiveCardList(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.lg,
                AppSpace.lg,
                96,
              ),
              itemCount: _campaigns.length,
              // Full width in both layouts: the paging spinner belongs to the list,
              // not to whichever column happens to end last.
              footer: PagingFooter(loading: _loadingMore, hasMore: _hasMore),
              itemBuilder: (context, i) => _CampaignCard(
                campaign: _campaigns[i],
                canSend: widget.canSend,
                onSend: widget.onSend,
              ),
            ),
    );
  }
}

/// Web/wide: campaigns as a table.
///
/// A campaign is read for four things — what it said, who it went to, how it
/// landed, and when. Cards spread those across two lines and a badge; columns
/// put the whole send history in one scan, which is how you notice that
/// yesterday's driver push failed.
class _CampaignTable extends StatelessWidget {
  const _CampaignTable({
    required this.campaigns,
    required this.controller,
    required this.canSend,
    required this.onSend,
    required this.loadingMore,
    required this.hasMore,
  });

  final List<NotificationCampaign> campaigns;
  final ScrollController controller;
  final bool canSend;
  final void Function(NotificationCampaign campaign, {bool asCopy}) onSend;
  final bool loadingMore;
  final bool hasMore;

  String _audience(BuildContext context, String audience) => switch (audience) {
    'customers' => context.l10n.audienceCustomers,
    'vendors' => context.l10n.audienceVendors,
    'drivers' => context.l10n.audienceDrivers,
    _ => context.l10n.audienceAll,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final columns = [
      WebTableColumn(label: l10n.titleLabel, flex: 3),
      WebTableColumn(label: l10n.audience, width: 120),
      WebTableColumn(label: l10n.delivered, width: 130),
      WebTableColumn(label: l10n.dateLabel, width: 120),
      WebTableColumn(label: l10n.statusLabel, width: 96),
    ];

    return SingleChildScrollView(
      controller: controller,
      child: Column(
        children: [
          WebTable(
            columns: columns,
            trailingWidth: canSend ? 84 : 20,
            rows: [
              for (final campaign in campaigns)
                WebTableRow.aligned(
                  columns: columns,
                  trailingWidth: canSend ? 84 : 20,
                  cells: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          campaign.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                        Text(
                          campaign.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      _audience(context, campaign.audience),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    // Failures are the reason to open this screen, so they
                    // are coloured rather than left to be counted.
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${campaign.delivered}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: ' / ${campaign.recipients}'),
                          if (campaign.failed > 0)
                            TextSpan(
                              text: '  ·  ${campaign.failed}',
                              style: const TextStyle(
                                color: AppColors.dangerInk,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                      style: AppType.mono(12, color: AppColors.textSecondary),
                    ),
                    Text(
                      DateFormat(
                        'MMM d, y',
                      ).format(campaign.sentAt ?? campaign.createdAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                    _CampaignStatus(status: campaign.status),
                  ],
                  trailing: canSend && campaign.canSend
                      ? Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton(
                            onPressed: () => onSend(campaign),
                            child: Text(l10n.sendNow),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
          PagingFooter(loading: loadingMore, hasMore: hasMore),
          const SizedBox(height: AppSpace.xl),
        ],
      ),
    );
  }
}

class _CampaignStatus extends StatelessWidget {
  const _CampaignStatus({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (label, fill, ink) = switch (status) {
      'sent' => (l10n.statusSent, AppColors.successFill, AppColors.successInk),
      'sending' => (
        l10n.statusSending,
        AppColors.amberFill,
        AppColors.amberInk,
      ),
      'failed' => (
        l10n.statusFailed,
        AppColors.dangerFill,
        AppColors.dangerInk,
      ),
      _ => (l10n.statusDraft, AppColors.neutralFill, AppColors.textMuted),
    };
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SoftBadge(label: label, fill: fill, ink: ink),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({
    required this.campaign,
    required this.canSend,
    required this.onSend,
  });

  final NotificationCampaign campaign;
  final bool canSend;
  final void Function(NotificationCampaign campaign, {bool asCopy}) onSend;

  String _audienceLabel(BuildContext context) => switch (campaign.audience) {
    'customers' => context.l10n.audienceCustomers,
    'vendors' => context.l10n.audienceVendors,
    'drivers' => context.l10n.audienceDrivers,
    _ => context.l10n.audienceAll,
  };

  ({String label, Color fill, Color ink}) _status(BuildContext context) {
    final l10n = context.l10n;
    return switch (campaign.status) {
      'sent' => (
        label: l10n.statusSent,
        fill: AppColors.successFill,
        ink: AppColors.successInk,
      ),
      'sending' => (
        label: l10n.statusSending,
        fill: AppColors.amberFill,
        ink: AppColors.amberInk,
      ),
      'failed' => (
        label: l10n.statusFailed,
        fill: AppColors.dangerFill,
        ink: AppColors.dangerInk,
      ),
      _ => (
        label: l10n.statusDraft,
        fill: AppColors.neutralFill,
        ink: AppColors.textMuted,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = _status(context);
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  campaign.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
              ),
              SoftBadge(
                label: status.label,
                fill: status.fill,
                ink: status.ink,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            campaign.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            [
              _audienceLabel(context),
              DateFormat.yMMMd().add_jm().format(
                campaign.sentAt ?? campaign.createdAt,
              ),
              // Only meaningful once it has actually gone out.
              if (campaign.isSent)
                l10n.deliveredOf(campaign.delivered, campaign.failed),
            ].join(' · '),
            style: const TextStyle(fontSize: 11.5, color: AppColors.textFaint),
          ),
          if (campaign.error != null) ...[
            const SizedBox(height: 6),
            Text(
              campaign.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.dangerInk),
            ),
          ],
          if (canSend && campaign.canSend) ...[
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                onPressed: () => onSend(campaign),
                icon: const Icon(Icons.send_rounded, size: 17),
                label: Text(l10n.sendNow),
              ),
            ),
          ],
          if (canSend && campaign.isSent) ...[
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => onSend(campaign, asCopy: true),
                icon: const Icon(Icons.replay_rounded, size: 17),
                label: Text(l10n.resend),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Write the message and pick who gets it.
class _Composer extends StatefulWidget {
  const _Composer({required this.repo});

  final CampaignsRepository repo;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _link = TextEditingController();
  String _audience = 'all';
  int? _reach;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadReach();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _link.dispose();
    super.dispose();
  }

  /// Shown live as the audience changes, so the size of the decision is
  /// visible before the message is even written.
  Future<void> _loadReach() async {
    final reach = await widget.repo
        .audienceSize(_audience)
        .catchError((_) => 0);
    if (mounted) setState(() => _reach = reach);
  }

  bool get _valid =>
      _title.text.trim().isNotEmpty && _body.text.trim().isNotEmpty;

  /// Prepare one without sending it — for a message that is going out later.
  Future<void> _saveDraft() async {
    if (!_valid) return;
    setState(() => _saving = true);
    try {
      await widget.repo.create(
        title: _title.text,
        body: _body.text,
        audience: _audience,
        deepLink: _link.text,
      );
      if (mounted) Navigator.pop(context, const _ComposeOutcome(null));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showFailure(context, error);
    }
  }

  /// What the button on this sheet does, because it is what the person who
  /// just wrote a message expects it to do.
  ///
  /// The campaign row is still created first — the sender takes an id, and the
  /// row is what records the outcome — but creating and sending are one action
  /// here rather than two screens apart. A send that fails leaves the draft
  /// behind, which is exactly what the list's own send button is for.
  Future<void> _sendNow() async {
    if (!_valid) return;
    final l10n = context.l10n;
    final navigator = Navigator.of(context);

    final reach = await widget.repo
        .audienceSize(_audience)
        .catchError((_) => 0);
    if (!mounted) return;
    if (reach == 0) {
      showSnack(context, l10n.campaignNothingToReach, error: true);
      return;
    }

    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: _title.text.trim(),
      message: l10n.campaignSendConfirm(reach),
      confirmText: l10n.sendNow,
      cancelText: l10n.cancel,
      isDestructive: false,
      icon: Icons.campaign_outlined,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final campaign = await widget.repo.create(
        title: _title.text,
        body: _body.text,
        audience: _audience,
        deepLink: _link.text,
      );
      final result = await widget.repo.send(campaign.id);
      navigator.pop(_ComposeOutcome(result));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      // The row exists as a draft at this point, so nothing typed is lost —
      // the list can retry it.
      showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpace.xl,
        right: AppSpace.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpace.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.newAnnouncement, style: AppType.heading(18)),
            const SizedBox(height: AppSpace.md),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'all', label: Text(l10n.audienceAll)),
                ButtonSegment(
                  value: 'customers',
                  label: Text(l10n.audienceCustomers),
                ),
                ButtonSegment(
                  value: 'vendors',
                  label: Text(l10n.audienceVendors),
                ),
                ButtonSegment(
                  value: 'drivers',
                  label: Text(l10n.audienceDrivers),
                ),
              ],
              selected: {_audience},
              onSelectionChanged: (s) {
                setState(() {
                  _audience = s.first;
                  _reach = null;
                });
                _loadReach();
              },
            ),
            const SizedBox(height: 6),
            Text(
              _reach == null ? '…' : l10n.reachableDevices(_reach!),
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _title,
              maxLength: 80,
              // Rebuilds so the send button reflects whether there is
              // anything to send, rather than accepting a tap and ignoring it.
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: l10n.announcementTitle),
            ),
            TextField(
              controller: _body,
              maxLines: 3,
              maxLength: 240,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: l10n.announcementBody),
            ),
            TextField(
              controller: _link,
              decoration: InputDecoration(
                labelText: l10n.deepLinkOptional,
                hintText: '/vendors/…',
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            FilledButton.icon(
              onPressed: _saving || !_valid ? null : _sendNow,
              icon: _saving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(l10n.sendNow),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            TextButton(
              onPressed: _saving || !_valid ? null : _saveDraft,
              child: Text(l10n.saveAsDraft),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the composer sheet hands back.
///
/// A null [result] means it was saved as a draft; anything else is the
/// sender's report, which the list turns into a "sent to N of M" message.
class _ComposeOutcome {
  const _ComposeOutcome(this.result);

  final Map<String, dynamic>? result;
}
