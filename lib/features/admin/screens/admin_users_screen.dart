import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/tokens.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/responsive_list.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import '../../../core/widgets/web/web_table.dart';
import '../../auth/auth_cubit.dart';
import '../../../core/widgets/skeleton.dart' show ButtonSpinner;
import 'admin_manage_screen.dart' show adminManageWebSections;
import 'package:multi_vendor/core/utils/l10n_extension.dart';
import '../../../core/widgets/web/adaptive_sheet.dart';

/// Every account on the platform, with the levers an operator has: block
/// (reversible), delete, and a wallet adjustment.
///
/// Delete really removes the row when the account has no order history. When
/// it does, `orders` references it with NO ACTION and removing it would take
/// the order ledger too — so the account is anonymised and locked out of
/// sign-in instead, and the snackbar says which of the two happened rather
/// than claiming a removal that did not occur.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key, this.embedded = false});

  /// True when a web sidebar is already drawing the shell around this screen
  /// (`_AdminWebShell`) — skips this widget's own [WebPageChrome]/[Scaffold]
  /// and returns just the search row + list.
  final bool embedded;

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  static const _pageSize = 40;

  final _repo = AdminRepository();
  final _scroll = ScrollController();
  final _users = <AdminUser>[];

  String _search = '';

  /// Null means "every role" / "any status". Both are sent to the query
  /// rather than applied to the page — see [AdminRepository.fetchUsers].
  String? _role;
  String? _status;

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
      final page = await _repo.fetchUsers(
        search: _search,
        role: _role,
        status: _status,
        limit: _pageSize,
      );
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
        role: _role,
        status: _status,
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

  /// Changing a filter restarts paging from zero — keeping the old offset
  /// would page a list that no longer exists.
  void _setRole(String? role) {
    setState(() => _role = role);
    _load();
  }

  void _setStatus(String? status) {
    setState(() => _status = status);
    _load();
  }

  bool get _hasFilters =>
      _role != null || _status != null || _search.isNotEmpty;

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
    final result = await showAdaptiveSheet<({double amount, String reason})>(
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
    final webWide = AppBreakpoints.isWebWide(context);

    final search = TextField(
      onChanged: _onSearch,
      decoration: InputDecoration(
        hintText: l10n.searchUsers,
        prefixIcon: const Icon(Icons.search),
      ),
    );

    final list = Builder(
      builder: (context) {
        if (_loading) return const LoadingView();
        if (_error != null) {
          return FailureView(error: _error!, onRetry: _reload);
        }
        if (_users.isEmpty) {
          // Distinguishes "nobody here" from "nobody matching", which are
          // different problems: one is an empty platform, the other a filter
          // the operator can undo — so say which, and offer the undo.
          return EmptyView(
            message: _hasFilters ? l10n.noUsersMatch : l10n.users,
            icon: Icons.people_outline,
          );
        }
        if (webWide) {
          return _UsersTable(
            users: _users,
            controller: _scroll,
            busyId: _busyId,
            canBlock: auth.can('users.block'),
            canDelete: auth.can('users.delete'),
            canAdjustWallet: auth.can('wallets.adjust'),
            onToggleBlock: _toggleBlock,
            onDelete: _delete,
            onAdjustWallet: _adjustWallet,
            loadingMore: _loadingMore,
            hasMore: _hasMore,
          );
        }
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: ResponsiveCardList(
            controller: _scroll,
            padding: webWide
                ? const EdgeInsets.only(bottom: AppSpace.xl)
                : EdgeInsets.fromLTRB(
                    AppSpace.gutter,
                    AppSpace.xs,
                    AppSpace.gutter,
                    AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
                  ),
            itemCount: _users.length,
            footer: PagingFooter(loading: _loadingMore, hasMore: _hasMore),
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
    );

    final filters = _FilterBar(
      role: _role,
      status: _status,
      onRole: _setRole,
      onStatus: _setStatus,
    );

    Widget webContent() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A search box has no reason to span a 1200px pane — a user is
            // typing a name into it, not writing a paragraph.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: search,
            ),
            const SizedBox(width: AppSpace.lg),
            Expanded(child: filters),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        Expanded(child: list),
      ],
    );

    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: webContent(),
      );
    }

    if (webWide) {
      return WebPageChrome(
        activeId: 'manage:/admin-app/users',
        sections: adminManageWebSections(context),
        pageTitle: l10n.users,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: webContent(),
        ),
      );
    }

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
            child: search,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter,
              0,
              AppSpace.gutter,
              AppSpace.sm,
            ),
            child: filters,
          ),
          Expanded(child: list),
        ],
      ),
    );
  }
}

/// Role and status, as two rows of chips.
///
/// Chips rather than dropdowns because the whole set is five and three items
/// — small enough that showing every option costs less than hiding them
/// behind a menu, and an operator can see what is filtered without opening
/// anything.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.role,
    required this.status,
    required this.onRole,
    required this.onStatus,
  });

  final String? role;
  final String? status;
  final ValueChanged<String?> onRole;
  final ValueChanged<String?> onStatus;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (value, label) in <(String?, String)>[
          (null, l10n.allRoles),
          ('customer', l10n.roleCustomer),
          ('vendor', l10n.roleVendor),
          ('driver', l10n.roleDriver),
          ('admin', l10n.roleAdmin),
        ])
          _Chip(
            label: label,
            selected: role == value,
            onTap: () => onRole(value),
          ),
        // A hairline between the two groups: without it the eight chips read
        // as one list of alternatives rather than two independent filters.
        Container(
          width: 1,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: AppColors.border,
        ),
        for (final (value, label) in <(String?, String)>[
          (null, l10n.allStatuses),
          ('active', l10n.statusActive),
          ('blocked', l10n.statusBlocked),
          ('closed', l10n.statusClosed),
        ])
          _Chip(
            label: label,
            selected: status == value,
            onTap: () => onStatus(value),
            tone: value == 'blocked' ? AppColors.dangerInk : null,
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.tone,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final ink = tone ?? AppColors.primary;
    return Material(
      color: selected ? ink.withValues(alpha: 0.10) : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
              color: selected ? ink : AppColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? ink : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Web/wide: one row per account.
///
/// A user is a genuinely tabular record — name, role, phone, joined, status —
/// so a table reads it far faster than a grid of cards, which is what this
/// screen used to be on desktop. Actions stay in the row: an operator
/// scanning for someone to block should not have to open anything to do it.
class _UsersTable extends StatelessWidget {
  const _UsersTable({
    required this.users,
    required this.controller,
    required this.busyId,
    required this.canBlock,
    required this.canDelete,
    required this.canAdjustWallet,
    required this.onToggleBlock,
    required this.onDelete,
    required this.onAdjustWallet,
    required this.loadingMore,
    required this.hasMore,
  });

  final List<AdminUser> users;
  final ScrollController controller;
  final String? busyId;
  final bool canBlock;
  final bool canDelete;
  final bool canAdjustWallet;
  final void Function(AdminUser) onToggleBlock;
  final void Function(AdminUser) onDelete;
  final void Function(AdminUser) onAdjustWallet;
  final bool loadingMore;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final columns = [
      WebTableColumn(label: l10n.userLabel, flex: 3),
      WebTableColumn(label: l10n.roleLabel, width: 110),
      WebTableColumn(label: l10n.phoneNumber, flex: 2),
      WebTableColumn(label: l10n.joinedLabel, width: 110),
      WebTableColumn(label: l10n.statusLabel, width: 96),
    ];

    return SingleChildScrollView(
      controller: controller,
      child: Column(
        children: [
          WebTable(
            columns: columns,
            trailingWidth: 132,
            rows: [
              for (final user in users)
                WebTableRow.aligned(
                  columns: columns,
                  trailingWidth: 132,
                  cells: [
                    _NameCell(user: user),
                    _RolePill(role: user.role),
                    Text(
                      user.phone ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.mono(12.5, color: AppColors.textSecondary),
                    ),
                    Text(
                      user.createdAt == null
                          ? '—'
                          : DateFormat('MMM d, y').format(user.createdAt!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                    _StatusPill(user: user),
                  ],
                  trailing: _RowActions(
                    user: user,
                    busy: busyId == user.id,
                    canBlock: canBlock,
                    canDelete: canDelete,
                    canAdjustWallet: canAdjustWallet,
                    onToggleBlock: () => onToggleBlock(user),
                    onDelete: () => onDelete(user),
                    onAdjustWallet: () => onAdjustWallet(user),
                  ),
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

class _NameCell extends StatelessWidget {
  const _NameCell({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    final initial = user.name.trim().isEmpty
        ? '?'
        : user.name.trim().characters.first.toUpperCase();
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.warmFill,
            shape: BoxShape.circle,
          ),
          child: Text(
            initial,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                user.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              // Only when there is one: an empty second line under every name
              // would push every row taller for the few that use it.
              if (user.isBlocked &&
                  (user.blockedReason?.trim().isNotEmpty ?? false))
                Text(
                  user.blockedReason!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.dangerInk,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (label, fill, ink) = switch (role) {
      'admin' => (l10n.roleAdmin, AppColors.warmFill, AppColors.primary),
      'vendor' => (
        l10n.roleVendor,
        AppColors.successFill,
        AppColors.successInk,
      ),
      'driver' => (l10n.roleDriver, AppColors.amberFill, AppColors.amberInk),
      _ => (l10n.roleCustomer, AppColors.neutralFill, AppColors.textSecondary),
    };
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SoftBadge(label: label, fill: fill, ink: ink),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (label, fill, ink) = user.isDeleted
        ? (l10n.statusClosed, AppColors.neutralFill, AppColors.textMuted)
        : user.isBlocked
        ? (l10n.statusBlocked, AppColors.dangerFill, AppColors.dangerInk)
        : (l10n.statusActive, AppColors.successFill, AppColors.successInk);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SoftBadge(label: label, fill: fill, ink: ink),
    );
  }
}

/// The same three levers the mobile card offers, as icon buttons.
///
/// Hidden rather than disabled when the permission is missing, matching the
/// card: the server refuses these too, and a row of buttons that always fail
/// is not a console.
class _RowActions extends StatelessWidget {
  const _RowActions({
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
  final bool canBlock;
  final bool canDelete;
  final bool canAdjustWallet;
  final VoidCallback onToggleBlock;
  final VoidCallback onDelete;
  final VoidCallback onAdjustWallet;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (busy) return const Center(child: ButtonSpinner(size: 16));
    // A closed account offers nothing to do, and an admin is exempt from both
    // levers server-side.
    if (user.isDeleted || user.isAdmin) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (canAdjustWallet)
          _IconAction(
            icon: Icons.account_balance_wallet_outlined,
            tooltip: l10n.adjustWallet,
            onTap: onAdjustWallet,
          ),
        if (canBlock)
          _IconAction(
            icon: user.isBlocked
                ? Icons.lock_open_outlined
                : Icons.block_outlined,
            tooltip: user.isBlocked ? l10n.unblockUser : l10n.blockUser,
            tone: user.isBlocked ? AppColors.successInk : AppColors.amberInk,
            onTap: onToggleBlock,
          ),
        if (canDelete)
          _IconAction(
            icon: Icons.person_remove_outlined,
            tooltip: l10n.deleteAccount,
            tone: AppColors.dangerInk,
            onTap: onDelete,
          ),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.tone,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        color: tone ?? AppColors.textMuted,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        padding: EdgeInsets.zero,
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
                        icon: const Icon(Icons.account_balance_wallet_outlined),
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
  String? _amountError;
  String? _reasonError;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _amountError = context.l10n.enterAValidPrice);
    } else {
      setState(() => _amountError = null);
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _reasonError = context.l10n.walletAdjustReasonRequired);
    } else {
      setState(() => _reasonError = null);
    }
    if (amount == null || amount <= 0 || _reason.text.trim().isEmpty) {
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
            decoration: InputDecoration(
              labelText: l10n.walletAdjustAmount,
              errorText: _amountError,
            ),
            onChanged: (_) {
              if (_amountError != null) setState(() => _amountError = null);
            },
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: _reason,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.walletAdjustReason,
              errorText: _reasonError,
            ),
            onChanged: (_) {
              if (_reasonError != null) setState(() => _reasonError = null);
            },
          ),
          const SizedBox(height: AppSpace.lg),
          FilledButton(onPressed: _submit, child: Text(l10n.save)),
        ],
      ),
    );
  }
}
