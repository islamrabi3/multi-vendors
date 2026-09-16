import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/tokens.dart';
import '../../../core/errors/app_failure.dart' show UserMessage;
import '../../../core/supabase_client.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart' show ButtonSpinner;

/// Change the signed-in account's password. Every role reaches this from its
/// own settings, so it lives outside any shell at `/change-password`.
///
/// The current password is checked first: a phone left unlocked must not be
/// enough to lock the owner out of their own account. An account that signed
/// up with Google or Apple has no password yet, so it simply sets one.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  User? get _user => supabase.auth.currentUser;

  /// Whether the account signs in with an email and password at all.
  bool get _hasPassword =>
      _user?.identities?.any((i) => i.provider == 'email') ??
      (_user?.appMetadata['provider'] == 'email');

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    if (!_formKey.currentState!.validate()) return;
    final email = _user?.email;
    setState(() => _saving = true);
    try {
      if (_hasPassword && _next.text == _current.text) {
        throw UserMessage(l10n.newPasswordSameAsOld);
      }
      // Re-signing in with the current password is the check; it also makes
      // the session fresh, which Supabase wants before a password change.
      if (_hasPassword && email != null) {
        try {
          await supabase.auth.signInWithPassword(
            email: email,
            password: _current.text,
          );
        } on AuthException {
          throw UserMessage(l10n.currentPasswordWrong);
        }
      }
      await supabase.auth.updateUser(UserAttributes(password: _next.text));
      if (!mounted) return;
      showSnack(context, l10n.passwordChanged);
      context.canPop() ? context.pop() : context.go('/');
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showFailure(context, error);
      }
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    TextInputAction action = TextInputAction.next,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: _obscure,
      autocorrect: false,
      enableSuggestions: false,
      textDirection: TextDirection.ltr,
      textInputAction: action,
      onFieldSubmitted: action == TextInputAction.done
          ? (_) => _submit()
          : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
        suffixIcon: IconButton(
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 20,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.changePassword)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(AppSpace.gutter),
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.warmFill,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.key_rounded,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: AppSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _hasPassword
                                        ? l10n.changePassword
                                        : l10n.setAPassword,
                                    style: AppType.heading(16),
                                  ),
                                  if (_user?.email != null)
                                    Text(
                                      _user!.email!,
                                      textDirection: TextDirection.ltr,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpace.lg),
                        if (_hasPassword) ...[
                          _field(
                            controller: _current,
                            label: l10n.currentPassword,
                            validator: (v) =>
                                (v == null || v.isEmpty) ? l10n.required : null,
                          ),
                          const SizedBox(height: AppSpace.md),
                        ],
                        _field(
                          controller: _next,
                          label: l10n.newPassword,
                          validator: (v) => (v == null || v.length < 8)
                              ? l10n.passwordMin8
                              : null,
                        ),
                        const SizedBox(height: AppSpace.md),
                        _field(
                          controller: _confirm,
                          label: l10n.confirmNewPassword,
                          action: TextInputAction.done,
                          validator: (v) =>
                              v != _next.text ? l10n.passwordsDoNotMatch : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const ButtonSpinner(size: 18)
                        : Text(l10n.savePassword),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
