import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:multi_vendor/core/errors/app_failure.dart'
    show AppFailure, UserMessage;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/utils/email.dart';
import '../../../core/widgets/web/web_auth_frame.dart';
import '../../../core/utils/platform_capabilities.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../core/widgets/common.dart';
import '../auth_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _resetEmail = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _resetEmail.dispose();
    super.dispose();
  }

  /// Collects an address and fires the reset email. Always shows the same
  /// confirmation regardless of whether the address has an account — see
  /// [AuthRepository.sendPasswordResetEmail] for why.
  Future<void> _forgotPassword() async {
    final l10n = context.l10n;
    _resetEmail.text = _email.text.trim();

    final sent = await showFormDialog<bool>(
      context: context,
      title: l10n.resetPasswordTitle,
      subtitle: l10n.resetPasswordSubtitle,
      icon: Icons.lock_reset_rounded,
      contentBuilder: (_) => TextField(
        controller: _resetEmail,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
          labelText: l10n.email,
          hintText: l10n.saraemailcom,
        ),
      ),
      submitLabel: l10n.sendResetLink,
      cancelLabel: l10n.cancel,
      onSubmit: (_) async {
        final email = _resetEmail.text.trim();
        if (!isValidEmail(email)) throw UserMessage(l10n.enterValidEmail);
        await context.read<AuthCubit>().sendPasswordReset(email);
        return true;
      },
    );

    if (sent == true && mounted) {
      // The email carries both a link and a code. The code is the one that
      // works everywhere — another device, a phone without the app's link
      // set up — so it is asked for right here.
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => BlocProvider.value(
          value: context.read<AuthCubit>(),
          child: _ResetCodeDialog(email: _resetEmail.text.trim()),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final webWide = AppBreakpoints.isWebWide(context);
    final body = BlocListener<AuthCubit, AppAuthState>(
      listenWhen: (previous, current) =>
          (previous.error != current.error && current.error != null) ||
          (previous.status != AuthStatus.authenticated &&
              current.status == AuthStatus.authenticated),
      listener: (context, state) {
        // Signed in: the password has done its job and is not kept, so
        // nothing is left in the field if this screen is ever shown again.
        if (state.status == AuthStatus.authenticated) {
          _password.clear();
          return;
        }
        showFailure(context, state.error!);
      },
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // On web the brand panel beside this already shows the
                  // lockup and the welcome, so repeating them here printed
                  // the same three lines twice on one screen.
                  if (!webWide) ...[
                    // Logo lockup — the mark and the wordmark, drawn from the
                    // one definition in `brand_logo.dart` so the arch here and
                    // the arch on the splash cannot drift apart.
                    const Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: KitchenInLockup(markSize: 46, fontSize: 30),
                    ),
                    const SizedBox(height: 40),
                    Text(
                      context.l10n.welcomeBack,
                      style: AppType.display(32, color: AppColors.ink),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.logInToPickUpWhereYouLeftOff,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],

                  // Email Field
                  Text(
                    context.l10n.emailOrUsername,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 7),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: InputDecoration(
                      hintText: context.l10n.emailOrUsernameHint,
                      fillColor: Colors.white,
                    ),
                    // Either form is fine; the repository swaps a username
                    // for its email before the password is sent.
                    validator: (v) => (v == null || v.trim().length < 3)
                        ? context.l10n.enterValidEmail
                        : null,
                  ),
                  const SizedBox(height: 13),

                  // Password Field
                  Text(
                    context.l10n.password,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 7),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscurePassword,
                    enableSuggestions: false,
                    autocorrect: false,
                    style: const TextStyle(fontSize: 18, letterSpacing: 1.5),
                    decoration: InputDecoration(
                      // Words, not a row of dots: dots in an empty field
                      // read as a password the app had remembered.
                      hintText: context.l10n.passwordHint,
                      hintStyle: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textFaint,
                      ),
                      fillColor: Colors.white,
                      // An icon reads at a glance in either language; the old
                      // "Show"/"Hide" button was a literal English word baked
                      // into the widget tree — never translated, regardless of
                      // the app's language.
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        tooltip: _obscurePassword
                            ? context.l10n.showPassword
                            : context.l10n.hidePassword,
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 6)
                        ? context.l10n.passwordTooShort
                        : null,
                  ),

                  // Forgot Password
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _forgotPassword,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        context.l10n.forgotPassword,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),

                  // Log In Button
                  BlocBuilder<AuthCubit, AppAuthState>(
                    builder: (context, state) => InkWell(
                      onTap: state.busy
                          ? null
                          : () {
                              if (_formKey.currentState!.validate()) {
                                context.read<AuthCubit>().signIn(
                                  _email.text,
                                  _password.text,
                                );
                              }
                            },
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
                                context.l10n.logIn,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),

                  // Or Separator
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      Expanded(child: Divider(color: AppColors.border)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          context.l10n.or,
                          style: TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: AppColors.border)),
                    ],
                  ),
                  const SizedBox(height: 26),

                  // Social Logins
                  BlocBuilder<AuthCubit, AppAuthState>(
                    builder: (context, state) {
                      return Row(
                        children: [
                          // Apple only where it means something. On Android
                          // it drops into a web flow for an Apple ID most
                          // users do not have.
                          if (supportsAppleSignIn) ...[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: state.busy
                                    ? null
                                    : () => context
                                          .read<AuthCubit>()
                                          .signInWithApple(),
                                icon: const Icon(Icons.apple, size: 20),
                                label: Text(context.l10n.apple),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  side: BorderSide(color: AppColors.border),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: state.busy
                                  ? null
                                  : () => context
                                        .read<AuthCubit>()
                                        .signInWithGoogle(),
                              icon: Text(
                                'G',
                                style: AppType.display(
                                  18,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                              label: Text(context.l10n.google),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                side: BorderSide(color: AppColors.border),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 40),

                  // Footer Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        context.l10n.newHere,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textMuted,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => context.push('/signup'),
                        child: Text(
                          context.l10n.createAccount,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // The brand panel carries the welcome on web, so the form's own heading
    // would say it twice; the frame gets the words and the form keeps its
    // fields.
    if (webWide) {
      return WebAuthFrame(
        headline: context.l10n.welcomeBack,
        subhead: context.l10n.logInToPickUpWhereYouLeftOff,
        child: body,
      );
    }

    return Scaffold(backgroundColor: AppColors.canvas, body: body);
  }
}

/// Step two of a password reset: the code from the email. A correct code
/// signs in with a recovery session, and the router takes it from there to
/// the new-password screen.
class _ResetCodeDialog extends StatefulWidget {
  const _ResetCodeDialog({required this.email});

  final String email;

  @override
  State<_ResetCodeDialog> createState() => _ResetCodeDialogState();
}

class _ResetCodeDialogState extends State<_ResetCodeDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  int _cooldown = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  bool get _complete => _code.text.trim().length >= 6;

  Future<void> _verify() async {
    if (!_complete || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthCubit>().verifyRecoveryCode(
        widget.email,
        _code.text,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppFailure.from(error).message(context.l10n);
      });
    }
  }

  Future<void> _resend() async {
    setState(() => _error = null);
    try {
      await context.read<AuthCubit>().sendPasswordReset(widget.email);
      if (!mounted) return;
      _startCooldown();
      showSnack(context, context.l10n.resetCodeResent);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = AppFailure.from(error).message(context.l10n));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      icon: const Icon(Icons.mark_email_read_rounded, color: AppColors.primary),
      title: Text(l10n.enterResetCodeTitle),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.enterResetCodeBody(widget.email),
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _verify(),
              style: AppType.mono(24, color: AppColors.ink),
              decoration: InputDecoration(
                counterText: '',
                hintText: '••••••',
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: _cooldown > 0 || _busy ? null : _resend,
                child: Text(
                  _cooldown > 0
                      ? l10n.resendCodeIn(_cooldown)
                      : l10n.resendCode,
                ),
              ),
            ),
            Text(
              l10n.resetLinkAlsoWorks,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _complete && !_busy ? _verify : null,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(l10n.verifyCode),
        ),
      ],
    );
  }
}
