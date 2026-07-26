import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/tokens.dart';
import '../../../core/models/address.dart';
import '../../../core/repositories/address_repository.dart';
import '../../../core/widgets/common.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

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

  IconData _getIconForLabel(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('home')) {
      return Icons.home_rounded;
    } else if (lower.contains('work') ||
        lower.contains('office') ||
        lower.contains('business')) {
      return Icons.business_rounded;
    } else if (lower.contains('partner') ||
        lower.contains('love') ||
        lower.contains('friend')) {
      return Icons.favorite_rounded;
    }
    return Icons.location_on_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final addresses = _addresses;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(
          context.l10n.myAddresses,
          style: AppType.display(22, color: AppColors.ink),
        ),
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          boxShadow: AppShadows.primaryGlow,
        ),
        child: FloatingActionButton(
          onPressed: () => _edit(),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: const Icon(Icons.add, size: 28),
        ),
      ),
      body: addresses == null
          ? const LoadingView()
          : addresses.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: addresses.length,
                  itemBuilder: (context, index) {
                    final address = addresses[index];
                    final icon = _getIconForLabel(address.label);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadii.xl),
                        border: Border.all(
                          color: address.isDefault
                              ? AppColors.primary.withValues(alpha: 0.3)
                              : AppColors.border,
                          width: address.isDefault ? 1.5 : 1.0,
                        ),
                        boxShadow: AppShadows.card,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadii.xl),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _edit(address),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Icon
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: address.isDefault
                                          ? AppColors.warmFill
                                          : AppColors.canvas,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      icon,
                                      color: address.isDefault
                                          ? AppColors.primary
                                          : AppColors.textSecondary,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Text Content
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              address.label,
                                              style: AppType.heading(16,
                                                  color: AppColors.ink),
                                            ),
                                            if (address.isDefault) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.successFill,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          AppRadii.pill),
                                                ),
                                                child: Text(
                                                  context.l10n.defaultAddress,
                                                  style: const TextStyle(
                                                    color: AppColors.successInk,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          address.summary,
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 13.5,
                                            height: 1.3,
                                          ),
                                        ),
                                        if (address.notes != null &&
                                            address.notes!.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons
                                                    .chat_bubble_outline_rounded,
                                                size: 14,
                                                color: AppColors.textMuted,
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  address.notes!,
                                                  style: const TextStyle(
                                                    color: AppColors.textMuted,
                                                    fontSize: 12,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Actions
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      // Edit Button
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: AppColors.canvas,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: AppColors.borderSoft),
                                        ),
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          icon: const Icon(Icons.edit_outlined,
                                              size: 16),
                                          color: AppColors.textSecondary,
                                          onPressed: () => _edit(address),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      // Delete Button
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: AppColors.canvas,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: AppColors.borderSoft),
                                        ),
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 16),
                                          color: Colors.redAccent,
                                          onPressed: () async {
                                            final confirm =
                                                await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: Text(
                                                    context.l10n.deleteAddress),
                                                content: Text(
                                                    context.l10n.areYouSureYouWantToDeleteThisAddress),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            ctx, false),
                                                    child: Text(context.l10n.cancel),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            ctx, true),
                                                    style: TextButton.styleFrom(
                                                        foregroundColor:
                                                            Colors.red),
                                                    child: Text(context.l10n.delete),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              await _repository
                                                  .deleteAddress(address.id);
                                              _load();
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: const BoxDecoration(
                color: AppColors.warmFill,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.map_rounded,
                color: AppColors.primary,
                size: 48,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              context.l10n.whereShouldWeDeliver,
              style: AppType.heading(20, color: AppColors.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              context.l10n.addYourDeliveryAddressesToOrderDeliciousFoodAndTrackItStraightToYourDoorstep,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add_location_alt_rounded),
              label: Text(context.l10n.saveAddress),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
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
  late final _label =
      TextEditingController(text: widget.address?.label ?? 'Home');
  late final _street = TextEditingController(text: widget.address?.street);
  late final _building = TextEditingController(text: widget.address?.building);
  late final _floor = TextEditingController(text: widget.address?.floor);
  late final _apartment =
      TextEditingController(text: widget.address?.apartment);
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
        if (mounted) showSnack(context, context.l10n.locationPermissionDenied);
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      setState(() => _pin = LatLng(position.latitude, position.longitude));
      _mapController.move(_pin, 16);
    } catch (_) {
      if (mounted) showSnack(context, context.l10n.couldNotGetYourLocation);
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
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(
          widget.address == null ? context.l10n.addAddress : context.l10n.editAddress,
          style: AppType.heading(20, color: AppColors.ink),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // Map viewport container
            Container(
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.xl),
                border: Border.all(color: AppColors.border),
                boxShadow: AppShadows.card,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.xl - 1),
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
                            width: 50,
                            height: 50,
                            child: Center(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    )
                                  ],
                                ),
                                padding: const EdgeInsets.all(6),
                                child: const Icon(
                                  Icons.location_on_rounded,
                                  color: AppColors.primary,
                                  size: 26,
                                ),
                              ),
                            ),
                          ),
                        ]),
                      ],
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: FloatingActionButton.small(
                          heroTag: 'my-location',
                          onPressed: _useMyLocation,
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.primary,
                          shape: const CircleBorder(),
                          child: const Icon(Icons.my_location),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 14, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text(
                  context.l10n.tapTheMapToDropYourPin,
                  style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 24),

            _sectionHeader(context.l10n.addressLocation),
            const SizedBox(height: 10),
            TextFormField(
              controller: _street,
              decoration: InputDecoration(
                labelText: context.l10n.street,
                prefixIcon:
                    const Icon(Icons.route_outlined, color: AppColors.textFaint),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? context.l10n.required : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _label,
              decoration: InputDecoration(
                labelText: context.l10n.labelHomeWork,
                prefixIcon:
                    const Icon(Icons.tag_rounded, color: AppColors.textFaint),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? context.l10n.required : null,
            ),
            const SizedBox(height: 24),

            _sectionHeader(context.l10n.apartmentDetails),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _building,
                    decoration: InputDecoration(
                      labelText: context.l10n.building,
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _floor,
                    decoration: InputDecoration(
                      labelText: context.l10n.floor,
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _apartment,
                    decoration: InputDecoration(
                      labelText: context.l10n.apt,
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            _sectionHeader(context.l10n.deliveryInstructions),
            const SizedBox(height: 10),
            TextFormField(
              controller: _notes,
              decoration: InputDecoration(
                labelText: context.l10n.deliveryNotes,
                prefixIcon: const Icon(Icons.note_alt_outlined,
                    color: AppColors.textFaint),
              ),
            ),
            const SizedBox(height: 16),

            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: AppColors.border),
              ),
              child: SwitchListTile(
                title: Text(
                  context.l10n.defaultAddress,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                subtitle: Text(
                  context.l10n.useThisAsPrimaryDeliveryOption,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                value: _isDefault,
                activeThumbColor: Colors.white,
                activeTrackColor: AppColors.success,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: AppColors.border,
                onChanged: (v) => setState(() => _isDefault = v),
              ),
            ),
            const SizedBox(height: 28),

            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.lg),
                boxShadow: AppShadows.primaryGlow,
              ),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(context.l10n.saveAddress),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: AppColors.textMuted,
      ),
    );
  }
}
