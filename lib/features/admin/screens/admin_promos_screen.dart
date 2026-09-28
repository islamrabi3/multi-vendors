import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../app/tokens.dart';
import '../../../core/widgets/web/console.dart';
import '../../../core/models/coupon.dart';
import '../../../core/repositories/coupons_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import '../../../core/widgets/web/web_table.dart';
import '../admin_coupons_cubit.dart';
import '../widgets/ad_destination_field.dart' show pickActiveStore;
import 'admin_manage_screen.dart' show adminManageWebSections;
import 'package:multi_vendor/core/utils/l10n_extension.dart';
import '../../../core/widgets/web/adaptive_sheet.dart';

class AdminPromosScreen extends StatelessWidget {
  const AdminPromosScreen({super.key, this.embedded = false});

  /// True when a web sidebar is already drawing the shell around this screen
  /// (`_AdminWebShell`) — skips this widget's own [WebPageChrome]/[Scaffold]
  /// and returns just the content.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    // Only coupons live here now. Banners moved to the Ads screen, which
    // owns the same `banners` table but with the placement, schedule,
    // audience and counters this screen never had — two editors for one
    // table meant whichever you happened to open decided what you could set.
    return BlocProvider(
      create: (_) => AdminCouponsCubit(CouponsRepository()),
      child: _PromosView(embedded: embedded),
    );
  }
}

enum _CouponFilter { all, live, scheduled, paused, ended }

_CouponFilter _stateOf(Coupon c) => c.isExpired || c.isExhausted
    ? _CouponFilter.ended
    : c.isScheduled
    ? _CouponFilter.scheduled
    : c.isActive
    ? _CouponFilter.live
    : _CouponFilter.paused;

class _PromosView extends StatefulWidget {
  const _PromosView({required this.embedded});

  final bool embedded;

  @override
  State<_PromosView> createState() => _PromosViewState();
}

class _PromosViewState extends State<_PromosView> {
  String _query = '';
  _CouponFilter _filter = _CouponFilter.all;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final webWide = AppBreakpoints.isWebWide(context);

    if (webWide) {
      final page = _webPage(context);
      if (widget.embedded) {
        // Inside the Marketing tabs the tab names the page; standalone, the
        // console header does.
        if (ConsoleTabScope.of(context)) return page;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: ConsoleHeader(
                title: l10n.promos,
                description: l10n.pageDescPromos,
              ),
            ),
            Expanded(child: page),
          ],
        );
      }
      return WebPageChrome(
        forStaff: true,
        activeId: 'manage:/admin-app/promos',
        sections: adminManageWebSections(context),
        pageTitle: l10n.promos,
        child: page,
      );
    }

    final body = BlocListener<AdminCouponsCubit, AdminCouponsState>(
      listenWhen: (p, c) => p.error != c.error && c.error != null,
      listener: (context, s) => showFailure(context, s.error!),
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => context.read<AdminCouponsCubit>().load(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            _SectionLabel(),
            SizedBox(height: 10),
            _CouponsSection(),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.canvas,
      // Default leading rather than a hand-built `arrow_back_ios`: that
      // glyph is the iOS chevron specifically and never mirrors for Arabic.
      appBar: AppBar(title: Text(l10n.promos)),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 12, 16, 10),
              child: Row(children: [Spacer(), _NewButton()]),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  /// Desktop: how the codes are doing, then search and state filters beside
  /// the one thing to create, then the codes.
  Widget _webPage(BuildContext context) {
    final l10n = context.l10n;
    return BlocConsumer<AdminCouponsCubit, AdminCouponsState>(
      listenWhen: (p, c) => p.error != c.error && c.error != null,
      listener: (context, s) => showFailure(context, s.error!),
      builder: (context, state) {
        final cubit = context.read<AdminCouponsCubit>();
        final coupons = state.coupons;
        int count(_CouponFilter f) =>
            coupons.where((c) => _stateOf(c) == f).length;
        final query = _query.trim().toLowerCase();
        final shown = [
          for (final c in coupons)
            if ((_filter == _CouponFilter.all || _stateOf(c) == _filter) &&
                (query.isEmpty || c.code.toLowerCase().contains(query)))
              c,
        ];
        final redeemed = coupons.fold<int>(0, (n, c) => n + c.usedCount);

        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: cubit.load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
            children: [
              ConsoleGrid(
                children: [
                  ConsoleStat(
                    label: l10n.liveCodes,
                    value: '${count(_CouponFilter.live)}',
                    hint: l10n.partiesTotal(coupons.length),
                    icon: Icons.confirmation_number_outlined,
                  ),
                  ConsoleStat(
                    label: l10n.redemptions,
                    value: '$redeemed',
                    hint: l10n.redemptionsHint,
                    icon: Icons.shopping_bag_outlined,
                  ),
                  ConsoleStat(
                    label: l10n.couponScheduled,
                    value: '${count(_CouponFilter.scheduled)}',
                    icon: Icons.event_outlined,
                  ),
                  ConsoleStat(
                    label: l10n.endedFilter,
                    value: '${count(_CouponFilter.ended)}',
                    icon: Icons.history_rounded,
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xl),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: ConsoleToolbar(
                      search: ConsoleSearchField(
                        hint: l10n.searchCodes,
                        initialValue: _query,
                        onChanged: (v) => setState(() => _query = v),
                      ),
                      filters: [
                        for (final f in _CouponFilter.values)
                          ConsoleFilterChip(
                            label: switch (f) {
                              _CouponFilter.all => l10n.all,
                              _CouponFilter.live => l10n.active,
                              _CouponFilter.scheduled => l10n.couponScheduled,
                              _CouponFilter.paused => l10n.pausedLabel,
                              _CouponFilter.ended => l10n.endedFilter,
                            },
                            count: f == _CouponFilter.all
                                ? coupons.length
                                : count(f),
                            selected: _filter == f,
                            onSelected: () => setState(() => _filter = f),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  FilledButton.icon(
                    onPressed: () => _showCouponForm(context, cubit),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(l10n.newCoupon),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              if (state.loading && coupons.isEmpty)
                const SizedBox(height: 240, child: LoadingView())
              else
                _CouponTable(
                  coupons: shown,
                  cubit: cubit,
                  storeNames: state.storeNames,
                  empty: coupons.isEmpty
                      ? ConsoleEmpty(
                          icon: Icons.confirmation_number_outlined,
                          title: l10n.couponsEmptyTitle,
                          message: l10n.couponsEmptyBody,
                        )
                      : ConsoleEmpty(
                          icon: Icons.search_off_rounded,
                          title: l10n.noMatches,
                        ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One thing to create here now that banners live on the Ads screen, so this
/// is a button rather than the two-item menu it used to open.
class _NewButton extends StatelessWidget {
  const _NewButton();

  @override
  Widget build(BuildContext context) {
    // The same shape as the "add" button on the categories and drivers
    // screens, rather than a one-off pill with its own shadow recipe.
    return FilledButton.icon(
      onPressed: () =>
          _showCouponForm(context, context.read<AdminCouponsCubit>()),
      icon: const Icon(Icons.add_rounded, size: 18),
      label: Text(context.l10n.newText),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel();

  @override
  Widget build(BuildContext context) {
    // Counts coupons, not banners. The old version read the *offers* cubit
    // even under the Coupons heading, which was left over from when this
    // screen owned both.
    final active = context.select(
      (AdminCouponsCubit c) => c.state.coupons.where((o) => o.isLive).length,
    );
    // Plain case rather than upper-cased with letter-spacing: that combination
    // is meant for Latin capitals and breaks the joins between Arabic letters
    // instead of emphasising them.
    return Text(
      '${context.l10n.coupons} · $active ${context.l10n.active}',
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: AppColors.textFaint,
      ),
    );
  }
}

class _CouponsSection extends StatelessWidget {
  const _CouponsSection();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AdminCouponsCubit, AdminCouponsState>(
      builder: (context, state) {
        if (state.loading) {
          return SkeletonTheme(
            child: SkeletonList(
              itemCount: 4,
              padding: EdgeInsets.zero,
              separator: const SizedBox(height: AppSpace.sm),
              itemBuilder: (_) =>
                  const Skeleton.box(height: 64, radius: AppRadii.lg),
            ),
          );
        }
        if (state.coupons.isEmpty) {
          return _emptyCard(context.l10n.noCouponsYetTapNew);
        }
        final cubit = context.read<AdminCouponsCubit>();
        if (AppBreakpoints.isWebWide(context)) {
          return _CouponTable(
            coupons: state.coupons,
            cubit: cubit,
            storeNames: state.storeNames,
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < state.coupons.length; i++)
                _CouponRow(
                  coupon: state.coupons[i],
                  cubit: cubit,
                  last: i == state.coupons.length - 1,
                  storeName: state.storeNames[state.coupons[i].vendorId],
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Web/wide: coupons as a real table.
///
/// A coupon is a record with the same six facts every time — code, what it
/// takes off, who it is for, how much of it is gone, when it dies, whether it
/// is on. Stacked cards make you re-find each of those in a different place
/// per row; columns put them where the eye already is.
class _CouponTable extends StatelessWidget {
  const _CouponTable({
    required this.coupons,
    required this.cubit,
    required this.storeNames,
    this.empty,
  });

  final List<Coupon> coupons;
  final AdminCouponsCubit cubit;
  final Map<String, String> storeNames;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final columns = [
      WebTableColumn(label: l10n.couponCode, flex: 2),
      WebTableColumn(label: l10n.discount, flex: 3),
      WebTableColumn(label: l10n.couponAppliesTo, flex: 2),
      WebTableColumn(label: l10n.usesColumn, width: 130),
      WebTableColumn(label: l10n.expiresLabel, width: 120),
      WebTableColumn(label: l10n.statusLabel, width: 120),
    ];
    const trailing = 96.0;
    const muted = TextStyle(fontSize: 12, color: AppColors.textMuted);

    return WebTable(
      columns: columns,
      trailingWidth: trailing,
      emptyState: empty,
      rows: [
        for (final coupon in coupons)
          WebTableRow.aligned(
            columns: columns,
            trailingWidth: trailing,
            onTap: () => _showCouponForm(
              context,
              cubit,
              coupon: coupon,
              storeName: storeNames[coupon.vendorId],
            ),
            cells: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: coupon.isLive
                          ? AppColors.warmFill
                          : AppColors.neutralFill,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    child: Text(
                      coupon.code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.mono(
                        13,
                        weight: FontWeight.w800,
                        color: coupon.isLive
                            ? AppColors.primary
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                  if (coupon.firstOrderOnly) ...[
                    const SizedBox(height: 3),
                    Text(l10n.couponFirstOrderOnly, style: muted),
                  ],
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _value(context, coupon),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  if (_limits(context, coupon) case final limits?)
                    Text(
                      limits,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted,
                    ),
                ],
              ),
              _StoreScopeCell(
                coupon: coupon,
                storeName: storeNames[coupon.vendorId],
              ),
              _UsageCell(coupon: coupon),
              Text(
                coupon.expiresAt == null
                    ? '—'
                    : DateFormat.yMMMd(language).format(coupon.expiresAt!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: coupon.isExpired
                      ? AppColors.dangerInk
                      : AppColors.textSecondary,
                ),
              ),
              _CouponStatus(coupon: coupon),
            ],
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Expired or exhausted codes cannot be switched back on by
                // flipping a toggle — the date or the cap is what stopped
                // them, so the switch would lie.
                ConsoleRowSwitch(
                  value: coupon.isActive,
                  onChanged: coupon.isExpired || coupon.isExhausted
                      ? null
                      : (_) => cubit.toggleActive(coupon),
                ),
                ConsoleMoreMenu(
                  actions: [
                    ConsoleMenuAction(
                      label: l10n.edit,
                      icon: Icons.edit_outlined,
                      onSelected: () => _showCouponForm(
                        context,
                        cubit,
                        coupon: coupon,
                        storeName: storeNames[coupon.vendorId],
                      ),
                    ),
                    ConsoleMenuAction(
                      label: l10n.delete,
                      icon: Icons.delete_outline_rounded,
                      danger: true,
                      onSelected: () =>
                          _confirmDeleteCoupon(context, coupon, cubit),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _value(BuildContext context, Coupon coupon) {
    final l10n = context.l10n;
    if (coupon.isFreeDelivery) return l10n.couponTypeFreeDelivery;
    return coupon.isPercentage
        ? '${coupon.value.toStringAsFixed(0)}% ${l10n.off}'
        : '${formatMoney(coupon.value)} ${l10n.off}';
  }

  String? _limits(BuildContext context, Coupon coupon) {
    final l10n = context.l10n;
    final parts = [
      if (coupon.minOrderAmount > 0)
        '${l10n.min} ${formatMoney(coupon.minOrderAmount)}',
      if (coupon.maxDiscount != null)
        '${l10n.max} ${formatMoney(coupon.maxDiscount!)}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// How much of a code is gone: the count, and against a cap a bar and what
/// is left.
class _UsageCell extends StatelessWidget {
  const _UsageCell({required this.coupon});

  final Coupon coupon;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final limit = coupon.usageLimit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          limit == null
              ? '${coupon.usedCount}'
              : '${coupon.usedCount} / $limit',
          style: AppType.mono(13.5, weight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        if (limit != null && limit > 0) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: (coupon.usedCount / limit).clamp(0, 1).toDouble(),
              minHeight: 4,
              backgroundColor: AppColors.neutralFill,
              color: coupon.isExhausted
                  ? AppColors.dangerInk
                  : AppColors.primary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            l10n.usesLeft((limit - coupon.usedCount).clamp(0, limit)),
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
        ] else
          Text(
            l10n.noUseLimit,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
      ],
    );
  }
}

/// "All stores", or the store's name with who pays for the discount.
class _StoreScopeCell extends StatelessWidget {
  const _StoreScopeCell({required this.coupon, this.storeName});

  final Coupon coupon;
  final String? storeName;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (coupon.vendorId == null) {
      return Text(
        l10n.couponAllStores,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          storeName ?? l10n.store,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        Text(
          coupon.isVendorFunded
              ? l10n.couponFundedStore
              : l10n.couponFundedPlatform,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

/// Why a coupon is or is not working, in one badge.
class _CouponStatus extends StatelessWidget {
  const _CouponStatus({required this.coupon});

  final Coupon coupon;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Order matters: a code can be expired *and* switched off, and the
    // reason it stopped is more useful than the switch position.
    final (label, fill, ink) = coupon.isExpired
        ? (l10n.expired, AppColors.dangerFill, AppColors.dangerInk)
        : coupon.isExhausted
        ? (l10n.couponExhausted, AppColors.dangerFill, AppColors.dangerInk)
        : coupon.isScheduled
        ? (l10n.couponScheduled, AppColors.amberFill, AppColors.amberInk)
        : coupon.isActive
        ? (l10n.active, AppColors.successFill, AppColors.successInk)
        : (l10n.pausedLabel, AppColors.neutralFill, AppColors.textMuted);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SoftBadge(label: label, fill: fill, ink: ink),
    );
  }
}

class _CouponRow extends StatelessWidget {
  const _CouponRow({
    required this.coupon,
    required this.cubit,
    required this.last,
    this.storeName,
  });

  final Coupon coupon;
  final AdminCouponsCubit cubit;
  final bool last;
  final String? storeName;

  String _summary(BuildContext context) {
    final l10n = context.l10n;
    final v = coupon.isFreeDelivery
        ? l10n.couponTypeFreeDelivery
        : coupon.isPercentage
        ? '${coupon.value.toStringAsFixed(0)}%'
        : formatMoney(coupon.value);
    final cap = coupon.maxDiscount != null
        ? ' · ${l10n.max} ${formatMoney(coupon.maxDiscount!)}'
        : '';
    final min = coupon.minOrderAmount > 0
        ? ' · ${l10n.min} ${formatMoney(coupon.minOrderAmount)}'
        : '';
    // The reason it is not working, when it is not working — an admin looking
    // at a list of codes needs that before anything else.
    if (coupon.isExpired) return '$v · ${l10n.expired}';
    if (coupon.isScheduled) return '$v · ${l10n.couponScheduled}';
    if (coupon.isExhausted) return '$v · ${l10n.couponExhausted}';
    return coupon.isFreeDelivery ? '$v$min' : '$v ${l10n.off}$cap$min';
  }

  /// Both limits on one line: how much of the campaign is gone, and how many
  /// times any one customer may take it.
  String _usage(BuildContext context) {
    final l10n = context.l10n;
    final limit = coupon.usageLimit == null ? '∞' : '${coupon.usageLimit}';
    final perUser = switch (coupon.perUserLimit) {
      null => l10n.perCustomerUnlimited,
      1 => l10n.oncePerCustomer,
      final n => l10n.usesPerCustomer(n),
    };
    final store = coupon.vendorId == null ? null : (storeName ?? l10n.store);
    return [
      if (store != null)
        '$store · ${coupon.isVendorFunded ? l10n.couponFundedStore : l10n.couponFundedPlatform}',
      '${coupon.usedCount} / $limit ${l10n.used}',
      perUser,
      if (coupon.firstOrderOnly) l10n.couponFirstOrderOnly,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final dim = !coupon.isLive;
    return Container(
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.borderSoft)),
      ),
      child: ListTile(
        onTap: () => _showCouponForm(
          context,
          cubit,
          coupon: coupon,
          storeName: storeName,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: dim ? AppColors.neutralFill : AppColors.amberFill,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            coupon.code,
            style: AppType.mono(
              13,
              color: dim ? AppColors.textFaint : AppColors.ink,
            ),
          ),
        ),
        title: Text(
          _summary(context),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: dim ? AppColors.textMuted : AppColors.ink,
          ),
        ),
        subtitle: Text(
          _usage(context),
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: coupon.isActive,
              activeThumbColor: AppColors.primary,
              onChanged: coupon.isExpired || coupon.isExhausted
                  ? null
                  : (_) => cubit.toggleActive(coupon),
            ),
            IconButton(
              tooltip: context.l10n.delete,
              onPressed: () => _confirmDelete(context),
              icon: const Icon(
                Icons.delete_outline,
                color: AppColors.dangerInk,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) =>
      _confirmDeleteCoupon(context, coupon, cubit);
}

/// Shared by the mobile row and the desktop table, so the two cannot drift
/// into asking for confirmation differently.
Future<void> _confirmDeleteCoupon(
  BuildContext context,
  Coupon coupon,
  AdminCouponsCubit cubit,
) async {
  final confirmed = await AppDialogs.showConfirmDialog(
    context: context,
    title: context.l10n.deleteCoupon,
    message: '"${coupon.code}" ${context.l10n.willBeRemoved}',
    confirmText: context.l10n.delete,
    cancelText: context.l10n.cancel,
    isDestructive: true,
    icon: Icons.confirmation_number_outlined,
  );
  if (confirmed == true) cubit.delete(coupon);
}

Widget _emptyCard(String message) => Container(
  width: double.infinity,
  padding: const EdgeInsets.all(22),
  decoration: BoxDecoration(
    color: AppColors.surface,
    border: Border.all(color: AppColors.border),
    borderRadius: BorderRadius.circular(16),
  ),
  child: Text(
    message,
    textAlign: TextAlign.center,
    style: const TextStyle(color: AppColors.textMuted),
  ),
);

// ---------------------------------------------------------------------------
// Forms
// ---------------------------------------------------------------------------

void _showCouponForm(
  BuildContext context,
  AdminCouponsCubit cubit, {
  Coupon? coupon,
  String? storeName,
}) {
  showAdaptiveSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: _CouponForm(coupon: coupon, storeName: storeName),
    ),
  );
}

class _CouponForm extends StatefulWidget {
  const _CouponForm({this.coupon, this.storeName});

  /// Null when creating. Editing reuses the same form, so the two can never
  /// offer different fields.
  final Coupon? coupon;
  final String? storeName;

  @override
  State<_CouponForm> createState() => _CouponFormState();
}

class _CouponFormState extends State<_CouponForm> {
  final _code = TextEditingController();
  final _title = TextEditingController();
  final _value = TextEditingController();
  final _minOrder = TextEditingController();
  final _maxDiscount = TextEditingController();
  final _limit = TextEditingController();

  /// Defaults to one use per customer. That is what an admin almost always
  /// means by "promo code", and the old form had no way to say it at all —
  /// which is why a single code could be spent on every order.
  final _perUser = TextEditingController(text: '1');

  _CouponKind _kind = _CouponKind.percentage;
  DateTime? _startsAt;
  DateTime? _expiresAt;
  bool _firstOrderOnly = false;
  bool _isPublic = false;
  bool _saving = false;

  Coupon? get _editing => widget.coupon;

  @override
  void initState() {
    super.initState();
    final coupon = widget.coupon;
    if (coupon == null) return;
    _code.text = coupon.code;
    _title.text = coupon.title ?? '';
    _value.text = coupon.isFreeDelivery ? '' : trimZeros(coupon.value);
    _minOrder.text = coupon.minOrderAmount > 0
        ? trimZeros(coupon.minOrderAmount)
        : '';
    _maxDiscount.text = coupon.maxDiscount == null
        ? ''
        : trimZeros(coupon.maxDiscount!);
    _limit.text = coupon.usageLimit?.toString() ?? '';
    _perUser.text = coupon.perUserLimit?.toString() ?? '';
    _kind = switch (coupon.discountType) {
      'percentage' => _CouponKind.percentage,
      'free_delivery' => _CouponKind.freeDelivery,
      _ => _CouponKind.fixed,
    };
    _startsAt = coupon.startsAt;
    _expiresAt = coupon.expiresAt;
    _firstOrderOnly = coupon.firstOrderOnly;
    _isPublic = coupon.isPublic;
    _storePays = coupon.isVendorFunded;
    if (coupon.vendorId != null) {
      // Only the id is on the coupon; the list passes the name it already
      // resolved so the field does not read "Store" until something is picked.
      _storeId = coupon.vendorId;
      _storeName = widget.storeName;
    }
  }

  /// Null = every store. A picked store scopes the code to that store only.
  String? _storeId;
  String? _storeName;

  /// Who pays for a store-scoped code. Defaults to the platform: an admin
  /// campaign should not quietly come out of the store's payout.
  bool _storePays = false;

  Future<void> _chooseStore() async {
    final picked = await pickActiveStore(context);
    if (picked == null || !mounted) return;
    setState(() {
      _storeId = picked.id;
      _storeName = picked.name;
      // A store offer exists to be seen on that store's page.
      _isPublic = true;
    });
  }

  @override
  void dispose() {
    _code.dispose();
    _title.dispose();
    _value.dispose();
    _minOrder.dispose();
    _maxDiscount.dispose();
    _limit.dispose();
    _perUser.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final initial = (start ? _startsAt : _expiresAt) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      // End of day for an expiry: a code that dies at midnight-as-typed would
      // stop working the moment the admin picked today.
      if (start) {
        _startsAt = picked;
      } else {
        _expiresAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _editing == null ? l10n.newCoupon : l10n.editCoupon,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              // labelText, not hintText: a hint disappears the moment typing
              // starts, and "Code · e.g. EATY40" is the field's name, not a
              // placeholder example to type over.
              decoration: InputDecoration(labelText: l10n.codeEgEaty40),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _title,
              decoration: InputDecoration(labelText: l10n.couponTitleLabel),
            ),
            const SizedBox(height: 10),
            _StoreScopeField(
              storeName: _storeId == null ? null : (_storeName ?? ''),
              onTap: _chooseStore,
              onClear: () => setState(() {
                _storeId = null;
                _storeName = null;
                _storePays = false;
              }),
            ),
            if (_storeId != null) ...[
              const SizedBox(height: 12),
              Text(
                l10n.couponFundedBy,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              SegmentedButton<bool>(
                expandedInsets: EdgeInsets.zero,
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.account_balance_rounded, size: 16),
                    label: Text(
                      l10n.couponFundedPlatform,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.storefront_rounded, size: 16),
                    label: Text(
                      l10n.couponFundedStore,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                selected: {_storePays},
                onSelectionChanged: (v) => setState(() => _storePays = v.first),
              ),
            ],
            const SizedBox(height: 12),
            SegmentedButton<_CouponKind>(
              // Full width with a single-line, ellipsised label per segment:
              // three Arabic labels ("نسبة مئوية" / "مبلغ ثابت (جنيه)" /
              // "توصيل مجاني") had nowhere to go on a ~320px sheet and wrapped
              // onto whatever room the segment happened to get.
              expandedInsets: EdgeInsets.zero,
              segments: [
                ButtonSegment(
                  value: _CouponKind.percentage,
                  label: Text(
                    l10n.percentage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: _CouponKind.fixed,
                  label: Text(
                    l10n.fixedEgp(currencySymbol),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: _CouponKind.freeDelivery,
                  label: Text(
                    l10n.couponTypeFreeDelivery,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            // Free delivery has no amount of its own: it is worth whatever the
            // store charges, resolved when the code is applied.
            if (_kind != _CouponKind.freeDelivery) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _value,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _kind == _CouponKind.percentage
                      ? l10n.discountPercent
                      : l10n.discountAmountEgp(currencySymbol),
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _minOrder,
              keyboardType: TextInputType.number,
              // Named plainly rather than "optional": the minimum basket is
              // the rule most campaigns actually turn on.
              decoration: InputDecoration(
                labelText: l10n.minOrderLabel,
                helperText: l10n.minOrderHint,
                helperMaxLines: 2,
              ),
            ),
            if (_kind == _CouponKind.percentage) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _maxDiscount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.maxDiscountCapOptional,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _perUser,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.perCustomerLimit,
                      helperText: l10n.perCustomerUnlimited,
                      helperMaxLines: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _limit,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.totalUsageLimit,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: l10n.couponStartsAt,
                    value: _startsAt,
                    onTap: () => _pickDate(start: true),
                    onClear: () => setState(() => _startsAt = null),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DateField(
                    label: l10n.couponExpiresAt,
                    value: _expiresAt,
                    onTap: () => _pickDate(start: false),
                    onClear: () => setState(() => _expiresAt = null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _firstOrderOnly,
              onChanged: (v) => setState(() => _firstOrderOnly = v),
              title: Text(l10n.couponFirstOrderOnly),
              subtitle: Text(
                l10n.couponFirstOrderOnlyDesc,
                style: const TextStyle(fontSize: 11.5),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isPublic,
              onChanged: (v) => setState(() => _isPublic = v),
              title: Text(
                _storeId == null
                    ? l10n.couponPublic
                    : l10n.couponShowOnStorePage,
              ),
              subtitle: Text(
                _storeId == null
                    ? l10n.couponPublicDesc
                    : l10n.couponShowOnStorePageDesc(_storeName ?? ''),
                style: const TextStyle(fontSize: 11.5),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const ButtonSpinner()
                  : Text(_editing == null ? l10n.createCoupon : l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    final value = double.tryParse(_value.text.trim());
    final needsValue = _kind != _CouponKind.freeDelivery;
    if (code.isEmpty || (needsValue && (value == null || value <= 0))) {
      showSnack(context, context.l10n.enterACodeAndAValidDiscount, error: true);
      return;
    }
    setState(() => _saving = true);
    final editing = _editing;
    final cubit = context.read<AdminCouponsCubit>();
    final ok = editing != null
        ? await cubit.edit(
            id: editing.id,
            code: code,
            discountType: _kind.wire,
            value: value ?? 0,
            minOrderAmount: double.tryParse(_minOrder.text.trim()) ?? 0,
            maxDiscount: _kind == _CouponKind.percentage
                ? double.tryParse(_maxDiscount.text.trim())
                : null,
            usageLimit: int.tryParse(_limit.text.trim()),
            perUserLimit: int.tryParse(_perUser.text.trim()),
            startsAt: _startsAt,
            expiresAt: _expiresAt,
            firstOrderOnly: _firstOrderOnly,
            isPublic: _isPublic,
            title: _title.text.trim().isEmpty ? null : _title.text.trim(),
            vendorId: _storeId,
            fundedBy: _storePays ? 'vendor' : 'platform',
          )
        : await cubit.create(
            code: code,
            discountType: _kind.wire,
            value: value ?? 0,
            minOrderAmount: double.tryParse(_minOrder.text.trim()) ?? 0,
            maxDiscount: _kind == _CouponKind.percentage
                ? double.tryParse(_maxDiscount.text.trim())
                : null,
            usageLimit: int.tryParse(_limit.text.trim()),
            // Blank means unlimited, which the server reads as a null column.
            perUserLimit: int.tryParse(_perUser.text.trim()),
            startsAt: _startsAt,
            expiresAt: _expiresAt,
            firstOrderOnly: _firstOrderOnly,
            isPublic: _isPublic,
            title: _title.text.trim().isEmpty ? null : _title.text.trim(),
            vendorId: _storeId,
            fundedBy: _storePays ? 'vendor' : 'platform',
          );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
      showSnack(
        context,
        editing == null
            ? context.l10n.couponCreated
            : context.l10n.couponUpdated,
      );
    } else {
      setState(() => _saving = false);
    }
  }
}

/// Which stores a code works in: all of them, or the one picked.
class _StoreScopeField extends StatelessWidget {
  const _StoreScopeField({
    required this.storeName,
    required this.onTap,
    required this.onClear,
  });

  /// Null when the code applies to every store.
  final String? storeName;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final picked = storeName;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.couponAppliesTo,
          isDense: true,
          prefixIcon: const Icon(Icons.storefront_rounded, size: 18),
          suffixIcon: picked == null
              ? const Icon(Icons.search_rounded, size: 18)
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: onClear,
                  tooltip: l10n.couponAllStores,
                ),
        ),
        child: Text(
          (picked?.isEmpty ?? true)
              ? (picked == null ? l10n.couponAllStores : l10n.store)
              : picked!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: picked == null ? FontWeight.w400 : FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// The three shapes a discount can take.
enum _CouponKind {
  percentage('percentage'),
  fixed('fixed'),
  freeDelivery('free_delivery');

  const _CouponKind(this.wire);

  final String wire;
}

/// A date the admin may set or leave empty — an unset start means "live now",
/// an unset expiry means "until switched off".
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          suffixIcon: value == null
              ? const Icon(Icons.event_outlined, size: 18)
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: onClear,
                  tooltip: context.l10n.clearDate,
                ),
        ),
        child: Text(
          value == null
              ? context.l10n.notSet
              : DateFormat.yMMMd(
                  Localizations.localeOf(context).languageCode,
                ).format(value!),
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}
