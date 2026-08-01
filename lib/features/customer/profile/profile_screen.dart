import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'wallet_screen.dart';
import 'loyalty_screen.dart';
import '../../../app/tokens.dart';
import '../../../core/repositories/auth_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../auth/auth_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';
import 'package:multi_vendor/app/locale_cubit.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _repo = AuthRepository();
  late Future<({int orders, int favorites, int points})> _stats =
      _repo.fetchMyStats();

  void _reloadStats() => setState(() => _stats = _repo.fetchMyStats());

  /// Closing an account is irreversible, so the two things that would surprise
  /// someone afterwards are checked first: work still in flight, and money
  /// still in the wallet. An in-flight order is refused outright; a balance is
  /// stated plainly and forfeited only on an explicit second confirmation.
  Future<void> _confirmDeleteAccount() async {
    final l10n = context.l10n;
    AccountDeletionBlockers blockers;
    try {
      blockers = await _repo.accountDeletionBlockers();
    } catch (e) {
      if (mounted) showFailure(context, e);
      return;
    }
    if (!mounted) return;

    if (blockers.hasActiveOrders) {
      showSnack(context, l10n.deleteAccountActiveOrders, error: true);
      return;
    }

    final message = blockers.hasBalance
        ? '${l10n.deleteAccountWarning}\n\n'
            '${l10n.deleteAccountWalletWarning(formatMoney(blockers.walletBalance))}'
        : l10n.deleteAccountWarning;

    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: l10n.deleteAccount,
      message: message,
      confirmText: l10n.deleteAccountConfirm,
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;

    try {
      await _repo.deleteOwnAccount(forfeitBalance: blockers.hasBalance);
      if (mounted) showSnack(context, l10n.accountDeleted);
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  Future<void> _editProfile() async {
    final profile = context.read<AuthCubit>().state.profile;
    final nameController = TextEditingController(text: profile?.fullName ?? '');
    final phoneController = TextEditingController(text: profile?.phone ?? '');
    final l10n = context.l10n;

    final saved = await AppDialogs.showFormDialog<bool>(
      context: context,
      title: l10n.editProfile,
      icon: Icons.person_outline,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l10n.fullName),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: l10n.phoneNumber),
          ),
        ],
      ),
      primaryText: l10n.save,
      onPrimaryPressed: () {
        if (nameController.text.trim().isEmpty) {
          showSnack(context, l10n.nameRequired, error: true);
          return;
        }
        Navigator.of(context).pop(true);
      },
      secondaryText: l10n.cancel,
      onSecondaryPressed: () => Navigator.of(context).pop(false),
    );

    if (saved != true || !mounted) return;
    final ok = await context.read<AuthCubit>().updateProfile(
          fullName: nameController.text,
          phone: phoneController.text,
        );
    if (!mounted) return;
    showSnack(
      context,
      ok
          ? l10n.profileUpdated
          : errorText(context, context.read<AuthCubit>().state.error ?? ''),
      error: !ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.select((AuthCubit cubit) => cubit.state.profile);
    final name = profile?.fullName.isNotEmpty == true
        ? profile!.fullName
        : context.l10n.guest;
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
                _SquareIcon(icon: Icons.edit_outlined, onTap: _editProfile),
              ],
            ),
            const SizedBox(height: 18),
            // ===== mini stats =====
            // Real counts. These used to be hardcoded ('38', '12', '320'),
            // which read as a broken account to anyone who checked them.
            FutureBuilder<({int orders, int favorites, int points})>(
              future: _stats,
              builder: (context, snap) {
                final data = snap.data;
                String value(int? n) => data == null ? '—' : '$n';
                return Row(
                  children: [
                    Expanded(
                        child: _StatBox(
                            value: value(data?.orders),
                            label: context.l10n.orders)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _StatBox(
                            value: value(data?.favorites),
                            label: context.l10n.favorites)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _StatBox(
                            value: value(data?.points),
                            label: context.l10n.points,
                            accent: true)),
                  ],
                );
              },
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
                      icon: Icons.account_balance_wallet_outlined,
                      label: context.l10n.wallet,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const WalletScreen()),
                      )),
                  const _MenuDivider(),
                  _MenuRow(
                      icon: Icons.stars_outlined,
                      label: context.l10n.loyaltyRewards,
                      // Points can be spent in there, so the header counter is
                      // re-read on the way back.
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const LoyaltyScreen()),
                        );
                        _reloadStats();
                      }),
                  const _MenuDivider(),
                  _MenuRow(
                      icon: Icons.location_on_outlined,
                      label: context.l10n.addresses,
                      onTap: () => context.push('/addresses')),
                  const _MenuDivider(),
                  _MenuRow(
                      icon: Icons.favorite_border,
                      label: context.l10n.favorites,
                      onTap: () async {
                        await context.push('/favorites');
                        _reloadStats();
                      }),
                  const _MenuDivider(),
                  _MenuRow(
                      icon: Icons.support_agent_outlined,
                      label: context.l10n.supportChat,
                      onTap: () => context.push('/support')),
                  const _MenuDivider(),
                  _MenuRow(
                      icon: Icons.info_outline,
                      label: context.l10n.aboutUs,
                      onTap: () => context.push('/about')),
                  const _MenuDivider(),
                  _MenuRow(
                      icon: Icons.gavel_outlined,
                      label: context.l10n.termsAndConditions,
                      onTap: () => context.push('/terms')),
                  const _MenuDivider(),
                  _MenuRow(
                      icon: Icons.privacy_tip_outlined,
                      label: context.l10n.privacyPolicy,
                      onTap: () => context.push('/privacy')),
                  const _MenuDivider(),
                  _MenuRow(
                      icon: Icons.settings_outlined,
                      label: context.l10n.settings,
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
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
            // Deliberately last and understated: closing an account is a real
            // action the user is entitled to, but it should never be adjacent
            // to log out by accident.
            Center(
              child: TextButton(
                onPressed: _confirmDeleteAccount,
                child: Text(context.l10n.deleteAccount,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted)),
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
            const DirectionalIcon(Icons.chevron_right,
                size: 20, color: AppColors.navInactive),
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
