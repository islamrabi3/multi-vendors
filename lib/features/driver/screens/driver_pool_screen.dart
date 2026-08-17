import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/tokens.dart';
import '../../../core/models/order.dart';
import '../../../core/repositories/driver_repository.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/messages_button.dart';
import '../../../core/widgets/notification_bell.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../auth/auth_cubit.dart';
import '../driver_pool_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';
import 'package:multi_vendor/app/locale_cubit.dart';

class DriverPoolScreen extends StatelessWidget {
  const DriverPoolScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DriverPoolCubit(OrderRepository(), DriverRepository()),
      child: const _PoolView(),
    );
  }
}

class _PoolView extends StatefulWidget {
  const _PoolView();

  @override
  State<_PoolView> createState() => _PoolViewState();
}

class _PoolViewState extends State<_PoolView> {
  // One subscription, read by both the availability switch and the banner.
  late final Stream<DriverVerification> _verification = DriverRepository()
      .watchVerification();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DriverPoolCubit, DriverPoolState>(
      listenWhen: (previous, current) =>
          current.claimedOrderId != null || current.error != null,
      listener: (context, state) {
        if (state.claimedOrderId != null) {
          showSnack(context, context.l10n.orderClaimedHeadToTheStore);
          context.go('/driver-app/active');
        } else if (state.error != null) {
          showFailure(context, state.error!);
        }
      },
      builder: (context, state) {
        final cubit = context.read<DriverPoolCubit>();
        return StreamBuilder<DriverVerification>(
          stream: _verification,
          builder: (context, snap) {
            final verification = snap.data;
            // Until the row arrives, assume approved: an approved driver is
            // the normal case, and briefly disabling their switch on every
            // cold start would be worse than the rare wrong-way flash.
            final canWork = verification?.isApproved ?? true;
            return Scaffold(
              backgroundColor: AppColors.canvas,
              body: Column(
                children: [
                  _Header(
                    state: state,
                    onToggle: cubit.setOnline,
                    canWork: canWork,
                  ),
                  if (verification != null)
                    _VerificationBanner(verification: verification),
                  if (state.loading)
                    const Expanded(child: _PoolSkeleton())
                  else if (!state.isOnline)
                    Expanded(
                      child: RefreshIndicator(
                        color: AppColors.primary,
                        onRefresh: cubit.refresh,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 140),
                            EmptyView(
                              message: canWork
                                  ? context.l10n.goOnlineToSeeAvailableOrders
                                  : context.l10n.unverifiedDriverNotice,
                              icon: canWork
                                  ? Icons.power_settings_new
                                  : Icons.verified_user_outlined,
                            ),
                            const SizedBox(height: AppSpace.xxl),
                            // The state told the driver to go online but gave them
                            // no way to; the only toggle was a switch buried in the
                            // header, well off the reading path.
                            //
                            // Hidden outright while unverified rather than
                            // disabled: going online is refused server-side, so
                            // a greyed button is a dead end with no explanation.
                            // The banner above already says why and what to do.
                            if (canWork)
                              Center(
                                child: FilledButton.icon(
                                  onPressed: () => cubit.setOnline(true),
                                  icon: const Icon(
                                    Icons.power_settings_new,
                                    size: 20,
                                  ),
                                  label: Text(context.l10n.available),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.success,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 28,
                                      vertical: AppSpace.md,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.l10n.availableNearby,
                              style: AppType.display(18),
                            ),
                          ),
                          SoftBadge(
                            label:
                                '${state.orders.length} ${context.l10n.ready}',
                            fill: AppColors.warmFill,
                            ink: AppColors.primaryDark,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        color: AppColors.primary,
                        onRefresh: cubit.refresh,
                        child: state.orders.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 120),
                                  EmptyView(
                                    message:
                                        context.l10n.noOrdersWaitingForPickup,
                                    icon: Icons.hourglass_empty,
                                  ),
                                ],
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  4,
                                  20,
                                  24,
                                ),
                                itemCount: state.orders.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final order = state.orders[index];
                                  return _PoolCard(
                                    order: order,
                                    label: state.vendorLabels[order.vendorId],
                                    claiming: state.claimingOrderId == order.id,
                                    // Any claim in flight locks the rest of the
                                    // pool: two claims at once can only lose one.
                                    enabled: state.claimingOrderId == null,
                                    onClaim: () => cubit.claim(order),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Language, support and sign out — everything that is not "am I working".
///
/// These lived in the header as bare controls: a language switch identical to
/// the online switch, and a one-tap sign out with no confirmation. Support was
/// unreachable from the driver app entirely.
void _showDriverControls(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
    ),
    builder: (sheetContext) {
      final l10n = sheetContext.l10n;
      final isArabic =
          sheetContext.watch<LocaleCubit>().state.languageCode == 'ar';
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              value: isArabic,
              onChanged: (v) => sheetContext.read<LocaleCubit>().setLocale(
                Locale(v ? 'ar' : 'en'),
              ),
              secondary: const Icon(
                Icons.language_outlined,
                color: AppColors.textSecondary,
              ),
              title: Text(
                l10n.appLanguage,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                isArabic ? 'العربية' : 'English',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.borderSoft),
            ListTile(
              leading: const Icon(
                Icons.support_agent_outlined,
                color: AppColors.textSecondary,
              ),
              title: Text(
                l10n.contactSupport,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textFaint,
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/support');
              },
            ),
            const Divider(height: 1, color: AppColors.borderSoft),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.dangerInk),
              title: Text(
                l10n.signOut,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.dangerInk,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                context.read<AuthCubit>().signOut();
              },
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ),
      );
    },
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.onToggle,
    required this.canWork,
  });

  final DriverPoolState state;
  final ValueChanged<bool> onToggle;

  /// False while the driver is pending, rejected or suspended. Going online is
  /// refused server-side in that state, so offering the switch only produces
  /// an error the driver cannot act on.
  final bool canWork;

  String _greeting(BuildContext context) {
    final hour = DateTime.now().hour;
    if (hour < 12) return context.l10n.goodMorning;
    if (hour < 18) return context.l10n.goodAfternoon;
    return context.l10n.goodEvening;
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.select((AuthCubit c) => c.state.profile);
    final first = profile?.fullName.trim().split(' ').first;
    final firstName = (first == null || first.isEmpty)
        ? context.l10n.there
        : first;
    final greetingText = _greeting(context);
    return Container(
      color: AppColors.ink,
      padding: EdgeInsets.fromLTRB(
        22,
        MediaQuery.of(context).padding.top + 8,
        16,
        18,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$greetingText, $firstName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: state.isOnline && canWork
                                ? AppColors.onDarkSuccess
                                : AppColors.primaryLight,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            !canWork
                                ? context.l10n.driverVerificationTitle
                                : state.isOnline
                                ? context.l10n.youAreOnline
                                : context.l10n.youAreOffline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // The one control that decides whether the driver is working.
              // It used to sit beside an identically styled language switch,
              // so knocking yourself offline was one wrong tap away.
              Switch(
                value: state.isOnline && canWork,
                onChanged: state.loading || !canWork ? null : onToggle,
                activeThumbColor: Colors.white,
                activeTrackColor: AppColors.success,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: AppColors.onDarkTrack,
              ),
              const SizedBox(width: 4),
              const MessagesButton(compact: true, dark: true),
              const NotificationBell(compact: true, dark: true),
              IconButton(
                tooltip: context.l10n.settings,
                onPressed: () => _showDriverControls(context),
                icon: const Icon(
                  Icons.more_vert,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DarkStatTile(
                  value: formatMoney(state.todayEarnings),
                  label: context.l10n.earnedToday,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: DarkStatTile(
                  value: '${state.todayTrips}',
                  label: context.l10n.trips,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: DarkStatTile(
                  value: state.isOnline ? '${state.orders.length}' : '—',
                  label: context.l10n.inThePool,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PoolCard extends StatelessWidget {
  const _PoolCard({
    required this.order,
    required this.label,
    required this.onClaim,
    required this.claiming,
    required this.enabled,
  });

  final AppOrder order;
  final ({String name, String? logoUrl})? label;
  final VoidCallback onClaim;

  /// This card's claim is in flight.
  final bool claiming;

  /// No claim anywhere in the pool is in flight.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        // A 1px border and a drop shadow on the same card is the "ghost card"
        // look; the border alone reads better on the pool's canvas.
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.warmFill,
                  borderRadius: BorderRadius.circular(11),
                ),
                clipBehavior: Clip.antiAlias,
                child: label?.logoUrl != null
                    ? AppNetworkImage(
                        url: label!.logoUrl,
                        width: 38,
                        height: 38,
                      )
                    : const Icon(
                        Icons.storefront,
                        size: 20,
                        color: AppColors.primary,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label?.name ?? order.orderNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      '${context.l10n.ready} · ${DateFormat('h:mm a').format(order.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              // Capped: this column took whatever width it wanted, so a
              // four-figure fee or a longer translation of "payout" squeezed
              // the store name beside it down to an ellipsis.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        formatMoney(order.deliveryFee),
                        maxLines: 1,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                    Text(
                      context.l10n.payout,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          const Divider(height: 1, color: AppColors.borderSoft),
          const SizedBox(height: 11),
          Row(
            children: [
              const Icon(
                Icons.place_outlined,
                size: 15,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  order.addressSummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.success,
              minimumSize: const Size.fromHeight(48),
              textStyle: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            onPressed: enabled ? onClaim : null,
            // The cash variant is three pieces plus an amount, and in Arabic
            // it ran past a fixed-height button and was simply cut off — the
            // driver could not read what they were about to collect. Scaling
            // down keeps the whole label legible at any width instead.
            child: claiming
                ? const ButtonSpinner()
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      order.isCod
                          ? '${context.l10n.claimCollect} '
                                '${formatMoney(order.total)} '
                                '${context.l10n.cash}'
                          : context.l10n.claimDelivery,
                      maxLines: 1,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The pool while presence and the first realtime snapshot resolve. The dark
/// header above stays live, so this covers only the list area.
class _PoolSkeleton extends StatelessWidget {
  const _PoolSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonTheme(
      child: SkeletonList(
        itemCount: 4,
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xl,
          AppSpace.lg,
          AppSpace.xl,
          AppSpace.xxl,
        ),
        separator: const SizedBox(height: AppSpace.md),
        itemBuilder: (_) => DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Padding(
            padding: EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Skeleton(width: 38, height: 38, radius: AppRadii.sm),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Skeleton.line(widthFactor: 0.55, height: 14),
                          SizedBox(height: 5),
                          Skeleton.line(widthFactor: 0.4, height: 11),
                        ],
                      ),
                    ),
                    SizedBox(width: AppSpace.sm),
                    Skeleton(width: 56, height: 30),
                  ],
                ),
                SizedBox(height: 13),
                Skeleton.line(widthFactor: 0.7, height: 12),
                SizedBox(height: AppSpace.md),
                Skeleton(height: 48, radius: 13),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown until a driver is approved.
///
/// Going online is refused server-side by is_online_driver(), which requires
/// approval_status = 'active' — so an unverified driver cannot claim anything.
/// This says so in words, and routes to the one thing that unblocks them.
///
/// Live, because approval happens on someone else's screen: an admin's
/// decision lands here as it is made rather than the next time the driver
/// reopens the app.
class _VerificationBanner extends StatelessWidget {
  const _VerificationBanner({required this.verification});

  final DriverVerification verification;

  @override
  Widget build(BuildContext context) {
    // Nothing to say to an approved driver.
    if (verification.isApproved) {
      return const SizedBox.shrink();
    }
    final needsAction = verification.needsAttention;
    final suspended = verification.isSuspended;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        AppSpace.lg,
        AppSpace.sm,
      ),
      child: Material(
        color: suspended
            ? AppColors.dangerFill
            : needsAction
            ? AppColors.warmFill
            : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          onTap: suspended
              ? null
              : () => context.push('/driver-app/pool/documents'),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Row(
              children: [
                Icon(
                  suspended
                      ? Icons.block_rounded
                      : needsAction
                      ? Icons.assignment_late_rounded
                      : Icons.hourglass_top_rounded,
                  size: 20,
                  color: suspended
                      ? AppColors.dangerInk
                      : AppColors.primaryDark,
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Always the consequence first: what they cannot do,
                      // before what they have to do about it.
                      Text(
                        suspended
                            ? context.l10n.driverVerificationSuspended
                            : context.l10n.unverifiedDriverNotice,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          color: suspended
                              ? AppColors.dangerInk
                              : AppColors.primaryDark,
                        ),
                      ),
                      if (!suspended) ...[
                        const SizedBox(height: 2),
                        Text(
                          needsAction
                              ? context.l10n.driverDocumentsMissingBanner
                              : context.l10n.driverVerificationPending,
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.3,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!suspended)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.primaryDark,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
