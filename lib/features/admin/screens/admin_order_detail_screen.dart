import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/tokens.dart';
import '../../../core/models/order.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// Ordered happy-path stages used to render the intervention timeline.
const _flow = [
  OrderStatus.pending,
  OrderStatus.accepted,
  OrderStatus.preparing,
  OrderStatus.readyForPickup,
  OrderStatus.outForDelivery,
  OrderStatus.delivered,
];

/// Route entry for the phone flow: the detail view on its own page.
class AdminOrderDetailScreen extends StatelessWidget {
  const AdminOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) =>
      AdminOrderDetailView(orderId: orderId);
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
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchOrder(widget.orderId);
  }

  void _reload() => setState(() => _future = _repo.fetchOrder(widget.orderId));

  Future<void> _assign() async {
    final driver = await showModalBottomSheet<DriverOption>(
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
      if (mounted) showSnack(context, readableError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
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
      onPrimaryPressed: () => Navigator.pop(context, controller.text.trim()),
      secondaryText: context.l10n.back,
    );
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      await _repo.cancelOrder(widget.orderId,
          reason: reason.isEmpty ? localCancelledByAdmin : reason);
      if (!mounted) return;
      showSnack(context, context.l10n.orderCancelled);
      _reload();
    } catch (e) {
      if (mounted) showSnack(context, readableError(e), error: true);
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
      showSnack(context,
          '${context.l10n.refundedToWallet} (${formatMoney(amount)})');
      _reload();
    } catch (e) {
      debugPrint('refund failed: $e');
      if (mounted) showSnack(context, readableError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _content() => FutureBuilder<AppOrder>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const LoadingView();
          }
          if (snap.hasError || !snap.hasData) {
            return ErrorView(
                message: context.l10n.couldNotLoadThisOrder, onRetry: _reload);
          }
          return _Body(
            order: snap.data!,
            onAssign: _assign,
            showBack: !widget.embedded,
          );
        },
      );

  Widget _actionBar() => FutureBuilder<AppOrder>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          return _ActionBar(
            order: snap.data!,
            busy: _busy,
            onCancel: _cancel,
            onRefund: () => _refund(snap.data!),
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

class _Body extends StatelessWidget {
  const _Body({
    required this.order,
    required this.onAssign,
    this.showBack = true,
  });

  final AppOrder order;
  final VoidCallback onAssign;
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
                  '${context.l10n.placed} ${DateFormat('h:mm a').format(order.createdAt)} · '
                  '${order.isCod ? context.l10n.cod : context.l10n.card}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textMuted),
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
                  child: const Icon(Icons.warning_amber_rounded,
                      color: AppColors.primaryLight, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${context.l10n.stuckIn} ${order.status.localizedLabel(context)} · $mins${context.l10n.mShort}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                      Text(
                        order.driverId == null
                            ? context.l10n.pastSlaNoDriverAssigned
                            : context.l10n.pastSla,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 11.5),
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
                  color: _refunded
                      ? const Color(0xFFCDEBD9)
                      : const Color(0xFFF6E2C0)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                    _refunded
                        ? Icons.check_circle_outline
                        : Icons.account_balance_wallet_outlined,
                    size: 19,
                    color: _refunded
                        ? AppColors.successInk
                        : AppColors.amberInk),
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
                                  : AppColors.amberInk)),
                      if (!_refunded)
                        Text(context.l10n.refundDueDesc,
                            style: const TextStyle(
                                fontSize: 11.5, color: AppColors.textMuted)),
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
              child: _party(context.l10n.vendors.toUpperCase(), order.vendorName ?? context.l10n.store,
                  order.addressSummary.isEmpty ? '—' : context.l10n.store),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _party(context.l10n.customer.toUpperCase(), order.customerName ?? context.l10n.customer,
                  order.addressSummary),
            ),
          ],
        ),
        const SizedBox(height: 9),
        _DriverRow(order: order, onAssign: onAssign),
        if (order.rejectionReason != null &&
            order.rejectionReason!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFFFBE7E4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 18, color: Color(0xFFC0392B)),
                const SizedBox(width: 9),
                Expanded(
                  child: Text('${context.l10n.reason}: ${order.rejectionReason}',
                      style: const TextStyle(
                          fontSize: 12.5, color: Color(0xFFC0392B))),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _party(String label, String name, String sub) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textFaint)),
            const SizedBox(height: 2),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.ink)),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
      );
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.order});

  final AppOrder order;

  @override
  Widget build(BuildContext context) {
    final voided = order.status == OrderStatus.cancelled ||
        order.status == OrderStatus.rejected;
    final currentIndex = _flow.indexOf(order.status);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _flow.length; i++)
            _step(
              context,
              label: _flow[i].localizedLabel(context),
              done: !voided && currentIndex >= 0 && i < currentIndex,
              current: !voided && i == currentIndex,
              stalled: !voided &&
                  i == currentIndex &&
                  order.status != OrderStatus.delivered,
              isLast: i == _flow.length - 1,
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
        ? const Color(0xFFC0392B)
        : done
            ? AppColors.success
            : current
                ? AppColors.primaryDark
                : const Color(0xFFE4DDD4);
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
                  child: Container(
                    width: 2,
                    color: const Color(0xFFE4DDD4),
                  ),
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
                          : AppColors.textFaint),
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
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final assigned = order.driverId != null;
    final canAssign = !order.status.isTerminal && !assigned;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: assigned ? AppColors.successFill : AppColors.amberFill,
        border: Border.all(
            color: assigned
                ? const Color(0xFFCDEBD9)
                : const Color(0xFFF6E2C0)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(assigned ? Icons.delivery_dining : Icons.person_off_outlined,
              size: 19,
              color: assigned ? AppColors.successInk : AppColors.amberInk),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.driver,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color:
                            assigned ? AppColors.successInk : AppColors.amberInk)),
                Text(assigned ? context.l10n.assigned : context.l10n.notAssigned,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.ink)),
              ],
            ),
          ),
          if (canAssign)
            GestureDetector(
              onTap: onAssign,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(context.l10n.assign,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5)),
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
    required this.onCancel,
    required this.onRefund,
  });

  final AppOrder order;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onRefund;

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
              minimumSize: const Size.fromHeight(52)),
          onPressed: null,
          child: const ButtonSpinner(),
        ),
      );
    }
    if (order.status.isTerminal) {
      if (_refundDue) {
        return SafeArea(
          minimum: const EdgeInsets.fromLTRB(22, 10, 22, 18),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.ink,
                minimumSize: const Size.fromHeight(52)),
            onPressed: onRefund,
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 19),
            label: Text(
                '${context.l10n.refundToWallet} · ${formatMoney(order.total)}'),
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
          child: Text('${context.l10n.order} ${order.status.localizedLabel(context).toLowerCase()}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.textMuted)),
        ),
      );
    }
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(22, 10, 22, 18),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryDark,
            minimumSize: const Size.fromHeight(52)),
        onPressed: onCancel,
        icon: const Icon(Icons.close_rounded, size: 19),
        label: Text(context.l10n.cancelRefundOrder),
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
          Text(context.l10n.assignADriver,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          FutureBuilder<List<DriverOption>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                    padding: EdgeInsets.all(24), child: LoadingView());
              }
              final drivers = snap.data ?? const [];
              if (drivers.isEmpty) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(context.l10n.noDriversAreOnlineRightNow,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted)),
                );
              }
              return Column(
                children: drivers
                    .map((d) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.warmFill,
                            child: Icon(Icons.delivery_dining,
                                color: AppColors.primary),
                          ),
                          title: Text(d.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          subtitle: d.phone != null ? Text(d.phone!) : null,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(context, d),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
