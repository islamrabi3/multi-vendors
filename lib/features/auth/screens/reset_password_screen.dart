import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/tokens.dart';
import '../../../core/widgets/web/web_auth_frame.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../core/widgets/common.dart';
import '../auth_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// Where a password-reset email link lands.
///
/// Only ever reached through `AppAuthState.passwordRecovery` — see the router
/// — so there is no "cancel" here: the recovery session this screen is
/// standing on is not useful for anything else, and the only way out is
/// setting a password.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AuthCubit>().setNewPassword(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final webWide = AppBreakpoints.isWebWide(context);

    final body = BlocListener<AuthCubit, AppAuthState>(
      listenWhen: (previous, current) =>
          previous.error != current.error && current.error != null,
      listener: (context, state) => showFailure(context, state.error!),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!webWide) ...[
                    const Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: KitchenInLockup(markSize: 46, fontSize: 30),
                    ),
                    const SizedBox(height: 40),
                    Text(
                      l10n.setNewPasswordTitle,
                      style: AppType.display(28, color: AppColors.ink),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.setNewPasswordSubtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                  Text(
                    l10n.newPassword,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 7),
                  TextFormField(
                    controller: _password,
                    autofocus: true,
                    obscureText: _obscure,
                    style: const TextStyle(fontSize: 18, letterSpacing: 1.5),
                    decoration: InputDecoration(
                      fillColor: Colors.white,
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        tooltip: _obscure
                            ? l10n.showPassword
                            : l10n.hidePassword,
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 6)
                        ? l10n.passwordTooShort
                        : null,
                  ),
                  const SizedBox(height: 13),
                  Text(
                    l10n.confirmNewPassword,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 7),
                  TextFormField(
                    controller: _confirm,
                    obscureText: _obscure,
                    style: const TextStyle(fontSize: 18, letterSpacing: 1.5),
                    decoration: const InputDecoration(fillColor: Colors.white),
                    onFieldSubmitted: (_) => _submit(),
                    validator: (v) => v != _password.text
                        ? l10n.passwordsDoNotMatch
                        : null,
                  ),
                  const SizedBox(height: 26),
                  BlocBuilder<AuthCubit, AppAuthState>(
                    builder: (context, state) => InkWell(
                      onTap: state.busy ? null : _submit,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        height: 54,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: AppShadows.primaryGlow,
                        ),
                        child: state.busy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                l10n.setNewPasswordAction,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (webWide) {
      return WebAuthFrame(
        headline: l10n.setNewPasswordTitle,
        subhead: l10n.setNewPasswordSubtitle,
        child: body,
      );
    }
    return Scaffold(backgroundColor: AppColors.canvas, body: body);
  }
}
