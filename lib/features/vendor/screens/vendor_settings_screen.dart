import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:multi_vendor/app/locale_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../../app/tokens.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/vendor_admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/location_picker.dart';
import '../../auth/auth_cubit.dart';
import '../vendor_shell.dart' show VendorWebNav;
import 'menu_import_screen.dart';
import 'vendor_orders_history_screen.dart';
import 'vendor_schedule_screen.dart';

/// The store's own settings.
///
/// Grouped by what an owner is doing when they open it — is the shop taking
/// orders, what customers see, how orders behave, and the terms the platform
/// sets — rather than one long list. On a wide screen the store's identity
/// and its open/busy switches stay in a column of their own beside the rest.
class VendorSettingsScreen extends StatefulWidget {
  const VendorSettingsScreen({super.key});

  @override
  State<VendorSettingsScreen> createState() => _VendorSettingsScreenState();
}

class _VendorSettingsScreenState extends State<VendorSettingsScreen> {
  final _admin = VendorAdminRepository();
  bool _busy = false;
  bool _uploading = false;

  Future<void> _patch(Map<String, dynamic> values) async {
    final auth = context.read<AuthCubit>();
    final vendor = auth.state.vendor;
    if (vendor == null) return;
    setState(() => _busy = true);
    try {
      final updated = await _admin.updateVendor(vendor.id, values);
      auth.vendorUpdated(updated);
      if (mounted) showSnack(context, context.l10n.saved);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One text field in a form that opens as a sheet on a phone and a dialog on
  /// the web. [validate] returns an error message, or null to save.
  Future<void> _editText({
    required String title,
    required String label,
    required String initial,
    required IconData icon,
    required Future<void> Function(String value) onSave,
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
    String? Function(String value)? validate,
    List<TextInputFormatter>? formatters,
  }) async {
    final controller = TextEditingController(text: initial);
    await showFormSheet<bool>(
      context: context,
      title: title,
      icon: icon,
      contentBuilder: (_) => TextField(
        controller: controller,
        autofocus: true,
        keyboardType: keyboard,
        maxLines: maxLines,
        minLines: 1,
        inputFormatters: formatters,
        decoration: InputDecoration(labelText: label),
      ),
      submitLabel: context.l10n.save,
      cancelLabel: context.l10n.cancel,
      onSubmit: (_) async {
        final value = controller.text.trim();
        final error = validate?.call(value);
        if (error != null) throw Exception(error);
        await onSave(value);
        return true;
      },
    );
    controller.dispose();
  }

  /// Prep time is picked, not typed: a handful of realistic values covers
  /// almost every kitchen, and a typed "2" meaning hours is a real mistake.
  Future<void> _editPrepTime(Vendor vendor) async {
    var minutes = vendor.avgPrepMinutes;
    const presets = [10, 15, 20, 25, 30, 40, 45, 60];
    await showFormSheet<bool>(
      context: context,
      title: context.l10n.avgPrepTime,
      icon: Icons.timer_outlined,
      contentBuilder: (rebuild) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final value in presets)
            ChoiceChip(
              label: Text('$value ${context.l10n.minShort}'),
              selected: minutes == value,
              onSelected: (_) {
                minutes = value;
                rebuild();
              },
            ),
        ],
      ),
      submitLabel: context.l10n.save,
      cancelLabel: context.l10n.cancel,
      onSubmit: (_) async {
        await _patch({'avg_prep_minutes': minutes});
        return true;
      },
    );
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

    setState(() => _uploading = true);
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
      final updated = await _admin.updateVendor(vendor.id, {
        isLogo ? 'logo_url' : 'cover_url': url,
      });
      auth.vendorUpdated(updated);
      if (mounted) showSnack(context, context.l10n.photoUpdated);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickLocation(Vendor vendor) async {
    final hasPin = vendor.lat != null && vendor.lng != null;
    final picked = await showLocationPicker(
      context,
      initial: hasPin ? LatLng(vendor.lat!, vendor.lng!) : null,
      title: context.l10n.storeLocationOnMap,
    );
    if (picked == null) return;
    await _patch({
      'lat': picked.point.latitude,
      'lng': picked.point.longitude,
      // Only fill an empty address: the owner's own wording wins.
      if ((vendor.addressText?.trim().isEmpty ?? true) &&
          picked.address != null)
        'address_text': picked.address,
    });
  }

  /// Opens a tool in the desktop shell's content pane, or pushes it on a phone.
  void _openTool(String toolId, Widget Function() page) {
    final webNav = VendorWebNav.maybeOf(context);
    if (webNav != null) {
      webNav.openTool(toolId);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page()));
  }

  @override
  Widget build(BuildContext context) {
    final vendor = context.select((AuthCubit c) => c.state.vendor);
    if (vendor == null) return const LoadingView();

    final identity = [
      _ProfileHeader(
        vendor: vendor,
        uploading: _uploading,
        onChangeCover: () => _uploadImage(isLogo: false),
        onChangeLogo: () => _uploadImage(isLogo: true),
      ),
      const SizedBox(height: AppSpace.lg),
      _StatusCard(
        vendor: vendor,
        busy: _busy,
        onOpenChanged: (v) => _patch({'is_open': v}),
        onBusyChanged: (v) =>
            _patch({'is_busy': v, 'extra_prep_minutes': v ? 15 : 0}),
      ),
    ];

    final settings = _settingsGroups(context, vendor);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            if (wide) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 380, child: Column(children: identity)),
                        const SizedBox(width: 24),
                        Expanded(child: Column(children: settings)),
                      ],
                    ),
                  ),
                ),
              );
            }
            return ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                32 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                  child: Text(
                    context.l10n.settings,
                    style: AppType.display(26),
                  ),
                ),
                ...identity,
                const SizedBox(height: AppSpace.lg),
                ...settings,
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _settingsGroups(BuildContext context, Vendor vendor) {
    final l10n = context.l10n;
    final hasPin = vendor.lat != null && vendor.lng != null;
    final language = context.watch<LocaleCubit>().state.languageCode;

    return [
      _Group(
        title: l10n.storeProfile,
        children: [
          _Row(
            icon: Icons.storefront_rounded,
            label: l10n.storeName,
            value: vendor.name,
            onTap: _busy
                ? null
                : () => _editText(
                    title: l10n.storeName,
                    label: l10n.name,
                    initial: vendor.name,
                    icon: Icons.storefront_rounded,
                    validate: (v) => v.isEmpty ? l10n.required : null,
                    onSave: (v) => _patch({'name': v}),
                  ),
          ),
          _Row(
            icon: Icons.notes_rounded,
            label: l10n.description,
            value: (vendor.description?.trim().isNotEmpty ?? false)
                ? vendor.description!
                : l10n.addADescription,
            valueMuted: !(vendor.description?.trim().isNotEmpty ?? false),
            multiline: true,
            onTap: _busy
                ? null
                : () => _editText(
                    title: l10n.description,
                    label: l10n.description,
                    initial: vendor.description ?? '',
                    icon: Icons.notes_rounded,
                    maxLines: 4,
                    keyboard: TextInputType.multiline,
                    onSave: (v) => _patch({'description': v}),
                  ),
          ),
          _Row(
            icon: Icons.call_outlined,
            label: l10n.storePhone,
            value: (vendor.phone?.trim().isNotEmpty ?? false)
                ? vendor.phone!
                : '—',
            valueMuted: !(vendor.phone?.trim().isNotEmpty ?? false),
            ltrValue: true,
            onTap: _busy
                ? null
                : () => _editText(
                    title: l10n.storePhone,
                    label: l10n.phoneNumber,
                    initial: vendor.phone ?? '',
                    icon: Icons.call_outlined,
                    keyboard: TextInputType.phone,
                    formatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                    ],
                    onSave: (v) => _patch({'phone': v}),
                  ),
          ),
          _Row(
            icon: Icons.place_outlined,
            label: l10n.storeAddress,
            value: (vendor.addressText?.trim().isNotEmpty ?? false)
                ? vendor.addressText!
                : '—',
            valueMuted: !(vendor.addressText?.trim().isNotEmpty ?? false),
            multiline: true,
            onTap: _busy
                ? null
                : () => _editText(
                    title: l10n.storeAddress,
                    label: l10n.address,
                    initial: vendor.addressText ?? '',
                    icon: Icons.place_outlined,
                    maxLines: 3,
                    onSave: (v) => _patch({'address_text': v}),
                  ),
          ),
          // A missing pin hides the store from "nearby", so it is flagged in
          // the amber "needs you" colour rather than reading as another row.
          _Row(
            icon: hasPin
                ? Icons.where_to_vote_rounded
                : Icons.add_location_alt_outlined,
            iconTone: hasPin ? AppColors.successInk : AppColors.amberInk,
            label: l10n.storeLocationOnMap,
            value: hasPin ? l10n.locationPinSet : l10n.pickOnMap,
            subtitle: hasPin ? null : l10n.locationMissingHint,
            onTap: _busy ? null : () => _pickLocation(vendor),
          ),
        ],
      ),
      _Group(
        title: l10n.ordersSettingsTitle,
        children: [
          _SwitchRow(
            icon: Icons.bolt_rounded,
            label: l10n.autoAcceptOrders,
            subtitle: l10n.autoAcceptOrdersHint,
            value: vendor.autoAccept,
            onChanged: _busy ? null : (v) => _patch({'auto_accept': v}),
          ),
          _Row(
            icon: Icons.timer_outlined,
            label: l10n.avgPrepTime,
            value: '${vendor.avgPrepMinutes} ${l10n.minShort}',
            onTap: _busy ? null : () => _editPrepTime(vendor),
          ),
          _Row(
            icon: Icons.shopping_bag_outlined,
            label: l10n.minimumOrder,
            value: vendor.minOrderAmount > 0
                ? formatMoney(vendor.minOrderAmount)
                : l10n.noMinimum,
            onTap: _busy
                ? null
                : () => _editText(
                    title: l10n.minimumOrder,
                    label: l10n.minimumOrder,
                    initial: vendor.minOrderAmount > 0
                        ? vendor.minOrderAmount.toStringAsFixed(0)
                        : '',
                    icon: Icons.shopping_bag_outlined,
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    formatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    onSave: (v) =>
                        _patch({'min_order_amount': double.tryParse(v) ?? 0}),
                  ),
          ),
        ],
      ),
      _Group(
        title: l10n.operations,
        children: [
          _Row(
            icon: Icons.schedule_rounded,
            label: l10n.operatingHoursSchedule,
            onTap: () => _openTool(
              'schedule',
              () => VendorScheduleScreen(vendorId: vendor.id),
            ),
          ),
          _Row(
            icon: Icons.star_rate_rounded,
            iconTone: AppColors.rating,
            label: l10n.reviewsInbox,
            value: vendor.ratingCount == 0
                ? l10n.newStoreBadge
                : '${vendor.ratingAvg.toStringAsFixed(1)} · '
                      '${l10n.ratingsCountLabel(vendor.ratingCount)}',
            onTap: () {
              final webNav = VendorWebNav.maybeOf(context);
              if (webNav != null) {
                webNav.openTool('reviews');
                return;
              }
              context.push('/vendor-app/reviews');
            },
          ),
          _Row(
            icon: Icons.history_rounded,
            label: l10n.ordersHistory,
            onTap: () => _openTool(
              'history',
              () => VendorOrdersHistoryScreen(vendorId: vendor.id),
            ),
          ),
          // Only when an admin has granted it: a store cannot grant itself
          // the tool, so a permanently dead row would only raise questions.
          if (vendor.aiMenuEnabled)
            _Row(
              icon: Icons.document_scanner_outlined,
              label: l10n.aiMenuImport,
              subtitle: l10n.aiMenuImportHint,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MenuImportScreen(vendorId: vendor.id),
                ),
              ),
            ),
        ],
      ),
      // What the platform sets. Shown so the owner understands their terms,
      // locked so nobody tries to change them and gets a refused save.
      _Group(
        title: l10n.planAndFees,
        footer: l10n.setByPlatformFooter,
        children: [
          _Row(
            icon: Icons.delivery_dining_rounded,
            label: l10n.deliveryFee,
            value: vendor.deliveryFee == 0
                ? l10n.freeDelivery
                : formatMoney(vendor.deliveryFee),
            locked: true,
          ),
          _Row(
            icon: vendor.isSubscription
                ? Icons.card_membership_rounded
                : Icons.percent_rounded,
            label: l10n.billingPlan,
            value: vendor.isSubscription
                ? '${l10n.billingSubscription} · '
                      '${formatMoney(vendor.subscriptionFee)}'
                : '${l10n.billingCommission} · '
                      '${vendor.commissionRate.toStringAsFixed(0)}%',
            locked: true,
          ),
        ],
      ),
      _Group(
        title: l10n.appLanguage,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: SegmentedButton<String>(
              expandedInsets: EdgeInsets.zero,
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'ar', label: Text('العربية')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {language},
              onSelectionChanged: (v) =>
                  context.read<LocaleCubit>().setLocale(Locale(v.first)),
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpace.sm),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () async {
            final confirmed = await showConfirmDialog(
              context: context,
              title: l10n.signOut,
              message: l10n.signOutConfirm,
              confirmLabel: l10n.signOut,
              cancelLabel: l10n.cancel,
              tone: AppDialogTone.danger,
              icon: Icons.logout_rounded,
              onConfirm: () async {},
            );
            if (confirmed && context.mounted) {
              context.read<AuthCubit>().signOut();
            }
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.dangerInk,
            side: const BorderSide(color: AppColors.dangerInk),
            minimumSize: const Size.fromHeight(52),
          ),
          icon: const Icon(Icons.logout_rounded, size: 20),
          label: Text(l10n.signOut),
        ),
      ),
    ];
  }
}

// -----------------------------------------------------------------------------
// Identity and status
// -----------------------------------------------------------------------------

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.vendor,
    required this.uploading,
    required this.onChangeCover,
    required this.onChangeLogo,
  });

  final Vendor vendor;
  final bool uploading;
  final VoidCallback onChangeCover;
  final VoidCallback onChangeLogo;

  static const _coverHeight = 140.0;
  static const _logo = 76.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cover and logo share one Stack so the logo overlaps the cover
          // while staying inside the card's own bounds.
          SizedBox(
            height: _coverHeight + _logo / 2,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: _coverHeight,
                  child: InkWell(
                    onTap: uploading ? null : onChangeCover,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        vendor.coverUrl == null
                            ? const ColoredBox(
                                color: AppColors.warmFill,
                                child: Icon(
                                  Icons.add_photo_alternate_outlined,
                                  color: AppColors.primary,
                                  size: 32,
                                ),
                              )
                            : AppNetworkImage(
                                url: vendor.coverUrl,
                                height: _coverHeight,
                                width: double.infinity,
                              ),
                        PositionedDirectional(
                          top: 10,
                          end: 10,
                          child: _PhotoPill(label: l10n.changeCover),
                        ),
                      ],
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 16,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: uploading ? null : onChangeLogo,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: _logo,
                          height: _logo,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: AppShadows.card,
                          ),
                          child: AppNetworkImage(
                            url: vendor.logoUrl,
                            width: _logo - 6,
                            height: _logo - 6,
                            borderRadius: BorderRadius.circular(19),
                          ),
                        ),
                        PositionedDirectional(
                          end: -4,
                          bottom: -4,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.photo_camera_rounded,
                              color: Colors.white,
                              size: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (uploading)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black38,
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vendor.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.display(21),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SoftBadge(
                      icon: Icons.star_rounded,
                      label: vendor.ratingCount == 0
                          ? l10n.newStoreBadge
                          : '${vendor.ratingAvg.toStringAsFixed(1)} · '
                                '${l10n.ratingsCountLabel(vendor.ratingCount)}',
                      fill: AppColors.amberFill,
                      ink: AppColors.amberInk,
                    ),
                    SoftBadge(
                      icon: Icons.timer_outlined,
                      label: '${vendor.totalPrepMinutes} ${l10n.minShort}',
                      fill: AppColors.neutralFill,
                      ink: AppColors.textSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoPill extends StatelessWidget {
  const _PhotoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Open / closed and busy mode — the two switches that decide whether
/// customers can order right now, kept together and first.
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.vendor,
    required this.busy,
    required this.onOpenChanged,
    required this.onBusyChanged,
  });

  final Vendor vendor;
  final bool busy;
  final ValueChanged<bool> onOpenChanged;
  final ValueChanged<bool> onBusyChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final open = vendor.isOpen;
    return _Group(
      title: l10n.storeStatus,
      children: [
        _SwitchRow(
          icon: open ? Icons.storefront_rounded : Icons.store_mall_directory,
          iconTone: open ? AppColors.successInk : AppColors.textMuted,
          highlight: open ? AppColors.successFill : null,
          label: open ? l10n.storeIsOpen : l10n.storeIsClosed,
          subtitle: open ? l10n.acceptingOrdersNow : l10n.customersCantOrder,
          value: open,
          onChanged: busy ? null : onOpenChanged,
        ),
        _SwitchRow(
          icon: Icons.local_fire_department_rounded,
          iconTone: vendor.isBusy ? AppColors.amberInk : AppColors.textMuted,
          highlight: vendor.isBusy ? AppColors.amberFill : null,
          label: l10n.busyMode,
          subtitle: vendor.isBusy ? l10n.busyStoreNotice : l10n.busyModeHint,
          value: vendor.isBusy,
          activeColor: AppColors.amberInk,
          // Busy only means something while the store is taking orders.
          onChanged: busy || !open ? null : onBusyChanged,
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Rows
// -----------------------------------------------------------------------------

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children, this.footer});

  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(6, 0, 6, 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      indent: 56,
                      color: AppColors.borderSoft,
                    ),
                  children[i],
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 6, 0),
              child: Text(
                footer!,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textFaint,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IconWell extends StatelessWidget {
  const _IconWell({required this.icon, required this.tone});

  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      color: tone.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, size: 18, color: tone),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    this.value,
    this.subtitle,
    this.onTap,
    this.iconTone,
    this.valueMuted = false,
    this.multiline = false,
    this.ltrValue = false,
    this.locked = false,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? iconTone;
  final bool valueMuted;

  /// Long values (description, address) sit under the label instead of
  /// being squeezed into the trailing side.
  final bool multiline;
  final bool ltrValue;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final valueStyle = TextStyle(
      fontSize: 13.5,
      color: valueMuted ? AppColors.textFaint : AppColors.textMuted,
      fontWeight: FontWeight.w500,
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: multiline || subtitle != null
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            _IconWell(icon: icon, tone: iconTone ?? AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                      color: AppColors.ink,
                    ),
                  ),
                  if (multiline && value != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      value!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: valueStyle.copyWith(height: 1.4),
                    ),
                  ],
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: iconTone == AppColors.amberInk
                            ? AppColors.amberInk
                            : AppColors.textFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!multiline && value != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: ltrValue ? TextDirection.ltr : null,
                  style: valueStyle,
                ),
              ),
            ],
            const SizedBox(width: 4),
            if (locked)
              const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: AppColors.textFaint,
                ),
              )
            else if (onTap != null)
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textFaint,
              ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.iconTone,
    this.highlight,
    this.activeColor = AppColors.success,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? iconTone;
  final Color? highlight;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: highlight ?? AppColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          _IconWell(icon: icon, tone: iconTone ?? AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: AppColors.ink,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: activeColor,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: AppColors.border,
          ),
        ],
      ),
    );
  }
}
