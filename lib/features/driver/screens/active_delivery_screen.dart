import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/tokens.dart';
import '../../../core/models/order.dart';
import '../../../core/repositories/driver_repository.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/supabase_client.dart';
import '../../../core/utils/dialer.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart';
import '../../customer/orders/order_chat_sheet.dart';
import '../active_delivery_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class ActiveDeliveryScreen extends StatelessWidget {
  const ActiveDeliveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          ActiveDeliveryCubit(OrderRepository(), DriverRepository(), supabase),
      child: const _ActiveDeliveryView(),
    );
  }
}

class _ActiveDeliveryView extends StatelessWidget {
  const _ActiveDeliveryView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ActiveDeliveryCubit, ActiveDeliveryState>(
      listenWhen: (previous, current) =>
          previous.error != current.error && current.error != null,
      listener: (context, state) => showFailure(context, state.error!),
      builder: (context, state) {
        if (state.loading) return const LoadingView();
        final order = state.order;
        if (order == null) {
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: context.read<ActiveDeliveryCubit>().refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.75,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Outer styled container
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: AppColors.warmFill,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primary.withValues(
                                  alpha: 0.15,
                                ),
                                width: 4,
                              ),
                            ),
                            child: const Icon(
                              Icons.sports_motorsports_rounded,
                              color: AppColors.primary,
                              size: 56,
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            context.l10n.noActiveDelivery,
                            style: AppType.heading(22, color: AppColors.ink),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            context.l10n.noActiveDeliveryDesc,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 14,
                              height: 1.45,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),
                          ElevatedButton.icon(
                            onPressed: () =>
                                context.read<ActiveDeliveryCubit>().refresh(),
                            icon: const Icon(Icons.refresh_rounded, size: 20),
                            label: Text(context.l10n.refreshStatus),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadii.lg,
                                ),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        final destination =
            order.deliveryLat != null && order.deliveryLng != null
            ? LatLng(order.deliveryLat!, order.deliveryLng!)
            : null;
        final center =
            state.myLocation ??
            state.vendorLocation ??
            destination ??
            const LatLng(30.0444, 31.2357);

        String? distanceLabel;
        if (destination != null && state.myLocation != null) {
          final km = const Distance().as(
            LengthUnit.Kilometer,
            state.myLocation!,
            destination,
          );
          distanceLabel = '${km.toStringAsFixed(1)} ${context.l10n.km}';
        }

        return Stack(
          children: [
            Positioned.fill(
              child: _DeliveryMap(
                center: center,
                vendorLocation: state.vendorLocation,
                destination: destination,
                myLocation: state.myLocation,
              ),
            ),

            // Premium Floating Navigation Guidance Bar at top
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.navigation_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.l10n.headToDropoff,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              order.addressSummary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (distanceLabel != null) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                          ),
                          child: Text(
                            distanceLabel,
                            style: const TextStyle(
                              color: AppColors.onDarkSuccess,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Bottom Sheet
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _Sheet(
                order: order,
                vendorName: state.vendorName,
                destination: destination,
                myLocation: state.myLocation,
                busy: state.busy,
                onDelivered: () => _showDeliveryProofDialog(context),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Take a photo, upload it, and only then complete the drop.
  ///
  /// "Confirm with photo" has to mean the photo arrived. Two earlier versions
  /// of this completed the delivery when it had not: backing out of the
  /// camera marked the order delivered, and so did a failed upload. Delivery
  /// is not reversible, so both produced a completed drop with no proof and
  /// no way to undo it.
  ///
  /// The upload is also the slow step — a photo over a phone connection at
  /// someone's door — and it ran with no indication anything was happening,
  /// so the screen sat still and then jumped to delivered. It now blocks
  /// visibly, and a failure offers the choice rather than taking it.
  Future<void> _deliverWithPhoto(
    BuildContext context,
    ActiveDeliveryCubit cubit,
    String orderId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final l10n = context.l10n;

    XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        imageQuality: 85,
      );
    } catch (error) {
      // Could not even open the camera: leave the order alone so the driver
      // can retry or skip deliberately.
      showFailureOn(messenger, l10n, error);
      return;
    }

    // Backing out of the camera is not a decision to deliver. "Skip & mark
    // delivered" is a separate, deliberate button for that.
    if (file == null) {
      showSnackOn(messenger, l10n.proofPhotoCancelled);
      return;
    }

    final bytes = await file.readAsBytes();
    final name = file.name;
    while (true) {
      // Re-checked every pass, not once before the loop: the driver can leave
      // this screen while the camera is open or between retries, and anything
      // below would be pushing dialogs onto a navigator that has moved on.
      if (!navigator.mounted) return;

      // Captured so the dialog is closed by its own context rather than by
      // popping whatever happens to be on top of the navigator — the same
      // mistake that once tore a page down instead of a dialog.
      BuildContext? progressContext;
      // Barrier-locked: the upload decides whether the order completes, so
      // dismissing this would leave the driver guessing which way it went.
      unawaited(
        showDialog<void>(
          context: navigator.context,
          barrierDismissible: false,
          builder: (dialogContext) {
            progressContext = dialogContext;
            return PopScope(
              canPop: false,
              child: AlertDialog(
                content: Row(
                  children: [
                    const ButtonSpinner(size: 20),
                    const SizedBox(width: AppSpace.lg),
                    Expanded(child: Text(l10n.uploadingProofPhoto)),
                  ],
                ),
              ),
            );
          },
        ).then((_) => progressContext = null),
      );

      String? url;
      Object? failure;
      try {
        url = await OrderRepository().uploadDeliveryProofImage(
          orderId,
          bytes,
          name,
        );
      } catch (error) {
        failure = error;
      }

      if (progressContext case final dialogContext?
          when dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
      if (!navigator.mounted) return;

      if (url != null) {
        cubit.markDelivered(proofUrl: url);
        return;
      }

      // Failed. The driver chose to attach proof, so the app must not decide
      // on their behalf that going without it is fine.
      final choice = await showDialog<String>(
        context: navigator.context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.proofPhotoFailed),
          content: Text(errorText(dialogContext, failure!)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'skip'),
              child: Text(l10n.deliverWithoutPhoto),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'retry'),
              child: Text(l10n.retry),
            ),
          ],
        ),
      );

      if (choice == 'retry') continue;
      // Cancel leaves the order active and untouched; skip is the driver
      // saying out loud that the drop happened without proof.
      if (choice == 'skip') cubit.markDelivered();
      return;
    }
  }

  void _showDeliveryProofDialog(BuildContext context) {
    final cubit = context.read<ActiveDeliveryCubit>();
    final order = cubit.state.order;
    if (order == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: const BoxDecoration(
                  color: AppColors.successFill,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: AppColors.success,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.deliveryProofPhotoOptional,
                style: AppType.heading(18, color: AppColors.ink),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.deliveryProofOptionalHint,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Option 1: Take Photo (Optional)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetCtx);
                    _deliverWithPhoto(context, cubit, order.id);
                  },
                  icon: const Icon(
                    Icons.photo_camera_rounded,
                    color: AppColors.primary,
                  ),
                  label: Text(
                    context.l10n.addPhotoProof,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Option 2: Skip & Mark Delivered
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetCtx);
                    cubit.markDelivered();
                  },
                  icon: const Icon(Icons.done_all_rounded, size: 20),
                  label: Text(
                    context.l10n.skipAndDeliver,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DeliveryMap extends StatelessWidget {
  const _DeliveryMap({
    required this.center,
    required this.vendorLocation,
    required this.destination,
    required this.myLocation,
  });

  final LatLng center;
  final LatLng? vendorLocation;
  final LatLng? destination;
  final LatLng? myLocation;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: 13),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.multi_vendor',
        ),
        MarkerLayer(
          markers: [
            if (vendorLocation != null)
              Marker(
                point: vendorLocation!,
                width: 46,
                height: 46,
                child: _mapPin(Icons.storefront_rounded, AppColors.primary),
              ),
            if (destination != null)
              Marker(
                point: destination!,
                width: 46,
                height: 46,
                child: _mapPin(Icons.place_rounded, AppColors.success),
              ),
            if (myLocation != null)
              Marker(
                point: myLocation!,
                width: 46,
                height: 46,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.delivery_dining_rounded,
                    size: 24,
                    color: AppColors.primary,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _mapPin(IconData icon, Color color) => Container(
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2.5),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.35),
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Icon(icon, size: 20, color: Colors.white),
  );
}

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.order,
    required this.vendorName,
    required this.destination,
    required this.myLocation,
    required this.busy,
    required this.onDelivered,
  });

  final AppOrder order;
  final String? vendorName;
  final LatLng? destination;
  final LatLng? myLocation;
  final bool busy;
  final VoidCallback onDelivered;

  Future<void> _call(BuildContext context) =>
      callPhone(context, order.customerPhone);

  /// The store's own line, for the problems only the restaurant can answer:
  /// a missing item, a wrong bag, a shutter that is still down.
  ///
  /// Fetched on tap rather than with the order — most deliveries never need
  /// it, and the number is not on the order row.
  Future<void> _callVendor(BuildContext context) async {
    final contact = await showBlockingProgress(
      context,
      () => OrderRepository().fetchVendorContact(order.id),
    );
    if (!context.mounted) return;
    if (contact == null) {
      showSnack(context, context.l10n.noStorePhone, error: true);
      return;
    }
    await callPhone(context, contact.phone);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A1E1519),
            blurRadius: 30,
            offset: Offset(0, -8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),

            // Order Identity Row
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ACTIVE DELIVERY',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Order #${order.orderNumber}',
                      style: AppType.mono(
                        14.5,
                        color: AppColors.ink,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: order.isCod
                        ? AppColors.amberFill
                        : AppColors.successFill,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        order.isCod
                            ? Icons.payments_rounded
                            : Icons.credit_card_rounded,
                        size: 13,
                        color: order.isCod
                            ? AppColors.amberInk
                            : AppColors.successInk,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        order.isCod ? 'Collect Cash' : 'Paid Online',
                        style: TextStyle(
                          color: order.isCod
                              ? AppColors.amberInk
                              : AppColors.successInk,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Visual Timeline / Route Steps
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppRadii.xl),
                boxShadow: AppShadows.card,
              ),
              child: Column(
                children: [
                  _buildTimelineStep(
                    icon: Icons.storefront_rounded,
                    iconBg: AppColors.warmFill,
                    iconColor: AppColors.primary,
                    title: vendorName ?? context.l10n.store,
                    subtitle: context.l10n.pickedUp,
                    showConnector: true,
                  ),
                  _buildTimelineStep(
                    icon: Icons.location_on_rounded,
                    iconBg: AppColors.successFill,
                    iconColor: AppColors.success,
                    title: order.customerName ?? context.l10n.customer,
                    subtitle: order.addressSummary,
                    showConnector: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Collection instruction alert box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: order.isCod
                    ? AppColors.amberFill.withValues(alpha: 0.5)
                    : AppColors.successFill.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(
                  color: order.isCod
                      ? AppColors.amberInk.withValues(alpha: 0.2)
                      : AppColors.successInk.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    order.isCod
                        ? Icons.info_outline_rounded
                        : Icons.check_circle_outline_rounded,
                    color: order.isCod
                        ? AppColors.amberInk
                        : AppColors.successInk,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.isCod
                          ? '${context.l10n.collect} ${formatMoney(order.total)} ${context.l10n.inCash}'
                          : context.l10n.paidOnlineNothingToCollect,
                      style: TextStyle(
                        color: order.isCod
                            ? AppColors.amberInk
                            : AppColors.successInk,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Actions Row
            Row(
              children: [
                if (order.customerPhone != null) ...[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: IconButton(
                      onPressed: () => _call(context),
                      icon: const Icon(
                        Icons.phone_in_talk_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      tooltip: context.l10n.callCustomer,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: IconButton(
                    onPressed: () => _callVendor(context),
                    icon: const Icon(
                      Icons.storefront_rounded,
                      color: AppColors.ink,
                      size: 20,
                    ),
                    tooltip: context.l10n.callStore,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: IconButton(
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => OrderChatSheet(orderId: order.id),
                    ),
                    icon: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: Colors.orange,
                      size: 20,
                    ),
                    tooltip: context.l10n.liveChat,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: IconButton(
                    onPressed: () async {
                      if (destination != null) {
                        final url = Uri.parse(
                          'https://www.google.com/maps/search/?api=1&query=${destination!.latitude},${destination!.longitude}',
                        );
                        await launchUrl(
                          url,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    icon: const Icon(
                      Icons.navigation_rounded,
                      color: Colors.blue,
                      size: 20,
                    ),
                    tooltip: context.l10n.openInMaps,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.success.withValues(alpha: 0.25),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.lg),
                        ),
                      ),
                      onPressed: busy ? null : onDelivered,
                      icon: busy
                          ? const SizedBox.shrink()
                          : const Icon(Icons.done_all_rounded, size: 20),
                      label: busy
                          ? const ButtonSpinner()
                          : Text(context.l10n.markDelivered),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineStep({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool showConnector,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 16),
            ),
            if (showConnector)
              Container(
                width: 2,
                height: 30,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: const BoxDecoration(color: AppColors.border),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
