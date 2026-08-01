import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart' show ButtonSpinner;
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// Every account on the platform, with the two levers an operator has:
/// block (reversible, keeps the account) and close (final, scrubs identity).
///
/// Neither one deletes the row — orders reference it, and a hard delete simply
/// fails on the foreign key. That is a schema fact, so the UI says "close"
/// rather than promising a removal it cannot deliver.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _repo = AdminRepository();
  late Future<List<AdminUser>> _future = _repo.fetchUsers();
  String _search = '';
  String? _busyId;

  void _reload() => setState(() => _future = _repo.fetchUsers());

  Future<void> _toggleBlock(AdminUser user) async {
    String? reason;
    if (!user.isBlocked) {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.l10n.blockUser),
          content: TextField(
            controller: controller,
            decoration:
                InputDecoration(hintText: context.l10n.blockReasonHint),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.l10n.cancel)),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.dangerInk),
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(context.l10n.blockUser),
            ),
          ],
        ),
      );
      if (reason == null) return;
    }

    setState(() => _busyId = user.id);
    try {
      await _repo.setUserBlocked(user.id, !user.isBlocked, reason: reason);
      if (!mounted) return;
      showSnack(
          context,
          user.isBlocked
              ? context.l10n.userUnblocked
              : context.l10n.userBlocked);
      _reload();
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(AdminUser user) async {
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: user.name,
      message: context.l10n.deleteAccountWarning,
      confirmText: context.l10n.deleteAccount,
      isDestructive: true,
    );
    if (confirmed != true) return;
    setState(() => _busyId = user.id);
    try {
      await _repo.deleteUser(user.id);
      if (!mounted) return;
      showSnack(context, context.l10n.userDeleted);
      _reload();
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.users)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.sm),
            child: TextField(
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: l10n.searchUsers,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<AdminUser>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const LoadingView();
                }
                if (snap.hasError) {
                  return FailureView(error: snap.error!, onRetry: _reload);
                }
                final users = (snap.data ?? const <AdminUser>[])
                    .where((u) =>
                        _search.isEmpty ||
                        u.name.toLowerCase().contains(_search) ||
                        (u.phone ?? '').toLowerCase().contains(_search))
                    .toList();
                if (users.isEmpty) {
                  return EmptyView(
                      message: l10n.users, icon: Icons.people_outline);
                }
                return RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async => _reload(),
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                        AppSpace.gutter,
                        AppSpace.xs,
                        AppSpace.gutter,
                        AppSpace.xxl + MediaQuery.paddingOf(context).bottom),
                    itemCount: users.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpace.sm),
                    itemBuilder: (context, i) {
                      final user = users[i];
                      return _UserCard(
                        user: user,
                        busy: _busyId == user.id,
                        onToggleBlock: () => _toggleBlock(user),
                        onDelete: () => _delete(user),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.busy,
    required this.onToggleBlock,
    required this.onDelete,
  });

  final AdminUser user;
  final bool busy;
  final VoidCallback onToggleBlock;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // A closed account offers no actions: there is nothing left to do to it.
    final closed = user.isDeleted;
    return Opacity(
      opacity: closed ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(
              color: user.isBlocked
                  ? AppColors.dangerInk.withValues(alpha: 0.35)
                  : AppColors.border),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                        [user.role, if (user.phone != null) user.phone!]
                            .join(' · '),
                        style: const TextStyle(
                            fontSize: 12.5, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                if (user.isBlocked)
                  _chip(l10n.blocked, AppColors.dangerFill,
                      AppColors.dangerInk),
                if (closed) ...[
                  const SizedBox(width: 6),
                  _chip(l10n.deleteAccount, AppColors.neutralFill,
                      AppColors.textMuted),
                ],
              ],
            ),
            if (user.blockedReason != null &&
                user.blockedReason!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              Text(user.blockedReason!,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.dangerInk)),
            ],
            if (!closed && !user.isAdmin) ...[
              const SizedBox(height: AppSpace.md),
              if (busy)
                const Center(child: ButtonSpinner(size: 18))
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onToggleBlock,
                        icon: Icon(
                            user.isBlocked
                                ? Icons.lock_open_outlined
                                : Icons.block_outlined,
                            size: 17),
                        label: Text(user.isBlocked
                            ? l10n.unblockUser
                            : l10n.blockUser),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    IconButton(
                      onPressed: onDelete,
                      tooltip: l10n.deleteAccount,
                      color: AppColors.dangerInk,
                      icon: const Icon(Icons.person_remove_outlined),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color fill, Color ink) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppRadii.xs),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w800, color: ink)),
      );
}
