import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/tokens.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart' show ButtonSpinner;
import '../../../core/widgets/web/web_auth_frame.dart';
import '../auth_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// Asked once, after a social sign-up that carried no phone number.
///
/// Google and Apple hand back a name and an email and nothing else, so an
/// OAuth account reached the app with no way to be reached back. On a
/// delivery platform that is not a missing field, it is an order that cannot
/// be rescued when the address is wrong — for the customer, the store and the
/// rider alike.
///
/// There is no skip, for the same reason the role picker has none. Admins
/// never arrive here at all; see `AppAuthState.needsPhone`.
class PhoneCaptureScreen extends StatefulWidget {
  const PhoneCaptureScreen({super.key});

  @override
  State<PhoneCaptureScreen> createState() => _PhoneCaptureScreenState();
}

class _PhoneCaptureScreenState extends State<PhoneCaptureScreen> {
  final _phone = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final auth = context.read<AuthCubit>();
    // The name is already on the profile from the provider; sending it back
    // unchanged keeps this to the one field being asked for.
    final ok = await auth.updateProfile(
      fullName: auth.state.profile?.fullName ?? '',
      phone: _phone.text.trim(),
    );
    if (!ok || !mounted) return;
    // No navigation: the profile now carries a phone, `needsPhone` goes
    // false, and the router's redirect moves this on by itself.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final busy = context.select((AuthCubit c) => c.state.busy);

    final form = SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: KitchenInMark(size: 52)),
            const SizedBox(height: AppSpace.xl),
            Text(
              l10n.addYourPhoneTitle,
              textAlign: TextAlign.center,
              style: AppType.display(24, color: AppColors.ink),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              l10n.addYourPhoneBody,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            TextFormField(
              controller: _phone,
              autofocus: true,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => busy ? null : _submit(),
              decoration: InputDecoration(
                labelText: l10n.phoneNumber,
                prefixIcon: const Icon(Icons.phone_outlined, size: 20),
              ),
              validator: (value) {
                final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                // Deliberately loose: this is a field someone has to be
                // reachable on, not an identity check, and a strict Egyptian
                // pattern would reject the visiting numbers that also order.
                if (digits.length < 7) return l10n.enterAValidPhone;
                return null;
              },
            ),
            const SizedBox(height: AppSpace.xl),
            FilledButton(
              onPressed: busy ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: busy
                  ? const ButtonSpinner(size: 18)
                  : Text(l10n.continueText),
            ),
          ],
        ),
      ),
    );

    return BlocListener<AuthCubit, AppAuthState>(
      listenWhen: (previous, current) =>
          previous.error != current.error && current.error != null,
      listener: (context, state) => showFailure(context, state.error!),
      child: AppBreakpoints.isWebWide(context)
          ? WebAuthFrame(
              headline: l10n.addYourPhoneTitle,
              subhead: l10n.addYourPhoneBody,
              child: form,
            )
          : Scaffold(
              backgroundColor: AppColors.canvas,
              body: SafeArea(child: Center(child: form)),
            ),
    );
  }
}
