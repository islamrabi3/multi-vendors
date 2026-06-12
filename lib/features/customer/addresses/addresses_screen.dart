import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/models/address.dart';
import '../../../core/repositories/address_repository.dart';
import '../../../core/widgets/common.dart';

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  final _repository = AddressRepository();
  List<Address>? _addresses;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final addresses = await _repository.fetchAddresses();
      if (mounted) setState(() => _addresses = addresses);
    } catch (_) {
      if (mounted) setState(() => _addresses = []);
    }
  }

  Future<void> _edit([Address? address]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) =>
              _AddressEditor(repository: _repository, address: address)),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final addresses = _addresses;
    return Scaffold(
      appBar: AppBar(title: const Text('My addresses')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(),
        child: const Icon(Icons.add),
      ),
      body: addresses == null
          ? const LoadingView()
          : addresses.isEmpty
              ? const EmptyView(
                  message: 'No addresses yet',
                  icon: Icons.location_on_outlined)
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: addresses.length,
                  itemBuilder: (context, index) {
                    final address = addresses[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        leading: Icon(address.isDefault
                            ? Icons.star
                            : Icons.location_on_outlined),
                        title: Text(address.label),
                        subtitle: Text(address.summary),
                        onTap: () => _edit(address),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await _repository.deleteAddress(address.id);
                            _load();
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _AddressEditor extends StatefulWidget {
  const _AddressEditor({required this.repository, this.address});

  final AddressRepository repository;
  final Address? address;

  @override
  State<_AddressEditor> createState() => _AddressEditorState();
}

class _AddressEditorState extends State<_AddressEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.address?.label ?? 'Home');
  late final _street = TextEditingController(text: widget.address?.street);
  late final _building = TextEditingController(text: widget.address?.building);
  late final _floor = TextEditingController(text: widget.address?.floor);
  late final _apartment = TextEditingController(text: widget.address?.apartment);
  late final _notes = TextEditingController(text: widget.address?.notes);
  late bool _isDefault = widget.address?.isDefault ?? false;
  late LatLng _pin = widget.address?.lat != null
      ? LatLng(widget.address!.lat!, widget.address!.lng!)
      : const LatLng(30.0444, 31.2357); // Cairo default
  final _mapController = MapController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_label, _street, _building, _floor, _apartment, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _useMyLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) showSnack(context, 'Location permission denied');
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      setState(() => _pin = LatLng(position.latitude, position.longitude));
      _mapController.move(_pin, 16);
    } catch (_) {
      if (mounted) showSnack(context, 'Could not get your location');
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.repository.saveAddress({
        'label': _label.text.trim(),
        'street': _street.text.trim(),
        'building': _building.text.trim(),
        'floor': _floor.text.trim(),
        'apartment': _apartment.text.trim(),
        'notes': _notes.text.trim(),
        'lat': _pin.latitude,
        'lng': _pin.longitude,
        'is_default': _isDefault,
      }, id: widget.address?.id);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, readableError(error), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.address == null ? 'Add address' : 'Edit address')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SizedBox(
              height: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _pin,
                        initialZoom: 14,
                        onTap: (_, point) => setState(() => _pin = point),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.multi_vendor',
                        ),
                        MarkerLayer(markers: [
                          Marker(
                            point: _pin,
                            width: 40,
                            height: 40,
                            child: const Icon(Icons.location_pin,
                                color: Colors.red, size: 36),
                          ),
                        ]),
                      ],
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: FloatingActionButton.small(
                        heroTag: 'my-location',
                        onPressed: _useMyLocation,
                        child: const Icon(Icons.my_location),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text('Tap the map to drop your pin',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _label,
              decoration:
                  const InputDecoration(labelText: 'Label (Home, Work…)'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _street,
              decoration: const InputDecoration(labelText: 'Street'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _building,
                    decoration:
                        const InputDecoration(labelText: 'Building'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _floor,
                    decoration: const InputDecoration(labelText: 'Floor'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _apartment,
                    decoration: const InputDecoration(labelText: 'Apt'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              decoration:
                  const InputDecoration(labelText: 'Delivery notes'),
            ),
            SwitchListTile(
              title: const Text('Default address'),
              value: _isDefault,
              onChanged: (v) => setState(() => _isDefault = v),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save address'),
            ),
          ],
        ),
      ),
    );
  }
}
