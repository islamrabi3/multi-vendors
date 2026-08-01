import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/tokens.dart';
import '../../../core/models/address.dart';
import '../../../core/models/service_area.dart';
import '../../../core/repositories/address_repository.dart';
import '../../../core/repositories/service_area_repository.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/location_picker.dart';
import '../../../core/widgets/skeleton.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  final _repository = AddressRepository();
  final _areaRepository = ServiceAreaRepository();
  List<Address>? _addresses;
  List<ServiceArea> _coverage = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadCoverage();
  }

  Future<void> _load() async {
    try {
      final addresses = await _repository.fetchAddresses();
      if (mounted) setState(() => _addresses = addresses);
    } catch (_) {
      if (mounted) setState(() => _addresses = []);
    }
  }

  /// Coverage is advisory here — an empty list simply means every pin is
  /// accepted, which is also how the server behaves.
  Future<void> _loadCoverage() async {
    try {
      final areas = await _areaRepository.fetchActive();
      if (mounted) setState(() => _coverage = areas);
    } catch (_) {
      // Leave coverage empty; the order RPC still enforces the real rule.
    }
  }

  Future<void> _edit([Address? address]) async {
    // A new address starts on the map: picking the spot is the part that
    // actually matters, and it fills the street in for free.
    PickedLocation? picked;
    if (address == null) {
      picked = await showLocationPicker(
        context,
        coverage: _coverage,
        requireInsideCoverage: true,
      );
      if (picked == null || !mounted) return;
    }

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _AddressEditor(
          repository: _repository,
          address: address,
          coverage: _coverage,
          picked: picked,
        ),
      ),
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
                icon: const Icon(Icons.arrow_back, size: 22),
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
          ? const _AddressesSkeleton()
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
                                          color: AppColors.dangerInk,
                                          onPressed: () async {
                                            final deleted =
                                                await showConfirmDialog(
                                              context: context,
                                              title:
                                                  context.l10n.deleteAddress,
                                              message: context.l10n
                                                  .areYouSureYouWantToDeleteThisAddress,
                                              confirmLabel:
                                                  context.l10n.delete,
                                              cancelLabel:
                                                  context.l10n.cancel,
                                              tone: AppDialogTone.danger,
                                              icon: Icons.location_off_rounded,
                                              onConfirm: () => _repository
                                                  .deleteAddress(address.id),
                                            );
                                            if (deleted) _load();
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
  const _AddressEditor({
    required this.repository,
    this.address,
    this.coverage = const [],
    this.picked,
  });

  final AddressRepository repository;
  final Address? address;
  final List<ServiceArea> coverage;

  /// Set when the location was picked before this screen opened (new address).
  final PickedLocation? picked;

  @override
  State<_AddressEditor> createState() => _AddressEditorState();
}

class _AddressEditorState extends State<_AddressEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _label =
      TextEditingController(text: widget.address?.label ?? 'Home');
  late final _street = TextEditingController(
      text: widget.address?.street ?? widget.picked?.address);
  late final _building = TextEditingController(text: widget.address?.building);
  late final _floor = TextEditingController(text: widget.address?.floor);
  late final _apartment =
      TextEditingController(text: widget.address?.apartment);
  late final _notes = TextEditingController(text: widget.address?.notes);
  late bool _isDefault = widget.address?.isDefault ?? false;
  late LatLng _pin = widget.picked?.point ??
      (widget.address?.lat != null
          ? LatLng(widget.address!.lat!, widget.address!.lng!)
          : const LatLng(30.0444, 31.2357)); // Cairo default
  bool _saving = false;

  bool get _isCovered =>
      widget.coverage.isEmpty ||
      widget.coverage.any((a) => a.contains(_pin.latitude, _pin.longitude));

  @override
  void dispose() {
    for (final c in [_label, _street, _building, _floor, _apartment, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _changeLocation() async {
    final picked = await showLocationPicker(
      context,
      initial: _pin,
      coverage: widget.coverage,
      requireInsideCoverage: true,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _pin = picked.point;
      // Only fill an empty street: a customer who typed their own wording
      // should not have it overwritten by the geocoder.
      if (_street.text.trim().isEmpty && picked.address != null) {
        _street.text = picked.address!;
      }
    });
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
        showFailure(context, error);
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
          icon: const Icon(Icons.arrow_back, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          // Save sits at the end of the list, so the list clears Android's
          // gesture bar itself.
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
          children: [
            // The pin is chosen on a dedicated full-screen map; here it is a
            // read-only preview with one way back to it. A small inline map
            // fights the scrolling form for gestures and is hard to aim at.
            _LocationCard(
              pin: _pin,
              covered: _isCovered,
              onChange: _changeLocation,
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
                    ? const ButtonSpinner()
                    : Text(context.l10n.saveAddress),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => _sectionHeaderText(title);
}

/// A read-only map preview of the saved pin, with the single action that
/// matters: go back to the picker.
class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.pin,
    required this.covered,
    required this.onChange,
  });

  final LatLng pin;
  final bool covered;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(
            color: covered ? AppColors.border : AppColors.dangerInk),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 150,
            child: IgnorePointer(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: pin,
                  initialZoom: 15,
                  interactionOptions:
                      const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.multiVendors.app',
                  ),
                  MarkerLayer(markers: [
                    Marker(
                      point: pin,
                      width: 44,
                      height: 44,
                      child: Icon(Icons.location_on_rounded,
                          size: 36,
                          color: covered
                              ? AppColors.primary
                              : AppColors.dangerInk),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          if (!covered)
            Container(
              width: double.infinity,
              color: AppColors.dangerFill,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md, vertical: AppSpace.sm),
              child: Row(
                children: [
                  const Icon(Icons.block_rounded,
                      size: 16, color: AppColors.dangerInk),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(context.l10n.outsideServiceArea,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.dangerInk)),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(AppSpace.sm + 2),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onChange,
                icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                label: Text(context.l10n.changeLocation),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _sectionHeaderText(String title) => Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: AppColors.textMuted,
      ),
    );

/// Saved addresses while they load. Same 16/12 padding and 12px bottom margin
/// as the real cards, and the same 44px icon well.
class _AddressesSkeleton extends StatelessWidget {
  const _AddressesSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonTheme(
      child: SkeletonList(
        itemCount: 4,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg, vertical: AppSpace.md),
        separator: const SizedBox(height: AppSpace.md),
        itemBuilder: (_) => DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.xl),
            border: Border.all(color: AppColors.border),
          ),
          child: const Padding(
            padding: EdgeInsets.all(AppSpace.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton.circle(size: 44),
                SizedBox(width: AppSpace.md + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton.line(widthFactor: 0.35, height: 16),
                      SizedBox(height: AppSpace.sm),
                      Skeleton.line(widthFactor: 0.85, height: 13),
                      SizedBox(height: 6),
                      Skeleton.line(widthFactor: 0.5, height: 13),
                    ],
                  ),
                ),
                SizedBox(width: AppSpace.sm),
                Skeleton.circle(size: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
