import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/tokens.dart';
import '../../../core/repositories/vendor_admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';
import 'package:multi_vendor/app/locale_cubit.dart';

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
      if (mounted) showSnack(context, readableError(error), error: true);
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
    final result = await showModalBottomSheet<String>(
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
      if (mounted) showSnack(context, 'Photo updated successfully!');
    } catch (error) {
      if (mounted) showSnack(context, readableError(error), error: true);
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

            // Open / closed hero.
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: vendor.isOpen
                      ? const [Color(0xFF18A957), Color(0xFF0E7C3F)]
                      : const [Color(0xFF8C8178), Color(0xFF6B635C)],
                ),
                borderRadius: BorderRadius.circular(AppRadii.xl),
                boxShadow: [
                  BoxShadow(
                    color:
                        (vendor.isOpen
                                ? const Color(0xFF18A957)
                                : const Color(0xFF8C8178))
                            .withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: vendor.isOpen
                          ? const Color(0xFF5FE39B)
                          : const Color(0xFFE39B5F),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color:
                              (vendor.isOpen
                                      ? const Color(0xFF5FE39B)
                                      : const Color(0xFFE39B5F))
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
                    onChanged: _busy ? null : (v) => _patch({'is_open': v}),
                    activeThumbColor: Colors.white,
                    activeTrackColor: Colors.white.withValues(alpha: 0.45),
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Busy Mode Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: vendor.isBusy ? AppColors.amberFill : Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.xl),
                border: Border.all(
                  color: vendor.isBusy ? AppColors.amberInk.withValues(alpha: 0.4) : AppColors.border,
                ),
                boxShadow: AppShadows.card,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.local_fire_department_rounded,
                    color: vendor.isBusy ? AppColors.amberInk : AppColors.textMuted,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Busy Mode (+15 mins prep)',
                          style: TextStyle(
                            color: vendor.isBusy ? AppColors.amberInk : AppColors.ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          vendor.isBusy
                              ? 'Customers see store as busy with +15 min extra prep'
                              : 'Toggle when orders overflow to add prep time buffer',
                          style: TextStyle(
                            color: vendor.isBusy ? AppColors.amberInk.withValues(alpha: 0.8) : AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: vendor.isBusy,
                    onChanged: _busy
                        ? null
                        : (v) => _patch({
                              'is_busy': v,
                              'extra_prep_minutes': v ? 15 : 0,
                            }),
                    activeTrackColor: AppColors.amberInk,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Shop Cover & Logo Image Editor
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
                  // Cover Image
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
                          Container(color: Colors.black38),
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.add_photo_alternate_rounded,
                                  color: Colors.white70,
                                  size: 28,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  vendor.coverUrl != null
                                      ? 'Change Cover Photo'
                                      : 'Upload Cover Photo',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Logo/Avatar (Bottom Left)
                  Positioned(
                    bottom: 12,
                    left: 16,
                    child: GestureDetector(
                      onTap: _busy ? null : () => _uploadImage(isLogo: true),
                      child: Stack(
                        alignment: Alignment.center,
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
                          Container(
                            width: 68,
                            height: 68,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black26,
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              color: Colors.white,
                              size: 18,
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
            ]),
            const SizedBox(height: 20),

            _sectionLabel(context.l10n.feesAndOrders),
            _card([
              _navRow(
                Icons.delivery_dining_rounded,
                context.l10n.deliveryFee,
                formatMoney(vendor.deliveryFee),
                onTap: () => _editField(
                  title: context.l10n.deliveryFee3,
                  label: context.l10n.deliveryFee2,
                  initial: vendor.deliveryFee.toStringAsFixed(2),
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  icon: Icons.delivery_dining_rounded,
                  onSave: (v) =>
                      _patch({'delivery_fee': double.tryParse(v) ?? 0}),
                ),
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
              ),
              _switchRow(
                Icons.volume_up_rounded,
                context.l10n.newOrderSound,
                _soundOn,
                (v) => setState(() => _soundOn = v),
              ),
              _switchRow(
                Icons.language_rounded,
                context.l10n.arabic,
                context.watch<LocaleCubit>().state.languageCode == 'ar',
                (v) => context.read<LocaleCubit>().setLocale(
                  v ? const Locale('ar') : const Locale('en'),
                ),
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

  Widget _navRow(
    IconData icon,
    String label,
    String value, {
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14.5,
                color: AppColors.ink,
              ),
            ),
            const Spacer(),
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
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
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
