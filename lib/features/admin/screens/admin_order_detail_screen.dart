import 'dart:async';

import 'package:flutter/material.dart';
import 'package:multi_vendor/core/utils/time_format.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/models/order.dart';
import '../../../core/models/order_flow.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/utils/dialer.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart';
import '../../auth/auth_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';
import '../../../core/widgets/web/adaptive_sheet.dart';

/// Ordered happy-path stages used to render the intervention timeline.
const _flow = [
  OrderStatus.pending,
  OrderStatus.accepted,
  OrderStatus.preparing,
  OrderStatus.readyForPickup,
  OrderStatus.outForDelivery,
  OrderStatus.delivered,
];

/// The words the admin uses for the stages of an order no store is running.
/// "Ready for pickup" is the store's word for a step the store did not take;
/// there it means the order is confirmed and out to the riders.
String _platformStageLabel(BuildContext context, OrderStatus status) =>
    switch (status) {
      OrderStatus.accepted ||
      OrderStatus.preparing ||
      OrderStatus.readyForPickup => context.l10n.stageConfirmed,
      OrderStatus.outForDelivery => context.l10n.stageOnTheWay,
      _ => status.localizedLabel(context),
    };

/// The same order seen from the platform's side, when no store is running it:
/// waiting, confirmed and out to the riders, on the way, delivered.
///
/// "Accepted" and "preparing" are stages a store reports; without a store in
/// the loop nobody is there to report them, so showing them would be rows
/// that never light up. A direct order skips "waiting" on its own.
const _platformFlow = [
  OrderStatus.pending,
  OrderStatus.readyForPickup,
  OrderStatus.outForDelivery,
  OrderStatus.delivered,
];

/// Route entry for the phone flow: the detail view on its own page.
class AdminOrderDetailScreen extends StatelessWidget {
  const AdminOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) => AdminOrderDetailView(orderId: orderId);
}

/// The order intervention view. Embedded (`embedded: true`) it drops the back
/// button and its own Scaffold so it can live in the detail pane of a wide
/// master–detail layout.
class AdminOrderDetailView extends StatefulWidget {
  const AdminOrderDetailView({
    super.key,
    required this.orderId,
    this.embedded = false,
  });

  final String orderId;
  final bool embedded;

  @override
  State<AdminOrderDetailView> createState() => _AdminOrderDetailViewState();
}

class _AdminOrderDetailViewState extends State<AdminOrderDetailView> {
  final _repo = AdminRepository();
  late Future<AppOrder> _future;

  /// The same row, watched.
  ///
  /// This screen read the order once and never again, so a rider marking a
  /// delivery done left the operator looking at "on the way" until they
  /// reloaded the page — on a monitor that exists to be watched. The first
  /// fetch still feeds the initial paint; the stream takes over from there.
  StreamSubscription<AppOrder>? _liveSubscription;
  AppOrder? _live;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchOrder(widget.orderId);
    _watch();
  }

  void _watch() {
    _liveSubscription?.cancel();
    _liveSubscription = OrderRepository().watchOrder(widget.orderId).listen(
      (order) {
        if (mounted) setState(() => _live = order);
      },
      // A dropped socket is not worth an error screen over a row that is
      // already on display; the next reload picks it up.
      onError: (Object _) {},
    );
  }

  @override
  void didUpdateWidget(AdminOrderDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The wide layout keeps one detail pane and points it at another order.
    if (oldWidget.orderId != widget.orderId) {
      _live = null;
      _future = _repo.fetchOrder(widget.orderId);
      _watch();
    }
  }

  @override
  void dispose() {
    _liveSubscription?.cancel();
    super.dispose();
  }

  void _reload() => setState(() {
    _live = null;
    _future = _repo.fetchOrder(widget.orderId);
  });

  Future<void> _assign() async {
    final driver = await showAdaptiveSheet<DriverOption>(
      context: context,
      showDragHandle: true,
      builder: (_) => _DriverPicker(repo: _repo),
    );
    if (driver == null) return;
    setState(() => _busy = true);
    try {
      await _repo.assignDriver(widget.orderId, driver.id);
      if (!mounted) return;
      showSnack(context, '${context.l10n.assignedTo} ${driver.name}');
      _reload();
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The next step an operator can take on an order no store is running.
  /// Null on a store that runs its own orders — its own app is where accept
  /// and ready belong.
  ///
  /// Accepting is sending it to the riders. After that the order waits for a
  /// rider: it can only go out once somebody is carrying it, which the server
  /// enforces too (`NO_DRIVER_ASSIGNED`).
  OrderStatus? _nextStatusFor(AppOrder order) {
    if (order.orderFlow.runsThroughStore) return null;
    return switch (order.status) {
      // An unpaid card order is still a draft, and a scheduled one waits for
      // its slot; nothing to accept yet.
      OrderStatus.pending
          when order.isReleased &&
              (order.paymentMethod != 'paymob' || order.isPaid) =>
        OrderStatus.readyForPickup,
      OrderStatus.accepted ||
      OrderStatus.preparing ||
      OrderStatus.readyForPickup when order.driverId != null =>
        OrderStatus.outForDelivery,
      OrderStatus.outForDelivery => OrderStatus.delivered,
      _ => null,
    };
  }

  Future<void> _advance(AppOrder order, OrderStatus next) async {
    setState(() => _busy = true);
    try {
      await _repo.setOrderStatus(order.id, next);
      if (!mounted) return;
      setState(() => _busy = false);
      _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showFailure(context, error);
    }
  }

  Future<void> _cancel() async {
    final localCancelledByAdmin = context.l10n.cancelledByAdmin;
    final controller = TextEditingController();
    final String? reason = await AppDialogs.showFormDialog<String>(
      context: context,
      title: context.l10n.cancelRefundOrder,
      subtitle: context.l10n.cancelReasonDesc,
      icon: Icons.cancel_schedule_send_rounded,
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: context.l10n.reason,
          hintText: context.l10n.cancelReasonHint,
          prefixIcon: const Icon(Icons.edit_note_rounded),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
        ),
      ),
      primaryText: context.l10n.cancelOrder,
      onPrimaryPressed: (dialogContext) =>
          Navigator.pop(dialogContext, controller.text.trim()),
      secondaryText: context.l10n.back,
    );
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      await _repo.cancelOrder(
        widget.orderId,
        reason: reason.isEmpty ? localCancelledByAdmin : reason,
      );
      if (!mounted) return;
      showSnack(context, context.l10n.orderCancelled);
      _reload();
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refund(AppOrder order) async {
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: context.l10n.refundConfirmTitle,
      message:
          '${context.l10n.refundConfirmMessage}\n${formatMoney(order.total)}',
      confirmText: context.l10n.refundToWallet,
      cancelText: context.l10n.back,
      icon: Icons.account_balance_wallet_outlined,
      isDestructive: false,
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final amount = await _repo.refundOrderToWallet(widget.orderId);
      if (!mounted) return;
      showSnack(
        context,
        '${context.l10n.refundedToWallet} (${formatMoney(amount)})',
      );
      _reload();
    } catch (e) {
      debugPrint('refund failed: $e');
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _content() => FutureBuilder<AppOrder>(
    future: _future,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) {
        return const _OrderDetailSkeleton();
      }
      if (snap.hasError || !snap.hasData) {
        return ErrorView(
          message: context.l10n.couldNotLoadThisOrder,
          onRetry: _reload,
        );
      }
      return _Body(
        order: _live ?? snap.data!,
        // Reassigning a delivery is `orders.assign`; without it the row
        // still shows who is carrying the order, just no way to change it.
        onAssign: context.watch<AuthCubit>().state.can('orders.assign')
            ? _assign
            : null,
        showBack: !widget.embedded,
      );
    },
  );

  Widget _actionBar() => FutureBuilder<AppOrder>(
    future: _future,
    builder: (context, snap) {
      if (!snap.hasData) return const SizedBox.shrink();
      final auth = context.watch<AuthCubit>().state;
      final order = _live ?? snap.data!;
      final next = auth.can('orders.view') ? _nextStatusFor(order) : null;
      return _ActionBar(
        order: order,
        busy: _busy,
        canCancel: auth.can('orders.cancel'),
        canRefund: auth.can('payments.refund'),
        nextStatus: next,
        onAdvance: next == null ? null : () => _advance(order, next),
        onCancel: _cancel,
        onRefund: () => _refund(order),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Column(
        children: [
          Expanded(child: _content()),
          _actionBar(),
        ],
      );
    }
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(bottom: false, child: _content()),
      bottomNavigationBar: _actionBar(),
    );
  }
}

/// Shaped like [_Body]: id row, timeline, two party cards, an items card.
class _OrderDetailSkeleton extends StatelessWidget {
  const _OrderDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonTheme(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Row(
            children: const [
              Skeleton(width: 40, height: 40, radius: 12),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton.line(widthFactor: 0.4, height: 18),
                    SizedBox(height: 6),
                    Skeleton.line(widthFactor: 0.6, height: 11),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Skeleton.box(height: 64, radius: 16),
          const SizedBox(height: 13),
          Row(
            children: const [
              Expanded(child: Skeleton.box(height: 74, radius: 14)),
              SizedBox(width: 9),
              Expanded(child: Skeleton.box(height: 74, radius: 14)),
            ],
          ),
          const SizedBox(height: 9),
          const Skeleton.box(height: 56, radius: 14),
          const SizedBox(height: 12),
          const Skeleton.box(height: 160, radius: 14),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.order,
    required this.onAssign,
    this.showBack = true,
  });

  final AppOrder order;

  /// Null when this member of staff may not reassign the delivery.
  final VoidCallback? onAssign;
  final bool showBack;

  /// A cancelled/rejected card order whose money is still held: the customer
  /// paid but will not get the food, so the amount must go back to their
  /// wallet.
  bool get _refundDue =>
      order.paymentMethod == 'paymob' &&
      order.paymentStatus == 'paid' &&
      (order.status == OrderStatus.cancelled ||
          order.status == OrderStatus.rejected);

  bool get _refunded => order.paymentStatus == 'refunded';

  bool get _stuck =>
      !order.status.isTerminal &&
      order.status != OrderStatus.outForDelivery &&
      DateTime.now().difference(order.createdAt) > const Duration(minutes: 20);

  @override
  Widget build(BuildContext context) {
    final mins = DateTime.now().difference(order.createdAt).inMinutes;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
      children: [
        Row(
          children: [
            if (showBack) ...[
              GestureDetector(
                onTap: () => context.pop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.chevron_left, color: AppColors.ink),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableId(order.orderNumber, style: AppType.mono(20)),
                Text(
                  '${context.l10n.placed} ${formatClock(context, order.createdAt)} · '
                  '${order.isCod ? context.l10n.cod : context.l10n.card}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_stuck)
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.primaryLight,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${context.l10n.stuckIn} ${order.status.localizedLabel(context)} · $mins${context.l10n.mShort}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        order.driverId == null
                            ? context.l10n.pastSlaNoDriverAssigned
                            : context.l10n.pastSla,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (_refundDue || _refunded) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: _refunded ? AppColors.successFill : AppColors.amberFill,
              border: Border.all(
                color: _refunded ? AppColors.successFill : AppColors.amberFill,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  _refunded
                      ? Icons.check_circle_outline
                      : Icons.account_balance_wallet_outlined,
                  size: 19,
                  color: _refunded ? AppColors.successInk : AppColors.amberInk,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _refunded
                            ? context.l10n.refundedToWallet
                            : '${context.l10n.refundRequired} · ${formatMoney(order.total)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: _refunded
                              ? AppColors.successInk
                              : AppColors.amberInk,
                        ),
                      ),
                      if (!_refunded)
                        Text(
                          context.l10n.refundDueDesc,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        _Timeline(order: order),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: _party(
                context,
                context.l10n.vendors.toUpperCase(),
                order.vendorName ?? context.l10n.store,
                order.addressSummary.isEmpty ? '—' : context.l10n.store,
                phone: order.vendorPhone,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _party(
                context,
                context.l10n.customer.toUpperCase(),
                order.customerName ?? context.l10n.customer,
                order.addressSummary,
                phone: order.customerPhone,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        _DriverRow(order: order, onAssign: onAssign),
        const SizedBox(height: 12),
        _ItemsCard(order: order),
        if (order.customerNotes != null && order.customerNotes!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppColors.warmFill,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 16,
                  color: AppColors.primaryDark,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.customerNotesLabel,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        order.customerNotes!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        if (order.rejectionReason != null &&
            order.rejectionReason!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppColors.dangerFill,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 18,
                  color: AppColors.dangerInk,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '${context.l10n.reason}: ${order.rejectionReason}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.dangerInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _party(
    BuildContext context,
    String label,
    String name,
    String sub, {
    String? phone,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textFaint,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.ink,
                ),
              ),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        // An admin intervening on a stuck order needs to be able to actually
        // reach the two people it involves — this card named them and gave no
        // way to call either.
        if (phone != null && phone.isNotEmpty) ...[
          const SizedBox(width: 6),
          Material(
            color: AppColors.warmFill,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => callPhone(context, phone),
              child: const Padding(
                padding: EdgeInsets.all(7),
                child: Icon(
                  Icons.call_rounded,
                  size: 15,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// What was ordered and what it came to. Previously the only figure on this
/// whole screen was the total in the header row — an admin resolving a
/// dispute or a short refund had no way to see what was actually in the bag.
class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.order});

  final AppOrder order;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 11, 13, 4),
            child: Text(
              l10n.items,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textFaint,
              ),
            ),
          ),
          if (order.items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 0, 13, 11),
              child: Text(
                '—',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textMuted,
                ),
              ),
            )
          else
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 4, 13, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.quantity}×',
                      style: AppType.mono(
                        12.5,
                        weight: FontWeight.w700,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.nameFor(
                              Localizations.localeOf(context).languageCode,
                            ),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                          if (item.optionNames.isNotEmpty)
                            Text(
                              item.optionNames.join(', '),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatMoney(item.lineTotal),
                      style: AppType.mono(12.5, weight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 13),
            child: Divider(height: 17, color: AppColors.borderSoft),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 0, 13, 11),
            child: Column(
              children: [
                _totalRow(l10n.subtotal, formatMoney(order.subtotal)),
                if (order.deliveryFee > 0)
                  _totalRow(l10n.deliveryFee, formatMoney(order.deliveryFee)),
                if (order.serviceFee > 0)
                  _totalRow(l10n.serviceFee, formatMoney(order.serviceFee)),
                if (order.discount > 0)
                  _totalRow(
                    l10n.discount,
                    '-${formatMoney(order.discount)}',
                    tone: AppColors.successInk,
                  ),
                if (order.driverTip > 0)
                  _totalRow(l10n.tips, formatMoney(order.driverTip)),
                _totalRow(l10n.total, formatMoney(order.total), emphasis: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(
    String label,
    String value, {
    bool emphasis = false,
    Color? tone,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: emphasis ? 13 : 12,
              fontWeight: emphasis ? FontWeight.w800 : FontWeight.w500,
              color: emphasis ? AppColors.ink : AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: AppType.mono(
            emphasis ? 13.5 : 12,
            weight: emphasis ? FontWeight.w800 : FontWeight.w700,
            color: tone ?? (emphasis ? AppColors.ink : AppColors.ink),
          ),
        ),
      ],
    ),
  );
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.order});

  final AppOrder order;

  @override
  Widget build(BuildContext context) {
    final voided =
        order.status == OrderStatus.cancelled ||
        order.status == OrderStatus.rejected;
    final platformRun = !order.orderFlow.runsThroughStore;
    // A direct order never waits for anyone, so it has no "waiting" row.
    final flow = platformRun
        ? [
            for (final s in _platformFlow)
              if (s != OrderStatus.pending ||
                  order.orderFlow == OrderFlow.platform)
                s,
          ]
        : _flow;
    // An order taken over half-way may still sit in a store's stage; all of
    // those read as "confirmed" here.
    final effective =
        platformRun &&
            (order.status == OrderStatus.accepted ||
                order.status == OrderStatus.preparing ||
                (order.status == OrderStatus.pending &&
                    order.orderFlow == OrderFlow.direct))
        ? OrderStatus.readyForPickup
        : order.status;
    final currentIndex = flow.indexOf(effective);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var i = 0; i < flow.length; i++)
            _step(
              context,
              label: platformRun
                  ? _platformStageLabel(context, flow[i])
                  : flow[i].localizedLabel(context),
              done: !voided && currentIndex >= 0 && i < currentIndex,
              current: !voided && i == currentIndex,
              stalled:
                  !voided &&
                  i == currentIndex &&
                  order.status != OrderStatus.delivered,
              isLast: i == flow.length - 1,
            ),
          if (voided)
            _step(
              context,
              label: order.status.localizedLabel(context),
              done: false,
              current: true,
              stalled: false,
              isLast: true,
              voided: true,
            ),
        ],
      ),
    );
  }

  Widget _step(
    BuildContext context, {
    required String label,
    required bool done,
    required bool current,
    required bool stalled,
    required bool isLast,
    bool voided = false,
  }) {
    final Color dot = voided
        ? AppColors.dangerInk
        : done
        ? AppColors.success
        : current
        ? AppColors.primaryDark
        : AppColors.borderStrong;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                child: done
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: AppColors.borderStrong),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 14, top: 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stalled ? '$label${context.l10n.stalledSuffix}' : label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: (current || done)
                        ? (stalled ? AppColors.primaryDark : AppColors.ink)
                        : AppColors.textFaint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverRow extends StatelessWidget {
  const _DriverRow({required this.order, required this.onAssign});

  final AppOrder order;
  final VoidCallback? onAssign;

  @override
  Widget build(BuildContext context) {
    final assigned = order.driverId != null;
    // Null onAssign means this member of staff holds no `orders.assign`, so
    // the row still says who is carrying the order and offers no button.
    final canAssign = onAssign != null && !order.status.isTerminal && !assigned;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: assigned ? AppColors.successFill : AppColors.amberFill,
        border: Border.all(
          color: assigned ? AppColors.successFill : AppColors.amberFill,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            assigned ? Icons.delivery_dining : Icons.person_off_outlined,
            size: 19,
            color: assigned ? AppColors.successInk : AppColors.amberInk,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.driver,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: assigned ? AppColors.successInk : AppColors.amberInk,
                  ),
                ),
                Text(
                  assigned ? context.l10n.assigned : context.l10n.notAssigned,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
          if (canAssign)
            GestureDetector(
              onTap: onAssign,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  context.l10n.assign,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.order,
    required this.busy,
    required this.canCancel,
    required this.canRefund,
    required this.onCancel,
    required this.onRefund,
    this.nextStatus,
    this.onAdvance,
  });

  final AppOrder order;
  final bool busy;

  /// Held by this member of staff. Money and order state are different
  /// responsibilities, so a role can have one without the other.
  final bool canCancel;
  final bool canRefund;
  final VoidCallback onCancel;
  final VoidCallback onRefund;

  /// Set when the platform is running this store's orders: the admin is the
  /// one accepting and preparing, so the bar offers the next step.
  final OrderStatus? nextStatus;
  final VoidCallback? onAdvance;

  bool get _refundDue =>
      order.paymentMethod == 'paymob' &&
      order.paymentStatus == 'paid' &&
      (order.status == OrderStatus.cancelled ||
          order.status == OrderStatus.rejected);

  @override
  Widget build(BuildContext context) {
    if (busy) {
      // Keep the bar's shape while the action runs, so the sheet does not
      // jump — a bare spinner in a 52px bar reads as a broken button.
      return SafeArea(
        minimum: const EdgeInsets.fromLTRB(22, 10, 22, 18),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryDark,
            minimumSize: const Size.fromHeight(52),
          ),
          onPressed: null,
          child: const ButtonSpinner(),
        ),
      );
    }
    if (order.status.isTerminal) {
      if (_refundDue && canRefund) {
        return SafeArea(
          minimum: const EdgeInsets.fromLTRB(22, 10, 22, 18),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.ink,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: onRefund,
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 19),
            label: Text(
              '${context.l10n.refundToWallet} · ${formatMoney(order.total)}',
            ),
          ),
        );
      }
      return SafeArea(
        minimum: const EdgeInsets.fromLTRB(22, 10, 22, 18),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Text(
            '${context.l10n.order} ${order.status.localizedLabel(context).toLowerCase()}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
        ),
      );
    }
    final next = nextStatus;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(22, 10, 22, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (next != null && onAdvance != null) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: onAdvance,
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(
                next == OrderStatus.readyForPickup
                    ? context.l10n.acceptAndDispatch
                    : context.l10n.advanceOrder(
                        _platformStageLabel(context, next),
                      ),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryDark,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, size: 19),
            label: Text(context.l10n.cancelRefundOrder),
          ),
        ],
      ),
    );
  }
}

class _DriverPicker extends StatefulWidget {
  const _DriverPicker({required this.repo});

  final AdminRepository repo;

  @override
  State<_DriverPicker> createState() => _DriverPickerState();
}

class _DriverPickerState extends State<_DriverPicker> {
  late Future<List<DriverOption>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repo.fetchOnlineDrivers();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.assignADriver,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          FutureBuilder<List<DriverOption>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: LoadingView(),
                );
              }
              final drivers = snap.data ?? const [];
              if (drivers.isEmpty) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    context.l10n.noDriversAreOnlineRightNow,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                );
              }
              return Column(
                children: drivers
                    .map(
                      (d) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          backgroundColor: AppColors.warmFill,
                          child: Icon(
                            Icons.delivery_dining,
                            color: AppColors.primary,
                          ),
                        ),
                        title: Text(
                          d.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: d.phone != null ? Text(d.phone!) : null,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(context, d),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
