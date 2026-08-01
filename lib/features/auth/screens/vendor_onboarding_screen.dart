import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/tokens.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/location_picker.dart';
import '../auth_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// Map pin for the store, styled to sit beside the form's text fields.
///
/// Deliberately not optional: a store with no coordinates is invisible to the
/// customer's "nearby" list and cannot be distance-ranked, and backfilling one
/// later means chasing the owner.
class _LocationField extends StatelessWidget {
  const _LocationField({required this.pin, required this.onTap});

  final LatLng? pin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isSet = pin != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.storeLocationOnMap,
          errorText: isSet ? null : l10n.required,
          border: const OutlineInputBorder(),
        ),
        child: Row(
          children: [
            Icon(
              isSet ? Icons.location_on : Icons.add_location_alt_outlined,
              size: 20,
              color: isSet ? AppColors.success : AppColors.primary,
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                isSet
                    ? '${pin!.latitude.toStringAsFixed(5)}, '
                        '${pin!.longitude.toStringAsFixed(5)}'
                    : l10n.pickOnMap,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: isSet ? AppColors.ink : AppColors.textMuted,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
}

/// Shown once after a vendor-role signup: creates the `vendors` row.
class VendorOnboardingScreen extends StatefulWidget {
  const VendorOnboardingScreen({super.key});

  @override
  State<VendorOnboardingScreen> createState() => _VendorOnboardingScreenState();
}

class _VendorOnboardingScreenState extends State<VendorOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _deliveryFee = TextEditingController(text: '20');
  final _minOrder = TextEditingController(text: '0');
  final _prepMinutes = TextEditingController(text: '20');
  List<VendorCategory> _categories = const [];
  String? _categoryId;

  /// Where the store physically is. Required: without a pin the store cannot be
  /// ranked by distance and never appears in "nearby".
  LatLng? _pin;

  @override
  void initState() {
    super.initState();
    CatalogRepository().fetchVendorCategories().then((categories) {
      if (mounted) setState(() => _categories = categories);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [
      _name, _description, _phone, _address, _deliveryFee, _minOrder, _prepMinutes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final picked = await showLocationPicker(
      context,
      initial: _pin,
      title: context.l10n.storeAddress,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _pin = picked.point;
      // The picker resolves an address for the pin; only fill the field when
      // the vendor has not typed their own.
      final resolved = picked.address?.trim() ?? '';
      if (_address.text.trim().isEmpty && resolved.isNotEmpty) {
        _address.text = resolved;
      }
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final pin = _pin;
    if (pin == null) {
      showSnack(context, context.l10n.pickStoreLocationFirst, error: true);
      return;
    }
    context.read<AuthCubit>().completeVendorOnboarding({
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'phone': _phone.text.trim(),
      'address_text': _address.text.trim(),
      'category_id': _categoryId,
      'lat': pin.latitude,
      'lng': pin.longitude,
      'delivery_fee': double.tryParse(_deliveryFee.text) ?? 0,
      'min_order_amount': double.tryParse(_minOrder.text) ?? 0,
      'avg_prep_minutes': int.tryParse(_prepMinutes.text) ?? 20,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.setUpYourStore),
        actions: [
          IconButton(
            onPressed: () => context.read<AuthCubit>().signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: BlocListener<AuthCubit, AppAuthState>(
        listenWhen: (previous, current) =>
            previous.error != current.error && current.error != null,
        listener: (context, state) =>
            showFailure(context, state.error!),
        child: SingleChildScrollView(
          // "Open my store" is the last thing in this form, so the scroll view
          // has to clear Android's gesture bar itself.
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, 24 + MediaQuery.paddingOf(context).bottom),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(labelText: context.l10n.storeName),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  maxLines: 2,
                  decoration: InputDecoration(labelText: context.l10n.description),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  decoration: InputDecoration(labelText: context.l10n.category),
                  items: [
                    for (final category in _categories)
                      DropdownMenuItem(
                          value: category.id, child: Text(category.name)),
                  ],
                  onChanged: (value) => setState(() => _categoryId = value),
                  validator: (v) => v == null ? 'Pick a category' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: context.l10n.storePhone),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _address,
                  decoration:
                      InputDecoration(labelText: context.l10n.storeAddress),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                _LocationField(pin: _pin, onTap: _pickLocation),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _deliveryFee,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: context.l10n.deliveryFeeEgp),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _minOrder,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: context.l10n.minOrderEgp),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _prepMinutes,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: context.l10n.averagePrepTimeMinutes),
                ),
                const SizedBox(height: 24),
                BlocBuilder<AuthCubit, AppAuthState>(
                  builder: (context, state) => SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: state.busy ? null : _submit,
                      child: state.busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(context.l10n.openMyStore),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
