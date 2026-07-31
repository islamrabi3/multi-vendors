import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/adaptive_shell.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class VendorShell extends StatelessWidget {
  const VendorShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return AdaptiveShell(
      shell: shell,
      destinations: [
        AdaptiveDestination(
            icon: Icons.receipt_long_outlined,
            selectedIcon: Icons.receipt_long,
            label: context.l10n.orders),
        AdaptiveDestination(
            icon: Icons.menu_book_outlined,
            selectedIcon: Icons.menu_book,
            label: context.l10n.menu),
        AdaptiveDestination(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            label: context.l10n.settings),
      ],
    );
  }
}
