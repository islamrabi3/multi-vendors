import '../models/platform_config.dart';
import '../services/maintenance_gate.dart';
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

  /// The maintenance flag and its message, read once.
  Future<MaintenanceStatus> maintenanceStatus() async {
    final row = await supabase
        .from('platform_settings')
        .select('maintenance_mode, maintenance_message, maintenance_message_ar')
        .eq('id', 1)
        .maybeSingle();
    return row == null
        ? const MaintenanceStatus()
        : MaintenanceStatus.fromMap(row);
  }

  /// Admin only; the database refuses anyone who is not an admin.
  Future<void> setMaintenanceMode({
    required bool enabled,
    String? message,
    String? messageAr,
  }) => supabase.rpc(
    'admin_set_maintenance_mode',
    params: {
      'p_enabled': enabled,
      'p_message': message,
      'p_message_ar': messageAr,
    },
  );

  /// Admin only; the database refuses anyone without `finance.adjust`.
  Future<void> setServiceFee({
    required String type,
    required double value,
    double? max,
  }) => supabase.rpc(
    'admin_set_service_fee',
    params: {'p_type': type, 'p_value': value, 'p_max': max},
  );

  /// Every currency the admin has added, the active one included.
  Future<List<AppCurrency>> currencies() async {
    final rows = await supabase.from('currencies').select().order('code');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(AppCurrency.fromMap)
        .toList();
  }

  /// Adds [currency], or updates it when its code already exists. Admin
  /// only; needs `finance.adjust`.
  Future<void> saveCurrency(AppCurrency currency) => supabase.rpc(
    'admin_upsert_currency',
    params: {
      'p_code': currency.code,
      'p_name': currency.name,
      'p_name_ar': currency.nameAr,
      'p_symbol': currency.symbol,
      'p_symbol_ar': currency.symbolAr,
      'p_decimals': currency.decimals,
    },
  );

  /// Refused with `CURRENCY_IN_USE` for the platform's current currency.
  Future<void> deleteCurrency(String code) =>
      supabase.rpc('admin_delete_currency', params: {'p_code': code});

  /// Makes [code] the platform's currency. Relabels every amount; converts
  /// none.
  Future<void> setCurrency(String code) =>
      supabase.rpc('admin_set_currency', params: {'p_code': code});

  /// Admin only; needs `finance.adjust`. See [DeliveryFeeRule].
  Future<void> setDeliveryPricing(DeliveryFeeRule rule) => supabase.rpc(
    'admin_set_delivery_pricing',
    params: {
      'p_mode': rule.mode,
      'p_base_fee': rule.baseFee,
      'p_base_km': rule.baseKm,
      'p_per_km_fee': rule.perKmFee,
    },
  );

  /// Gives every store the same flat delivery fee. Returns how many changed.
  Future<int> setAllStoreDeliveryFees(double fee) async {
    final changed = await supabase.rpc(
      'admin_set_all_vendor_delivery_fees',
      params: {'p_fee': fee},
    );
    return (changed as num?)?.toInt() ?? 0;
  }
}
