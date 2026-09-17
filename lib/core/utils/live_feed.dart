import 'dart:async';

import 'package:flutter/widgets.dart';

/// A realtime subscription that survives the things that break sockets.
///
/// A plain `.stream().listen(...)` is live right up until it is not. The
/// socket drops on every network change, every laptop that sleeps, every tab
/// left open over lunch — and a dropped socket looks exactly like a quiet
/// evening: the screen stops moving and says nothing about it. Operators then
/// learn to reload the page, which is the moment a live screen has stopped
/// being one.
///
/// So three things together, none of which is sufficient alone:
///   * the subscription is rebuilt after any error or close, backing off so a
///     server that is genuinely down is not hammered by every screen open in
///     the office;
///   * a slow poll reads the same rows underneath, so a silently dead socket
///     costs one interval rather than the rest of the shift;
///   * both are redone when the app returns to the foreground, which is when
///     the socket is most likely to be dead and the screen most likely wrong.
class LiveFeed<T> with WidgetsBindingObserver {
  LiveFeed({
    required Stream<T> Function() stream,
    required Future<T> Function() fetch,
    required void Function(T data) onData,
    this.pollInterval = const Duration(seconds: 30),
  }) : _stream = stream,
       _fetch = fetch,
       _onData = onData;

  final Stream<T> Function() _stream;
  final Future<T> Function() _fetch;
  final void Function(T data) _onData;

  /// Slow on purpose: the net under the socket, not how data normally
  /// arrives.
  final Duration pollInterval;

  StreamSubscription<T>? _subscription;
  Timer? _poll;
  Timer? _retry;
  int _attempt = 0;
  bool _stopped = false;

  void start() {
    _stopped = false;
    WidgetsBinding.instance.addObserver(this);
    _subscribe();
    _poll = Timer.periodic(pollInterval, (_) => reconcile());
  }

  void _subscribe() {
    if (_stopped) return;
    _subscription?.cancel();
    _subscription = _stream().listen(
      (data) {
        _attempt = 0;
        _onData(data);
      },
      // Never surfaced: whatever is already on screen is still valid, and the
      // poll keeps it fresh while the socket is rebuilt.
      onError: (Object _) => _scheduleResubscribe(),
      onDone: _scheduleResubscribe,
    );
  }

  void _scheduleResubscribe() {
    if (_stopped) return;
    _retry?.cancel();
    final seconds = (1 << _attempt.clamp(0, 6)).clamp(1, 60);
    _attempt++;
    _retry = Timer(Duration(seconds: seconds), () {
      if (_stopped) return;
      _subscribe();
      reconcile();
    });
  }

  /// Re-reads once, ignoring failure: offline is not news, and the next tick
  /// will try again.
  Future<void> reconcile() async {
    if (_stopped) return;
    try {
      final data = await _fetch();
      if (!_stopped) _onData(data);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _subscribe();
      reconcile();
    }
  }

  void dispose() {
    _stopped = true;
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _poll?.cancel();
    _retry?.cancel();
  }
}
