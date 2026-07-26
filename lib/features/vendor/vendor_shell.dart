import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/tokens.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class VendorShell extends StatelessWidget {
  const VendorShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.warmFill,
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) => shell.goBranch(index,
            initialLocation: index == shell.currentIndex),
        destinations: [
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: context.l10n.orders),
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: context.l10n.menu),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: context.l10n.settings),
        ],
      ),
    );
  }
}
