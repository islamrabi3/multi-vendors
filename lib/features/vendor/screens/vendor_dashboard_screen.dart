import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/tokens.dart';
import '../../../core/models/order.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/repositories/vendor_admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_cubit.dart';
import '../vendor_orders_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

enum _OrderFilter { incoming, preparing, ready }

class VendorDashboardScreen extends StatelessWidget {
  const VendorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vendor = context.read<AuthCubit>().state.vendor;
    if (vendor == null) return const LoadingView();
    return BlocProvider(
      create: (_) => VendorOrdersCubit(OrderRepository(), vendor.id,
          autoAccept: vendor.autoAccept),
      child: const _DashboardView(),
    );
  }
}

class _DashboardView extends StatefulWidget {
  const _DashboardView();

  @override
  State<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<_DashboardView> {
  final _admin = VendorAdminRepository();
  _OrderFilter _filter = _OrderFilter.incoming;
  bool _togglingOpen = false;

  Future<void> _toggleOpen(bool open) async {
    final auth = context.read<AuthCubit>();
    final vendor = auth.state.vendor;
    if (vendor == null) return;
    setState(() => _togglingOpen = true);
    try {
      final updated = await _admin.updateVendor(vendor.id, {'is_open': open});
      auth.vendorUpdated(updated);
    } catch (error) {
      if (mounted) showSnack(context, readableError(error), error: true);
    } finally {
      if (mounted) setState(() => _togglingOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendor = context.select((AuthCubit c) => c.state.vendor);
    if (vendor == null) return const LoadingView();

    // Keep the cubit's auto-accept flag in sync with settings changes.
    context.read<VendorOrdersCubit>().autoAccept = vendor.autoAccept;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: BlocConsumer<VendorOrdersCubit, VendorOrdersState>(
        listenWhen: (p, c) => c.newOrderArrived || c.error != null,
        listener: (context, state) {
          if (state.newOrderArrived) {
            showSnack(context, context.l10n.newOrderReceived);
          } else if (state.error != null) {
            showSnack(context, readableError(state.error!), error: true);
          }
        },
        builder: (context, state) {
          return Column(
            children: [
              _Header(
                vendor: vendor,
                togglingOpen: _togglingOpen,
                onToggleOpen: _toggleOpen,
              ),
              if (state.loading)
                const Expanded(child: LoadingView())
              else ...[
                _KpiStrip(
                  revenue: state.todayRevenue,
                  orders: state.todayOrderCount,
                  avgPrep: vendor.avgPrepMinutes,
                ),
                _FilterTabs(
                  filter: _filter,
                  incoming: state.pending.length,
                  preparing: state.preparing.length,
                  ready: state.ready.length,
                  onChanged: (f) => setState(() => _filter = f),
                ),
                Expanded(
                  child: RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: context.read<VendorOrdersCubit>().refresh,
                    child: _OrderList(orders: _visibleOrders(state)),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  List<AppOrder> _visibleOrders(VendorOrdersState state) => switch (_filter) {
        _OrderFilter.incoming => state.pending,
        _OrderFilter.preparing => state.preparing,
        _OrderFilter.ready => state.ready,
      };
}

class _Header extends StatelessWidget {
  const _Header({
    required this.vendor,
    required this.togglingOpen,
    required this.onToggleOpen,
  });

  final Vendor vendor;
  final bool togglingOpen;
  final ValueChanged<bool> onToggleOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.ink,
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 12, 16, 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.warmFill,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            clipBehavior: Clip.antiAlias,
            child: vendor.logoUrl != null
                ? AppNetworkImage(url: vendor.logoUrl, width: 44, height: 44)
                : const Icon(Icons.storefront_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vendor.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.heading(18, color: Colors.white),
                ),
                if (vendor.addressText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    vendor.addressText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _OpenToggle(
              isOpen: vendor.isOpen,
              busy: togglingOpen,
              onChanged: onToggleOpen),
        ],
      ),
    );
  }
}

class _OpenToggle extends StatelessWidget {
  const _OpenToggle({
    required this.isOpen,
    required this.busy,
    required this.onChanged,
  });

  final bool isOpen;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 5, 5, 5),
      decoration: BoxDecoration(
        color: isOpen
            ? AppColors.success.withValues(alpha: 0.15)
            : AppColors.textMuted.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
          color: isOpen
              ? AppColors.success.withValues(alpha: 0.3)
              : AppColors.textMuted.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isOpen ? context.l10n.open.toUpperCase() : context.l10n.closed.toUpperCase(),
            style: TextStyle(
                color: isOpen ? AppColors.success : AppColors.textMuted,
                fontWeight: FontWeight.w800,
                fontSize: 10.5,
                letterSpacing: 0.5),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 38,
            height: 22,
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(3),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: isOpen,
                      onChanged: onChanged,
                      activeThumbColor: Colors.white,
                      activeTrackColor: AppColors.success,
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor: AppColors.border,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _KpiStrip extends StatelessWidget {
  const _KpiStrip({
    required this.revenue,
    required this.orders,
    required this.avgPrep,
  });

  final double revenue;
  final int orders;
  final int avgPrep;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          _kpiCard(
            value: formatMoney(revenue),
            label: context.l10n.today,
            icon: Icons.payments_rounded,
            bgColor: AppColors.warmFill,
            iconColor: AppColors.primary,
          ),
          const SizedBox(width: 10),
          _kpiCard(
            value: '$orders',
            label: context.l10n.orders,
            icon: Icons.shopping_bag_rounded,
            bgColor: AppColors.successFill,
            iconColor: AppColors.successInk,
          ),
          const SizedBox(width: 10),
          _kpiCard(
            value: '$avgPrep′',
            label: context.l10n.avgPrep,
            icon: Icons.timer_rounded,
            bgColor: AppColors.amberFill,
            iconColor: AppColors.amberInk,
          ),
        ],
      ),
    );
  }

  Widget _kpiCard({
    required String value,
    required String label,
    required IconData icon,
    required Color bgColor,
    required Color iconColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadii.xl),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 16),
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: AppType.mono(18, color: AppColors.ink, weight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({
    required this.filter,
    required this.incoming,
    required this.preparing,
    required this.ready,
    required this.onChanged,
  });

  final _OrderFilter filter;
  final int incoming;
  final int preparing;
  final int ready;
  final ValueChanged<_OrderFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          _tab(context.l10n.newText, incoming, _OrderFilter.incoming, context),
          const SizedBox(width: 10),
          _tab(context.l10n.preparing, preparing, _OrderFilter.preparing, context),
          const SizedBox(width: 10),
          _tab(context.l10n.ready, ready, _OrderFilter.ready, context),
        ],
      ),
    );
  }

  Widget _tab(String label, int count, _OrderFilter value, BuildContext context) {
    final selected = filter == value;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.surface,
          border: Border.all(
            color: selected ? AppColors.ink : AppColors.border,
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: selected ? AppShadows.card : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary
                    : AppColors.warmFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  const _OrderList({required this.orders});

  final List<AppOrder> orders;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          EmptyView(
              message: context.l10n.nothingHereRightNow,
              icon: Icons.receipt_long_outlined),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _OrderCard(order: orders[i]),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final AppOrder order;

  String _payLabel(BuildContext context) => order.isCod
      ? context.l10n.cod
      : order.isPaid
          ? context.l10n.cardPaid
          : context.l10n.cardUnpaid;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<VendorOrdersCubit>();
    final isNew = order.status == OrderStatus.pending;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(
          color: isNew ? AppColors.primary.withValues(alpha: 0.3) : AppColors.border,
          width: isNew ? 1.6 : 1.0,
        ),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => context.push('/vendor-app/orders/${order.id}'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order.orderNumber,
                              style: AppType.mono(14.5, color: AppColors.ink, weight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${order.customerName ?? context.l10n.customer} · '
                              '${DateFormat('h:mm a').format(order.createdAt)}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OrderStatusChip(status: order.status),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TOTAL AMOUNT',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textFaint,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 3),
                          PriceText(formatMoney(order.total), size: 16),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: order.isCod ? AppColors.amberFill : AppColors.successFill,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                        child: Text(
                          _payLabel(context).toUpperCase(),
                          style: TextStyle(
                            color: order.isCod ? AppColors.amberInk : AppColors.successInk,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  _ActionRow(order: order, cubit: cubit),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.order, required this.cubit});

  final AppOrder order;
  final VendorOrdersCubit cubit;

  Future<void> _rejectWithReason(BuildContext context) async {
    final localUnavailable = context.l10n.unavailable;
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.rejectOrder),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: context.l10n.reason),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.l10n.back)),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(context.l10n.reject),
          ),
        ],
      ),
    );
    if (reason != null) {
      await cubit.reject(order, reason.isEmpty ? localUnavailable : reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = switch (order.status) {
      OrderStatus.pending => Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                    )),
                onPressed: () => _rejectWithReason(context),
                child: Text(context.l10n.reject),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                    )),
                onPressed: () => cubit.accept(order),
                child: Text(context.l10n.acceptOrder),
              ),
            ),
          ],
        ),
      OrderStatus.accepted => FilledButton(
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.lg),
              )),
          onPressed: () => cubit.startPreparing(order),
          child: Text(context.l10n.startPreparing),
        ),
      OrderStatus.preparing => FilledButton(
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.lg),
              )),
          onPressed: () => cubit.markReady(order),
          child: Text(context.l10n.markReadyForPickup),
        ),
      OrderStatus.readyForPickup => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              const Icon(Icons.hourglass_empty_rounded, color: AppColors.success, size: 16),
              const SizedBox(width: 6),
              Text(
                context.l10n.waitingForADriver,
                style: const TextStyle(
                    color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ],
          ),
        ),
      _ => const SizedBox.shrink(),
    };
    if (child is SizedBox) return child;
    return Padding(padding: const EdgeInsets.only(top: 14), child: child);
  }
}
