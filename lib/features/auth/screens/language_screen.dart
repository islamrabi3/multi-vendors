import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/locale_cubit.dart';
import '../../../app/tokens.dart';
import '../../../core/widgets/brand_logo.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// The first thing a new install shows: which language to speak.
///
/// Every label here is deliberately bilingual or in its own script. The one
/// screen whose whole purpose is asking which language you read cannot itself
/// assume an answer — a picker written only in English is unusable to exactly
/// the people who need it most.
///
/// Tapping a row applies the locale immediately rather than on Continue, so
/// the choice is visible in the button and the text direction before it is
/// committed. Continue only records that the question has been answered.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key, this.onDone});

  /// What to do once a language is committed. Null on first launch — marking
  /// the choice flips `AppLanguage.chosen`, which the router listens to, so
  /// this screen redirects itself onward. Settings passes a pop instead.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleCubit>().state;
    final isWide = AppBreakpoints.isWebWide(context);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: KitchenInMark(size: isWide ? 64 : 56)),
                  const SizedBox(height: AppSpace.xl),
                  // Both scripts, both readable before a choice exists.
                  const Text(
                    'Choose your language',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'اختر لغتك',
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  _LanguageOption(
                    // Endonyms, never translated: a language is named in
                    // itself, which is the only name someone looking for it
                    // is guaranteed to recognise.
                    nativeName: 'English',
                    subtitle: 'English',
                    flag: '🇬🇧',
                    selected: locale.languageCode == 'en',
                    onTap: () => context.read<LocaleCubit>().setLocale(
                      const Locale('en'),
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  _LanguageOption(
                    nativeName: 'العربية',
                    subtitle: 'Arabic',
                    flag: '🇪🇬',
                    rtl: true,
                    selected: locale.languageCode == 'ar',
                    onTap: () => context.read<LocaleCubit>().setLocale(
                      const Locale('ar'),
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  FilledButton(
                    onPressed: () {
                      // Already applied by the taps above; this only records
                      // that the question was answered, so a user who keeps
                      // the default English still moves on.
                      AppLanguage.markChosen();
                      onDone?.call();
                    },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: Text(context.l10n.continueText),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text(
                    context.l10n.languageChangeLaterHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppColors.textMuted,
                    ),
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

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.nativeName,
    required this.subtitle,
    required this.flag,
    required this.selected,
    required this.onTap,
    this.rtl = false,
  });

  final String nativeName;
  final String subtitle;
  final String flag;
  final bool selected;
  final bool rtl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.warmFill : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: AppSpace.md,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(flag, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nativeName,
                      textDirection: rtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      subtitle,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 22,
                color: selected ? AppColors.primary : AppColors.navInactive,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
