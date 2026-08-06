import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/tokens.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/responsive_list.dart';
import '../../auth/auth_cubit.dart';
import '../../../core/widgets/skeleton.dart' show ButtonSpinner;
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// Every account on the platform, with the levers an operator has: block
/// (reversible), delete, and a wallet adjustment.
///
/// Delete really removes the row when the account has no order history. When
/// it does, `orders` references it with NO ACTION and removing it would take
/// the order ledger too — so the account is anonymised and locked out of
/// sign-in instead, and the snackbar says which of the two happened rather
/// than claiming a removal that did not occur.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  static const _pageSize = 40;

  final _repo = AdminRepository();
  final _scroll = ScrollController();
  final _users = <AdminUser>[];

  String _search = '';
  String? _busyId;
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  /// Search runs against the database now, so it is debounced rather than
  /// filtering a list the app had already downloaded in full.
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_hasMore || _loadingMore || _loading) return;
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
        _loadMore();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    setState(() => _search = value.trim());
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repo.fetchUsers(search: _search, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _users
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
      final page = await _repo.fetchUsers(
        search: _search,
        limit: _pageSize,
        offset: _users.length,
      );
      if (!mounted) return;
      setState(() {
        _users.addAll(page);
        _hasMore = page.length == _pageSize;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showFailure(context, error, onRetry: _loadMore);
    }
  }

  void _reload() => _load();

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
            decoration: InputDecoration(hintText: context.l10n.blockReasonHint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.dangerInk,
              ),
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
        user.isBlocked ? context.l10n.userUnblocked : context.l10n.userBlocked,
      );
      _reload();
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Moves money into or out of a customer's wallet, with a reason.
  ///
  /// The reason is required by the server and shown to the customer in their
  /// wallet history, so an unexplained balance change cannot be made.
  Future<void> _adjustWallet(AdminUser user) async {
    final result = await showModalBottomSheet<({double amount, String reason})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _WalletAdjustSheet(user: user),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _busyId = user.id);
    try {
      final balance = await _repo.adjustWallet(
        userId: user.id,
        amount: result.amount,
        reason: result.reason,
      );
      if (!mounted) return;
      showSnack(context, context.l10n.walletAdjusted(formatMoney(balance)));
    } catch (error) {
      if (mounted) showFailure(context, error);
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
      final hardDeleted = await _repo.deleteUser(user.id);
      if (!mounted) return;
      showSnack(
        context,
        hardDeleted
            ? context.l10n.userDeleted
            : context.l10n.userDeletedAnonymised,
      );
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
    final auth = context.watch<AuthCubit>().state;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.users)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter,
              AppSpace.md,
              AppSpace.gutter,
              AppSpace.sm,
            ),
            child: TextField(
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: l10n.searchUsers,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                if (_loading) return const LoadingView();
                if (_error != null) {
                  return FailureView(error: _error!, onRetry: _reload);
                }
                if (_users.isEmpty) {
                  return EmptyView(
                    message: l10n.users,
                    icon: Icons.people_outline,
                  );
                }
                return RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _load,
                  child: ResponsiveCardList(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(
                      AppSpace.gutter,
                      AppSpace.xs,
                      AppSpace.gutter,
                      AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
                    ),
                    itemCount: _users.length,
                    footer: PagingFooter(
                      loading: _loadingMore,
                      hasMore: _hasMore,
                    ),
                    itemBuilder: (context, i) {
                      final user = _users[i];
                      return _UserCard(
                        user: user,
                        busy: _busyId == user.id,
                        canBlock: auth.can('users.block'),
                        canDelete: auth.can('users.delete'),
                        canAdjustWallet: auth.can('wallets.adjust'),
                        onToggleBlock: () => _toggleBlock(user),
                        onDelete: () => _delete(user),
                        onAdjustWallet: () => _adjustWallet(user),
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
    required this.canBlock,
    required this.canDelete,
    required this.canAdjustWallet,
    required this.onToggleBlock,
    required this.onDelete,
    required this.onAdjustWallet,
  });

  final AdminUser user;
  final bool busy;

  /// What this member of staff actually holds. Blocking and closing an
  /// account are separate permissions, so a role can have one without the
  /// other.
  final bool canBlock;
  final bool canDelete;
  final bool canAdjustWallet;
  final VoidCallback onToggleBlock;
  final VoidCallback onDelete;
  final VoidCallback onAdjustWallet;

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
                : AppColors.border,
          ),
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
                      Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          user.role,
                          if (user.phone != null) user.phone!,
                        ].join(' · '),
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (user.isBlocked)
                  _chip(
                    l10n.blocked,
                    AppColors.dangerFill,
                    AppColors.dangerInk,
                  ),
                if (closed) ...[
                  const SizedBox(width: 6),
                  _chip(
                    l10n.deleteAccount,
                    AppColors.neutralFill,
                    AppColors.textMuted,
                  ),
                ],
              ],
            ),
            if (user.blockedReason != null &&
                user.blockedReason!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                user.blockedReason!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.dangerInk,
                ),
              ),
            ],
            // Hidden rather than shown-and-refused: the server checks these
            // too, but a button that always fails is worse than no button.
            if (!closed &&
                !user.isAdmin &&
                (canBlock || canDelete || canAdjustWallet)) ...[
              const SizedBox(height: AppSpace.md),
              if (busy)
                const Center(child: ButtonSpinner(size: 18))
              else
                Row(
                  children: [
                    if (canBlock)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onToggleBlock,
                          icon: Icon(
                            user.isBlocked
                                ? Icons.lock_open_outlined
                                : Icons.block_outlined,
                            size: 17,
                          ),
                          label: Text(
                            user.isBlocked ? l10n.unblockUser : l10n.blockUser,
                          ),
                        ),
                      ),
                    if (canBlock && canDelete)
                      const SizedBox(width: AppSpace.sm),
                    if (canAdjustWallet)
                      IconButton(
                        onPressed: onAdjustWallet,
                        tooltip: l10n.adjustWallet,
                        icon: const Icon(
                          Icons.account_balance_wallet_outlined,
                        ),
                      ),
                    if (canDelete)
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
    child: Text(
      label,
      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: ink),
    ),
  );
}

/// Credit or debit, an amount, and a reason.
class _WalletAdjustSheet extends StatefulWidget {
  const _WalletAdjustSheet({required this.user});

  final AdminUser user;

  @override
  State<_WalletAdjustSheet> createState() => _WalletAdjustSheetState();
}

class _WalletAdjustSheetState extends State<_WalletAdjustSheet> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  bool _credit = true;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      showSnack(context, context.l10n.enterAValidPrice, error: true);
      return;
    }
    if (_reason.text.trim().isEmpty) {
      showSnack(context, context.l10n.walletAdjustReasonRequired, error: true);
      return;
    }
    Navigator.pop(context, (
      // Direction lives in the sign, which is what the server reads.
      amount: _credit ? amount : -amount,
      reason: _reason.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        AppSpace.lg,
        AppSpace.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.adjustWallet, style: AppType.display(20)),
          const SizedBox(height: 4),
          Text(
            widget.user.name,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: AppSpace.lg),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.walletAdjustCredit),
              ),
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.remove, size: 18),
                label: Text(l10n.walletAdjustDebit),
              ),
            ],
            selected: {_credit},
            onSelectionChanged: (v) => setState(() => _credit = v.first),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: l10n.walletAdjustAmount),
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: _reason,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: l10n.walletAdjustReason),
          ),
          const SizedBox(height: AppSpace.lg),
          FilledButton(onPressed: _submit, child: Text(l10n.save)),
        ],
      ),
    );
  }
}
