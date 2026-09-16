import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/tokens.dart';
import '../../../core/repositories/vendor_staff_repository.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart' show ButtonSpinner;

/// The store's own team: logins that take orders or edit the menu without
/// seeing what the store earns.
///
/// Only the owner reaches this screen, and only the owner's token can write
/// here — the database checks that on every call, so hiding the screen is a
/// courtesy rather than the control.
class VendorStaffScreen extends StatefulWidget {
  const VendorStaffScreen({super.key, required this.vendorId});

  final String vendorId;

  @override
  State<VendorStaffScreen> createState() => _VendorStaffScreenState();
}

class _VendorStaffScreenState extends State<VendorStaffScreen> {
  final _repository = VendorStaffRepository();

  List<VendorStaffMember>? _staff;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final staff = await _repository.fetchStaff(widget.vendorId);
      if (!mounted) return;
      setState(() {
        _staff = staff;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  String _permissionLabel(BuildContext context, String key) => switch (key) {
    'orders' => context.l10n.staffPermOrders,
    'menu' => context.l10n.staffPermMenu,
    'reviews' => context.l10n.staffPermReviews,
    'settings' => context.l10n.staffPermSettings,
    _ => key,
  };

  Future<void> _add() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
      ),
      builder: (_) => _StaffForm(repository: _repository),
    );
    if (created == true) _load();
  }

  Future<void> _editPermissions(VendorStaffMember member) async {
    final selected = {...member.permissions};
    final saved = await showFormSheet<bool>(
      context: context,
      title: member.name,
      subtitle: context.l10n.staffPermissionsHint,
      icon: Icons.badge_outlined,
      contentBuilder: (rebuild) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final key in VendorStaffRepository.permissionKeys)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: selected.contains(key),
              onChanged: (checked) {
                checked == true ? selected.add(key) : selected.remove(key);
                rebuild();
              },
              title: Text(_permissionLabel(context, key)),
            ),
        ],
      ),
      submitLabel: context.l10n.save,
      cancelLabel: context.l10n.cancel,
      onSubmit: (_) async {
        await _repository.setPermissions(member.userId, selected.toList());
        return true;
      },
    );
    if (saved == true) _load();
  }

  Future<void> _remove(VendorStaffMember member) async {
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: member.name,
      message: context.l10n.staffRemoveConfirm,
      confirmText: context.l10n.delete,
      cancelText: context.l10n.cancel,
      isDestructive: true,
      icon: Icons.person_remove_alt_1_rounded,
    );
    if (confirmed != true) return;
    try {
      await _repository.removeStaff(member.userId);
      await _load();
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final staff = _staff;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.staffTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(l10n.staffAdd),
      ),
      body: SafeArea(
        top: false,
        child: staff == null
            ? (_error != null
                  ? FailureView(error: _error!, onRetry: _load)
                  : const LoadingView())
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.gutter,
                    AppSpace.md,
                    AppSpace.gutter,
                    96,
                  ),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpace.md),
                      decoration: BoxDecoration(
                        color: AppColors.warmFill,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Text(
                        l10n.staffIntro,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpace.lg),
                    if (staff.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 60),
                        child: EmptyView(
                          message: l10n.staffEmpty,
                          icon: Icons.groups_outlined,
                        ),
                      )
                    else
                      for (final member in staff)
                        Container(
                          margin: const EdgeInsets.only(bottom: AppSpace.sm),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadii.lg),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: AppColors.warmFill,
                              child: Icon(
                                Icons.person_rounded,
                                color: AppColors.primary,
                              ),
                            ),
                            title: Text(
                              member.name.isEmpty
                                  ? l10n.staffTitle
                                  : member.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              member.permissions.isEmpty
                                  ? l10n.staffNoPermissions
                                  : member.permissions
                                        .map(
                                          (k) => _permissionLabel(context, k),
                                        )
                                        .join(' · '),
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: l10n.edit,
                                  onPressed: () => _editPermissions(member),
                                  icon: const Icon(
                                    Icons.tune_rounded,
                                    size: 20,
                                  ),
                                ),
                                IconButton(
                                  tooltip: l10n.delete,
                                  onPressed: () => _remove(member),
                                  icon: const Icon(
                                    Icons.person_remove_alt_1_outlined,
                                    size: 20,
                                    color: AppColors.dangerInk,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Creating a staff login: name, email, password, and what they may do.
class _StaffForm extends StatefulWidget {
  const _StaffForm({required this.repository});

  final VendorStaffRepository repository;

  @override
  State<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends State<_StaffForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _selected = <String>{'orders'};
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _generatePassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
    final random = Random.secure();
    setState(() {
      _password.text = List.generate(
        10,
        (_) => chars[random.nextInt(chars.length)],
      ).join();
    });
  }

  String _permissionLabel(String key) => switch (key) {
    'orders' => context.l10n.staffPermOrders,
    'menu' => context.l10n.staffPermMenu,
    'reviews' => context.l10n.staffPermReviews,
    'settings' => context.l10n.staffPermSettings,
    _ => key,
  };

  Future<void> _submit() async {
    final l10n = context.l10n;
    if (!_formKey.currentState!.validate()) return;
    if (_selected.isEmpty) {
      showSnack(context, l10n.staffPickOnePermission, error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.createStaff(
        email: _email.text,
        password: _password.text,
        fullName: _name.text,
        permissions: _selected.toList(),
      );
      if (!mounted) return;
      final credentials =
          '${l10n.email}: ${_email.text.trim().toLowerCase()}\n'
          '${l10n.password}: ${_password.text}';
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_rounded,
            color: AppColors.successInk,
            size: 36,
          ),
          title: Text(l10n.accountCreatedTitle),
          content: SelectableText(
            credentials,
            textDirection: TextDirection.ltr,
            style: AppType.mono(13.5, color: AppColors.ink),
          ),
          actions: [
            TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: credentials)),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text(l10n.copyLoginDetails),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.done),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showFailure(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpace.gutter,
          right: AppSpace.gutter,
          top: AppSpace.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpace.lg,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.staffAdd, style: AppType.heading(18)),
                const SizedBox(height: AppSpace.lg),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: l10n.fullName),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? l10n.required : null,
                ),
                const SizedBox(height: AppSpace.md),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  decoration: InputDecoration(labelText: l10n.email),
                  validator: (v) =>
                      (v == null ||
                          !RegExp(r'^\S+@\S+\.\S+$').hasMatch(v.trim()))
                      ? l10n.enterValidEmail
                      : null,
                ),
                const SizedBox(height: AppSpace.md),
                TextFormField(
                  controller: _password,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: l10n.password,
                    helperText: l10n.passwordMin8,
                    suffixIcon: IconButton(
                      tooltip: l10n.generatePassword,
                      onPressed: _generatePassword,
                      icon: const Icon(Icons.casino_outlined, size: 20),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.length < 8) ? l10n.passwordMin8 : null,
                ),
                const SizedBox(height: AppSpace.lg),
                Text(
                  l10n.staffPermissionsHint,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
                for (final key in VendorStaffRepository.permissionKeys)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _selected.contains(key),
                    onChanged: (checked) => setState(() {
                      checked == true
                          ? _selected.add(key)
                          : _selected.remove(key);
                    }),
                    title: Text(_permissionLabel(key)),
                  ),
                const SizedBox(height: AppSpace.md),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const ButtonSpinner(size: 18)
                      : Text(l10n.staffAdd),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
