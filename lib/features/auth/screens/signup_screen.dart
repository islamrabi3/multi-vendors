import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/models/profile.dart';
import '../../../core/widgets/common.dart';
import '../auth_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class SignupScreen extends StatelessWidget {
  const SignupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SignupForm();
  }
}

class _SignupFormState extends State<SignupForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  UserRole _role = UserRole.customer;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.ink, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: BlocListener<AuthCubit, AppAuthState>(
        listenWhen: (previous, current) =>
            previous.error != current.error || previous.info != current.info,
        listener: (context, state) {
          if (state.error != null) {
            showSnack(context, readableError(state.error!), error: true);
          } else if (state.info != null) {
            showSnack(context, state.info!);
            context.go('/login');
          }
        },
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 8),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.l10n.createYournaccount,
                    style: AppType.display(30, color: AppColors.ink),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.howWillYouUseEaty,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Role selector cards
                  _RoleCard(
                    emoji: '🍔',
                    title: context.l10n.orderFood,
                    subtitle: 'Browse stores & get it delivered',
                    selected: _role == UserRole.customer,
                    onTap: () => setState(() => _role = UserRole.customer),
                  ),
                  const SizedBox(height: 12),
                  _RoleCard(
                    emoji: '🏪',
                    title: context.l10n.sellAsAVendor,
                    subtitle: 'Manage a store & menu',
                    selected: _role == UserRole.vendor,
                    onTap: () => setState(() => _role = UserRole.vendor),
                  ),
                  const SizedBox(height: 12),
                  _RoleCard(
                    emoji: '🛵',
                    title: context.l10n.deliverOrders,
                    subtitle: 'Earn on your schedule',
                    selected: _role == UserRole.driver,
                    onTap: () => setState(() => _role = UserRole.driver),
                  ),

                  const SizedBox(height: 22),

                  // Inputs
                  TextFormField(
                    controller: _name,
                    decoration: InputDecoration(
                      hintText: context.l10n.fullName,
                      fillColor: Colors.white,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 11),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: context.l10n.phoneNumber,
                      fillColor: Colors.white,
                    ),
                    validator: (v) => (v == null || v.trim().length < 8)
                        ? 'Enter a valid phone'
                        : null,
                  ),
                  const SizedBox(height: 11),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: context.l10n.nameemailcom,
                      fillColor: Colors.white,
                    ),
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'Enter a valid email'
                        : null,
                  ),
                  const SizedBox(height: 11),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: context.l10n.passwordMin6Chars,
                      fillColor: Colors.white,
                    ),
                    validator: (v) => (v == null || v.length < 6)
                        ? 'Min 6 characters'
                        : null,
                  ),
                  const SizedBox(height: 30),

                  BlocBuilder<AuthCubit, AppAuthState>(
                    builder: (context, state) => InkWell(
                      onTap: state.busy
                          ? null
                          : () {
                              if (_formKey.currentState!.validate()) {
                                context.read<AuthCubit>().signUp(
                                      email: _email.text,
                                      password: _password.text,
                                      fullName: _name.text,
                                      phone: _phone.text,
                                      role: _role,
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
                                context.l10n.continueText,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SignupForm extends StatefulWidget {
  const SignupForm({super.key});

  @override
  State<SignupForm> createState() => _SignupFormState();
}

class _RoleCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2.0 : 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                    spreadRadius: -4,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected ? AppColors.warmFill : const Color(0xFFF3EEE8),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 22),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: selected ? AppColors.primary : const Color(0xFFDDD4CB),
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(
                      Icons.check,
                      size: 14,
                      color: Colors.white,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
