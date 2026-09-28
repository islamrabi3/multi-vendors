import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/widgets/web/console.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import '../../auth/auth_cubit.dart';
import 'admin_ads_screen.dart';
import 'admin_manage_screen.dart' show adminManageWebSections;
import 'admin_price_campaigns_screen.dart';
import 'admin_promos_screen.dart';

/// Everything that makes customers look twice, on one page: coupon codes,
/// price campaigns, and the ads on the home screen.
///
/// Three tools an operator reaches for together — a weekend push is usually a
/// coupon, a campaign and a banner — used to be three sidebar entries. Each
/// tab is the full tool; only the tabs this admin may use are shown.
class AdminMarketingScreen extends StatelessWidget {
  const AdminMarketingScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = context.watch<AuthCubit>().state;
    final tabs = <({String label, IconData icon, String route, Widget page})>[
      if (auth.can('promos.manage'))
        (
          label: l10n.promos,
          icon: Icons.local_offer_outlined,
          route: '/admin-app/promos',
          page: const AdminPromosScreen(embedded: true),
        ),
      if (auth.can('catalog.manage'))
        (
          label: l10n.campaignsTitle,
          icon: Icons.trending_up_rounded,
          route: '/admin-app/price-campaigns',
          page: const AdminPriceCampaignsScreen(embedded: true),
        ),
      if (auth.can('ads.manage'))
        (
          label: l10n.adManager,
          icon: Icons.ad_units_outlined,
          route: '/admin-app/ads',
          page: const AdminAdsScreen(embedded: true),
        ),
    ];

    // A phone: the three tools as three rows, each opening its own screen
    // built for a phone.
    if (!embedded && !AppBreakpoints.isWebWide(context)) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(title: Text(l10n.marketing)),
        body: ListView(
          padding: const EdgeInsets.all(AppSpace.gutter),
          children: [
            for (final tab in tabs)
              Card(
                child: ListTile(
                  leading: Icon(tab.icon, color: AppColors.primary),
                  title: Text(tab.label),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(tab.route),
                ),
              ),
          ],
        ),
      );
    }

    final page = DefaultTabController(
      length: tabs.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: ConsoleHeader(
              title: l10n.marketing,
              description: l10n.pageDescMarketing,
            ),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: const EdgeInsetsDirectional.only(start: 4),
            tabs: [
              for (final tab in tabs)
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(tab.icon, size: 18),
                      const SizedBox(width: 8),
                      Text(tab.label),
                    ],
                  ),
                ),
            ],
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.border),
          Expanded(
            child: TabBarView(
              children: [
                for (final tab in tabs) ConsoleTabScope(child: tab.page),
              ],
            ),
          ),
        ],
      ),
    );

    if (embedded) return page;
    return WebPageChrome(
      forStaff: true,
      activeId: 'manage:/admin-app/marketing',
      sections: adminManageWebSections(context),
      pageTitle: l10n.marketing,
      maxContentWidth: 1680,
      child: page,
    );
  }
}
