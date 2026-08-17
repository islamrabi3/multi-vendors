import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:image_picker/image_picker.dart';

import '../../../app/tokens.dart';
import '../../../core/widgets/web/web_auth_frame.dart';
import '../../../core/utils/platform_capabilities.dart';
import '../../../core/models/profile.dart';
import '../../../core/repositories/auth_repository.dart';
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

  XFile? _idFront;
  XFile? _idBack;
  XFile? _licenseFront;
  XFile? _licenseBack;

  DriverDocuments get _documents => DriverDocuments(
    idCardFront: _idFront,
    idCardBack: _idBack,
    licenseFront: _licenseFront,
    licenseBack: _licenseBack,
  );

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _pickDocument(ValueChanged<XFile> onPicked) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Identity photos come off a modern camera at several megabytes each,
      // and four of those on a phone connection is a signup people abandon.
      // Still far more than legible for reading an ID.
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked != null) onPicked(picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    // A driver whose documents are missing gets a pending account nobody can
    // approve, so the application stops here rather than in the review queue,
    // where it would sit as an unexplained rejection.
    if (_role == UserRole.driver && !_documents.isComplete) {
      showSnack(context, context.l10n.driverDocumentsIncomplete, error: true);
      return;
    }
    context.read<AuthCubit>().signUp(
      email: _email.text,
      password: _password.text,
      fullName: _name.text,
      phone: _phone.text,
      role: _role,
      documents: _role == UserRole.driver ? _documents : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final webWide = AppBreakpoints.isWebWide(context);
    final body = BlocListener<AuthCubit, AppAuthState>(
      listenWhen: (previous, current) =>
          previous.error != current.error || previous.info != current.info,
      listener: (context, state) {
        if (state.error != null) {
          showFailure(context, state.error!);
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
                // The brand panel beside this carries the heading on web;
                // printing it here too said the same thing twice.
                if (!webWide) ...[
                  Text(
                    context.l10n.createYournaccount,
                    style: AppType.display(30, color: AppColors.ink),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.howWillYouUseKitchenIn,
                    style: TextStyle(fontSize: 14, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 22),
                ],

                // Role selector cards
                _RoleCard(
                  emoji: '🍔',
                  title: context.l10n.orderFood,
                  subtitle: context.l10n.roleCustomerDesc,
                  selected: _role == UserRole.customer,
                  onTap: () => setState(() => _role = UserRole.customer),
                ),
                const SizedBox(height: 12),
                _RoleCard(
                  emoji: '🏪',
                  title: context.l10n.sellAsAVendor,
                  subtitle: context.l10n.roleVendorDesc,
                  selected: _role == UserRole.vendor,
                  onTap: () => setState(() => _role = UserRole.vendor),
                ),
                const SizedBox(height: 12),
                _RoleCard(
                  emoji: '🛵',
                  title: context.l10n.deliverOrders,
                  subtitle: context.l10n.roleDriverDesc,
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
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? context.l10n.required
                      : null,
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
                      ? context.l10n.enterAValidPhone
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
                      ? context.l10n.enterAValidEmail
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
                      ? context.l10n.passwordMinSixChars
                      : null,
                ),
                if (_role == UserRole.driver) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadii.xl),
                      border: Border.all(color: AppColors.border),
                      boxShadow: AppShadows.card,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.badge_rounded,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                context.l10n.driverDocumentsTitle,
                                style: AppType.heading(
                                  15,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.l10n.driverDocumentsSubtitle,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11.5,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),

                        Text(
                          '🪪 ${context.l10n.nationalIdSection}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _DocUploadButton(
                                label: context.l10n.idFront,
                                file: _idFront,
                                onTap: () => _pickDocument(
                                  (f) => setState(() => _idFront = f),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _DocUploadButton(
                                label: context.l10n.idBack,
                                file: _idBack,
                                onTap: () => _pickDocument(
                                  (f) => setState(() => _idBack = f),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        Text(
                          '📜 ${context.l10n.vehicleLicenseSection}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _DocUploadButton(
                                label: context.l10n.licenseFront,
                                file: _licenseFront,
                                onTap: () => _pickDocument(
                                  (f) => setState(() => _licenseFront = f),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _DocUploadButton(
                                label: context.l10n.licenseBack,
                                file: _licenseBack,
                                onTap: () => _pickDocument(
                                  (f) => setState(() => _licenseBack = f),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 30),

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
                // Identity providers carry no role, so the picked role is
                // claimed server-side on the first session.
                ...[
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      const Expanded(child: Divider(color: AppColors.border)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          context.l10n.or,
                          style: const TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider(color: AppColors.border)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  BlocBuilder<AuthCubit, AppAuthState>(
                    builder: (context, state) => Row(
                      children: [
                        // Apple only where it means something; see the
                        // login screen.
                        if (supportsAppleSignIn) ...[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: state.busy
                                  ? null
                                  : () => context
                                        .read<AuthCubit>()
                                        .signInWithApple(signupRole: _role),
                              icon: const Icon(Icons.apple, size: 20),
                              label: Text(context.l10n.apple),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                side: const BorderSide(color: AppColors.border),
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
                                      .signInWithGoogle(signupRole: _role),
                            icon: Text(
                              'G',
                              style: AppType.display(
                                18,
                                color: AppColors.primaryDark,
                              ),
                            ),
                            label: Text(context.l10n.google),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: AppColors.border),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const _TermsNotice(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );

    if (webWide) {
      // No AppBar on web — a lone back chevron floating over a 1400px window
      // is a phone affordance. The "already have an account" link at the foot
      // of the form is the way back, and the browser's own back button still
      // works.
      return WebAuthFrame(
        headline: context.l10n.createAccount,
        subhead: context.l10n.signupWebSubhead,
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: AppColors.ink,
            size: 20,
          ),
          onPressed: () => context.pop(),
        ),
      ),
      body: body,
    );
  }
}

/// Continuing is the acceptance, which is why this sits under every sign-up
/// path — password and both identity providers — rather than beside one button.
///
/// The two pages it links are fetched at read time, so amending them is an
/// admin edit rather than a store release.
class _TermsNotice extends StatelessWidget {
  const _TermsNotice();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const base = TextStyle(
      fontSize: 11.5,
      height: 1.5,
      color: AppColors.textMuted,
    );
    final link = base.copyWith(
      color: AppColors.primaryDark,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.primaryDark,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: '${l10n.bySigningUpYouAgree} '),
          TextSpan(
            text: l10n.termsAndConditions,
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => context.push('/terms'),
          ),
          TextSpan(text: ' ${l10n.and} '),
          TextSpan(
            text: l10n.privacyPolicy,
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => context.push('/privacy'),
          ),
        ],
      ),
      textAlign: TextAlign.center,
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
                color: selected ? AppColors.warmFill : AppColors.neutralFill,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
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
                  color: selected ? AppColors.primary : AppColors.borderStrong,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// One document slot: tap to pick, then a thumbnail of what was picked.
///
/// The preview is the point. A tick alone tells an applicant a file was
/// attached but not which one, and the failure this screen has to catch is a
/// photo of the wrong side, or of a thumb — the review queue would otherwise
/// catch it days later.
class _DocUploadButton extends StatefulWidget {
  const _DocUploadButton({
    required this.label,
    required this.file,
    required this.onTap,
  });

  final String label;
  final XFile? file;
  final VoidCallback onTap;

  @override
  State<_DocUploadButton> createState() => _DocUploadButtonState();
}

class _DocUploadButtonState extends State<_DocUploadButton> {
  Uint8List? _preview;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void didUpdateWidget(_DocUploadButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file?.path != widget.file?.path) _loadPreview();
  }

  /// Read once per pick, not per rebuild — this runs on the platform's file
  /// channel and the form rebuilds on every keystroke.
  Future<void> _loadPreview() async {
    final file = widget.file;
    if (file == null) {
      if (mounted) setState(() => _preview = null);
      return;
    }
    try {
      final bytes = await file.readAsBytes();
      if (mounted && widget.file?.path == file.path) {
        setState(() => _preview = bytes);
      }
    } catch (_) {
      // The tick still shows: the file is attached even if it will not render.
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = widget.file != null;
    return Semantics(
      button: true,
      label: widget.label,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 96,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: hasFile ? AppColors.successFill : AppColors.canvas,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasFile ? AppColors.success : AppColors.border,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_preview != null)
                Image.memory(_preview!, fit: BoxFit.cover)
              else
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      hasFile
                          ? Icons.check_circle_rounded
                          : Icons.add_a_photo_rounded,
                      size: 20,
                      color: hasFile ? AppColors.success : AppColors.primary,
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              // Over the thumbnail, so the slot stays identifiable once it is
              // filled — which is when knowing which one it is matters most.
              if (_preview != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    color: Colors.black.withValues(alpha: 0.55),
                    child: Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
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
