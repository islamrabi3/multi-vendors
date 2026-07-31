import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/vendor.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/widgets/common.dart';
import '../auth_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AuthCubit>().completeVendorOnboarding({
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'phone': _phone.text.trim(),
      'address_text': _address.text.trim(),
      'category_id': _categoryId,
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
            showSnack(context, readableError(state.error!), error: true),
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
