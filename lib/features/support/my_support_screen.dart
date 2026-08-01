import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/tokens.dart';
import '../../core/models/support.dart';
import '../../core/repositories/support_repository.dart';
import '../../core/widgets/common.dart';
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

  void _reload() => setState(() => _future = _repo.fetchMyThreads());

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
            padding: EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.md,
                AppSpace.gutter, 96 + MediaQuery.paddingOf(context).bottom),
            itemCount: threads.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
            itemBuilder: (context, i) =>
                _ThreadTile(thread: threads[i], onTap: () => _openThread(threads[i])),
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
          backgroundColor:
              thread.isOpen ? AppColors.warmFill : AppColors.neutralFill,
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
            color:
                thread.isOpen ? AppColors.successFill : AppColors.neutralFill,
            borderRadius: BorderRadius.circular(AppRadii.xs),
          ),
          child: Text(
            thread.isOpen ? l10n.open : l10n.resolved,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: thread.isOpen
                  ? AppColors.successInk
                  : AppColors.textMuted,
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
  const AdminSupportScreen({super.key});

  @override
  State<AdminSupportScreen> createState() => _AdminSupportScreenState();
}

class _AdminSupportScreenState extends State<AdminSupportScreen> {
  final _repo = SupportRepository();
  bool _openOnly = false;
  late Future<List<SupportThread>> _future = _repo.fetchAllThreads();

  void _reload() =>
      setState(() => _future = _repo.fetchAllThreads(openOnly: _openOnly));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(l10n.supportChat),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.sm),
            child: FilterChip(
              label: Text(l10n.openOnly),
              selected: _openOnly,
              onSelected: (v) {
                setState(() => _openOnly = v);
                _reload();
              },
            ),
          ),
        ],
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
                message: l10n.noSupportThreads,
                icon: Icons.support_agent_outlined);
          }
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.md,
                  AppSpace.gutter, AppSpace.xxl + MediaQuery.paddingOf(context).bottom),
              itemCount: threads.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
              itemBuilder: (context, i) {
                final thread = threads[i];
                return _ThreadTile(
                  thread: thread,
                  subtitle: thread.userName ?? context.l10n.customer,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SupportChatScreen(thread: thread, asAdmin: true),
                      ),
                    );
                    _reload();
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
