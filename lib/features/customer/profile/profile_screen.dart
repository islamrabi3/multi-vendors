import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../auth/auth_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';
import 'package:multi_vendor/app/locale_cubit.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.select((AuthCubit cubit) => cubit.state.profile);
    final name = profile?.fullName.isNotEmpty == true ? profile!.fullName : 'Guest';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
          children: [
            // ===== head =====
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primaryLight, AppColors.primaryDark],
                    ),
                  ),
                  child: Text(initial,
                      style: AppType.display(26, color: Colors.white)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: AppType.display(22)),
                      if (profile?.phone != null && profile!.phone!.isNotEmpty)
                        Text(profile.phone!,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                _SquareIcon(icon: Icons.edit_outlined, onTap: () {}),
              ],
            ),
            const SizedBox(height: 18),
            // ===== mini stats =====
            Row(
              children: [
                Expanded(child: _StatBox(value: '38', label: context.l10n.orders)),
                SizedBox(width: 10),
                Expanded(child: _StatBox(value: '12', label: context.l10n.favorites)),
                SizedBox(width: 10),
                Expanded(
                    child: _StatBox(
                        value: '320', label: context.l10n.points, accent: true)),
              ],
            ),
            const SizedBox(height: 18),
            // ===== menu list =====
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(18),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _MenuRow(
                      icon: Icons.location_on_outlined,
                      label: context.l10n.addresses,
                      onTap: () => context.push('/addresses')),
                  const _MenuDivider(),
                  _MenuRow(
                      icon: Icons.favorite_border,
                      label: context.l10n.favorites,
                      onTap: () => context.push('/favorites')),
                  const _MenuDivider(),
                  _MenuRow(
                      icon: Icons.credit_card,
                      label: context.l10n.paymentMethods,
                      onTap: () {}),
                  const _MenuDivider(),
                  _MenuRow(
                      icon: Icons.settings_outlined,
                      label: context.l10n.settings,
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: AppColors.canvas,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                          ),
                          builder: (ctx) {
                            return BlocProvider.value(
                              value: context.read<LocaleCubit>(),
                              child: BlocBuilder<LocaleCubit, Locale>(
                                builder: (sheetCtx, locale) {
                                  final currentIsAr = locale.languageCode == 'ar';
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          sheetCtx.l10n.settings,
                                          style: AppType.display(20),
                                        ),
                                        const SizedBox(height: 20),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              sheetCtx.l10n.appLanguage,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.ink,
                                              ),
                                            ),
                                            Switch(
                                              value: currentIsAr,
                                              onChanged: (v) {
                                                sheetCtx.read<LocaleCubit>().setLocale(
                                                  v ? const Locale('ar') : const Locale('en'),
                                                );
                                              },
                                              activeThumbColor: Colors.white,
                                              activeTrackColor: AppColors.primary,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          currentIsAr ? 'العربية (Arabic)' : 'English (الإنجليزية)',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        );
                      }),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () => context.read<AuthCubit>().signOut(),
                child: Text(context.l10n.logOut,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SquareIcon extends StatelessWidget {
  const _SquareIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, size: 18, color: AppColors.ink),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox(
      {required this.value, required this.label, this.accent = false});

  final String value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(value,
              style: AppType.display(20,
                  color: accent ? AppColors.primary : AppColors.ink)),
          const SizedBox(height: 1),
          Text(label,
              style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.warmFill,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink)),
            ),
            const Icon(Icons.chevron_right,
                size: 20, color: Color(0xFFC9BCB0)),
          ],
        ),
      ),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: AppColors.borderSoft);
}
