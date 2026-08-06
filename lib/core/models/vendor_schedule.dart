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

  // Tolerant of a partial row: joined into a store query the schedule is read
  // for its hours, and selecting the keys back would be dead weight on every
  // card in the list.
  factory VendorSchedule.fromMap(Map<String, dynamic> map) => VendorSchedule(
        id: (map['id'] as String?) ?? '',
        vendorId: (map['vendor_id'] as String?) ?? '',
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

  /// Minutes past midnight, or null when the stored text is not `HH:MM`.
  static int? _minutes(String value) {
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  /// Whether [at] falls inside this day's window.
  ///
  /// A window whose close is earlier than its open crosses midnight — an
  /// 18:00–02:00 shift is one continuous opening, not a store that is shut for
  /// sixteen hours of it. Equal times mean "open all day", which is how a
  /// 24-hour store is expressed. Mirrors `public.time_within_window`.
  bool containsTime(DateTime at) {
    if (isClosed) return false;
    final open = _minutes(openTime);
    final close = _minutes(closeTime);
    // Unparseable hours must not silently shut a store that is trading.
    if (open == null || close == null) return true;
    if (open == close) return true;
    final now = at.hour * 60 + at.minute;
    return close > open ? now >= open && now < close : now >= open || now < close;
  }

  @override
  List<Object?> get props => [id, vendorId, dayOfWeek, openTime, closeTime, isClosed];
}

/// Postgres `extract(dow)` and this app both count Sunday as 0; Dart counts
/// Monday as 1 and Sunday as 7.
int dayOfWeekIndex(DateTime at) => at.weekday % 7;
