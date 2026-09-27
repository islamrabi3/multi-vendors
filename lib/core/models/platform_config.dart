import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// A currency the platform can run in. The platform uses one at a time; the
/// admin keeps the list and picks which. Amounts are never converted — the
/// currency only says what the numbers already stored mean.
class AppCurrency extends Equatable {
  const AppCurrency({
    required this.code,
    required this.name,
    this.nameAr,
    required this.symbol,
    this.symbolAr,
    this.decimals = 2,
  });

  /// ISO 4217, three capital letters: `EGP`, `SAR`.
  final String code;
  final String name;
  final String? nameAr;

  /// Written before the amount.
  final String symbol;

  /// Used on the Arabic UI when set; otherwise [symbol].
  final String? symbolAr;

  /// How many fraction digits an amount shows (0–3).
  final int decimals;

  static const egp = AppCurrency(
    code: 'EGP',
    name: 'Egyptian Pound',
    nameAr: 'جنيه مصري',
    symbol: 'EGP',
  );

  String symbolFor(String languageCode) {
    final ar = symbolAr?.trim();
    if (languageCode == 'ar' && ar != null && ar.isNotEmpty) return ar;
    return symbol.trim().isEmpty ? code : symbol.trim();
  }

  String nameFor(String languageCode) {
    final ar = nameAr?.trim();
    if (languageCode == 'ar' && ar != null && ar.isNotEmpty) return ar;
    return name;
  }

  factory AppCurrency.fromMap(Map<String, dynamic> map) => AppCurrency(
    code: map['code'] as String,
    name: (map['name'] as String?) ?? map['code'] as String,
    nameAr: map['name_ar'] as String?,
    symbol: (map['symbol'] as String?) ?? map['code'] as String,
    symbolAr: map['symbol_ar'] as String?,
    decimals: ((map['decimals'] as num?) ?? 2).toInt(),
  );

  @override
  List<Object?> get props => [code, name, nameAr, symbol, symbolAr, decimals];
}

/// How delivery is priced. Mirrors `public.compute_delivery_fee`, which is
/// what actually charges it — this copy only lets the app show the same
/// number before the order exists.
class DeliveryFeeRule extends Equatable {
  const DeliveryFeeRule({
    this.mode = storeMode,
    this.baseFee = 0,
    this.baseKm = 10,
    this.perKmFee = 0,
  });

  static const storeMode = 'store';
  static const distanceMode = 'distance';

  /// `store`: each store's own flat fee. `distance`: [baseFee] for the first
  /// [baseKm], plus [perKmFee] for every started kilometre beyond.
  final String mode;
  final double baseFee;
  final double baseKm;
  final double perKmFee;

  bool get byDistance => mode == distanceMode;

  /// The fee for a delivery from a store charging [storeFee] on its own, over
  /// [km] (straight line). A null [km] — either end has no pin — charges the
  /// base fee, as the server does.
  double feeFor({required double storeFee, double? km}) {
    if (!byDistance) return _round(storeFee);
    if (km == null) return _round(baseFee);
    final extra = math.max((km - baseKm).ceil(), 0);
    return _round(baseFee + extra * perKmFee);
  }

  /// The lowest fee a customer can be charged: what a store card can promise
  /// before anyone has said where the order is going.
  double startingFee(double storeFee) => byDistance ? baseFee : storeFee;

  static double _round(double v) => (v * 100).roundToDouble() / 100;

  factory DeliveryFeeRule.fromMap(Map<String, dynamic> map) => DeliveryFeeRule(
    mode: (map['delivery_fee_mode'] as String?) ?? storeMode,
    baseFee: ((map['delivery_base_fee'] as num?) ?? 0).toDouble(),
    baseKm: ((map['delivery_base_km'] as num?) ?? 10).toDouble(),
    perKmFee: ((map['delivery_per_km_fee'] as num?) ?? 0).toDouble(),
  );

  @override
  List<Object?> get props => [mode, baseFee, baseKm, perKmFee];
}

/// Straight-line distance in kilometres, the same haversine the server's
/// `distance_km` uses, so the fee shown is the fee charged.
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 6371 * 2 * math.asin(math.sqrt(a));
}

/// Platform-wide settings every screen may need: the currency amounts are in,
/// and how delivery is priced.
class PlatformConfig extends Equatable {
  const PlatformConfig({
    this.currency = AppCurrency.egp,
    this.delivery = const DeliveryFeeRule(),
  });

  final AppCurrency currency;
  final DeliveryFeeRule delivery;

  PlatformConfig copyWith({AppCurrency? currency, DeliveryFeeRule? delivery}) =>
      PlatformConfig(
        currency: currency ?? this.currency,
        delivery: delivery ?? this.delivery,
      );

  @override
  List<Object?> get props => [currency, delivery];
}
