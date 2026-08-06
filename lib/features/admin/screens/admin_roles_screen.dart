import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../app/tokens.dart';
import '../../../core/models/admin_role.dart';
import '../../../core/repositories/admin_roles_repository.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/responsive_list.dart';
import '../../auth/auth_cubit.dart';

/// Management roles, who holds them, and what has been done.
///
/// `role = 'admin'` used to be all-or-nothing: every admin could block any
/// user, refund any order, and set any store's commission. This is where that
/// gets narrowed — and the audit tab is the other half, because a permission
/// system nobody can review is only half a control.
class AdminRolesScreen extends StatefulWidget {
  const AdminRolesScreen({super.key});

  @override
  State<AdminRolesScreen> createState() => _AdminRolesScreenState();
}

class _AdminRolesScreenState extends State<AdminRolesScreen> {
  final _repo = AdminRolesRepository();

  late Future<({List<AdminRole> roles, List<StaffMember> staff})> _future =
      _load();

  Future<({List<AdminRole> roles, List<StaffMember> staff})> _load() async {
    final results = await Future.wait([_repo.fetchRoles(), _repo.fetchStaff()]);
    return (
      roles: results[0] as List<AdminRole>,
      staff: results[1] as List<StaffMember>,
    );
  }

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _editRole(AdminRole? role) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RoleEditor(role: role, repo: _repo),
    );
    if (saved != true || !mounted) return;
    _reload();
    showSnack(context, context.l10n.roleSaved);
  }

  Future<void> _deleteRole(AdminRole role) async {
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: role.name,
      message: context.l10n.deleteRoleConfirm,
      confirmText: context.l10n.delete,
      cancelText: context.l10n.cancel,
    );
    if (confirmed != true) return;
    try {
      await _repo.deleteRole(role.id);
      if (!mounted) return;
      _reload();
      showSnack(context, context.l10n.roleDeleted);
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  /// Two ways in: make a login for somebody who has none, or promote an
  /// account that already exists. Both end at the same place — an admin
  /// profile holding a role — so they are offered together.
  Future<void> _addStaff() async {
    final roles = await _repo.fetchRoles().catchError((_) => <AdminRole>[]);
    if (!mounted) return;
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddStaffSheet(repo: _repo, roles: roles),
    );
    if (added == true && mounted) _reload();
  }

  /// Demotes somebody back to a customer. Their orders and history stay
  /// theirs; only admin access goes.
  Future<void> _revoke(StaffMember member) async {
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: member.name.isEmpty ? (member.email ?? '') : member.name,
      message: context.l10n.removeFromStaffConfirm,
      confirmText: context.l10n.removeFromStaff,
      cancelText: context.l10n.cancel,
    );
    if (confirmed != true) return;
    try {
      final restored = await _repo.revokeStaff(member.id);
      if (!mounted) return;
      // Says what they went back to, because for a store owner it is not
      // "customer" and the difference matters.
      showSnack(context, context.l10n.staffRestoredTo(restored));
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      // Always: a write that fails partway still leaves the server ahead of
      // this screen, and a stale list is how somebody removes the same person
      // twice.
      if (mounted) _reload();
    }
  }

  /// null [roleId] hands somebody full access, so it is offered last and
  /// labelled as what it is.
  Future<void> _assign(String userId, List<AdminRole> roles) async {
    final chosen = await showModalBottomSheet<({String? id, bool ok})>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.xl,
                0,
                AppSpace.xl,
                AppSpace.md,
              ),
              child: Text(context.l10n.assignRole, style: AppType.heading(17)),
            ),
            for (final role in roles)
              ListTile(
                title: Text(role.name),
                subtitle: Text(
                  context.l10n.permissionsCount(role.permissions.length),
                ),
                onTap: () =>
                    Navigator.pop(sheetContext, (id: role.id, ok: true)),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.shield_outlined,
                color: AppColors.dangerInk,
              ),
              title: Text(context.l10n.unrestricted),
              subtitle: Text(context.l10n.unrestrictedDesc),
              onTap: () => Navigator.pop(sheetContext, (id: null, ok: true)),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    try {
      await _repo.assignRole(userId, chosen.id);
      if (!mounted) return;
      _reload();
      showSnack(context, context.l10n.roleAssigned);
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // The screen is itself behind a permission: an admin who cannot manage
    // staff has no business seeing who else holds what.
    final canManage = context.select(
      (AuthCubit c) => c.state.can('staff.manage'),
    );

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          title: Text(l10n.managementRoles),
          actions: [
            if (canManage)
              IconButton(
                tooltip: l10n.newRole,
                onPressed: () => _editRole(null),
                icon: const Icon(Icons.add_moderator_outlined),
              ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.managementRoles),
              Tab(text: l10n.staff),
              Tab(text: l10n.auditTrail),
            ],
          ),
        ),
        floatingActionButton: canManage
            ? FloatingActionButton.extended(
                onPressed: _addStaff,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text(l10n.addStaff),
              )
            : null,
        body: FutureBuilder(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const LoadingView();
            }
            if (snap.hasError) {
              return FailureView(error: snap.error!, onRetry: _reload);
            }
            final data = snap.data!;
            return TabBarView(
              children: [
                _RolesTab(
                  roles: data.roles,
                  canManage: canManage,
                  onEdit: _editRole,
                  onDelete: _deleteRole,
                ),
                _StaffTab(
                  staff: data.staff,
                  roles: data.roles,
                  canManage: canManage,
                  onAssign: (userId) => _assign(userId, data.roles),
                  onRevoke: _revoke,
                ),
                const _AuditTab(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RolesTab extends StatelessWidget {
  const _RolesTab({
    required this.roles,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  final List<AdminRole> roles;
  final bool canManage;
  final ValueChanged<AdminRole?> onEdit;
  final ValueChanged<AdminRole> onDelete;

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    if (roles.isEmpty) {
      return EmptyView(
        message: context.l10n.noStaffYet,
        icon: Icons.shield_outlined,
      );
    }
    return ResponsiveCardList(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.lg,
        96,
      ),
      itemCount: roles.length,
      itemBuilder: (context, i) {
        final role = roles[i];
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: ListTile(
            title: Text(
              role.displayName(language),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              context.l10n.permissionsCount(role.permissions.length),
            ),
            trailing: canManage
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 19),
                        onPressed: () => onEdit(role),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 19,
                          color: AppColors.dangerInk,
                        ),
                        onPressed: () => onDelete(role),
                      ),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _StaffTab extends StatelessWidget {
  const _StaffTab({
    required this.staff,
    required this.roles,
    required this.canManage,
    required this.onAssign,
    required this.onRevoke,
  });

  final List<StaffMember> staff;
  final List<AdminRole> roles;
  final bool canManage;
  final ValueChanged<String> onAssign;
  final ValueChanged<StaffMember> onRevoke;

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    final me = context.select((AuthCubit c) => c.state.profile?.id);
    if (staff.isEmpty) {
      return EmptyView(
        message: context.l10n.noStaffYet,
        icon: Icons.badge_outlined,
      );
    }
    return ResponsiveCardList(
      padding: const EdgeInsets.all(AppSpace.lg),
      itemCount: staff.length,
      // Staff cards carry an email and sometimes a conflict warning, so they
      // need more room than a role card before they will split.
      itemExtent: 520,
      itemBuilder: (context, i) {
        final member = staff[i];
        final role = roles.where((r) => r.id == member.roleId).firstOrNull;
        final isMe = member.id == me;
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: role == null
                  ? AppColors.dangerFill
                  : AppColors.warmFill,
              child: Icon(
                role == null ? Icons.shield_outlined : Icons.badge_outlined,
                size: 19,
                color: role == null
                    ? AppColors.dangerInk
                    : AppColors.primaryDark,
              ),
            ),
            title: Text(
              member.name.isEmpty ? '—' : member.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (member.email != null)
                  Text(
                    member.email!,
                    style: AppType.mono(11.5, color: AppColors.textFaint),
                  ),
                Text(
                  role?.displayName(language) ?? context.l10n.unrestricted,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: role == null
                        ? AppColors.dangerInk
                        : AppColors.textMuted,
                  ),
                ),
                // A store owner or driver holding admin rights can approve,
                // price or promote themselves. New grants are refused; one
                // made before that rule existed needs to be visible.
                if (member.hasConflict) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      SoftBadge(
                        label: member.ownsVendor
                            ? context.l10n.ownsStore
                            : context.l10n.isDriverAccount,
                        fill: AppColors.dangerFill,
                        ink: AppColors.dangerInk,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.conflictWarning,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.dangerInk,
                    ),
                  ),
                ],
              ],
            ),
            isThreeLine: member.hasConflict,
            // Changing your own role is refused by the server too — it is how
            // a restricted admin would promote themselves, and how the last
            // unrestricted one would lock everybody out.
            trailing: canManage && !isMe
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => onAssign(member.id),
                        child: Text(context.l10n.assignRole),
                      ),
                      IconButton(
                        tooltip: context.l10n.removeFromStaff,
                        onPressed: () => onRevoke(member),
                        icon: const Icon(
                          Icons.person_remove_outlined,
                          size: 19,
                          color: AppColors.dangerInk,
                        ),
                      ),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }
}

/// Who did what, newest first.
class _AuditTab extends StatefulWidget {
  const _AuditTab();

  @override
  State<_AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<_AuditTab> {
  final _repo = AdminRolesRepository();
  late Future<List<AdminAuditEntry>> _future = _repo.fetchAuditLog();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AdminAuditEntry>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const LoadingView();
        }
        if (snap.hasError) {
          return FailureView(
            error: snap.error!,
            onRetry: () => setState(() {
              _future = _repo.fetchAuditLog();
            }),
          );
        }
        final entries = snap.data ?? const <AdminAuditEntry>[];
        if (entries.isEmpty) {
          return EmptyView(
            message: context.l10n.noAuditYet,
            icon: Icons.history_rounded,
          );
        }
        return RefreshIndicator(
          onRefresh: () async => setState(() {
            _future = _repo.fetchAuditLog();
          }),
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpace.lg),
            itemCount: entries.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: AppColors.borderSoft),
            itemBuilder: (context, i) {
              final entry = entries[i];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  entry.action,
                  style: AppType.mono(13, color: AppColors.ink),
                ),
                subtitle: Text(
                  [
                    entry.actorName ?? '—',
                    DateFormat.yMMMd().add_jm().format(entry.createdAt),
                    if (entry.detail.isNotEmpty) entry.detail.toString(),
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Create or edit a role: a name and a set of ticks.
class _RoleEditor extends StatefulWidget {
  const _RoleEditor({required this.role, required this.repo});

  final AdminRole? role;
  final AdminRolesRepository repo;

  @override
  State<_RoleEditor> createState() => _RoleEditorState();
}

class _RoleEditorState extends State<_RoleEditor> {
  late final _name = TextEditingController(text: widget.role?.name);
  late final _nameAr = TextEditingController(text: widget.role?.nameAr);
  late final Set<String> _selected = {...?widget.role?.permissions};
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _nameAr.dispose();
    super.dispose();
  }

  String _groupLabel(BuildContext context, String group) => switch (group) {
    'orders' => context.l10n.permGroupOrders,
    'vendors' => context.l10n.permGroupVendors,
    'catalogue' => context.l10n.permGroupCatalogue,
    'drivers' => context.l10n.permGroupDrivers,
    'users' => context.l10n.permGroupUsers,
    'support' => context.l10n.permGroupSupport,
    _ => context.l10n.permGroupFinance,
  };

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      if (widget.role == null) {
        await widget.repo.createRole(
          name: _name.text,
          nameAr: _nameAr.text,
          permissions: _selected.toList(),
        );
      } else {
        await widget.repo.updateRole(
          widget.role!.id,
          name: _name.text,
          nameAr: _nameAr.text,
          permissions: _selected.toList(),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
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
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.role == null ? l10n.newRole : l10n.editRole,
              style: AppType.heading(18),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: l10n.roleName),
            ),
            const SizedBox(height: AppSpace.sm),
            TextField(
              controller: _nameAr,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(labelText: l10n.roleNameArabic),
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              l10n.permissions,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final group in AdminPermission.groups) ...[
                    Padding(
                      padding: const EdgeInsets.only(
                        top: AppSpace.md,
                        bottom: 4,
                      ),
                      child: Text(
                        _groupLabel(context, group).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: AppColors.textFaint,
                        ),
                      ),
                    ),
                    for (final permission in AdminPermission.all.where(
                      (p) => p.group == group,
                    ))
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: _selected.contains(permission.key),
                        // The key itself is the label: these are read by
                        // operators who also read the audit trail, where the
                        // same strings appear.
                        title: Text(
                          permission.key,
                          style: AppType.mono(12.5, color: AppColors.ink),
                        ),
                        onChanged: (on) => setState(
                          () => on == true
                              ? _selected.add(permission.key)
                              : _selected.remove(permission.key),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }
}

/// Adding somebody to the staff.
///
/// Creating a login needs the Auth admin API, so it goes through an edge
/// function; promoting an existing account is an RPC. Both are restricted to
/// an admin with no role — creating admins is how a limited account would
/// escalate itself.
class _AddStaffSheet extends StatefulWidget {
  const _AddStaffSheet({required this.repo, required this.roles});

  final AdminRolesRepository repo;
  final List<AdminRole> roles;

  @override
  State<_AddStaffSheet> createState() => _AddStaffSheetState();
}

class _AddStaffSheetState extends State<_AddStaffSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _search = TextEditingController();

  String? _roleId;
  List<StaffCandidate> _results = const [];
  bool _searching = false;
  bool _saving = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  bool get _canCreate =>
      _email.text.contains('@') &&
      _password.text.length >= 8 &&
      _name.text.trim().isNotEmpty;

  Future<void> _runSearch(String query) async {
    if (query.trim().length < 3) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await widget.repo.searchUsers(query);
      if (mounted) setState(() => _results = results);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _create() async {
    final messenger = ScaffoldMessenger.of(context);
    final done = context.l10n.staffCreated;
    setState(() => _saving = true);
    try {
      await widget.repo.createStaff(
        email: _email.text,
        password: _password.text,
        fullName: _name.text,
        roleId: _roleId,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showFailure(context, error);
    }
  }

  Future<void> _promote(StaffCandidate candidate) async {
    final messenger = ScaffoldMessenger.of(context);
    final done = context.l10n.staffPromoted;
    setState(() => _saving = true);
    try {
      await widget.repo.grantStaff(candidate.id, roleId: _roleId);
      if (!mounted) return;
      Navigator.pop(context, true);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showFailure(context, error);
    }
  }

  /// Shared by both tabs: which role the new member starts with. Null is
  /// unrestricted, so it is spelled out rather than left as a blank default.
  Widget _rolePicker(BuildContext context) => DropdownButtonFormField<String?>(
    initialValue: _roleId,
    isExpanded: true,
    decoration: InputDecoration(labelText: context.l10n.roleForNewStaff),
    items: [
      DropdownMenuItem(value: null, child: Text(context.l10n.ownerFullAccess)),
      for (final role in widget.roles)
        DropdownMenuItem(value: role.id, child: Text(role.name)),
    ],
    onChanged: (value) => setState(() => _roleId = value),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
                child: Text(l10n.addStaff, style: AppType.heading(18)),
              ),
              TabBar(
                tabs: [
                  Tab(text: l10n.createNewLogin),
                  Tab(text: l10n.promoteExisting),
                ],
              ),
              Flexible(
                child: TabBarView(
                  children: [
                    // --- new login ---
                    ListView(
                      padding: const EdgeInsets.all(AppSpace.xl),
                      children: [
                        Text(
                          l10n.createNewLoginDesc,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpace.md),
                        TextField(
                          controller: _name,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(labelText: l10n.fullName),
                        ),
                        const SizedBox(height: AppSpace.sm),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: l10n.emailAddress,
                          ),
                        ),
                        const SizedBox(height: AppSpace.sm),
                        TextField(
                          controller: _password,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: l10n.password,
                            helperText: l10n.passwordMin,
                          ),
                        ),
                        const SizedBox(height: AppSpace.md),
                        _rolePicker(context),
                        const SizedBox(height: AppSpace.lg),
                        FilledButton(
                          onPressed: _saving || !_canCreate ? null : _create,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(l10n.addStaff),
                        ),
                      ],
                    ),

                    // --- promote existing ---
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpace.xl,
                            AppSpace.lg,
                            AppSpace.xl,
                            0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.promoteExistingDesc,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: AppSpace.md),
                              TextField(
                                controller: _search,
                                onChanged: _runSearch,
                                decoration: InputDecoration(
                                  hintText: l10n.searchUsersHint,
                                  prefixIcon: const Icon(Icons.search_rounded),
                                ),
                              ),
                              const SizedBox(height: AppSpace.sm),
                              _rolePicker(context),
                            ],
                          ),
                        ),
                        Flexible(
                          child: _searching
                              ? const Padding(
                                  padding: EdgeInsets.all(AppSpace.xl),
                                  child: LoadingView(),
                                )
                              : _results.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(AppSpace.xl),
                                  child: Text(
                                    _search.text.trim().length < 3
                                        ? l10n.searchMinChars
                                        : l10n.noUsersFound,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpace.md,
                                  ),
                                  itemCount: _results.length,
                                  itemBuilder: (context, i) {
                                    final candidate = _results[i];
                                    return ListTile(
                                      title: Text(
                                        candidate.name.isEmpty
                                            ? (candidate.email ?? '—')
                                            : candidate.name,
                                      ),
                                      subtitle: Text(
                                        [
                                          candidate.email,
                                          candidate.phone,
                                          candidate.role,
                                        ].whereType<String>().join(' · '),
                                        style: const TextStyle(fontSize: 11.5),
                                      ),
                                      trailing: candidate.isAlreadyStaff
                                          ? Text(
                                              l10n.alreadyStaff,
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                color: AppColors.textFaint,
                                              ),
                                            )
                                          : candidate.isConflicted
                                          ? Text(
                                              candidate.role == 'vendor'
                                                  ? l10n.ownsStore
                                                  : l10n.isDriverAccount,
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                color: AppColors.dangerInk,
                                              ),
                                            )
                                          : TextButton(
                                              onPressed: _saving
                                                  ? null
                                                  : () => _promote(candidate),
                                              child: Text(l10n.addStaff),
                                            ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
