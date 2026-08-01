import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/tokens.dart';
import '../../../core/models/order.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/repositories/payment_repository.dart';
import '../../../core/repositories/report_repository.dart';
import '../../../core/repositories/review_repository.dart';
import '../../../core/utils/dialer.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/reviews.dart';
import '../../../core/widgets/skeleton.dart';
import '../checkout/paymob_flow.dart';
import 'order_chat_sheet.dart';
import 'order_details_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class OrderDetailsScreen extends StatelessWidget {
  const OrderDetailsScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => OrderDetailsCubit(
          OrderRepository(), ReviewRepository(), PaymentRepository(), orderId),
      child: const _OrderDetailsView(),
    );
  }
}

class _OrderDetailsView extends StatelessWidget {
  const _OrderDetailsView();

  /// Reporting an issue is exactly the flow that must not lose the user's
  /// typing: they have just described a problem in their own words. `onSubmit`
  /// runs inside the dialog, so a failed write shows inline and the text stays.
  Future<void> _showReportDialog(BuildContext context, AppOrder order) async {
    final subject = TextEditingController();
    final description = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final submitted = context.l10n.reportSubmitted;

    try {
      final ok = await showFormDialog<bool>(
        context: context,
        title: context.l10n.reportStoreOrOrder,
        icon: Icons.report_problem_rounded,
        tone: AppDialogTone.danger,
        submitLabel: context.l10n.submitReport,
        cancelLabel: context.l10n.cancel,
        contentBuilder: (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: subject,
              textCapitalization: TextCapitalization.sentences,
              decoration:
                  InputDecoration(labelText: context.l10n.issueSubject),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: description,
              maxLines: 3,
              decoration: InputDecoration(
                  labelText: context.l10n.issueDescription),
            ),
          ],
        ),
        onSubmit: () async {
          final subj = subject.text.trim();
          final desc = description.text.trim();
          // Returning null keeps the dialog open — nothing to report yet.
          if (subj.isEmpty || desc.isEmpty) return null;
          await ReportRepository().submitReport(
            subject: subj,
            description: desc,
            orderId: order.id,
            vendorId: order.vendorId,
          );
          return true;
        },
      );
      if (ok == true) {
        messenger.showSnackBar(SnackBar(content: Text(submitted)));
      }
    } finally {
      subject.dispose();
      description.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.orderDetails)),
      body: BlocConsumer<OrderDetailsCubit, OrderDetailsState>(
        listenWhen: (previous, current) =>
            previous.error != current.error && current.error != null,
        listener: (context, state) =>
            showFailure(context, state.error!),
        builder: (context, state) {
          if (state.loading) return const _OrderDetailsSkeleton();
          final order = state.order;
          if (order == null) {
            return ErrorView(message: context.l10n.orderNotFound);
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 16, 16,
                16 + MediaQuery.paddingOf(context).bottom),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(order.orderNumber,
                      style: Theme.of(context).textTheme.titleLarge),
                  OrderStatusChip(status: order.status),
                ],
              ),
              if (order.vendorName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(order.vendorName!,
                      style: Theme.of(context).textTheme.bodyLarge),
                ),
              const SizedBox(height: 16),
              if (order.status == OrderStatus.rejected ||
                  order.status == OrderStatus.cancelled)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(order.status == OrderStatus.rejected
                        ? context.l10n.rejectedByStore(
                            order.rejectionReason != null ? ': ${order.rejectionReason}' : '')
                        : context.l10n.orderCancelled),
                  ),
                )
              else
                _StatusStepper(order: order),
              if (order.status == OrderStatus.outForDelivery) ...[
                const SizedBox(height: 16),
                _EtaBanner(
                  order: order,
                  driverLocation: state.driverLocation,
                ),
                const SizedBox(height: 12),
                _TrackingMap(order: order, driverLocation: state.driverLocation),
                if (state.driverContact != null) ...[
                  const SizedBox(height: 12),
                  _CallDriverCard(contact: state.driverContact!),
                ],
              ],
              if (order.deliveryProofUrl != null && order.deliveryProofUrl!.isNotEmpty) ...[
                const SizedBox(height: 16),
                _DeliveryProofCard(proofUrl: order.deliveryProofUrl!),
              ],
              const Divider(height: 32),
              _PaymentCard(order: order, busy: state.busy),
              const SizedBox(height: 8),
              Text(context.l10n.items, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              for (final item in state.items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Text('${item.quantity}x',
                      style: Theme.of(context).textTheme.titleSmall),
                  title: Text(item.productName),
                  subtitle: item.optionNames.isEmpty
                      ? null
                      : Text(item.optionNames.join(', ')),
                  trailing: Text(formatMoney(item.lineTotal)),
                ),
              const Divider(),
              _Row(label: context.l10n.subtotal, value: formatMoney(order.subtotal)),
              _Row(label: context.l10n.deliveryFee1, value: formatMoney(order.deliveryFee)),
              if (order.discount > 0)
                _Row(label: context.l10n.discount1, value: '-${formatMoney(order.discount)}'),
              _Row(label: context.l10n.total, value: formatMoney(order.total), bold: true),
              const SizedBox(height: 16),
              Text(context.l10n.deliveringTo(order.addressSummary),
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 24),
              const SizedBox(height: 24),
              if (order.status == OrderStatus.outForDelivery || order.status == OrderStatus.preparing || order.status == OrderStatus.accepted)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => OrderChatSheet(orderId: order.id),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: Text(context.l10n.liveChatWithDriverSupport),
                    ),
                  ),
                ),
              if (order.status == OrderStatus.pending)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: state.busy
                        ? null
                        : () =>
                            context.read<OrderDetailsCubit>().cancelOrder(),
                    child: Text(context.l10n.cancelOrder),
                  ),
                ),
              if (order.status == OrderStatus.delivered) ...[
                if (!state.hasReview)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _showReviewSheet(context),
                        icon: const Icon(Icons.star_outline),
                        label: Text(context.l10n.rateThisOrder),
                      ),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await OrderRepository().reorderPastOrder(order);
                      if (context.mounted) {
                        context.push('/cart');
                      }
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(context.l10n.reorderItems),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => _showReportDialog(context, order),
                  icon: const Icon(Icons.report_problem_outlined,
                      color: AppColors.dangerInk),
                  label: Text(
                    context.l10n.reportAnIssue,
                    style: const TextStyle(
                        color: AppColors.dangerInk,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }


  void _showReviewSheet(BuildContext context) {
    final cubit = context.read<OrderDetailsCubit>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReviewSheet(cubit: cubit),
    );
  }
}

class _StatusStepper extends StatelessWidget {
  const _StatusStepper({required this.order});

  final AppOrder order;

  @override
  Widget build(BuildContext context) {
    int currentStep = 0;
    if (order.status == OrderStatus.pending) {
      currentStep = 0;
    } else if (order.status == OrderStatus.accepted || order.status == OrderStatus.preparing) {
      currentStep = 1;
    } else if (order.status == OrderStatus.readyForPickup || order.status == OrderStatus.outForDelivery) {
      currentStep = 2;
    } else if (order.status == OrderStatus.delivered) {
      currentStep = 3;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildStepNode(0, currentStep, isIcon: false, text: '✓'),
              _buildLine(0, currentStep),
              _buildStepNode(1, currentStep, isIcon: false, text: '✓'),
              _buildLine(1, currentStep),
              _buildStepNode(2, currentStep, isIcon: true, icon: Icons.delivery_dining),
              _buildLine(2, currentStep),
              _buildStepNode(3, currentStep, isIcon: false, text: ''),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStepLabel(context.l10n.statusConfirmed, 0, currentStep),
              _buildStepLabel(context.l10n.statusPrepared, 1, currentStep),
              _buildStepLabel(context.l10n.statusOnTheWay, 2, currentStep),
              _buildStepLabel(context.l10n.statusDelivered, 3, currentStep),
            ],
          ),
          // When each stage actually happened. The columns were always
          // written; nothing read them, so the tracker could say an order was
          // "prepared" without saying whether that was two minutes or two
          // hours ago.
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStepTime(context, order.acceptedAt),
              _buildStepTime(context, order.readyAt),
              _buildStepTime(context, order.pickedUpAt),
              _buildStepTime(context, order.deliveredAt),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepTime(BuildContext context, DateTime? at) => SizedBox(
        width: 62,
        child: Text(
          at == null
              ? ''
              : TimeOfDay.fromDateTime(at).format(context),
          textAlign: TextAlign.center,
          style: AppType.mono(9.5, color: AppColors.textFaint),
        ),
      );

  Widget _buildStepNode(int index, int currentStep, {required bool isIcon, IconData? icon, String text = ''}) {
    final done = index < currentStep;
    final active = index == currentStep;

    Color bg = AppColors.surface;
    Color border = AppColors.borderStrong;
    Widget child = const SizedBox.shrink();

    if (done) {
      bg = AppColors.success;
      border = AppColors.success;
      child = const Icon(Icons.check, size: 12, color: Colors.white);
    } else if (active) {
      bg = AppColors.primary;
      border = AppColors.primary;
      child = Icon(icon ?? Icons.check, size: 12, color: Colors.white);
    } else {
      bg = AppColors.surface;
      border = AppColors.borderStrong;
    }

    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(color: border, width: 2),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  Widget _buildLine(int index, int currentStep) {
    final active = index < currentStep;
    return Expanded(
      child: Container(
        height: 3,
        color: active ? AppColors.success : AppColors.borderStrong,
      ),
    );
  }

  Widget _buildStepLabel(String label, int index, int currentStep) {
    final active = index == currentStep;
    final color = active ? AppColors.primary : AppColors.textMuted;
    return Text(
      label,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    );
  }
}

/// "Arriving in about N minutes", while the order is on the road.
///
/// Deliberately a straight-line estimate rather than a routed one: this app
/// has no routing service, and a number derived from one would be no more
/// honest than this — so the wording says "about", and the padding factor
/// accounts for streets not being straight.
class _EtaBanner extends StatelessWidget {
  const _EtaBanner({required this.order, required this.driverLocation});

  final AppOrder order;
  final LatLng? driverLocation;

  /// City average once stops, lights and parking are folded in.
  static const _averageKmPerHour = 18.0;

  /// Streets are longer than the line between two points.
  static const _detourFactor = 1.35;

  int? get _minutes {
    final driver = driverLocation;
    final lat = order.deliveryLat;
    final lng = order.deliveryLng;
    if (driver == null || lat == null || lng == null) return null;
    final km = const Distance().as(
          LengthUnit.Kilometer,
          driver,
          LatLng(lat, lng),
        ) *
        _detourFactor;
    return (km / _averageKmPerHour * 60).ceil();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final minutes = _minutes;
    final label = minutes == null
        ? l10n.etaUnavailable
        : minutes <= 2
            ? l10n.arrivingSoon
            : l10n.estimatedArrival(minutes);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg, vertical: AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.successFill,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(
        children: [
          const Icon(Icons.delivery_dining_rounded,
              size: 20, color: AppColors.successInk),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.successInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingMap extends StatelessWidget {
  const _TrackingMap({required this.order, required this.driverLocation});

  final AppOrder order;
  final LatLng? driverLocation;

  @override
  Widget build(BuildContext context) {
    final destination = order.deliveryLat != null && order.deliveryLng != null
        ? LatLng(order.deliveryLat!, order.deliveryLng!)
        : null;
    final center = driverLocation ?? destination;
    if (center == null) {
      return Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(context.l10n.yourRiderIsOnTheWay),
        ),
      );
    }
    return SizedBox(
      height: 220,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FlutterMap(
          options: MapOptions(initialCenter: center, initialZoom: 14),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.multi_vendor',
            ),
            MarkerLayer(markers: [
              if (destination != null)
                Marker(
                  point: destination,
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.home,
                      color: AppColors.dangerInk, size: 32),
                ),
              if (driverLocation != null)
                Marker(
                  point: driverLocation!,
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.delivery_dining,
                      color: AppColors.primary, size: 36),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _CallDriverCard extends StatelessWidget {
  const _CallDriverCard({required this.contact});

  final DriverContact contact;

  Future<void> _call(BuildContext context) => callPhone(context, contact.phone);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.warmFill,
          child: Icon(Icons.delivery_dining, color: AppColors.primary),
        ),
        title: Text(contact.name),
        subtitle: Text(context.l10n.yourDeliveryDriver),
        trailing: FilledButton.icon(
          onPressed: () => _call(context),
          icon: const Icon(Icons.call, size: 18),
          label: Text(context.l10n.call),
        ),
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.order, required this.busy});

  final AppOrder order;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final needsPayment = !order.isCod && !order.isPaid && !order.status.isTerminal;
    return Card(
      child: ListTile(
        leading: Icon(
            order.isCod ? Icons.payments_outlined : Icons.credit_card),
        title: Text(order.isCod ? context.l10n.cashOnDelivery : context.l10n.cardOrWallet),
        subtitle: Text(context.l10n.paymentStatusLabel(
            order.paymentStatus == 'paid' ? context.l10n.paymentStatusPaid : context.l10n.paymentStatusUnpaid)),
        trailing: needsPayment
            ? FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final cubit = context.read<OrderDetailsCubit>();
                        final messenger = ScaffoldMessenger.of(context);
                        final router = GoRouter.of(context);
                        final checkout = await cubit.retryPayment();
                        if (checkout == null) return;

                        final result =
                            await runPaymobCheckout(router, checkout);
                        if (result != PaymobFlowResult.paid) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: const Text(
                                  'Payment not completed. The order stays '
                                  'unpaid and is not sent to the restaurant.'),
                              backgroundColor: AppColors.dangerInk,
                            ),
                          );
                        }
                      },
                child: Text(context.l10n.payNow),
              )
            : order.isPaid
                ? const Icon(Icons.check_circle, color: AppColors.success)
                : null,
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.cubit});

  final OrderDetailsCubit cubit;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _rating = 5;

  /// Zero until tapped. The delivery is rated separately from the food, and a
  /// customer who only wants to talk about one of them should not have to
  /// invent a score for the other — a null driver rating is left out of the
  /// driver's average entirely.
  int _driverRating = 0;
  final _comment = TextEditingController();
  final _driverComment = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _comment.dispose();
    _driverComment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final ok = await widget.cubit.submitReview(
      rating: _rating,
      comment: _comment.text,
      driverRating: _driverRating == 0 ? null : _driverRating,
      driverComment: _driverComment.text,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
      showSnack(context, context.l10n.thanksForYourReview);
    } else {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Only offered when somebody actually delivered it.
    final driverId = widget.cubit.state.order?.driverId;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.howWasYourOrder,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(l10n.rateTheStore,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 13, color: AppColors.textMuted)),
            RatingInput(
              value: _rating,
              size: 32,
              onChanged: (star) => setState(() => _rating = star),
            ),
            TextField(
              controller: _comment,
              maxLines: 3,
              decoration: InputDecoration(labelText: l10n.commentOptional),
            ),
            if (driverId != null) ...[
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text(l10n.howWasTheDriver,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textMuted)),
              RatingInput(
                value: _driverRating,
                size: 30,
                onChanged: (star) => setState(() => _driverRating = star),
              ),
              if (_driverRating > 0)
                TextField(
                  controller: _driverComment,
                  maxLines: 2,
                  decoration: InputDecoration(labelText: l10n.commentOptional),
                ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const ButtonSpinner()
                    : Text(l10n.submitReview),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryProofCard extends StatelessWidget {
  const _DeliveryProofCard({required this.proofUrl});

  final String proofUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded, color: AppColors.success, size: 20),
              const SizedBox(width: 8),
              Text(
                context.l10n.proofOfDelivery,
                style: AppType.heading(15, color: AppColors.ink),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            child: AppNetworkImage(
              url: proofUrl,
              height: 180,
              width: double.infinity,
            ),
          ),
        ],
      ),
    );
  }
}

/// Order details while the order, its items and the driver's position load.
/// Mirrors the real page: number + chip, stepper, payment row, item lines,
/// totals block.
class _OrderDetailsSkeleton extends StatelessWidget {
  const _OrderDetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonTheme(
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          Row(
            children: const [
              Expanded(child: Skeleton.line(widthFactor: 0.5, height: 20)),
              Skeleton(width: 84, height: 26, shape: SkeletonShape.pill),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          const Skeleton.line(widthFactor: 0.35, height: 15),
          const SizedBox(height: AppSpace.lg),
          const Skeleton.box(height: 96, radius: 18),
          const SizedBox(height: AppSpace.xxl),
          const Skeleton.box(height: 72, radius: AppRadii.xl),
          const SizedBox(height: AppSpace.lg),
          const Skeleton.line(widthFactor: 0.2, height: 16),
          const SizedBox(height: AppSpace.md),
          for (var i = 0; i < 3; i++) ...[
            Row(
              children: const [
                Skeleton(width: 26, height: 14),
                SizedBox(width: AppSpace.md),
                Expanded(child: Skeleton.line(widthFactor: 0.6, height: 14)),
                SizedBox(width: AppSpace.md),
                Skeleton(width: 56, height: 14),
              ],
            ),
            const SizedBox(height: AppSpace.md + 2),
          ],
          const Skeleton.box(height: 104, radius: AppRadii.md),
        ],
      ),
    );
  }
}
