import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/order.dart';
import '../../core/repositories/admin_repository.dart';
import '../../core/utils/paging.dart';

enum OrderMonitorFilter { all, flagged, preparing, onTheWay }

/// An order is "flagged" when it has been sitting in a non-terminal state past
/// the platform SLA (stuck vendor / no driver).
const _stuckAfter = Duration(minutes: 20);

class AdminOrdersState extends Equatable {
  const AdminOrdersState({
    this.loading = true,
    this.liveOrders = const [],
    this.history = const [],
    this.vendorLabels = const {},
    this.filter = OrderMonitorFilter.all,
    this.loadingMore = false,
    this.hasMore = true,
    this.error,
    this.day,
  });

  final bool loading;

  /// Every order still in flight, streamed in realtime.
  final List<AppOrder> liveOrders;

  /// Finished orders, loaded a page at a time.
  final List<AppOrder> history;
  final Map<String, ({String name, String? logoUrl})> vendorLabels;
  final OrderMonitorFilter filter;
  final bool loadingMore;
  final bool hasMore;
  final String? error;

  /// The calendar day being read. Null is never used: the monitor opens on
  /// today, and an older day is chosen deliberately.
  final DateTime? day;

  DateTime get selectedDay => day ?? DateTime.now();

  bool get isToday {
    final now = DateTime.now();
    final d = selectedDay;
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool isFlagged(AppOrder o) =>
      !o.status.isTerminal &&
      o.status != OrderStatus.outForDelivery &&
      DateTime.now().difference(o.createdAt) > _stuckAfter;

  /// Live and history are disjoint by status, so this never repeats a row.
  /// Both are narrowed to the day on screen.
  List<AppOrder> get orders => [
    ...liveOrders.where((o) => _sameDay(o.createdAt, selectedDay)),
    ...history,
  ];

  int get liveCount => liveOrders.length;
  int get flaggedCount => liveOrders.where(isFlagged).length;

  /// Only the unfiltered view reaches into the paged history; the other tabs
  /// are subsets of the live stream, which is always fully loaded.
  bool get canLoadMore => filter == OrderMonitorFilter.all && hasMore;

  List<AppOrder> get visible {
    final list = switch (filter) {
      OrderMonitorFilter.all => orders,
      OrderMonitorFilter.flagged => liveOrders.where(isFlagged).toList(),
      OrderMonitorFilter.preparing =>
        liveOrders
            .where(
              (o) =>
                  o.status == OrderStatus.accepted ||
                  o.status == OrderStatus.preparing ||
                  o.status == OrderStatus.readyForPickup,
            )
            .toList(),
      OrderMonitorFilter.onTheWay =>
        liveOrders
            .where((o) => o.status == OrderStatus.outForDelivery)
            .toList(),
    };
    return list..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  AdminOrdersState copyWith({
    bool? loading,
    List<AppOrder>? liveOrders,
    List<AppOrder>? history,
    Map<String, ({String name, String? logoUrl})>? vendorLabels,
    OrderMonitorFilter? filter,
    bool? loadingMore,
    bool? hasMore,
    String? error,
    DateTime? day,
    bool clearError = false,
  }) => AdminOrdersState(
    loading: loading ?? this.loading,
    liveOrders: liveOrders ?? this.liveOrders,
    history: history ?? this.history,
    vendorLabels: vendorLabels ?? this.vendorLabels,
    filter: filter ?? this.filter,
    loadingMore: loadingMore ?? this.loadingMore,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : (error ?? this.error),
    day: day ?? this.day,
  );

  @override
  List<Object?> get props => [
    loading,
    liveOrders,
    history,
    vendorLabels,
    filter,
    loadingMore,
    hasMore,
    error,
    day,
  ];
}

/// Realtime monitor of the orders in flight, backed by a paged history.
///
/// The socket alone is not enough to call this live. It drops on every network
/// change and every sleeping laptop, and a dropped socket looked exactly like
/// a quiet evening — the board simply stopped moving, and an operator watching
/// an order marked delivered half an hour ago had no way to know except to
/// reload the page. The subscription is rebuilt after any error, and a slow
/// poll reconciles underneath it so a silently dead socket costs one interval.
class AdminOrdersCubit extends Cubit<AdminOrdersState>
    with WidgetsBindingObserver {
  AdminOrdersCubit(this._repository) : super(const AdminOrdersState()) {
    WidgetsBinding.instance.addObserver(this);
    _subscribe();
    _poll = Timer.periodic(_pollInterval, (_) => _reconcile());
    loadMore();
  }

  final AdminRepository _repository;
  Timer? _poll;
  Timer? _retry;
  int _retryAttempt = 0;

  /// Slow on purpose: the net under the socket, not how orders normally
  /// arrive.
  static const _pollInterval = Duration(seconds: 30);

  void _subscribe() {
    _subscription?.cancel();
    _subscription = _repository
        .liveOrdersStream()
        .listen(
          (orders) {
            _retryAttempt = 0;
            _onLiveOrders(orders);
          },
          // Not shown to the operator: the board in front of them is still
          // valid, and the poll keeps it fresh while the socket is rebuilt.
          onError: (Object _) => _scheduleResubscribe(),
          onDone: _scheduleResubscribe,
        );
  }

  /// Backs off to a minute, so a server that is genuinely down is not hammered
  /// by every console left open in the office.
  void _scheduleResubscribe() {
    if (isClosed) return;
    _retry?.cancel();
    final seconds = (1 << _retryAttempt.clamp(0, 6)).clamp(1, 60);
    _retryAttempt++;
    _retry = Timer(Duration(seconds: seconds), () {
      if (isClosed) return;
      _subscribe();
      _reconcile();
    });
  }

  Future<void> _reconcile() async {
    if (isClosed) return;
    try {
      await _onLiveOrders(await _repository.fetchLiveOrders());
    } catch (_) {
      // Offline. The next tick tries again; nothing to tell the operator.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the tab is when the socket is most likely to be dead and
    // the board most likely to be wrong.
    if (state == AppLifecycleState.resumed) {
      _subscribe();
      _reconcile();
    }
  }

  /// Reads another day: the history is dropped and re-paged from that day.
  Future<void> setDay(DateTime day) async {
    emit(
      state.copyWith(
        day: DateTime(day.year, day.month, day.day),
        history: const [],
        hasMore: true,
        loadingMore: false,
      ),
    );
    await loadMore();
  }

  StreamSubscription<List<AppOrder>>? _subscription;
  Set<String> _liveIds = {};

  Future<void> _onLiveOrders(List<AppOrder> orders) async {
    if (isClosed) return;
    final ids = orders.map((o) => o.id).toSet();
    final finished = _liveIds.difference(ids);
    _liveIds = ids;

    emit(
      state.copyWith(
        loading: false,
        liveOrders: orders,
        vendorLabels: await _withLabels(orders),
      ),
    );

    // An order that just left the live stream became terminal: pull the head of
    // the history so it does not vanish from the unfiltered view.
    if (finished.isNotEmpty) await _refreshHistoryHead();
  }

  Future<Map<String, ({String name, String? logoUrl})>> _withLabels(
    List<AppOrder> orders,
  ) async {
    var labels = state.vendorLabels;
    final missing = orders
        .map((o) => o.vendorId)
        .where((id) => !labels.containsKey(id))
        .toSet();
    if (missing.isNotEmpty) {
      try {
        labels = {...labels, ...await _repository.vendorLabels(missing)};
      } catch (_) {}
    }
    return labels;
  }

  /// Appends the next page of finished orders. Rows already held are skipped:
  /// a fresh terminal order shifts every offset, so pages can overlap.
  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore) return;
    emit(state.copyWith(loadingMore: true));
    try {
      final page = await _repository.fetchOrdersHistoryPage(
        limit: kPageSize,
        offset: state.history.length,
        day: state.selectedDay,
      );
      final labels = await _withLabels(page);
      if (isClosed) return;
      final known = state.history.map((o) => o.id).toSet();
      emit(
        state.copyWith(
          loading: false,
          loadingMore: false,
          hasMore: page.length == kPageSize,
          history: [
            ...state.history,
            ...page.where((o) => !known.contains(o.id)),
          ],
          vendorLabels: labels,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(loading: false, loadingMore: false, error: e.toString()),
      );
    }
  }

  /// Re-reads the newest page and prepends rows not held yet.
  Future<void> _refreshHistoryHead() async {
    try {
      final page = await _repository.fetchOrdersHistoryPage(
        limit: kPageSize,
        offset: 0,
        day: state.selectedDay,
      );
      if (isClosed) return;
      final known = state.history.map((o) => o.id).toSet();
      final fresh = page.where((o) => !known.contains(o.id)).toList();
      if (fresh.isEmpty) return;
      final labels = await _withLabels(fresh);
      if (isClosed) return;
      emit(
        state.copyWith(
          history: [...fresh, ...state.history],
          vendorLabels: labels,
        ),
      );
    } catch (_) {}
  }

  void setFilter(OrderMonitorFilter filter) =>
      emit(state.copyWith(filter: filter));

  @override
  Future<void> close() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _retry?.cancel();
    _subscription?.cancel();
    return super.close();
  }
}
