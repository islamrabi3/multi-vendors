import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/repositories/vendor_admin_repository.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_cubit.dart';

class VendorSettingsScreen extends StatefulWidget {
  const VendorSettingsScreen({super.key});

  @override
  State<VendorSettingsScreen> createState() => _VendorSettingsScreenState();
}

class _VendorSettingsScreenState extends State<VendorSettingsScreen> {
  final _admin = VendorAdminRepository();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _deliveryFee;
  late final TextEditingController _minOrder;
  late final TextEditingController _prepMinutes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final vendor = context.read<AuthCubit>().state.vendor;
    _name = TextEditingController(text: vendor?.name);
    _description = TextEditingController(text: vendor?.description);
    _deliveryFee =
        TextEditingController(text: vendor?.deliveryFee.toStringAsFixed(2));
    _minOrder =
        TextEditingController(text: vendor?.minOrderAmount.toStringAsFixed(2));
    _prepMinutes =
        TextEditingController(text: vendor?.avgPrepMinutes.toString());
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _deliveryFee, _minOrder, _prepMinutes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _toggleOpen(bool open) async {
    final auth = context.read<AuthCubit>();
    final vendor = auth.state.vendor;
    if (vendor == null) return;
    try {
      final updated = await _admin.updateVendor(vendor.id, {'is_open': open});
      auth.vendorUpdated(updated);
    } catch (error) {
      if (mounted) showSnack(context, readableError(error), error: true);
    }
  }

  Future<void> _save() async {
    final auth = context.read<AuthCubit>();
    final vendor = auth.state.vendor;
    if (vendor == null) return;
    setState(() => _saving = true);
    try {
      final updated = await _admin.updateVendor(vendor.id, {
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'delivery_fee': double.tryParse(_deliveryFee.text) ?? 0,
        'min_order_amount': double.tryParse(_minOrder.text) ?? 0,
        'avg_prep_minutes': int.tryParse(_prepMinutes.text) ?? 20,
      });
      auth.vendorUpdated(updated);
      if (mounted) showSnack(context, 'Settings saved');
    } catch (error) {
      if (mounted) showSnack(context, readableError(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendor = context.select((AuthCubit cubit) => cubit.state.vendor);
    if (vendor == null) return const LoadingView();
    return Scaffold(
      appBar: AppBar(title: const Text('Store settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: SwitchListTile(
              title: Text(vendor.isOpen
                  ? 'Open — accepting orders'
                  : 'Closed — not accepting orders'),
              value: vendor.isOpen,
              onChanged: _toggleOpen,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Store name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _deliveryFee,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Delivery fee'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _minOrder,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Min order'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _prepMinutes,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Prep (min)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save settings'),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title:
                  const Text('Sign out', style: TextStyle(color: Colors.red)),
              onTap: () => context.read<AuthCubit>().signOut(),
            ),
          ),
        ],
      ),
    );
  }
}
