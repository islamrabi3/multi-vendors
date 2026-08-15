import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/tokens.dart';
import '../../core/models/support.dart';
import '../../core/repositories/support_repository.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/web/web_shell_frame.dart';
import '../admin/screens/admin_manage_screen.dart' show adminManageWebSections;
import 'support_chat_screen.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// The user's own support conversations.
///
/// Opening this with no history goes straight into a thread rather than showing
/// an empty list with a button — the only reason to be here is to talk to
/// someone.
class MySupportScreen extends StatefulWidget {
  const MySupportScreen({super.key});

  @override
  State<MySupportScreen> createState() => _MySupportScreenState();
}

class _MySupportScreenState extends State<MySupportScreen> {
  final _repo = SupportRepository();
  late Future<List<SupportThread>> _future = _repo.fetchMyThreads();
  bool _opening = false;

  /// Returns the fetch so `RefreshIndicator` can hold its spinner until the
  /// data lands. A `void` reload completed instantly, so pulling down flashed
  /// the spinner and dropped it before anything arrived — which reads as "that
  /// did nothing" even though it worked.
  Future<void> _reload() {
    final future = _repo.fetchMyThreads();
    // Block body: an arrow closure returns the assigned value, and a closure
    // returning a Future makes setState throw.
    setState(() {
      _future = future;
    });
    return future;
  }

  Future<void> _openThread([SupportThread? thread]) async {
    var target = thread;
    if (target == null) {
      setState(() => _opening = true);
      try {
        target = await _repo.openOrCreateThread();
      } catch (e) {
        if (mounted) showFailure(context, e);
        return;
      } finally {
        if (mounted) setState(() => _opening = false);
      }
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SupportChatScreen(thread: target!)),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.supportChat)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _opening ? null : () => _openThread(),
        icon: const Icon(Icons.support_agent_outlined),
        label: Text(l10n.supportChat),
      ),
      body: FutureBuilder<List<SupportThread>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const LoadingView();
          }
          if (snap.hasError) {
            return FailureView(error: snap.error!, onRetry: _reload);
          }
          final threads = snap.data ?? const <SupportThread>[];
          if (threads.isEmpty) {
            return EmptyView(
              message: l10n.supportChatEmpty,
              icon: Icons.support_agent_outlined,
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              AppSpace.gutter,
              AppSpace.md,
              AppSpace.gutter,
              96 + MediaQuery.paddingOf(context).bottom,
            ),
            itemCount: threads.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
            itemBuilder: (context, i) => _ThreadTile(
              thread: threads[i],
              onTap: () => _openThread(threads[i]),
            ),
          );
        },
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.thread, required this.onTap, this.subtitle});

  final SupportThread thread;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: thread.isOpen
              ? AppColors.warmFill
              : AppColors.neutralFill,
          child: Icon(
            thread.isOpen
                ? Icons.mark_chat_unread_outlined
                : Icons.mark_chat_read_outlined,
            size: 18,
            color: thread.isOpen ? AppColors.primary : AppColors.textMuted,
          ),
        ),
        title: Text(
          subtitle ??
              (thread.subject.trim().isEmpty
                  ? l10n.supportChat
                  : thread.subject),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          DateFormat('MMM d · h:mm a').format(thread.lastMessageAt.toLocal()),
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: thread.isOpen
                ? AppColors.successFill
                : AppColors.neutralFill,
            borderRadius: BorderRadius.circular(AppRadii.xs),
          ),
          child: Text(
            thread.isOpen ? l10n.open : l10n.resolved,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: thread.isOpen ? AppColors.successInk : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// The admin inbox. Same tile, but titled by who is asking rather than by the
/// subject, because that is what an operator scans for.
class AdminSupportScreen extends StatefulWidget {
  const AdminSupportScreen({super.key, this.embedded = false});

  /// True when a web sidebar is already drawing the shell around this screen
  /// (`_AdminWebShell`) — skips this widget's own [WebPageChrome]/[Scaffold]
  /// and returns just the filter row + table.
  final bool embedded;

  @override
  State<AdminSupportScreen> createState() => _AdminSupportScreenState();
}

class _AdminSupportScreenState extends State<AdminSupportScreen> {
  final _repo = SupportRepository();
  bool _openOnly = false;
  late Future<List<SupportThread>> _future = _repo.fetchAllThreads();

  /// Selected thread for the web split view. Mobile never sets this — it
  /// pushes [SupportChatScreen] as a full page instead.
  String? _selectedId;

  Future<void> _reload() {
    final future = _repo.fetchAllThreads(openOnly: _openOnly);
    // Block body: an arrow closure returns the assigned value, and a closure
    // returning a Future makes setState throw.
    setState(() {
      _future = future;
    });
    return future;
  }

  Future<void> _openThread(SupportThread thread) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupportChatScreen(thread: thread, asAdmin: true),
      ),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final webWide = AppBreakpoints.isWebWide(context);

    final filter = FilterChip(
      label: Text(l10n.openOnly),
      selected: _openOnly,
      onSelected: (v) {
        setState(() => _openOnly = v);
        _reload();
      },
    );

    final body = FutureBuilder<List<SupportThread>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const LoadingView();
        }
        if (snap.hasError) {
          return FailureView(error: snap.error!, onRetry: _reload);
        }
        final threads = snap.data ?? const <SupportThread>[];
        if (threads.isEmpty) {
          return EmptyView(
            message: l10n.noSupportThreads,
            icon: Icons.support_agent_outlined,
          );
        }
        if (webWide) {
          if (_selectedId != null && !threads.any((t) => t.id == _selectedId)) {
            _selectedId = null;
          }
          return _SupportSplitView(
            threads: threads,
            selectedId: _selectedId,
            onSelect: (id) => setState(() => _selectedId = id),
            onChanged: _reload,
          );
        }
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => _reload(),
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(
              AppSpace.gutter,
              AppSpace.md,
              AppSpace.gutter,
              AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
            ),
            itemCount: threads.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
            itemBuilder: (context, i) {
              final thread = threads[i];
              return _ThreadTile(
                thread: thread,
                subtitle: thread.userName ?? context.l10n.customer,
                onTap: () => _openThread(thread),
              );
            },
          ),
        );
      },
    );

    if (widget.embedded) {
      // The web shell is already drawing the sidebar/top bar around this —
      // just the filter row and the table.
      return Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(alignment: Alignment.centerRight, child: filter),
            const SizedBox(height: AppSpace.lg),
            Expanded(child: body),
          ],
        ),
      );
    }

    if (webWide) {
      return WebPageChrome(
        activeId: 'manage:/admin-app/support',
        sections: adminManageWebSections(context),
        pageTitle: l10n.supportChat,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(alignment: Alignment.centerRight, child: filter),
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
        title: Text(l10n.supportChat),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.sm),
            child: filter,
          ),
        ],
      ),
      body: body,
    );
  }
}

/// Web/wide: a thread list beside the chat pane itself, so opening a
/// conversation swaps content in place instead of covering the sidebar with
/// a full-screen modal — the same list+detail shape [admin_complaints_screen.dart]
/// uses for reports.
class _SupportSplitView extends StatelessWidget {
  const _SupportSplitView({
    required this.threads,
    required this.selectedId,
    required this.onSelect,
    required this.onChanged,
  });

  final List<SupportThread> threads;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected = threads.cast<SupportThread?>().firstWhere(
      (t) => t?.id == selectedId,
      orElse: () => null,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 4,
          child: ListView.separated(
            itemCount: threads.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
            itemBuilder: (context, i) {
              final thread = threads[i];
              final isSelected = thread.id == selectedId;
              return Material(
                color: isSelected ? AppColors.warmFill : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  onTap: () => onSelect(thread.id),
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
                                thread.userName ?? l10n.customer,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SoftBadge(
                              label: thread.isOpen ? l10n.open : l10n.resolved,
                              fill: thread.isOpen
                                  ? AppColors.warmFill
                                  : AppColors.neutralFill,
                              ink: thread.isOpen
                                  ? AppColors.primary
                                  : AppColors.textMuted,
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          DateFormat(
                            'MMM d · h:mm a',
                          ).format(thread.lastMessageAt.toLocal()),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
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
                      message: l10n.supportChatEmpty,
                      icon: Icons.support_agent_outlined,
                    ),
                  )
                : SupportChatScreen(
                    key: ValueKey(selected.id),
                    thread: selected,
                    asAdmin: true,
                    embedded: true,
                    onChanged: onChanged,
                  ),
          ),
        ),
      ],
    );
  }
}
