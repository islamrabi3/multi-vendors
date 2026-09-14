import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

/// What is waiting on staff right now — the numbers behind the red badges on
/// the admin console's tabs, sidebar and Overview grid.
///
/// One store for the whole console: every badge reads the same counts from
/// one `admin_action_counts` call, refreshed when any of the tables behind
/// them changes (and once a minute as a safety net for missed events).
class AdminActionBadges {
  AdminActionBadges._();
  static final instance = AdminActionBadges._();

  static const supportAwaiting = 'support_awaiting';
  static const reportsPending = 'reports_pending';
  static const vendorsPending = 'vendors_pending';
  static const driversPending = 'drivers_pending';
  static const settlementRequests = 'settlement_requests';
  static const depositsPending = 'deposits_pending';
  static const ordersAttention = 'orders_attention';

  static const _tables = [
    'support_threads',
    'support_messages',
    'customer_reports',
    'vendors',
    'drivers',
    'settlements',
    'deposit_requests',
    'orders',
  ];

  final Map<String, ValueNotifier<int>> _counts = {};

  /// Everything on the Overview grid combined, for the Overview tab itself —
  /// so work waiting there is visible from the other tabs too.
  static const _gridKeys = [
    supportAwaiting,
    reportsPending,
    driversPending,
    settlementRequests,
    depositsPending,
  ];
  final ValueNotifier<int> _gridTotal = ValueNotifier(0);
  ValueListenable<int> get gridTotal => _gridTotal;
  RealtimeChannel? _channel;
  Timer? _debounce;
  Timer? _poll;
  DateTime? _lastFetch;
  bool _fetching = false;

  /// A live count for [key]; 0 when nothing is waiting or the viewer's role
  /// cannot act on it.
  ValueListenable<int> countFor(String key) =>
      _counts.putIfAbsent(key, () => ValueNotifier(0));

  /// Safe to call on every build of the admin shell.
  void ensureStarted() {
    final stale =
        _lastFetch == null ||
        DateTime.now().difference(_lastFetch!) > const Duration(seconds: 30);
    if (_channel != null) {
      if (stale) refresh();
      return;
    }
    var channel = supabase.channel('admin-action-badges');
    for (final table in _tables) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => _scheduleRefresh(),
      );
    }
    _channel = channel.subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed) refresh();
    });
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
    refresh();
  }

  /// Signing out must not leave the next account looking at these numbers.
  Future<void> stop() async {
    _debounce?.cancel();
    _poll?.cancel();
    _poll = null;
    final channel = _channel;
    _channel = null;
    _lastFetch = null;
    for (final notifier in _counts.values) {
      notifier.value = 0;
    }
    _gridTotal.value = 0;
    if (channel != null) await supabase.removeChannel(channel);
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), refresh);
  }

  Future<void> refresh() async {
    if (_fetching || supabase.auth.currentUser == null) return;
    _fetching = true;
    try {
      final data = await supabase.rpc('admin_action_counts');
      final map = (data as Map?)?.cast<String, dynamic>() ?? const {};
      _lastFetch = DateTime.now();
      for (final key in {..._counts.keys, ...map.keys}) {
        final value = ((map[key] as num?) ?? 0).toInt();
        final notifier = _counts.putIfAbsent(key, () => ValueNotifier(0));
        if (notifier.value != value) notifier.value = value;
      }
      _gridTotal.value = _gridKeys.fold(
        0,
        (sum, key) => sum + (_counts[key]?.value ?? 0),
      );
    } catch (_) {
      // A badge that fails to refresh keeps its last number.
    } finally {
      _fetching = false;
    }
  }
}
