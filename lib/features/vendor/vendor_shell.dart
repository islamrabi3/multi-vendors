import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/tokens.dart';
import '../../core/widgets/adaptive_shell.dart';
import '../../core/widgets/web/web_shell_frame.dart';
import '../auth/auth_cubit.dart';
import 'screens/vendor_analytics_screen.dart';
import 'screens/vendor_orders_history_screen.dart';
import 'screens/vendor_payouts_screen.dart';
import 'screens/vendor_reviews_screen.dart';
import 'screens/vendor_schedule_screen.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class VendorShell extends StatelessWidget {
  const VendorShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    if (AppBreakpoints.isWebWide(context)) {
      return _VendorWebShell(shell: shell);
    }
    return AdaptiveShell(
      shell: shell,
      destinations: [
        AdaptiveDestination(
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long,
          label: context.l10n.orders,
        ),
        AdaptiveDestination(
          icon: Icons.menu_book_outlined,
          selectedIcon: Icons.menu_book,
          label: context.l10n.menu,
        ),
        AdaptiveDestination(
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings,
          label: context.l10n.settings,
        ),
      ],
    );
  }
}

/// Lets content *inside* the web shell open one of the sidebar's tools in
/// the content pane, instead of pushing a full-screen route over the shell.
///
/// The vendor's screens are written for a phone, where "see my opening
/// hours" is a `Navigator.push`. On web that push covers the sidebar and
/// reads as the app having navigated away — the exact thing the persistent
/// shell exists to prevent. Screens ask for this and fall back to their
/// push when it is absent, so nothing changes on mobile.
class VendorWebNav extends InheritedWidget {
  const VendorWebNav({super.key, required this.openTool, required super.child});

  /// Ids match [_VendorWebShellState._toolScreen]: analytics, history,
  /// payouts, schedule, reviews.
  final void Function(String toolId) openTool;

  /// Null anywhere the web shell is not an ancestor — every mobile layout,
  /// and any narrow web window.
  static VendorWebNav? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VendorWebNav>();

  @override
  bool updateShouldNotify(VendorWebNav oldWidget) => false;
}

/// Desktop gives the vendor's occasional work a permanent, grouped home.
/// These pages used to be reachable only from mobile-first sheets or routes,
/// which made the web view feel like a narrow app placed inside a browser.
class _VendorWebShell extends StatefulWidget {
  const _VendorWebShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  State<_VendorWebShell> createState() => _VendorWebShellState();
}

class _VendorWebShellState extends State<_VendorWebShell> {
  String? _toolId;

  void _selectBranch(int index) {
    setState(() => _toolId = null);
    widget.shell.goBranch(
      index,
      initialLocation: index == widget.shell.currentIndex,
    );
  }

  void _selectTool(String id) => setState(() => _toolId = id);

  Widget? _toolScreen(String id, String vendorId) => switch (id) {
    'analytics' => VendorAnalyticsScreen(vendorId: vendorId, embedded: true),
    'history' => VendorOrdersHistoryScreen(vendorId: vendorId, embedded: true),
    'payouts' => VendorPayoutsScreen(vendorId: vendorId, embedded: true),
    'schedule' => VendorScheduleScreen(vendorId: vendorId, embedded: true),
    'reviews' => const VendorReviewsScreen(embedded: true),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final vendor = context.select((AuthCubit c) => c.state.vendor);
    if (vendor == null) return const SizedBox.shrink();
    final tool = _toolId == null ? null : _toolScreen(_toolId!, vendor.id);
    final toolLabels = <String, String>{
      'analytics': l10n.storeAnalyticsAndReports,
      'history': l10n.ordersHistory,
      'payouts': l10n.payouts,
      'schedule': l10n.operatingHoursSchedule,
      'reviews': l10n.reviews,
    };

    return WebShellFrame(
      activeId: tool == null ? 'branch:${widget.shell.currentIndex}' : _toolId!,
      pageTitle: tool == null
          ? switch (widget.shell.currentIndex) {
              0 => l10n.orders,
              1 => l10n.menu,
              _ => l10n.settings,
            }
          : toolLabels[_toolId!]!,
      onSignOut: () => context.read<AuthCubit>().signOut(),
      maxContentWidth: 1200,
      sections: [
        WebNavSection(
          items: [
            WebNavItem(
              id: 'branch:0',
              icon: Icons.receipt_long_outlined,
              selectedIcon: Icons.receipt_long,
              label: l10n.orders,
              onTap: () => _selectBranch(0),
            ),
            WebNavItem(
              id: 'branch:1',
              icon: Icons.menu_book_outlined,
              selectedIcon: Icons.menu_book,
              label: l10n.menu,
              onTap: () => _selectBranch(1),
            ),
          ],
        ),
        WebNavSection(
          title: l10n.storeAnalyticsAndReports,
          items: [
            WebNavItem(
              id: 'analytics',
              icon: Icons.insights_outlined,
              label: l10n.storeAnalyticsAndReports,
              onTap: () => _selectTool('analytics'),
            ),
            WebNavItem(
              id: 'history',
              icon: Icons.history_rounded,
              label: l10n.ordersHistory,
              onTap: () => _selectTool('history'),
            ),
            WebNavItem(
              id: 'payouts',
              icon: Icons.account_balance_wallet_outlined,
              label: l10n.payouts,
              onTap: () => _selectTool('payouts'),
            ),
          ],
        ),
        WebNavSection(
          title: l10n.settings,
          items: [
            WebNavItem(
              id: 'schedule',
              icon: Icons.schedule_outlined,
              label: l10n.operatingHoursSchedule,
              onTap: () => _selectTool('schedule'),
            ),
            WebNavItem(
              id: 'reviews',
              icon: Icons.rate_review_outlined,
              label: l10n.reviews,
              onTap: () => _selectTool('reviews'),
            ),
            WebNavItem(
              id: 'branch:2',
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              label: l10n.settings,
              onTap: () => _selectBranch(2),
            ),
          ],
        ),
      ],
      child: VendorWebNav(
        openTool: _selectTool,
        child: Stack(
          children: [
            Offstage(offstage: tool != null, child: widget.shell),
            ?tool,
          ],
        ),
      ),
    );
  }
}
