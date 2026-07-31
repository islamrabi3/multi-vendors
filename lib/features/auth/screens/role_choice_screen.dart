import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/tokens.dart';
import '../../../core/models/profile.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart' show ButtonSpinner;
import '../auth_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// Asked once, right after a Google/Apple sign-up.
///
/// Identity providers carry no role, so without this every social account was
/// silently a customer for good. There is no skip: the answer decides which
/// half of the app the user gets, and the server only accepts it while the
/// account is still brand-new.
class RoleChoiceScreen extends StatefulWidget {
  const RoleChoiceScreen({super.key});

  @override
  State<RoleChoiceScreen> createState() => _RoleChoiceScreenState();
}

class _RoleChoiceScreenState extends State<RoleChoiceScreen> {
  UserRole _selected = UserRole.customer;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final busy = context.select((AuthCubit c) => c.state.busy);

    final options = <(UserRole, IconData, String, String)>[
      (
        UserRole.customer,
        Icons.shopping_bag_outlined,
        l10n.orderFood,
        l10n.roleCustomerDesc,
      ),
      (
        UserRole.vendor,
        Icons.storefront_outlined,
        l10n.sellAsAVendor,
        l10n.roleVendorDesc,
      ),
      (
        UserRole.driver,
        Icons.delivery_dining_outlined,
        l10n.deliverOrders,
        l10n.roleDriverDesc,
      ),
    ];

    return BlocListener<AuthCubit, AppAuthState>(
      listenWhen: (a, b) => b.error != null && a.error != b.error,
      listener: (context, state) =>
          showSnack(context, readableError(state.error!), error: true),
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                  children: [
                    Text(l10n.chooseYourRole, style: AppType.display(26)),
                    const SizedBox(height: 8),
                    Text(
                      l10n.chooseYourRoleSubtitle,
                      style: const TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    for (final (role, icon, title, body) in options) ...[
                      _RoleCard(
                        icon: icon,
                        title: title,
                        body: body,
                        selected: _selected == role,
                        onTap: busy
                            ? null
                            : () => setState(() => _selected = role),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // The picker decides account type, and the server will not
                    // let it be changed once the account has any history — so
                    // say that here rather than in a support ticket later.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            size: 16, color: AppColors.textFaint),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.roleChoiceIsPermanent,
                            style: const TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: AppColors.textFaint),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                    24, 8, 24, 16 + MediaQuery.paddingOf(context).bottom),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54)),
                  onPressed: busy
                      ? null
                      : () => context.read<AuthCubit>().chooseRole(_selected),
                  child: busy
                      ? const ButtonSpinner()
                      : Text(l10n.continueText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(AppSpace.md + 2),
        decoration: BoxDecoration(
          color: selected ? AppColors.warmFill : AppColors.surface,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.warmFill,
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: Icon(icon,
                  size: 22,
                  color: selected ? Colors.white : AppColors.primary),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(body,
                      style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: AppColors.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.sm),
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
    );
  }
}
