import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';

var _channelSeq = 0;

/// A badge count that stays live without downloading the rows it counts.
///
/// `.stream()` on a table loads every matching row and re-sends the whole set
/// on each change, which is a heavy price for a number on an icon — and the
/// bell sits on every shell. This runs [count] (a `count()`-only query) once
/// on listen, then again whenever realtime reports a change on [table].
/// Changes are debounced so a burst of inserts costs one query, not one each.
Stream<int> liveCount({
  required String table,
  required Future<int> Function() count,
  PostgresChangeFilter? filter,
}) {
  final controller = StreamController<int>();
  RealtimeChannel? channel;
  Timer? debounce;
  var active = true;

  Future<void> refresh() async {
    try {
      final value = await count();
      if (active) controller.add(value);
    } catch (_) {
      // A badge that fails to refresh keeps its last number; the next change
      // or the next screen open tries again.
    }
  }

  controller.onListen = () {
    refresh();
    channel = supabase
        .channel('count:$table:${_channelSeq++}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          filter: filter,
          callback: (_) {
            debounce?.cancel();
            debounce = Timer(const Duration(milliseconds: 400), refresh);
          },
        )
        .subscribe((status, _) {
          // Anything that changed while the socket was reconnecting produced
          // no event, so catch up once the channel is back.
          if (status == RealtimeSubscribeStatus.subscribed) refresh();
        });
  };

  controller.onCancel = () async {
    active = false;
    debounce?.cancel();
    final open = channel;
    if (open != null) await supabase.removeChannel(open);
    await controller.close();
  };

  return controller.stream;
}
