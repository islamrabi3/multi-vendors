import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/tokens.dart';
import '../../../core/models/order.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/utils/dialer.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// Route entry for the phone flow: the order view on its own page.
class VendorOrderDetailsScreen extends StatelessWidget {
  const VendorOrderDetailsScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) =>
      VendorOrderDetailsView(orderId: orderId);
}

/// The order view. Embedded (`embedded: true`) it drops the back button and its
/// own Scaffold so it can live in the detail pane of the wide dashboard.
class VendorOrderDetailsView extends StatefulWidget {
  const VendorOrderDetailsView({
    super.key,
    required this.orderId,
    this.embedded = false,
  });

  final String orderId;
  final bool embedded;

  @override
  State<VendorOrderDetailsView> createState() =>
      _VendorOrderDetailsViewState();
}

class _VendorOrderDetailsViewState extends State<VendorOrderDetailsView> {
  final _repository = OrderRepository();
  AppOrder? _order;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final order = await _repository.fetchOrder(widget.orderId);
      if (mounted) setState(() => _order = order);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _advance(OrderStatus status, {String? reason}) async {
    setState(() => _busy = true);
    try {
      await _repository.updateStatus(widget.orderId, status, reason: reason);
      await _load();
    } catch (error) {
      if (mounted) showSnack(context, readableError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _callCustomer(String phone) => callPhone(context, phone);

  Future<void> _reject() async {
    final localUnavailable = context.l10n.unavailable;
    final controller = TextEditingController();
    final String? reason = await AppDialogs.showFormDialog<String>(
      context: context,
      title: context.l10n.rejectOrder,
      subtitle: context.l10n.rejectReasonDesc,
      icon: Icons.cancel_outlined,
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: context.l10n.reason,
          hintText: context.l10n.rejectReasonHint,
          prefixIcon: const Icon(Icons.edit_note_rounded),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
        ),
      ),
      primaryText: context.l10n.reject,
      onPrimaryPressed: () => Navigator.pop(context, controller.text.trim()),
      secondaryText: context.l10n.cancel,
    );
    if (reason != null) {
      await _advance(OrderStatus.rejected,
          reason: reason.isEmpty ? localUnavailable : reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final content = _error != null
        ? ErrorView(message: readableError(_error!), onRetry: _load)
        : order == null
            ? const LoadingView()
            : Column(
                children: [
                  _topBar(order),
                  Expanded(child: _body(order)),
                  _bottomCta(order),
                ],
              );
    if (widget.embedded) return content;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(child: content),
    );
  }

  Widget _topBar(AppOrder order) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          if (!widget.embedded) ...[
            InkWell(
              onTap: () => context.pop(),
              customBorder: const CircleBorder(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child:
                    const Icon(Icons.chevron_left_rounded, color: AppColors.ink),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: SelectableId(
              order.orderNumber,
              style: AppType.mono(18,
                  color: AppColors.ink, weight: FontWeight.w800),
            ),
          ),
          OrderStatusChip(status: order.status),
        ],
      ),
    );
  }

  Widget _body(AppOrder order) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        // Customer card.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration,
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.warmFill,
                child: Text(_initials(order.customerName),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.primary)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.customerName ?? context.l10n.customer,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: AppColors.ink)),
                    const SizedBox(height: 3),
                    Text(order.addressSummary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textMuted, height: 1.25)),
                  ],
                ),
              ),
              if (order.customerPhone != null) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _callCustomer(order.customerPhone!),
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.warmFill,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
                    ),
                    child: const Icon(Icons.phone_in_talk_rounded,
                        size: 20, color: AppColors.primary),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        
        // Items.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: _cardDecoration,
          child: Column(
            children: [
              for (var i = 0; i < order.items.length; i++)
                _itemRow(order.items[i],
                    last: i == order.items.length - 1),
            ],
          ),
        ),
        
        if (order.customerNotes?.isNotEmpty ?? false) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.amberFill.withValues(alpha: 0.5),
              border: Border.all(color: AppColors.amberInk.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: AppColors.amberInk, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: AppColors.amberInk),
                      children: [
                        TextSpan(
                            text: '${context.l10n.noteLabel} ',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.amberInk)),
                        TextSpan(text: order.customerNotes),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        
        // Order Summary Footer
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      order.isCod
                          ? context.l10n.totalCashOnDelivery
                          : order.isPaid
                              ? context.l10n.totalCardPaid
                              : context.l10n.totalCardUnpaid,
                      style: const TextStyle(
                          fontSize: 13.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  PriceText(formatMoney(order.total), size: 18),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 13, color: AppColors.textFaint),
                  const SizedBox(width: 6),
                  Text(
                      DateFormat('d MMM y, h:mm a').format(order.createdAt),
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textFaint, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _itemRow(OrderItem item, {required bool last}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(
                bottom: BorderSide(color: AppColors.borderSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Text('${item.quantity}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.productName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.ink)),
                if (item.optionNames.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(item.optionNames.join(' · '),
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textMuted, height: 1.25)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          PriceText(formatMoney(item.lineTotal), size: 13.5),
        ],
      ),
    );
  }

  Widget _bottomCta(AppOrder order) {
    final (label, status) = switch (order.status) {
      OrderStatus.pending => (context.l10n.acceptOrder, OrderStatus.accepted),
      OrderStatus.accepted => (context.l10n.startPreparing, OrderStatus.preparing),
      OrderStatus.preparing => (
          context.l10n.markReadyForPickup,
          OrderStatus.readyForPickup
        ),
      _ => (null, null),
    };

    if (label == null) {
      return const SizedBox(height: 8);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderSoft)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (order.status == OrderStatus.pending) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                    )),
                onPressed: _busy ? null : _reject,
                child: Text(context.l10n.rejectOrder),
              ),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: Container(
              height: 54,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.lg),
                boxShadow: [
                  BoxShadow(
                    color: (order.status == OrderStatus.pending ? AppColors.success : AppColors.primary)
                        .withValues(alpha: 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    backgroundColor: order.status == OrderStatus.pending
                        ? AppColors.success
                        : AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                    )),
                onPressed: _busy ? null : () => _advance(status!),
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static final _cardDecoration = BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(AppRadii.xl),
    border: Border.all(color: AppColors.border),
    boxShadow: AppShadows.card,
  );

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '🙂';
    final parts = name.trim().split(RegExp(r'\s+'));
    final letters =
        parts.take(2).map((p) => p[0].toUpperCase()).join();
    return letters;
  }
}
