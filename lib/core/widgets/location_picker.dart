import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../app/tokens.dart';
import '../models/service_area.dart';
import '../services/place_search_service.dart';
import 'common.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// Cairo — the map has to open somewhere before we know better.
const _fallbackCenter = LatLng(30.0444, 31.2357);

class PickedLocation {
  const PickedLocation({required this.point, this.address});

  final LatLng point;

  /// Reverse-geocoded street address, when Places answered.
  final String? address;
}

/// Full-screen "drop a pin" picker.
///
/// The pin is fixed to the centre of the viewport and the map moves under it —
/// the pattern every maps app uses, because it works one-handed and there is
/// nothing small to hit. Search, my-location and coverage circles are all
/// optional layers on top of that.
Future<PickedLocation?> showLocationPicker(
  BuildContext context, {
  LatLng? initial,
  String? title,
  List<ServiceArea> coverage = const [],
  bool requireInsideCoverage = false,
}) {
  return Navigator.of(context).push<PickedLocation>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _LocationPickerScreen(
        initial: initial,
        title: title,
        coverage: coverage,
        requireInsideCoverage: requireInsideCoverage,
      ),
    ),
  );
}

class _LocationPickerScreen extends StatefulWidget {
  const _LocationPickerScreen({
    this.initial,
    this.title,
    required this.coverage,
    required this.requireInsideCoverage,
  });

  final LatLng? initial;
  final String? title;
  final List<ServiceArea> coverage;
  final bool requireInsideCoverage;

  @override
  State<_LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<_LocationPickerScreen> {
  final _mapController = MapController();
  final _searchController = TextEditingController();
  final _search = PlaceSearchService();

  late LatLng _center = widget.initial ?? _fallbackCenter;
  String? _address;
  bool _resolvingAddress = false;
  List<PlaceSuggestion> _suggestions = const [];
  Timer? _geocodeDebounce;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    // No pin yet means the user is adding their first address; opening on
    // wherever they are beats opening on a default city.
    if (widget.initial == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _useMyLocation());
    } else {
      _resolveAddress();
    }
  }

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  bool get _isCovered =>
      widget.coverage.isEmpty ||
      widget.coverage.any((a) => a.contains(_center.latitude, _center.longitude));

  /// Reverse geocoding is billed per call, so it waits for the map to settle
  /// rather than firing on every frame of a pan.
  void _resolveAddress() {
    _geocodeDebounce?.cancel();
    if (!_search.isAvailable) return;
    setState(() => _resolvingAddress = true);
    _geocodeDebounce = Timer(const Duration(milliseconds: 600), () async {
      final point = _center;
      final address = await _search.reverseGeocode(
        point.latitude,
        point.longitude,
        languageCode: Localizations.localeOf(context).languageCode,
      );
      if (!mounted) return;
      setState(() {
        _resolvingAddress = false;
        // A slower earlier lookup must not overwrite a newer pin.
        if (point == _center) _address = address;
      });
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _suggestions = const []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final results = await _search.autocomplete(
        value,
        languageCode: Localizations.localeOf(context).languageCode,
        nearLat: _center.latitude,
        nearLng: _center.longitude,
      );
      if (mounted) setState(() => _suggestions = results);
    });
  }

  Future<void> _pickSuggestion(PlaceSuggestion suggestion) async {
    FocusScope.of(context).unfocus();
    final location = await _search.resolve(
      suggestion,
      languageCode: Localizations.localeOf(context).languageCode,
    );
    if (!mounted || location == null) return;
    setState(() {
      _suggestions = const [];
      _searchController.clear();
      _center = LatLng(location.lat, location.lng);
      _address = location.address;
    });
    _mapController.move(_center, 16);
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
      if (!mounted) return;
      setState(() => _center = LatLng(position.latitude, position.longitude));
      _mapController.move(_center, 16);
      _resolveAddress();
    } catch (_) {
      if (mounted) showSnack(context, context.l10n.couldNotGetYourLocation);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final blocked = widget.requireInsideCoverage && !_isCovered;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(widget.title ?? l10n.pickLocationOnMap)),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15,
              onPositionChanged: (camera, hasGesture) {
                if (!hasGesture) return;
                setState(() => _center = camera.center);
                _resolveAddress();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.multiVendors.app',
              ),
              if (widget.coverage.isNotEmpty)
                CircleLayer(
                  circles: [
                    for (final area in widget.coverage)
                      CircleMarker(
                        point: LatLng(area.lat, area.lng),
                        radius: area.radiusKm * 1000,
                        useRadiusInMeter: true,
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderColor: AppColors.primary.withValues(alpha: 0.55),
                        borderStrokeWidth: 1.5,
                      ),
                  ],
                ),
            ],
          ),

          // The pin belongs to the viewport, not the map, so it never drifts
          // out from under the finger while panning.
          IgnorePointer(
            child: Center(
              child: Padding(
                // Lifts the point of the pin onto the map centre.
                padding: const EdgeInsets.only(bottom: 34),
                child: Icon(Icons.location_on_rounded,
                    size: 44,
                    color: blocked ? AppColors.dangerInk : AppColors.primary),
              ),
            ),
          ),

          if (_search.isAvailable)
            PositionedDirectional(
              top: AppSpace.md,
              start: AppSpace.md,
              end: AppSpace.md,
              child: _SearchField(
                controller: _searchController,
                suggestions: _suggestions,
                onChanged: _onSearchChanged,
                onPick: _pickSuggestion,
              ),
            ),

          PositionedDirectional(
            end: AppSpace.md,
            bottom: 150,
            child: FloatingActionButton.small(
              heroTag: 'picker-my-location',
              onPressed: _useMyLocation,
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              shape: const CircleBorder(),
              child: const Icon(Icons.my_location),
            ),
          ),

          Align(
            alignment: Alignment.bottomCenter,
            child: _ConfirmBar(
              address: _address,
              resolving: _resolvingAddress,
              blocked: blocked,
              onConfirm: blocked
                  ? null
                  : () => Navigator.pop(
                      context, PickedLocation(point: _center, address: _address)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.suggestions,
    required this.onChanged,
    required this.onPick,
  });

  final TextEditingController controller;
  final List<PlaceSuggestion> suggestions;
  final ValueChanged<String> onChanged;
  final ValueChanged<PlaceSuggestion> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: context.l10n.searchForAPlace,
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.lg),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
          ),
        ),
        if (suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              boxShadow: AppShadows.card,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: suggestions.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: AppColors.borderSoft),
              itemBuilder: (context, i) => ListTile(
                dense: true,
                leading: const Icon(Icons.place_outlined,
                    size: 20, color: AppColors.textMuted),
                title: Text(suggestions[i].primary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: suggestions[i].secondary.isEmpty
                    ? null
                    : Text(suggestions[i].secondary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                onTap: () => onPick(suggestions[i]),
              ),
            ),
          ),
      ],
    );
  }
}

class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({
    required this.address,
    required this.resolving,
    required this.blocked,
    required this.onConfirm,
  });

  final String? address;
  final bool resolving;
  final bool blocked;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.md, AppSpace.gutter,
          AppSpace.md + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
        boxShadow: [
          BoxShadow(color: Color(0x1A1E1519), blurRadius: 24, offset: Offset(0, -6)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(blocked ? Icons.block_rounded : Icons.place_rounded,
                  size: 18,
                  color: blocked ? AppColors.dangerInk : AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  blocked
                      ? l10n.outsideServiceArea
                      : resolving
                          ? l10n.locatingAddress
                          : (address ?? l10n.dragTheMapToPlaceThePin),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: blocked ? AppColors.dangerInk : AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          FilledButton(
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: onConfirm,
            child: Text(l10n.confirmLocation),
          ),
        ],
      ),
    );
  }
}
