import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/tokens.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.shell});

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
              icon: const Icon(Icons.grid_view_outlined),
              selectedIcon: const Icon(Icons.grid_view_rounded),
              label: context.l10n.overview),
          NavigationDestination(
              icon: const Icon(Icons.storefront_outlined),
              selectedIcon: const Icon(Icons.storefront),
              label: context.l10n.vendors),
          NavigationDestination(
              icon: const Icon(Icons.receipt_long_outlined),
              selectedIcon: const Icon(Icons.receipt_long),
              label: context.l10n.orders),
          NavigationDestination(
              icon: const Icon(Icons.local_offer_outlined),
              selectedIcon: const Icon(Icons.local_offer),
              label: context.l10n.promos),
          NavigationDestination(
              icon: const Icon(Icons.category_outlined),
              selectedIcon: const Icon(Icons.category_rounded),
              label: 'Categories'),
        ],
      ),
    );
  }
}
