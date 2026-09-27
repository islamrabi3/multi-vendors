import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/models/order.dart';
import '../../../core/models/order_flow.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/supabase_client.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/time_format.dart';

/// Everything a driver needs to know about an order, before or after taking
/// it: where it comes from and goes to, what is in the bag, what to collect.
///
/// The customer's phone number is only shown once this driver has the order;
/// before that the order is still anyone's, and so is the customer's number.
Future<void> showDriverOrderDetails(BuildContext context, AppOrder order) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.canvas,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, controller) =>
            _DriverOrderDetails(order: order, controller: controller),
      ),
    );

class _DriverOrderDetails extends StatefulWidget {
  const _DriverOrderDetails({required this.order, required this.controller});

  final AppOrder order;
  final ScrollController controller;

  @override
  State<_DriverOrderDetails> createState() => _DriverOrderDetailsState();
}

class _DriverOrderDetailsState extends State<_DriverOrderDetails> {
  late final Future<AppOrder> _full = OrderRepository()
      .fetchOrder(widget.order.id)
      // The row on screen is enough to show the trip even if the full read
      // fails; the items section says so on its own.
      .catchError((Object _) => widget.order);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppOrder>(
      future: _full,
      builder: (context, snap) {
        final order = snap.data ?? widget.order;
        final loading = snap.connectionState != ConnectionState.done;
        return ListView(
          controller: widget.controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            _Header(order: order),
            const SizedBox(height: AppSpace.lg),
            _Route(order: order),
            const SizedBox(height: AppSpace.lg),
            _Section(
              title: context.l10n.items,
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpace.lg),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _Items(order: order),
            ),
            if ((order.customerNotes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              _Section(
                title: context.l10n.customerNote,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    order.customerNotes!.trim(),
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpace.md),
            _Section(
              title: context.l10n.payment,
              child: _Money(order: order),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.order});

  final AppOrder order;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.orderRef(order.orderNumber),
                style: AppType.heading(20),
              ),
              const SizedBox(height: 2),
              Text(
                '${formatClock(context, order.createdAt)} · '
                '${order.orderFlow == OrderFlow.direct ? l10n.buyAndDeliver : l10n.pickUpAndDeliver}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: order.isCod ? AppColors.amberFill : AppColors.successFill,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Text(
            order.isCod ? l10n.collectCashBadge : l10n.paidOnlineBadge,
            style: TextStyle(
              color: order.isCod ? AppColors.amberInk : AppColors.successInk,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

/// From the store, to the customer — as two stops.
class _Route extends StatelessWidget {
  const _Route({required this.order});

  final AppOrder order;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final a = order.deliveryAddress;
    final mine = order.driverId == supabase.auth.currentUser?.id;
    String? part(String key) {
      final v = (a[key] as String?)?.trim();
      return v == null || v.isEmpty ? null : v;
    }

    final detail = [
      if (part('building') != null) l10n.buildingShort(part('building')!),
      if (part('floor') != null) l10n.floorShort(part('floor')!),
      if (part('apartment') != null) l10n.apartmentShort(part('apartment')!),
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        children: [
          _Stop(
            icon: Icons.storefront_rounded,
            fill: AppColors.warmFill,
            ink: AppColors.primary,
            title: order.vendorName ?? l10n.store,
            lines: [
              order.orderFlow == OrderFlow.direct
                  ? l10n.buyAtStoreSubtitle
                  : l10n.goToStoreSubtitle,
            ],
          ),
          const Padding(
            padding: EdgeInsetsDirectional.only(start: 15),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SizedBox(
                height: 16,
                child: VerticalDivider(width: 2, color: AppColors.border),
              ),
            ),
          ),
          _Stop(
            icon: Icons.location_on_rounded,
            fill: AppColors.successFill,
            ink: AppColors.success,
            title: order.customerName ?? l10n.customer,
            lines: [
              if ((part('street') ?? '').isNotEmpty) part('street')!,
              if (detail.isNotEmpty) detail,
              if (part('notes') != null) part('notes')!,
              if (mine && order.customerPhone != null) order.customerPhone!,
            ],
          ),
        ],
      ),
    );
  }
}

class _Stop extends StatelessWidget {
  const _Stop({
    required this.icon,
    required this.fill,
    required this.ink,
    required this.title,
    required this.lines,
  });

  final IconData icon;
  final Color fill;
  final Color ink;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: ink),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 5),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    line,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2, right: 2),
          child: Text(title, style: AppType.heading(15)),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _Items extends StatelessWidget {
  const _Items({required this.order});

  final AppOrder order;

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    if (order.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          context.l10n.couldNotLoadThisOrder,
          style: const TextStyle(color: AppColors.textMuted),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < order.items.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: AppColors.borderSoft),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: const BoxConstraints(minWidth: 30),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warmFill,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${order.items[i].quantity}×',
                    textAlign: TextAlign.center,
                    style: AppType.mono(
                      13,
                      color: AppColors.primary,
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.items[i].nameFor(language),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      if (order.items[i].optionNames.isNotEmpty)
                        Text(
                          order.items[i].optionNames.join(', '),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatMoney(order.items[i].lineTotal),
                  style: AppType.mono(12.5, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Money extends StatelessWidget {
  const _Money({required this.order});

  final AppOrder order;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget row(String label, double value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
                color: strong ? AppColors.ink : AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            formatMoney(value),
            style: AppType.mono(
              strong ? 15 : 13.5,
              weight: strong ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(l10n.subtotal, order.subtotal),
          row(l10n.deliveryFee, order.deliveryFee),
          if (order.serviceFee > 0) row(l10n.serviceFee, order.serviceFee),
          if (order.discount > 0) row(l10n.discount, -order.discount),
          const Divider(height: 18, color: AppColors.borderSoft),
          row(l10n.total, order.total, strong: true),
          const SizedBox(height: 10),
          // The one line that decides what the driver does with money.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: order.isCod ? AppColors.amberFill : AppColors.successFill,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Text(
              [
                if (!order.orderFlow.runsThroughStore)
                  l10n.buyAtStoreNote(formatMoney(order.subtotal)),
                order.isCod
                    ? '${l10n.collect} ${formatMoney(order.total)} ${l10n.inCash}'
                    : l10n.paidOnlineNothingToCollect,
              ].join('. '),
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w700,
                color: order.isCod ? AppColors.amberInk : AppColors.successInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
