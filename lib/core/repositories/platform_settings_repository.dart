import '../supabase_client.dart';

/// The platform's per-order service fee rule. Mirrors
/// `public.compute_service_fee`, which is what actually charges it — this
/// copy only lets checkout show the same number before the order exists.
class ServiceFeeRule {
  const ServiceFeeRule({this.type = 'fixed', this.value = 0, this.max});

  /// `fixed` | `percent`.
  final String type;
  final double value;

  /// Cap on a percentage fee; null means uncapped. Ignored for `fixed`.
  final double? max;

  bool get isPercent => type == 'percent';
  bool get isOff => value <= 0;

  double feeFor(double subtotal) {
    if (isOff) return 0;
    if (!isPercent) return _round(value);
    final raw = (subtotal < 0 ? 0 : subtotal) * value / 100;
    final capped = max == null || raw <= max! ? raw : max!;
    return _round(capped);
  }

  static double _round(double v) => (v * 100).roundToDouble() / 100;

  factory ServiceFeeRule.fromMap(Map<String, dynamic> map) => ServiceFeeRule(
    type: (map['service_fee_type'] as String?) ?? 'fixed',
    value: ((map['service_fee_value'] as num?) ?? 0).toDouble(),
    max: (map['service_fee_max'] as num?)?.toDouble(),
  );
}

class PlatformSettingsRepository {
  Future<ServiceFeeRule> serviceFee() async {
    final row = await supabase
        .from('platform_settings')
        .select('service_fee_type, service_fee_value, service_fee_max')
        .eq('id', 1)
        .maybeSingle();
    return row == null ? const ServiceFeeRule() : ServiceFeeRule.fromMap(row);
  }

  /// Admin only; the database refuses anyone without `finance.adjust`.
  Future<void> setServiceFee({
    required String type,
    required double value,
    double? max,
  }) => supabase.rpc(
    'admin_set_service_fee',
    params: {'p_type': type, 'p_value': value, 'p_max': max},
  );
}
