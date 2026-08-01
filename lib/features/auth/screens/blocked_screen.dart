import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../auth_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// Where a suspended or closed account lands.
///
/// Blocking was previously invisible: the server refused the writes that
/// mattered, but the app said nothing, so a blocked user just met unexplained
/// failures. This is the explanation, and the only two things still available
/// to them — reaching support, and signing out.
class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profile = context.select((AuthCubit c) => c.state.profile);
    final closed = profile?.isClosed ?? false;
    final reason = profile?.blockedReason?.trim();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: const BoxDecoration(
                    color: AppColors.dangerFill,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    closed ? Icons.person_off_outlined : Icons.block,
                    size: 34,
                    color: AppColors.dangerInk,
                  ),
                ),
                const SizedBox(height: AppSpace.xl),
                Text(
                  closed ? l10n.accountClosedTitle : l10n.accountBlockedTitle,
                  textAlign: TextAlign.center,
                  style: AppType.display(22),
                ),
                const SizedBox(height: AppSpace.md),
                Text(
                  closed
                      ? l10n.accountClosedBody
                      : l10n.accountBlockedBody,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: AppColors.textSecondary,
                  ),
                ),
                // The admin's note is for their own records, so it is only
                // shown when one was actually written.
                if (!closed && reason != null && reason.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.lg),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpace.lg),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: Text(
                      reason,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpace.xxl),
                // A closed account has nobody to appeal to; a blocked one does.
                if (!closed)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => context.push('/support'),
                      icon: const Icon(Icons.support_agent_outlined, size: 19),
                      label: Text(l10n.supportChat),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpace.md),
                TextButton(
                  onPressed: () => context.read<AuthCubit>().signOut(),
                  child: Text(l10n.logOut,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
