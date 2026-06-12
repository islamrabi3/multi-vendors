import 'package:equatable/equatable.dart';

class Address extends Equatable {
  const Address({
    required this.id,
    required this.label,
    required this.street,
    this.building,
    this.floor,
    this.apartment,
    this.notes,
    this.lat,
    this.lng,
    this.isDefault = false,
  });

  final String id;
  final String label;
  final String street;
  final String? building;
  final String? floor;
  final String? apartment;
  final String? notes;
  final double? lat;
  final double? lng;
  final bool isDefault;

  String get summary => [
        street,
        if (building?.isNotEmpty ?? false) 'Bldg $building',
        if (floor?.isNotEmpty ?? false) 'Floor $floor',
        if (apartment?.isNotEmpty ?? false) 'Apt $apartment',
      ].join(', ');

  factory Address.fromMap(Map<String, dynamic> map) => Address(
        id: map['id'] as String,
        label: (map['label'] as String?) ?? 'Home',
        street: (map['street'] as String?) ?? '',
        building: map['building'] as String?,
        floor: map['floor'] as String?,
        apartment: map['apartment'] as String?,
        notes: map['notes'] as String?,
        lat: (map['lat'] as num?)?.toDouble(),
        lng: (map['lng'] as num?)?.toDouble(),
        isDefault: (map['is_default'] as bool?) ?? false,
      );

  @override
  List<Object?> get props =>
      [id, label, street, building, floor, apartment, notes, lat, lng, isDefault];
}
