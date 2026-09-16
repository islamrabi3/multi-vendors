import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';

/// Whether the platform is closed for maintenance, and what to say about it.
class MaintenanceStatus {
  const MaintenanceStatus({this.enabled = false, this.message, this.messageAr});

  final bool enabled;
  final String? message;
  final String? messageAr;

  String? messageFor(String languageCode) {
    final text = languageCode == 'ar' ? (messageAr ?? message) : message;
    final trimmed = text?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  factory MaintenanceStatus.fromMap(Map<String, dynamic> map) =>
      MaintenanceStatus(
        enabled: (map['maintenance_mode'] as bool?) ?? false,
        message: map['maintenance_message'] as String?,
        messageAr: map['maintenance_message_ar'] as String?,
      );
}

/// The live maintenance flag, as one listenable the router can watch.
///
/// The switch has to reach phones that are already open — that is the whole
/// point of it — so this is a realtime subscription, not a value read once at
/// launch. Admins are never held by it: someone has to be able to turn it off.
class MaintenanceGate {
  MaintenanceGate._();

  static final MaintenanceGate instance = MaintenanceGate._();

  final ValueNotifier<MaintenanceStatus> status = ValueNotifier(
    const MaintenanceStatus(),
  );

  RealtimeChannel? _channel;
  bool _started = false;

  bool get isDown => status.value.enabled;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await refresh();
    _channel = supabase
        .channel('platform-settings')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'platform_settings',
          callback: (_) => refresh(),
        )
        .subscribe();
  }

  Future<void> refresh() async {
    try {
      final row = await supabase
          .from('platform_settings')
          .select(
            'maintenance_mode, maintenance_message, maintenance_message_ar',
          )
          .eq('id', 1)
          .maybeSingle();
      status.value = row == null
          ? const MaintenanceStatus()
          : MaintenanceStatus.fromMap(row);
    } catch (_) {
      // A failed read must never lock anyone out: the app keeps whatever it
      // last knew, which on launch is "open".
    }
  }

  Future<void> stop() async {
    final channel = _channel;
    _channel = null;
    _started = false;
    if (channel != null) await supabase.removeChannel(channel);
  }
}
