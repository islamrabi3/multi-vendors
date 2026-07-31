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

class _PoolView extends StatelessWidget {
  const _PoolView();

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
          showSnack(context, readableError(state.error!), error: true);
        }
      },
      builder: (context, state) {
        final cubit = context.read<DriverPoolCubit>();
        return Scaffold(
          backgroundColor: AppColors.canvas,
          body: Column(
            children: [
              _Header(state: state, onToggle: cubit.setOnline),
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
                            message: context.l10n.goOnlineToSeeAvailableOrders,
                            icon: Icons.power_settings_new),
                        const SizedBox(height: AppSpace.xxl),
                        // The state told the driver to go online but gave them
                        // no way to; the only toggle was a switch buried in the
                        // header, well off the reading path.
                        Center(
                          child: FilledButton.icon(
                            onPressed: () => cubit.setOnline(true),
                            icon: const Icon(Icons.power_settings_new, size: 20),
                            label: Text(context.l10n.available),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.success,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 28, vertical: AppSpace.md),
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
                        child: Text(context.l10n.availableNearby,
                            style: AppType.display(18)),
                      ),
                      SoftBadge(
                        label: '${state.orders.length} ${context.l10n.ready}',
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
                                  message: context.l10n.noOrdersWaitingForPickup,
                                  icon: Icons.hourglass_empty),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                            itemCount: state.orders.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final order = state.orders[index];
                              return _PoolCard(
                                order: order,
                                label: state.vendorLabels[order.vendorId],
                                claiming:
                                    state.claimingOrderId == order.id,
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
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.onToggle});

  final DriverPoolState state;
  final ValueChanged<bool> onToggle;

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
    final firstName = (first == null || first.isEmpty) ? context.l10n.there : first;
    final greetingText = _greeting(context);
    return Container(
      color: AppColors.ink,
      padding: EdgeInsets.fromLTRB(
          22, MediaQuery.of(context).padding.top + 8, 16, 18),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$greetingText, $firstName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.6))),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: state.isOnline
                                ? AppColors.onDarkSuccess
                                : AppColors.primaryLight,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                            state.isOnline
                                ? context.l10n.youAreOnline
                                : context.l10n.youAreOffline,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                                color: Colors.white)),
                      ],
                    ),
                  ],
                ),
              ),
              Switch(
                value: state.isOnline,
                onChanged: state.loading ? null : onToggle,
                activeThumbColor: Colors.white,
                activeTrackColor: AppColors.success,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: AppColors.onDarkTrack,
              ),
              const SizedBox(width: AppSpace.sm),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.watch<LocaleCubit>().state.languageCode == 'ar' ? 'AR' : 'EN',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: Colors.white70),
                  ),
                  const SizedBox(width: 2),
                  Switch(
                    value: context.watch<LocaleCubit>().state.languageCode == 'ar',
                    onChanged: (v) {
                      context.read<LocaleCubit>().setLocale(
                          v ? const Locale('ar') : const Locale('en'));
                    },
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.success,
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: AppColors.onDarkTrack,
                  ),
                ],
              ),
              IconButton(
                tooltip: context.l10n.signOut,
                onPressed: () => context.read<AuthCubit>().signOut(),
                icon: Icon(Icons.logout,
                    size: 20, color: Colors.white.withValues(alpha: 0.7)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DarkStatTile(
                    value: formatMoney(state.todayEarnings),
                    label: context.l10n.earnedToday),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: DarkStatTile(
                    value: '${state.todayTrips}', label: context.l10n.trips),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: DarkStatTile(
                    value: state.isOnline ? '${state.orders.length}' : '—',
                    label: context.l10n.inThePool),
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
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.card,
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
                        url: label!.logoUrl, width: 38, height: 38)
                    : const Icon(Icons.storefront,
                        size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label?.name ?? order.orderNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: AppColors.ink)),
                    Text(
                        '${context.l10n.ready} · ${DateFormat('h:mm a').format(order.createdAt)}',
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.textMuted)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatMoney(order.deliveryFee),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.success)),
                  Text(context.l10n.payout,
                      style: TextStyle(
                          fontSize: 10.5, color: AppColors.textFaint)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 13),
          const Divider(height: 1, color: AppColors.borderSoft),
          const SizedBox(height: 11),
          Row(
            children: [
              const Icon(Icons.place_outlined,
                  size: 15, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(order.addressSummary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.success,
              minimumSize: const Size.fromHeight(48),
              textStyle:
                  const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13)),
            ),
            onPressed: enabled ? onClaim : null,
            child: claiming
                ? const ButtonSpinner()
                : Text(order.isCod
                    ? '${context.l10n.claimCollect} ${formatMoney(order.total)} ${context.l10n.cash}'
                    : context.l10n.claimDelivery),
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
            AppSpace.xl, AppSpace.lg, AppSpace.xl, AppSpace.xxl),
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
