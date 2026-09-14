import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/tokens.dart';
import '../../../core/models/address.dart';
import '../../../core/models/service_area.dart';
import '../../../core/repositories/address_repository.dart';
import '../../../core/repositories/service_area_repository.dart';
import '../../../core/utils/address_format.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/location_picker.dart';
import '../../../core/widgets/skeleton.dart';

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key, this.selectedId});

  /// Pick mode: tapping a row pops the screen with that address's id, and the
  /// currently selected one is marked. Checkout is the only caller.
  ///
  /// Null (the normal "My addresses" screen) means rows open the editor.
  final String? selectedId;

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

enum _AddressAction { edit, makeDefault, delete }

class _AddressesScreenState extends State<AddressesScreen> {
  final _repository = AddressRepository();
  final _areaRepository = ServiceAreaRepository();
  List<Address>? _addresses;
  Object? _error;
  List<ServiceArea> _coverage = const [];

  bool get _picking => widget.selectedId != null;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCoverage();
  }

  Future<void> _load() async {
    try {
      final addresses = await _repository.fetchAddresses();
      if (mounted) {
        setState(() {
          _addresses = addresses;
          _error = null;
        });
      }
    } catch (error) {
      // A failed load is not "no addresses": saying so would invite the
      // customer to re-enter addresses they already have.
      if (mounted) setState(() => _error = error);
    }
  }

  /// Coverage is advisory here — an empty list simply means every pin is
  /// accepted, which is also how the server behaves.
  Future<void> _loadCoverage() async {
    try {
      final areas = await _areaRepository.fetchActive();
      if (mounted) setState(() => _coverage = areas);
    } catch (_) {}
  }

  bool _isCovered(Address address) {
    if (_coverage.isEmpty || address.lat == null || address.lng == null) {
      return true;
    }
    return _coverage.any((a) => a.contains(address.lat!, address.lng!));
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
          // The first address is the default whether or not anyone says so.
          firstAddress: (_addresses ?? const []).isEmpty,
        ),
      ),
    );
    if (changed != true) return;
    // In pick mode, adding a brand-new address finishes the pick.
    if (_picking && address == null) {
      final before = _addresses?.map((a) => a.id).toSet() ?? const {};
      await _load();
      final created = _addresses
          ?.map((a) => a.id)
          .where((id) => !before.contains(id))
          .firstOrNull;
      if (created != null && mounted) Navigator.of(context).pop(created);
      return;
    }
    _load();
  }

  Future<void> _onAction(Address address, _AddressAction action) async {
    final l10n = context.l10n;
    switch (action) {
      case _AddressAction.edit:
        await _edit(address);
      case _AddressAction.makeDefault:
        try {
          await _repository.saveAddress({'is_default': true}, id: address.id);
          if (mounted) showSnack(context, l10n.defaultAddressUpdated);
          await _load();
        } catch (error) {
          if (mounted) showFailure(context, error);
        }
      case _AddressAction.delete:
        final deleted = await showConfirmDialog(
          context: context,
          title: l10n.deleteAddress,
          message: l10n.areYouSureYouWantToDeleteThisAddress,
          confirmLabel: l10n.delete,
          cancelLabel: l10n.cancel,
          tone: AppDialogTone.danger,
          icon: Icons.location_off_rounded,
          onConfirm: () => _repository.deleteAddress(address.id),
        );
        if (deleted) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final addresses = _addresses;

    Widget body;
    if (addresses == null && _error != null) {
      body = FailureView(error: _error!, onRetry: _load);
    } else if (addresses == null) {
      body = const _AddressesSkeleton();
    } else if (addresses.isEmpty) {
      body = _EmptyAddresses(onAdd: () => _edit());
    } else {
      body = RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: addresses.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final address = addresses[index];
            return _AddressTile(
              address: address,
              covered: _isCovered(address),
              selected: address.id == widget.selectedId,
              picking: _picking,
              onTap: _picking
                  ? () => Navigator.of(context).pop(address.id)
                  : () => _edit(address),
              onAction: (action) => _onAction(address, action),
            );
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(_picking ? l10n.chooseDeliveryAddress : l10n.myAddresses),
      ),
      body: body,
      // One clear way to add, pinned where the thumb is — a floating "+" gave
      // no hint of what it would add.
      bottomNavigationBar: (addresses?.isEmpty ?? true)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: () => _edit(),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: const Icon(Icons.add_location_alt_rounded),
                  label: Text(l10n.addNewAddress),
                ),
              ),
            ),
    );
  }
}

class _AddressTile extends StatelessWidget {
  const _AddressTile({
    required this.address,
    required this.covered,
    required this.selected,
    required this.picking,
    required this.onTap,
    required this.onAction,
  });

  final Address address;
  final bool covered;
  final bool selected;
  final bool picking;
  final VoidCallback onTap;
  final ValueChanged<_AddressAction> onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final highlighted = selected || (!picking && address.isDefault);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 4, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: highlighted ? AppColors.warmFill : AppColors.canvas,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  addressIcon(address.label),
                  color: highlighted
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          addressLabelText(context, address.label),
                          style: AppType.heading(15.5),
                        ),
                        if (address.isDefault)
                          SoftBadge(
                            label: l10n.defaultAddress,
                            fill: AppColors.successFill,
                            ink: AppColors.successInk,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      addressSummaryText(context, address),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                    if (address.notes?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.sticky_note_2_outlined,
                            size: 14,
                            color: AppColors.textFaint,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              address.notes!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (!covered) ...[
                      const SizedBox(height: 8),
                      SoftBadge(
                        label: l10n.outsideServiceArea,
                        fill: AppColors.dangerFill,
                        ink: AppColors.dangerInk,
                        icon: Icons.block_rounded,
                      ),
                    ] else if (address.lat == null) ...[
                      const SizedBox(height: 8),
                      SoftBadge(
                        label: l10n.addressNeedsPin,
                        fill: AppColors.amberFill,
                        ink: AppColors.amberInk,
                        icon: Icons.push_pin_outlined,
                      ),
                    ],
                  ],
                ),
              ),
              if (picking)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10, top: 10),
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: selected ? AppColors.primary : AppColors.textFaint,
                  ),
                )
              else
                PopupMenuButton<_AddressAction>(
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: AppColors.textMuted,
                  ),
                  onSelected: onAction,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _AddressAction.edit,
                      child: _menuRow(Icons.edit_outlined, l10n.edit),
                    ),
                    if (!address.isDefault)
                      PopupMenuItem(
                        value: _AddressAction.makeDefault,
                        child: _menuRow(
                          Icons.check_circle_outline_rounded,
                          l10n.setAsDefault,
                        ),
                      ),
                    PopupMenuItem(
                      value: _AddressAction.delete,
                      child: _menuRow(
                        Icons.delete_outline_rounded,
                        l10n.delete,
                        color: AppColors.dangerInk,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuRow(IconData icon, String label, {Color? color}) => Row(
    children: [
      Icon(icon, size: 19, color: color ?? AppColors.textSecondary),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(color: color ?? AppColors.ink)),
    ],
  );
}

class _EmptyAddresses extends StatelessWidget {
  const _EmptyAddresses({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppColors.warmFill,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.map_rounded,
                color: AppColors.primary,
                size: 46,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              l10n.whereShouldWeDeliver,
              style: AppType.heading(20),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.addYourDeliveryAddressesToOrderDeliciousFoodAndTrackItStraightToYourDoorstep,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              style: FilledButton.styleFrom(minimumSize: const Size(220, 52)),
              icon: const Icon(Icons.add_location_alt_rounded),
              label: Text(l10n.addNewAddress),
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
    this.firstAddress = false,
  });

  final AddressRepository repository;
  final Address? address;
  final List<ServiceArea> coverage;

  /// Set when the location was picked before this screen opened (new address).
  final PickedLocation? picked;
  final bool firstAddress;

  @override
  State<_AddressEditor> createState() => _AddressEditorState();
}

class _AddressEditorState extends State<_AddressEditor> {
  final _formKey = GlobalKey<FormState>();
  late AddressKind _kind = addressKindOf(widget.address?.label ?? 'home');
  late final _customLabel = TextEditingController(
    text:
        _kind == AddressKind.other &&
            (widget.address?.label.trim().toLowerCase() ?? 'other') != 'other'
        ? widget.address?.label
        : null,
  );
  late final _street = TextEditingController(
    text: widget.address?.street ?? widget.picked?.address,
  );
  late final _building = TextEditingController(text: widget.address?.building);
  late final _floor = TextEditingController(text: widget.address?.floor);
  late final _apartment = TextEditingController(
    text: widget.address?.apartment,
  );
  late final _notes = TextEditingController(text: widget.address?.notes);
  late bool _isDefault = widget.address?.isDefault ?? widget.firstAddress;
  late LatLng _pin =
      widget.picked?.point ??
      (widget.address?.lat != null
          ? LatLng(widget.address!.lat!, widget.address!.lng!)
          : const LatLng(30.0444, 31.2357)); // Cairo default
  bool _saving = false;

  bool get _isCovered =>
      widget.coverage.isEmpty ||
      widget.coverage.any((a) => a.contains(_pin.latitude, _pin.longitude));

  @override
  void dispose() {
    for (final c in [
      _customLabel,
      _street,
      _building,
      _floor,
      _apartment,
      _notes,
    ]) {
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

  String get _labelValue => switch (_kind) {
    AddressKind.home => 'Home',
    AddressKind.work => 'Work',
    AddressKind.other =>
      _customLabel.text.trim().isEmpty ? 'Other' : _customLabel.text.trim(),
  };

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.repository.saveAddress({
        'label': _labelValue,
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
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(
          widget.address == null ? l10n.addAddress : l10n.editAddress,
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: _saving ? const ButtonSpinner() : Text(l10n.saveAddress),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // The pin is chosen on a dedicated full-screen map; here it is a
            // read-only preview with one way back to it.
            _LocationCard(
              pin: _pin,
              covered: _isCovered,
              onChange: _changeLocation,
            ),
            const SizedBox(height: 22),

            _sectionHeaderText(l10n.saveAddressAs),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final kind in AddressKind.values) ...[
                  if (kind != AddressKind.home) const SizedBox(width: 8),
                  Expanded(
                    child: _KindChip(
                      icon: addressIcon(
                        kind == AddressKind.other ? '' : kind.name,
                      ),
                      label: switch (kind) {
                        AddressKind.home => l10n.addressHome,
                        AddressKind.work => l10n.work,
                        AddressKind.other => l10n.other,
                      },
                      selected: _kind == kind,
                      onTap: () => setState(() => _kind = kind),
                    ),
                  ),
                ],
              ],
            ),
            if (_kind == AddressKind.other) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _customLabel,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.customAddressLabel,
                  prefixIcon: const Icon(
                    Icons.label_outline_rounded,
                    color: AppColors.textFaint,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 22),

            _sectionHeaderText(l10n.addressLocation),
            const SizedBox(height: 10),
            TextFormField(
              controller: _street,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.street,
                prefixIcon: const Icon(
                  Icons.route_outlined,
                  color: AppColors.textFaint,
                ),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? l10n.required : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _building,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: l10n.building),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _floor,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: l10n.floor),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _apartment,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: l10n.apt),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),

            _sectionHeaderText(l10n.deliveryInstructions),
            const SizedBox(height: 10),
            TextFormField(
              controller: _notes,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: l10n.deliveryNotes,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),

            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: AppColors.border),
              ),
              child: SwitchListTile(
                title: Text(
                  l10n.defaultAddress,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                subtitle: Text(
                  l10n.useThisAsPrimaryDeliveryOption,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.warmFill : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.primaryDark : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
          color: covered ? AppColors.border : AppColors.dangerInk,
        ),
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
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.multiVendors.app',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: pin,
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.location_on_rounded,
                          size: 36,
                          color: covered
                              ? AppColors.primary
                              : AppColors.dangerInk,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (!covered)
            Container(
              width: double.infinity,
              color: AppColors.dangerFill,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md,
                vertical: AppSpace.sm,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.block_rounded,
                    size: 16,
                    color: AppColors.dangerInk,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.l10n.outsideServiceArea,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.dangerInk,
                      ),
                    ),
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

// Not upper-cased: that does nothing in Arabic and shouts in English.
Widget _sectionHeaderText(String title) => Text(
  title,
  style: const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
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
          horizontal: AppSpace.lg,
          vertical: AppSpace.md,
        ),
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
