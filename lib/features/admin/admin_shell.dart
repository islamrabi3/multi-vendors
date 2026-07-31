import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/adaptive_shell.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return AdaptiveShell(
      shell: shell,
      maxContentWidth: 1200,
      // Four destinations, not six. A phone tab bar stops reading at a glance
      // past four or five labels, and the admin area kept gaining tools —
      // drivers and menu import were already hidden in an avatar menu because
      // there was nowhere left to put them. Daily work keeps its tabs;
      // everything occasional moved behind "Manage".
      destinations: [
        AdaptiveDestination(
            icon: Icons.grid_view_outlined,
            selectedIcon: Icons.grid_view_rounded,
            label: context.l10n.overview),
        AdaptiveDestination(
            icon: Icons.receipt_long_outlined,
            selectedIcon: Icons.receipt_long,
            label: context.l10n.orders),
        AdaptiveDestination(
            icon: Icons.storefront_outlined,
            selectedIcon: Icons.storefront,
            label: context.l10n.vendors),
        AdaptiveDestination(
            icon: Icons.tune_outlined,
            selectedIcon: Icons.tune_rounded,
            label: context.l10n.manage),
      ],
    );
  }
}
