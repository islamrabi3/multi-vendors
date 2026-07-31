import 'package:equatable/equatable.dart';

class VendorSchedule extends Equatable {
  const VendorSchedule({
    required this.id,
    required this.vendorId,
    required this.dayOfWeek,
    required this.openTime,
    required this.closeTime,
    required this.isClosed,
  });

  final String id;
  final String vendorId;
  final int dayOfWeek; // 0 = Sunday, 6 = Saturday
  final String openTime; // "09:00"
  final String closeTime; // "23:00"
  final bool isClosed;

  factory VendorSchedule.fromMap(Map<String, dynamic> map) => VendorSchedule(
        id: map['id'] as String,
        vendorId: map['vendor_id'] as String,
        dayOfWeek: ((map['day_of_week'] as num?) ?? 0).toInt(),
        openTime: (map['open_time'] as String?) ?? '09:00',
        closeTime: (map['close_time'] as String?) ?? '23:00',
        isClosed: (map['is_closed'] as bool?) ?? false,
      );

  Map<String, dynamic> toMap() => {
        'vendor_id': vendorId,
        'day_of_week': dayOfWeek,
        'open_time': openTime,
        'close_time': closeTime,
        'is_closed': isClosed,
      };

  @override
  List<Object?> get props => [id, vendorId, dayOfWeek, openTime, closeTime, isClosed];
}
