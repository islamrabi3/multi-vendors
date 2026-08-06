import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../auth/auth_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// Everything the admin does occasionally, in one place.
///
/// The admin area had grown to six bottom-bar destinations plus two tools
/// buried in an avatar menu — past the point where a phone tab bar reads at a
/// glance, and with no room left for the tools that kept being added. Day-to-day
/// work (overview, orders, stores) keeps its tabs; the rest lives here, grouped
/// by what the admin is trying to get done rather than by which table it edits.
class AdminManageScreen extends StatelessWidget {
  const AdminManageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = context.watch<AuthCubit>().state;
    bool can(_ManageItem item) => auth.can(item.permission);

    final groups = <(String, List<_ManageItem>)>[
      (
        l10n.operations,
        [
          _ManageItem(
            icon: Icons.report_problem_outlined,
            label: l10n.customerReports,
            route: '/admin-app/complaints',
            permission: 'support.handle',
          ),
          _ManageItem(
            icon: Icons.support_agent_outlined,
            label: l10n.supportChat,
            route: '/admin-app/support',
            permission: 'support.handle',
          ),
          _ManageItem(
            icon: Icons.people_outline,
            label: l10n.users,
            route: '/admin-app/users',
            permission: 'users.block',
          ),
          _ManageItem(
            icon: Icons.admin_panel_settings_outlined,
            label: l10n.managementRoles,
            route: '/admin-app/roles',
            permission: 'staff.manage',
          ),
          _ManageItem(
            icon: Icons.campaign_outlined,
            label: l10n.announcements,
            route: '/admin-app/announcements',
            permission: 'notifications.send',
          ),
          _ManageItem(
            icon: Icons.payments_outlined,
            label: l10n.salesAndFinancialReports,
            route: '/admin-app/sales-reports',
            permission: 'reports.view',
          ),
          _ManageItem(
            icon: Icons.delivery_dining_outlined,
            label: l10n.driverApprovals,
            route: '/admin-app/drivers',
            permission: 'drivers.view',
          ),
          _ManageItem(
            icon: Icons.map_outlined,
            label: l10n.serviceAreas,
            route: '/admin-app/service-areas',
            permission: 'content.manage',
          ),
        ],
      ),
      (
        l10n.catalog,
        [
          _ManageItem(
            icon: Icons.category_outlined,
            label: l10n.categoriesTab,
            route: '/admin-app/categories',
            permission: 'catalog.manage',
          ),
          _ManageItem(
            icon: Icons.document_scanner_outlined,
            label: l10n.importMenuFromPhotos,
            route: '/admin-app/menu-import',
            permission: 'catalog.manage',
          ),
          _ManageItem(
            icon: Icons.price_change_outlined,
            label: l10n.priceAdjustment,
            route: '/admin-app/price-adjustment',
            permission: 'catalog.manage',
          ),
        ],
      ),
      (
        l10n.growth,
        [
          _ManageItem(
            icon: Icons.local_offer_outlined,
            label: l10n.promos,
            route: '/admin-app/promos',
            permission: 'promos.manage',
          ),
          _ManageItem(
            icon: Icons.ad_units_outlined,
            label: l10n.adManager,
            route: '/admin-app/ads',
            permission: 'ads.manage',
          ),
          _ManageItem(
            icon: Icons.article_outlined,
            label: l10n.content,
            route: '/admin-app/content',
            permission: 'content.manage',
          ),
        ],
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.manage)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.md,
            AppSpace.gutter,
            AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            for (final (title, allItems) in groups)
              if (allItems.where(can).toList() case final items
                  when items.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.xs,
                    AppSpace.sm,
                    AppSpace.xs,
                    AppSpace.sm,
                  ),
                  child: Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0)
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: AppColors.borderSoft,
                          ),
                        _ManageRow(item: items[i]),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
              ],
            const SizedBox(height: AppSpace.sm),
            Center(
              child: TextButton.icon(
                onPressed: () => context.read<AuthCubit>().signOut(),
                icon: const Icon(Icons.logout_rounded, size: 18),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.dangerInk,
                ),
                label: Text(l10n.signOut),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in the Manage grid.
class _ManageItem {
  const _ManageItem({
    required this.icon,
    required this.label,
    required this.route,
    required this.permission,
  });

  final IconData icon;
  final String label;
  final String route;

  /// What a member of staff needs to hold for this row to be worth showing.
  /// Hiding is courtesy — the screen behind it and every RPC it calls check
  /// again — but a console full of buttons that refuse is not a console.
  final String permission;
}

class _ManageRow extends StatelessWidget {
  const _ManageRow({required this.item});

  final _ManageItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(item.route),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.warmFill,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(item.icon, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                item.label,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.navInactive,
            ),
          ],
        ),
      ),
    );
  }
}
