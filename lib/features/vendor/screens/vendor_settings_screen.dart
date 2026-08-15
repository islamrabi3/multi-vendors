import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/tokens.dart';
import '../../../core/repositories/vendor_admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/location_picker.dart';
import '../../auth/auth_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';
import 'package:multi_vendor/app/locale_cubit.dart';
import '../../../core/widgets/web/adaptive_sheet.dart';
import '../vendor_shell.dart' show VendorWebNav;

class VendorSettingsScreen extends StatefulWidget {
  const VendorSettingsScreen({super.key});

  @override
  State<VendorSettingsScreen> createState() => _VendorSettingsScreenState();
}

class _VendorSettingsScreenState extends State<VendorSettingsScreen> {
  final _admin = VendorAdminRepository();
  bool _busy = false;
  // Device-local preference (sound plays via the dashboard snackbar/alert).
  bool _soundOn = true;

  Future<void> _patch(Map<String, dynamic> values) async {
    final auth = context.read<AuthCubit>();
    final vendor = auth.state.vendor;
    if (vendor == null) return;
    setState(() => _busy = true);
    try {
      final updated = await _admin.updateVendor(vendor.id, values);
      auth.vendorUpdated(updated);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editField({
    required String title,
    required String label,
    required String initial,
    required TextInputType keyboard,
    required IconData icon,
    required ValueChanged<String> onSave,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showAdaptiveSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          left: 20,
          right: 20,
          top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4.5,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Text(title, style: AppType.heading(19, color: AppColors.ink)),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: keyboard,
              decoration: InputDecoration(
                labelText: label,
                prefixIcon: Icon(icon),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                      ),
                    ),
                    onPressed: () => Navigator.pop(sheetContext),
                    child: Text(context.l10n.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.lg),
                        ),
                      ),
                      onPressed: () =>
                          Navigator.pop(sheetContext, controller.text.trim()),
                      child: Text(context.l10n.save),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (result != null) onSave(result);
  }

  Future<void> _uploadImage({required bool isLogo}) async {
    final auth = context.read<AuthCubit>();
    final vendor = auth.state.vendor;
    if (vendor == null) return;

    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
    );
    if (file == null) return;

    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      final folder = isLogo ? 'logo' : 'cover';
      final path =
          '$folder/${vendor.id}/${DateTime.now().millisecondsSinceEpoch}_${file.name}';

      final url = await _admin.uploadImage(
        bucket: 'vendor-assets',
        path: path,
        bytes: bytes,
      );

      final field = isLogo ? 'logo_url' : 'cover_url';
      await _patch({field: url});
      if (mounted) showSnack(context, context.l10n.photoUpdated);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendor = context.select((AuthCubit c) => c.state.vendor);
    if (vendor == null) return const LoadingView();
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                context.l10n.settings,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 26,
                  color: AppColors.ink,
                ),
              ),
            ),

            // Store status — open/closed and busy mode share one container so
            // the two most consequential switches on the screen read as a
            // single control surface, not two competing hero cards.
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.xl),
                boxShadow: AppShadows.raised,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  // Open / closed.
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: vendor.isOpen
                            ? const [AppColors.success, AppColors.successInk]
                            : const [
                                AppColors.textMuted,
                                AppColors.textSecondary,
                              ],
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: vendor.isOpen
                                ? AppColors.onDarkSuccess
                                : AppColors.textFaint,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (vendor.isOpen
                                            ? AppColors.onDarkSuccess
                                            : AppColors.textFaint)
                                        .withValues(alpha: 0.5),
                                blurRadius: 6,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                vendor.isOpen
                                    ? context.l10n.storeIsOpen
                                    : context.l10n.storeIsClosed,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                vendor.isOpen
                                    ? context.l10n.acceptingOrdersNow
                                    : context.l10n.customersCantOrder,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: vendor.isOpen,
                          onChanged: _busy
                              ? null
                              : (v) => _patch({'is_open': v}),
                          activeThumbColor: Colors.white,
                          activeTrackColor: Colors.white.withValues(
                            alpha: 0.45,
                          ),
                          inactiveThumbColor: Colors.white,
                          inactiveTrackColor: Colors.white.withValues(
                            alpha: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Busy mode — only meaningful while open, so it is visually
                  // subordinate: same card, plain surface, no shadow of its own.
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: vendor.isBusy ? AppColors.amberFill : Colors.white,
                    child: Row(
                      children: [
                        Icon(
                          Icons.local_fire_department_rounded,
                          color: vendor.isBusy
                              ? AppColors.amberInk
                              : AppColors.textMuted,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.l10n.busyMode,
                                style: TextStyle(
                                  color: vendor.isBusy
                                      ? AppColors.amberInk
                                      : AppColors.ink,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                vendor.isBusy
                                    ? context.l10n.busyStoreNotice
                                    : context.l10n.busyModeHint,
                                style: TextStyle(
                                  color: vendor.isBusy
                                      ? AppColors.amberInk.withValues(
                                          alpha: 0.8,
                                        )
                                      : AppColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: vendor.isBusy,
                          onChanged: !_busy && vendor.isOpen
                              ? (v) => _patch({
                                  'is_busy': v,
                                  'extra_prep_minutes': v ? 15 : 0,
                                })
                              : null,
                          activeTrackColor: AppColors.amberInk,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Shop cover & logo. The cover photo stays fully visible at rest —
            // a permanent dark scrim over the vendor's own photo hid the thing
            // they came here to check. A bottom gradient plus a small "change"
            // pill carry the edit affordance instead.
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: AppColors.warmFill,
                borderRadius: BorderRadius.circular(AppRadii.xl),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // Cover image.
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: _busy ? null : () => _uploadImage(isLogo: false),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          AppNetworkImage(
                            url: vendor.coverUrl,
                            height: 180,
                            width: double.infinity,
                          ),
                          if (vendor.coverUrl == null)
                            Container(
                              color: Colors.black26,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.add_photo_alternate_rounded,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      context.l10n.tapToAddPhoto,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else ...[
                            // Bottom scrim only, so the logo and pill stay
                            // legible without dimming the photo itself.
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              height: 64,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0),
                                      Colors.black.withValues(alpha: 0.45),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 10,
                              right: 10,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.pill,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.edit_rounded,
                                        color: Colors.white,
                                        size: 13,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        context.l10n.tapToChangePhoto,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Logo, bottom-left, overlapping the cover. The image stays
                  // uncovered; a small pencil badge at the corner is the only
                  // edit affordance, so the logo itself is always checkable.
                  Positioned(
                    bottom: 12,
                    left: 16,
                    child: GestureDetector(
                      onTap: _busy ? null : () => _uploadImage(isLogo: true),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.surface,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 6,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: AppNetworkImage(
                              url: vendor.logoUrl,
                              width: 68,
                              height: 68,
                            ),
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primary,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.edit_rounded,
                                color: Colors.white,
                                size: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_busy)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black45,
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            _sectionLabel(context.l10n.storeProfile),
            _card([
              _navRow(
                Icons.storefront_rounded,
                context.l10n.storeName,
                vendor.name,
                onTap: () => _editField(
                  title: context.l10n.storeName,
                  label: context.l10n.name,
                  initial: vendor.name,
                  keyboard: TextInputType.text,
                  icon: Icons.storefront_rounded,
                  onSave: (v) {
                    if (v.isNotEmpty) _patch({'name': v});
                  },
                ),
              ),
              _navRow(
                Icons.description_outlined,
                context.l10n.description,
                vendor.description ?? context.l10n.addADescription,
                onTap: () => _editField(
                  title: context.l10n.description,
                  label: context.l10n.description,
                  initial: vendor.description ?? '',
                  keyboard: TextInputType.text,
                  icon: Icons.description_outlined,
                  onSave: (v) => _patch({'description': v}),
                ),
              ),
              // Stores created before the map picker existed have no
              // coordinates, so they are invisible to "nearby" until the owner
              // drops a pin here — flagged with the same amber "needs you"
              // language as busy mode, rather than reading as just another row.
              _navRow(
                vendor.lat == null
                    ? Icons.add_location_alt_outlined
                    : Icons.location_on_outlined,
                context.l10n.storeLocationOnMap,
                vendor.lat == null || vendor.lng == null
                    ? context.l10n.pickOnMap
                    : '${vendor.lat!.toStringAsFixed(5)}, '
                          '${vendor.lng!.toStringAsFixed(5)}',
                subtitle: vendor.lat == null || vendor.lng == null
                    ? context.l10n.locationMissingHint
                    : null,
                iconColor: vendor.lat == null || vendor.lng == null
                    ? AppColors.amberInk
                    : null,
                onTap: () async {
                  final picked = await showLocationPicker(
                    context,
                    initial: vendor.lat == null || vendor.lng == null
                        ? null
                        : LatLng(vendor.lat!, vendor.lng!),
                    title: context.l10n.storeLocationOnMap,
                  );
                  if (picked == null) return;
                  await _patch({
                    'lat': picked.point.latitude,
                    'lng': picked.point.longitude,
                  });
                },
              ),
            ]),
            const SizedBox(height: 20),

            _sectionLabel(context.l10n.reviews),
            _card([
              _navRow(
                Icons.reviews_outlined,
                context.l10n.reviewsInbox,
                vendor.ratingCount == 0
                    ? '—'
                    : '${vendor.ratingAvg.toStringAsFixed(1)} · '
                          '${vendor.ratingCount}',
                // In the desktop shell this opens in the content pane beside
                // the sidebar — the same place the sidebar's own Reviews row
                // opens it — rather than pushing a page over the shell.
                onTap: () {
                  final webNav = VendorWebNav.maybeOf(context);
                  if (webNav != null) {
                    webNav.openTool('reviews');
                    return;
                  }
                  context.push('/vendor-app/reviews');
                },
              ),
            ]),
            const SizedBox(height: 20),

            _sectionLabel(context.l10n.feesAndOrders),
            _card([
              // Read-only: the delivery fee is the platform's price, not the
              // store's. A database trigger refuses the write regardless, so
              // an editable row here would only produce a failed save.
              _readOnlyRow(
                Icons.delivery_dining_rounded,
                context.l10n.deliveryFee,
                formatMoney(vendor.deliveryFee),
                context.l10n.setByPlatform,
              ),
              _readOnlyRow(
                vendor.isSubscription
                    ? Icons.card_membership_rounded
                    : Icons.percent_rounded,
                context.l10n.billingPlan,
                vendor.isSubscription
                    ? '${context.l10n.billingSubscription} · '
                          '${formatMoney(vendor.subscriptionFee)}'
                    : '${context.l10n.billingCommission} · '
                          '${vendor.commissionRate.toStringAsFixed(0)}%',
                context.l10n.setByPlatform,
              ),
              _navRow(
                Icons.shopping_bag_outlined,
                context.l10n.minimumOrder,
                formatMoney(vendor.minOrderAmount),
                onTap: () => _editField(
                  title: context.l10n.minimumOrder1,
                  label: context.l10n.minimumOrder,
                  initial: vendor.minOrderAmount.toStringAsFixed(2),
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  icon: Icons.shopping_bag_outlined,
                  onSave: (v) =>
                      _patch({'min_order_amount': double.tryParse(v) ?? 0}),
                ),
              ),
              _navRow(
                Icons.timer_outlined,
                context.l10n.avgPrepTime,
                '${vendor.avgPrepMinutes} ${context.l10n.minShort}',
                onTap: () => _editField(
                  title: context.l10n.avgPrepTime,
                  label: context.l10n.minutes,
                  initial: vendor.avgPrepMinutes.toString(),
                  keyboard: TextInputType.number,
                  icon: Icons.timer_outlined,
                  onSave: (v) =>
                      _patch({'avg_prep_minutes': int.tryParse(v) ?? 20}),
                ),
              ),
            ]),
            const SizedBox(height: 20),

            _sectionLabel(context.l10n.preferences),
            _card([
              _switchRow(
                Icons.autorenew_rounded,
                context.l10n.autoAcceptOrders,
                vendor.autoAccept,
                (v) => _patch({'auto_accept': v}),
                subtitle: context.l10n.autoAcceptOrdersHint,
              ),
              _switchRow(
                Icons.volume_up_rounded,
                context.l10n.newOrderSound,
                _soundOn,
                (v) => setState(() => _soundOn = v),
                subtitle: context.l10n.newOrderSoundHint,
              ),
              _switchRow(
                Icons.language_rounded,
                context.l10n.arabic,
                context.watch<LocaleCubit>().state.languageCode == 'ar',
                (v) => context.read<LocaleCubit>().setLocale(
                  v ? const Locale('ar') : const Locale('en'),
                ),
                subtitle:
                    context.watch<LocaleCubit>().state.languageCode == 'ar'
                    ? context.l10n.arabic
                    : context.l10n.english,
              ),
            ]),
            const SizedBox(height: 32),

            OutlinedButton.icon(
              onPressed: () => context.read<AuthCubit>().signOut(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent, width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
              ),
              icon: const Icon(Icons.logout_rounded, size: 20),
              label: Text(
                context.l10n.signOut,
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Colors.redAccent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: AppColors.textMuted,
      ),
    ),
  );

  Widget _card(List<Widget> rows) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      children.add(rows[i]);
      if (i != rows.length - 1) {
        children.add(const Divider(height: 1, color: AppColors.borderSoft));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  /// A setting the store can see but not change, with the reason why.
  Widget _readOnlyRow(
    IconData icon,
    String label,
    String value,
    String reason,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  reason,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textFaint,
                  ),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.lock_outline_rounded,
            size: 15,
            color: AppColors.textFaint,
          ),
        ],
      ),
    );
  }

  Widget _navRow(
    IconData icon,
    String label,
    String value, {
    required VoidCallback onTap,
    String? subtitle,
    Color? iconColor,
  }) {
    return InkWell(
      onTap: _busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: iconColor ?? AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14.5,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: iconColor ?? AppColors.textFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textFaint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _switchRow(
    IconData icon,
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                    color: AppColors.ink,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textFaint,
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: _busy ? null : onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.success,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: AppColors.border,
          ),
        ],
      ),
    );
  }
}
