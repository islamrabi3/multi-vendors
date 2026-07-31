import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// A circle the platform delivers inside: a centre and a radius in kilometres.
///
/// The admin can move the centre or change the radius at any time — it is a
/// plain row, and coverage is evaluated per order rather than baked into
/// anything.
class ServiceArea extends Equatable {
  const ServiceArea({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusKm,
    this.nameAr,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String? nameAr;
  final double lat;
  final double lng;
  final double radiusKm;
  final bool isActive;

  String displayName(String languageCode) {
    final ar = nameAr?.trim();
    if (languageCode == 'ar' && ar != null && ar.isNotEmpty) return ar;
    return name;
  }

  factory ServiceArea.fromMap(Map<String, dynamic> map) => ServiceArea(
        id: map['id'] as String,
        name: (map['name'] as String?) ?? '',
        nameAr: map['name_ar'] as String?,
        lat: (map['lat'] as num).toDouble(),
        lng: (map['lng'] as num).toDouble(),
        radiusKm: (map['radius_km'] as num).toDouble(),
        isActive: (map['is_active'] as bool?) ?? true,
      );

  /// Mirrors `public.is_within_service_area` so the picker can answer
  /// instantly while the pin is being dragged. The server still decides at
  /// order time — this is feedback, not the control.
  bool contains(double pointLat, double pointLng) =>
      distanceKm(lat, lng, pointLat, pointLng) <= radiusKm;

  @override
  List<Object?> get props => [id, name, nameAr, lat, lng, radiusKm, isActive];
}

/// Great-circle distance in kilometres — the same haversine the database uses.
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0;
  double toRad(double deg) => deg * math.pi / 180;
  final dLat = toRad(lat2 - lat1);
  final dLng = toRad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(toRad(lat1)) *
          math.cos(toRad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return earthRadiusKm * 2 * math.asin(math.sqrt(a.toDouble()));
}
