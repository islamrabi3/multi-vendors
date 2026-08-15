import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/widgets/web/web_auth_frame.dart';
import '../../../core/utils/platform_capabilities.dart';
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
  bool _obscurePassword = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  // Logo lockup — the mark and the wordmark, drawn from the
                  // one definition in `brand_logo.dart` so the arch here and
                  // the arch on the splash cannot drift apart.
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: KitchenInLockup(markSize: 46, fontSize: 30),
                  ),
                  const SizedBox(height: 40),

                  // Welcome Text
                  Text(
                    context.l10n.welcomeBack,
                    style: AppType.display(32, color: AppColors.ink),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.logInToPickUpWhereYouLeftOff,
                    style: TextStyle(fontSize: 14, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 30),

                  // Email Field
                  Text(
                    context.l10n.email,
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
                    decoration: InputDecoration(
                      hintText: context.l10n.saraemailcom,
                      fillColor: Colors.white,
                    ),
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'Enter a valid email'
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
                    style: const TextStyle(fontSize: 18, letterSpacing: 1.5),
                    decoration: InputDecoration(
                      hintText: context.l10n.emptyString,
                      hintStyle: const TextStyle(letterSpacing: 1.5),
                      fillColor: Colors.white,
                      suffixIcon: TextButton(
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        child: Text(
                          _obscurePassword ? 'Show' : 'Hide',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.length < 6) ? 'Min 6 characters' : null,
                  ),

                  // Forgot Password
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {},
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
