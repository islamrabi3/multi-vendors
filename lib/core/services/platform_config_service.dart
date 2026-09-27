import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/platform_config.dart';
import '../supabase_client.dart';

/// The live [PlatformConfig], as one listenable the whole app reads.
///
/// Read before the first frame, so an app running in riyals never flashes
/// pounds, and kept current over realtime, so an admin's change reaches
/// phones that are already open.
class PlatformConfigService {
  PlatformConfigService._();

  static final PlatformConfigService instance = PlatformConfigService._();

  final ValueNotifier<PlatformConfig> config = ValueNotifier(
    const PlatformConfig(),
  );

  PlatformConfig get current => config.value;

  RealtimeChannel? _channel;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await refresh();
    _channel = supabase
        .channel('platform-config')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'platform_settings',
          callback: (_) => refresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'currencies',
          callback: (_) => refresh(),
        )
        .subscribe();
  }

  Future<void> refresh() async {
    try {
      final row = await supabase
          .from('platform_settings')
          .select(
            'currency_code, delivery_fee_mode, delivery_base_fee, '
            'delivery_base_km, delivery_per_km_fee, '
            'currencies(code, name, name_ar, symbol, symbol_ar, decimals)',
          )
          .eq('id', 1)
          .maybeSingle();
      if (row == null) return;
      final currency = row['currencies'];
      config.value = PlatformConfig(
        currency: currency is Map<String, dynamic>
            ? AppCurrency.fromMap(currency)
            : AppCurrency.egp,
        delivery: DeliveryFeeRule.fromMap(row),
      );
    } catch (_) {
      // Keep whatever was last known; on launch that is EGP and store fees,
      // which is what the platform ran on before either could be changed.
    }
  }

  Future<void> stop() async {
    final channel = _channel;
    _channel = null;
    _started = false;
    if (channel != null) await supabase.removeChannel(channel);
  }
}
