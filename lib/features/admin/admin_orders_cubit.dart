import 'dart:async';

import 'package:equatable/equatable.dart';
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

  static bool isFlagged(AppOrder o) =>
      !o.status.isTerminal &&
      o.status != OrderStatus.outForDelivery &&
      DateTime.now().difference(o.createdAt) > _stuckAfter;

  /// Live and history are disjoint by status, so this never repeats a row.
  List<AppOrder> get orders => [...liveOrders, ...history];

  int get liveCount => liveOrders.length;
  int get flaggedCount => liveOrders.where(isFlagged).length;

  /// Only the unfiltered view reaches into the paged history; the other tabs
  /// are subsets of the live stream, which is always fully loaded.
  bool get canLoadMore => filter == OrderMonitorFilter.all && hasMore;

  List<AppOrder> get visible {
    final list = switch (filter) {
      OrderMonitorFilter.all => orders,
      OrderMonitorFilter.flagged => liveOrders.where(isFlagged).toList(),
      OrderMonitorFilter.preparing => liveOrders
          .where((o) =>
              o.status == OrderStatus.accepted ||
              o.status == OrderStatus.preparing ||
              o.status == OrderStatus.readyForPickup)
          .toList(),
      OrderMonitorFilter.onTheWay => liveOrders
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
    bool clearError = false,
  }) =>
      AdminOrdersState(
        loading: loading ?? this.loading,
        liveOrders: liveOrders ?? this.liveOrders,
        history: history ?? this.history,
        vendorLabels: vendorLabels ?? this.vendorLabels,
        filter: filter ?? this.filter,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: clearError ? null : (error ?? this.error),
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
      ];
}

/// Realtime monitor of the orders in flight, backed by a paged history.
class AdminOrdersCubit extends Cubit<AdminOrdersState> {
  AdminOrdersCubit(this._repository) : super(const AdminOrdersState()) {
    _subscription = _repository.liveOrdersStream().listen(_onLiveOrders,
        onError: (Object e) =>
            emit(state.copyWith(loading: false, error: e.toString())));
    loadMore();
  }

  final AdminRepository _repository;
  StreamSubscription<List<AppOrder>>? _subscription;
  Set<String> _liveIds = {};

  Future<void> _onLiveOrders(List<AppOrder> orders) async {
    if (isClosed) return;
    final ids = orders.map((o) => o.id).toSet();
    final finished = _liveIds.difference(ids);
    _liveIds = ids;

    emit(state.copyWith(
      loading: false,
      liveOrders: orders,
      vendorLabels: await _withLabels(orders),
    ));

    // An order that just left the live stream became terminal: pull the head of
    // the history so it does not vanish from the unfiltered view.
    if (finished.isNotEmpty) await _refreshHistoryHead();
  }

  Future<Map<String, ({String name, String? logoUrl})>> _withLabels(
      List<AppOrder> orders) async {
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
      );
      final labels = await _withLabels(page);
      if (isClosed) return;
      final known = state.history.map((o) => o.id).toSet();
      emit(state.copyWith(
        loading: false,
        loadingMore: false,
        hasMore: page.length == kPageSize,
        history: [
          ...state.history,
          ...page.where((o) => !known.contains(o.id)),
        ],
        vendorLabels: labels,
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
          loading: false, loadingMore: false, error: e.toString()));
    }
  }

  /// Re-reads the newest page and prepends rows not held yet.
  Future<void> _refreshHistoryHead() async {
    try {
      final page =
          await _repository.fetchOrdersHistoryPage(limit: kPageSize, offset: 0);
      if (isClosed) return;
      final known = state.history.map((o) => o.id).toSet();
      final fresh = page.where((o) => !known.contains(o.id)).toList();
      if (fresh.isEmpty) return;
      final labels = await _withLabels(fresh);
      if (isClosed) return;
      emit(state.copyWith(
        history: [...fresh, ...state.history],
        vendorLabels: labels,
      ));
    } catch (_) {}
  }

  void setFilter(OrderMonitorFilter filter) =>
      emit(state.copyWith(filter: filter));

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
