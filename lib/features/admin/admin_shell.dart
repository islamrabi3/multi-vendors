import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/tokens.dart';
import '../../core/widgets/adaptive_shell.dart';
import '../../core/widgets/web/web_shell_frame.dart';
import '../auth/auth_cubit.dart';
import '../support/my_support_screen.dart' show AdminSupportScreen;
import 'screens/admin_ads_screen.dart';
import 'screens/admin_announcements_screen.dart';
import 'screens/admin_categories_screen.dart';
import 'screens/admin_complaints_screen.dart';
import 'screens/admin_content_screen.dart';
import 'screens/admin_deposits_screen.dart';
import 'screens/admin_drivers_screen.dart';
import 'screens/admin_finance_screen.dart';
import 'screens/admin_manage_screen.dart';
import 'screens/admin_menu_import_screen.dart';
import 'screens/admin_price_adjustment_screen.dart';
import 'screens/admin_promos_screen.dart';
import 'screens/admin_reports_screen.dart';
import 'screens/admin_roles_screen.dart';
import 'screens/admin_service_areas_screen.dart';
import 'screens/admin_settlements_screen.dart';
import 'screens/admin_users_screen.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    if (AppBreakpoints.isWebWide(context)) {
      return _AdminWebShell(shell: shell);
    }
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
          label: context.l10n.overview,
        ),
        AdaptiveDestination(
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long,
          label: context.l10n.orders,
        ),
        AdaptiveDestination(
          icon: Icons.storefront_outlined,
          selectedIcon: Icons.storefront,
          label: context.l10n.vendors,
        ),
        AdaptiveDestination(
          icon: Icons.tune_outlined,
          selectedIcon: Icons.tune_rounded,
          label: context.l10n.manage,
        ),
      ],
    );
  }
}

/// Lets content *inside* the web shell open a Manage destination in the
/// content pane, instead of pushing a full-screen route over the shell.
///
/// The admin's screens are written for a phone, where "review the deposits"
/// is a `context.push`. On web that push covers the sidebar and reads as the
/// app having navigated away — the thing the persistent shell exists to
/// prevent. Callers ask for this and fall back to their push when it is
/// absent, so nothing changes on mobile or on a narrow window.
class AdminWebNav extends InheritedWidget {
  const AdminWebNav({super.key, required this.openRoute, required super.child});

  /// Returns false when [route] is not an embeddable Manage destination, so
  /// the caller can push it instead of silently doing nothing.
  final bool Function(String route) openRoute;

  /// Null anywhere the web shell is not an ancestor.
  static AdminWebNav? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdminWebNav>();

  /// Opens [route] in the shell's content pane if that is possible here,
  /// otherwise pushes it. The one call every "go to that screen" tap makes.
  static void go(BuildContext context, String route) {
    if (maybeOf(context)?.openRoute(route) ?? false) return;
    context.push(route);
  }

  @override
  bool updateShouldNotify(AdminWebNav oldWidget) => false;
}

/// The desktop web layout: a persistent sidebar instead of the four-tab
/// rail. "Manage" isn't a destination of its own here — its sub-screens
/// (Support, Settlements, Roles, …) are grouped sections in the same
/// sidebar via [adminManageGroups], reused from the mobile Manage screen so
/// the two never list different things.
///
/// A Manage item's `onTap` does **not** push a route — it sets local state
/// and swaps the content pane in place, the same way the three pinned
/// branches already do via `shell.goBranch`. Routing through the navigator
/// for these produced a page-transition animation that read as "the app
/// just navigated," exactly the mobile-in-a-browser-tab feeling a
/// persistent sidebar is supposed to avoid. [_embeddedManageScreen] now
/// covers every route the sidebar can offer, so the `context.push` fallback
/// below is unreachable in practice and kept only so a route added to
/// [adminManageGroups] without an embedded form still opens rather than
/// doing nothing.
class _AdminWebShell extends StatefulWidget {
  const _AdminWebShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  State<_AdminWebShell> createState() => _AdminWebShellState();
}

class _AdminWebShellState extends State<_AdminWebShell> {
  /// The route of the Manage item currently shown inline, or null when a
  /// pinned branch (Overview/Orders/Vendors) owns the content pane instead.
  String? _manageRoute;
  String? _manageLabel;

  void _selectBranch(int index) {
    setState(() {
      _manageRoute = null;
      _manageLabel = null;
    });
    widget.shell.goBranch(
      index,
      initialLocation: index == widget.shell.currentIndex,
    );
  }

  void _selectManage(String route, String label) {
    setState(() {
      _manageRoute = route;
      _manageLabel = label;
    });
  }

  /// Opens a Manage route asked for by content *inside* the shell (a
  /// dashboard tile, a "see all settlements" link), looking its label up in
  /// the same [adminManageGroups] the sidebar is built from so the top bar
  /// title matches whichever sidebar row is now highlighted.
  ///
  /// Returns false when the route isn't a Manage destination (an order or
  /// store detail, say) so the caller can fall back to its own push.
  bool _openManageRoute(String route) {
    if (_embeddedManageScreen(route) == null) return false;
    for (final (_, items) in adminManageGroups(context)) {
      for (final item in items) {
        if (item.route == route) {
          _selectManage(route, item.label);
          return true;
        }
      }
    }
    return false;
  }

  /// The embeddable (`embedded: true`, chrome-free) form of a Manage screen,
  /// or null if this route hasn't been converted yet.
  ///
  /// Every route [adminManageGroups] can produce is listed here, so no
  /// sidebar tile falls through to a `context.push` — one that did would
  /// slide a new page over the shell and break the illusion the sidebar
  /// exists to create.
  Widget? _embeddedManageScreen(String route) => switch (route) {
    '/admin-app/complaints' => const AdminComplaintsScreen(embedded: true),
    '/admin-app/support' => const AdminSupportScreen(embedded: true),
    '/admin-app/users' => const AdminUsersScreen(embedded: true),
    '/admin-app/roles' => const AdminRolesScreen(embedded: true),
    '/admin-app/announcements' => const AdminAnnouncementsScreen(
      embedded: true,
    ),
    '/admin-app/sales-reports' => const AdminReportsScreen(embedded: true),
    '/admin-app/drivers' => const AdminDriversScreen(embedded: true),
    '/admin-app/service-areas' => const AdminServiceAreasScreen(embedded: true),
    '/admin-app/categories' => const AdminCategoriesScreen(embedded: true),
    '/admin-app/menu-import' => const AdminMenuImportScreen(embedded: true),
    '/admin-app/price-adjustment' => const AdminPriceAdjustmentScreen(
      embedded: true,
    ),
    '/admin-app/finance' => const AdminFinanceScreen(embedded: true),
    '/admin-app/settlements' => const AdminSettlementsScreen(embedded: true),
    '/admin-app/deposits' => const AdminDepositsScreen(embedded: true),
    '/admin-app/promos' => const AdminPromosScreen(embedded: true),
    '/admin-app/ads' => const AdminAdsScreen(embedded: true),
    '/admin-app/content' => const AdminContentScreen(embedded: true),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final embedded = _manageRoute == null
        ? null
        : _embeddedManageScreen(_manageRoute!);

    return WebShellFrame(
      activeId: _manageRoute != null
          ? 'manage:$_manageRoute'
          : 'branch:${widget.shell.currentIndex}',
      pageTitle: _manageRoute != null
          ? _manageLabel!
          : switch (widget.shell.currentIndex) {
              0 => l10n.overview,
              1 => l10n.orders,
              2 => l10n.vendors,
              _ => l10n.manage,
            },
      onSignOut: () => context.read<AuthCubit>().signOut(),
      maxContentWidth: 1200,
      sections: [
        WebNavSection(
          items: [
            WebNavItem(
              id: 'branch:0',
              icon: Icons.grid_view_outlined,
              selectedIcon: Icons.grid_view_rounded,
              label: l10n.overview,
              onTap: () => _selectBranch(0),
            ),
            WebNavItem(
              id: 'branch:1',
              icon: Icons.receipt_long_outlined,
              selectedIcon: Icons.receipt_long,
              label: l10n.orders,
              onTap: () => _selectBranch(1),
            ),
            WebNavItem(
              id: 'branch:2',
              icon: Icons.storefront_outlined,
              selectedIcon: Icons.storefront,
              label: l10n.vendors,
              onTap: () => _selectBranch(2),
            ),
          ],
        ),
        for (final (title, items) in adminManageGroups(context))
          WebNavSection(
            title: title,
            items: [
              for (final item in items)
                WebNavItem(
                  id: 'manage:${item.route}',
                  icon: item.icon,
                  label: item.label,
                  onTap: () => _embeddedManageScreen(item.route) != null
                      ? _selectManage(item.route, item.label)
                      : context.push(item.route),
                ),
            ],
          ),
      ],
      // A pinned branch's own selection (`_selectedId` in the dashboard,
      // scroll offset, …) must survive switching away to a Manage screen and
      // back, so the branch content stays alive underneath rather than being
      // rebuilt — `Offstage` keeps it mounted, `embedded` just paints on top.
      child: AdminWebNav(
        openRoute: _openManageRoute,
        child: Stack(
          children: [
            Offstage(offstage: embedded != null, child: widget.shell),
            ?embedded,
          ],
        ),
      ),
    );
  }
}
