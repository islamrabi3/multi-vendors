import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/services/maintenance_gate.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/widgets/brand_logo.dart';

/// What everyone but an admin sees while the platform is closed for
/// maintenance. No navigation out of it: the gate in the router puts it back
/// until the flag is switched off.
class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ValueListenableBuilder<MaintenanceStatus>(
              valueListenable: MaintenanceGate.instance.status,
              builder: (context, status, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const KitchenInLockup(),
                  const SizedBox(height: AppSpace.xl),
                  Container(
                    width: 84,
                    height: 84,
                    decoration: const BoxDecoration(
                      color: AppColors.warmFill,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.build_rounded,
                      size: 38,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  Text(
                    l10n.maintenanceTitle,
                    textAlign: TextAlign.center,
                    style: AppType.display(22),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    status.messageFor(language) ?? l10n.maintenanceBody,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  OutlinedButton.icon(
                    onPressed: MaintenanceGate.instance.refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(l10n.retry),
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
