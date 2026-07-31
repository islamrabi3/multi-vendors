import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/tokens.dart';

/// One destination of an adaptive shell (mobile bottom bar / desktop rail).
class AdaptiveDestination {
  const AdaptiveDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Responsive scaffold for the vendor and admin dashboards: bottom
/// navigation on phones, a NavigationRail on tablet/desktop/web widths,
/// extended (with labels) on wide desktops. Content is capped so tables
/// and lists do not stretch edge-to-edge on a monitor.
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({
    super.key,
    required this.shell,
    required this.destinations,
    this.maxContentWidth = 1100,
  });

  final StatefulNavigationShell shell;
  final List<AdaptiveDestination> destinations;
  final double maxContentWidth;

  void _select(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final useRail = AppBreakpoints.isWide(width);

    if (!useRail) {
      return Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.warmFill,
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _select,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: AppColors.surface,
            indicatorColor: AppColors.warmFill,
            extended: width >= AppBreakpoints.extended,
            labelType: width >= AppBreakpoints.extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            selectedIndex: shell.currentIndex,
            onDestinationSelected: _select,
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(
              width: 1, thickness: 1, color: AppColors.border),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: shell,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
