import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/tokens.dart';
import '../../../core/models/service_area.dart';
import '../../../core/repositories/service_area_repository.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/location_picker.dart';
import '../../../core/widgets/skeleton.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// Where the platform delivers.
///
/// Each area is a centre plus a radius, and both stay editable for the life of
/// the area — widening coverage is a slider, not a migration. With no active
/// area the platform is ungeofenced and accepts orders everywhere, which is
/// stated on screen so an empty list is never mistaken for "nobody can order".
class AdminServiceAreasScreen extends StatefulWidget {
  const AdminServiceAreasScreen({super.key});

  @override
  State<AdminServiceAreasScreen> createState() =>
      _AdminServiceAreasScreenState();
}

class _AdminServiceAreasScreenState extends State<AdminServiceAreasScreen> {
  final _repo = ServiceAreaRepository();
  late Stream<List<ServiceArea>> _stream = _repo.serviceAreasStream();
  String? _busyId;

  void _reload() => setState(() => _stream = _repo.serviceAreasStream());

  Future<void> _edit([ServiceArea? area]) async {
    LatLng? centre = area == null ? null : LatLng(area.lat, area.lng);
    if (centre == null) {
      final picked = await showLocationPicker(context,
          title: context.l10n.addServiceArea);
      if (picked == null || !mounted) return;
      centre = picked.point;
    }

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ServiceAreaEditor(
          repository: _repo,
          area: area,
          centre: centre!,
        ),
      ),
    );
  }

  Future<void> _toggle(ServiceArea area) async {
    setState(() => _busyId = area.id);
    try {
      await _repo.setActive(area.id, !area.isActive);
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(ServiceArea area) async {
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: area.name,
      message: context.l10n.deleteServiceAreaConfirm,
      confirmText: context.l10n.delete,
      isDestructive: true,
    );
    if (confirmed != true) return;
    try {
      await _repo.delete(area.id);
      if (!mounted) return;
      showSnack(context, context.l10n.serviceAreaDeleted);
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(context.l10n.serviceAreas)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: Text(context.l10n.addServiceArea),
      ),
      body: SafeArea(
        top: false,
        child: StreamBuilder<List<ServiceArea>>(
          stream: _stream,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _AreasSkeleton();
            }
            if (snap.hasError) {
              return FailureView(error: snap.error!, onRetry: _reload);
            }
            final areas = snap.data ?? const <ServiceArea>[];
            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async => _reload(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                    AppSpace.gutter,
                    AppSpace.md,
                    AppSpace.gutter,
                    96 + MediaQuery.paddingOf(context).bottom),
                children: [
                  if (!areas.any((a) => a.isActive)) const _CoverageNotice(),
                  for (final area in areas) ...[
                    _AreaCard(
                      area: area,
                      busy: _busyId == area.id,
                      onEdit: () => _edit(area),
                      onToggle: () => _toggle(area),
                      onDelete: () => _delete(area),
                    ),
                    const SizedBox(height: AppSpace.sm),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Shown while nothing is limiting coverage, so the state is never ambiguous.
class _CoverageNotice extends StatelessWidget {
  const _CoverageNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.amberFill,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.amberInk.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.public, size: 18, color: AppColors.amberInk),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.noServiceAreasYet,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.amberInk)),
                const SizedBox(height: 2),
                Text(context.l10n.coverageEverywhereNote,
                    style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.amberInk)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AreaCard extends StatelessWidget {
  const _AreaCard({
    required this.area,
    required this.busy,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final ServiceArea area;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final languageCode = Localizations.localeOf(context).languageCode;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // The circle at a glance beats any list of coordinates.
          SizedBox(
            height: 130,
            child: Opacity(
              opacity: area.isActive ? 1 : 0.45,
              child: IgnorePointer(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(area.lat, area.lng),
                    initialZoom: _zoomForRadius(area.radiusKm),
                    interactionOptions:
                        const InteractionOptions(flags: InteractiveFlag.none),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.multiVendors.app',
                    ),
                    CircleLayer(circles: [
                      CircleMarker(
                        point: LatLng(area.lat, area.lng),
                        radius: area.radiusKm * 1000,
                        useRadiusInMeter: true,
                        color: AppColors.primary.withValues(alpha: 0.14),
                        borderColor: AppColors.primary,
                        borderStrokeWidth: 1.5,
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(area.displayName(languageCode),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.sm + 2, vertical: 4),
                      decoration: BoxDecoration(
                        color: area.isActive
                            ? AppColors.successFill
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(AppRadii.xs),
                      ),
                      child: Text(
                          area.isActive ? l10n.active : l10n.suspended,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: area.isActive
                                  ? AppColors.successInk
                                  : AppColors.textMuted)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${l10n.deliveryRadius}: '
                  '${area.radiusKm.toStringAsFixed(area.radiusKm % 1 == 0 ? 0 : 1)} '
                  '${l10n.kmUnit}',
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: AppSpace.md),
                if (busy)
                  const SizedBox(
                    height: 40,
                    child: Center(
                        child:
                            ButtonSpinner(size: 18, color: AppColors.primary)),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: Text(l10n.edit),
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      IconButton(
                        onPressed: onToggle,
                        tooltip: area.isActive ? l10n.suspended : l10n.active,
                        icon: Icon(area.isActive
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline),
                      ),
                      IconButton(
                        onPressed: onDelete,
                        tooltip: l10n.delete,
                        color: AppColors.dangerInk,
                        icon: const Icon(Icons.delete_outline),
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

/// Rough zoom that keeps the whole circle in a 130px-tall preview.
double _zoomForRadius(double radiusKm) {
  if (radiusKm <= 2) return 13;
  if (radiusKm <= 5) return 12;
  if (radiusKm <= 10) return 11;
  if (radiusKm <= 25) return 10;
  if (radiusKm <= 60) return 9;
  return 8;
}

class _ServiceAreaEditor extends StatefulWidget {
  const _ServiceAreaEditor({
    required this.repository,
    required this.centre,
    this.area,
  });

  final ServiceAreaRepository repository;
  final LatLng centre;
  final ServiceArea? area;

  @override
  State<_ServiceAreaEditor> createState() => _ServiceAreaEditorState();
}

class _ServiceAreaEditorState extends State<_ServiceAreaEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.area?.name);
  late final _nameAr = TextEditingController(text: widget.area?.nameAr);
  late LatLng _centre = widget.centre;
  late double _radiusKm = widget.area?.radiusKm ?? 5;
  late bool _isActive = widget.area?.isActive ?? true;
  final _mapController = MapController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _nameAr.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _moveCentre() async {
    final picked =
        await showLocationPicker(context, initial: _centre);
    if (picked == null || !mounted) return;
    setState(() => _centre = picked.point);
    _mapController.move(_centre, _zoomForRadius(_radiusKm));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.repository.save(
        id: widget.area?.id,
        name: _name.text.trim(),
        nameAr: _nameAr.text.trim(),
        lat: _centre.latitude,
        lng: _centre.longitude,
        radiusKm: _radiusKm,
        isActive: _isActive,
      );
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
        title: Text(widget.area == null
            ? l10n.addServiceArea
            : l10n.editServiceArea),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.md,
              AppSpace.gutter, AppSpace.md + MediaQuery.paddingOf(context).bottom),
          children: [
            // Live preview: the slider below redraws this circle as it moves,
            // so the radius is judged against the actual city, not a number.
            Container(
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.xl),
                border: Border.all(color: AppColors.border),
                boxShadow: AppShadows.card,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _centre,
                      initialZoom: _zoomForRadius(_radiusKm),
                      interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.pinchZoom |
                              InteractiveFlag.drag),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.multiVendors.app',
                      ),
                      CircleLayer(circles: [
                        CircleMarker(
                          point: _centre,
                          radius: _radiusKm * 1000,
                          useRadiusInMeter: true,
                          color: AppColors.primary.withValues(alpha: 0.14),
                          borderColor: AppColors.primary,
                          borderStrokeWidth: 2,
                        ),
                      ]),
                      MarkerLayer(markers: [
                        Marker(
                          point: _centre,
                          width: 36,
                          height: 36,
                          child: const Icon(Icons.my_location,
                              size: 20, color: AppColors.primary),
                        ),
                      ]),
                    ],
                  ),
                  PositionedDirectional(
                    end: AppSpace.sm,
                    bottom: AppSpace.sm,
                    child: FloatingActionButton.small(
                      heroTag: 'area-centre',
                      onPressed: _moveCentre,
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      shape: const CircleBorder(),
                      child: const Icon(Icons.edit_location_alt_outlined),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.lg),

            Row(
              children: [
                Expanded(
                  child: Text(l10n.deliveryRadius,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
                ),
                Text(
                  '${_radiusKm.toStringAsFixed(_radiusKm % 1 == 0 ? 0 : 1)} '
                  '${l10n.kmUnit}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary),
                ),
              ],
            ),
            Slider(
              value: _radiusKm,
              min: 0.5,
              max: 100,
              divisions: 199,
              onChanged: (v) => setState(() => _radiusKm = v),
            ),
            const SizedBox(height: AppSpace.md),

            TextFormField(
              controller: _name,
              decoration: InputDecoration(labelText: l10n.areaName),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? l10n.required : null,
            ),
            const SizedBox(height: AppSpace.md),
            TextFormField(
              controller: _nameAr,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(labelText: l10n.areaNameArabic),
            ),
            const SizedBox(height: AppSpace.md),

            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: AppColors.border),
              ),
              child: SwitchListTile(
                title: Text(l10n.areaActive,
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink)),
                subtitle: Text(l10n.areaActiveDesc,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted)),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
            ),
            const SizedBox(height: AppSpace.xl),

            FilledButton(
              style:
                  FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _saving ? null : _save,
              child: _saving ? const ButtonSpinner() : Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }
}

class _AreasSkeleton extends StatelessWidget {
  const _AreasSkeleton();

  @override
  Widget build(BuildContext context) => SkeletonTheme(
        child: SkeletonList(
          itemCount: 3,
          padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.xxl),
          separator: const SizedBox(height: AppSpace.sm),
          itemBuilder: (_) => const Skeleton(height: 220, radius: AppRadii.lg),
        ),
      );
}
