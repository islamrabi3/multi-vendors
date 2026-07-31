import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/order.dart';
import '../../core/repositories/order_repository.dart';
import '../../core/repositories/vendor_admin_repository.dart';
import '../../core/utils/paging.dart';

class VendorOrdersState extends Equatable {
  const VendorOrdersState({
    this.loading = true,
    this.orders = const [],
    this.error,
    this.newOrderArrived = false,
    this.history = const [],
    this.loadingHistory = false,
    this.hasMoreHistory = true,
  });

  final bool loading;
  final List<AppOrder> orders;
  final String? error;

  /// Pulses true when a new pending order lands, so the UI can alert.
  final bool newOrderArrived;

  /// Finished orders, loaded a page at a time (the live tabs come from the
  /// realtime stream in [orders]).
  final List<AppOrder> history;
  final bool loadingHistory;
  final bool hasMoreHistory;

  List<AppOrder> get pending =>
      orders.where((o) => o.status == OrderStatus.pending).toList();

  List<AppOrder> get active => orders
      .where((o) =>
          o.status == OrderStatus.accepted ||
          o.status == OrderStatus.preparing ||
          o.status == OrderStatus.readyForPickup ||
          o.status == OrderStatus.outForDelivery)
      .toList();

  List<AppOrder> get past =>
      orders.where((o) => o.status.isTerminal).toList();

  List<AppOrder> get preparing => orders
      .where((o) =>
          o.status == OrderStatus.accepted ||
          o.status == OrderStatus.preparing)
      .toList();

  List<AppOrder> get ready => orders
      .where((o) =>
          o.status == OrderStatus.readyForPickup ||
          o.status == OrderStatus.outForDelivery)
      .toList();

  /// Today's gross revenue from non-cancelled / non-rejected orders.
  double get todayRevenue {
    final now = DateTime.now();
    return orders
        .where((o) =>
            !_isVoided(o.status) &&
            o.createdAt.year == now.year &&
            o.createdAt.month == now.month &&
            o.createdAt.day == now.day)
        .fold(0.0, (sum, o) => sum + o.total);
  }

  /// Today's order count (excludes cancelled / rejected).
  int get todayOrderCount {
    final now = DateTime.now();
    return orders
        .where((o) =>
            !_isVoided(o.status) &&
            o.createdAt.year == now.year &&
            o.createdAt.month == now.month &&
            o.createdAt.day == now.day)
        .length;
  }

  bool _isVoided(OrderStatus s) =>
      s == OrderStatus.cancelled || s == OrderStatus.rejected;

  VendorOrdersState copyWith({
    bool? loading,
    List<AppOrder>? orders,
    String? error,
    bool clearError = false,
    bool? newOrderArrived,
    List<AppOrder>? history,
    bool? loadingHistory,
    bool? hasMoreHistory,
  }) =>
      VendorOrdersState(
        loading: loading ?? this.loading,
        orders: orders ?? this.orders,
        error: clearError ? null : (error ?? this.error),
        newOrderArrived: newOrderArrived ?? this.newOrderArrived,
        history: history ?? this.history,
        loadingHistory: loadingHistory ?? this.loadingHistory,
        hasMoreHistory: hasMoreHistory ?? this.hasMoreHistory,
      );

  @override
  List<Object?> get props => [
        loading,
        orders,
        error,
        newOrderArrived,
        history,
        loadingHistory,
        hasMoreHistory,
      ];
}

/// Realtime feed of the vendor's orders, partitioned for the dashboard, with
/// the finished ones paged in behind them.
class VendorOrdersCubit extends Cubit<VendorOrdersState> {
  VendorOrdersCubit(this._repository, this.vendorId, {bool autoAccept = false})
      : _autoAccept = autoAccept,
        super(const VendorOrdersState()) {
    _subscription =
        _repository.vendorOrdersStream(vendorId).listen(_onOrders,
            onError: (Object error) => emit(state.copyWith(
                loading: false,
                error: error.toString(),
                newOrderArrived: false)));
  }

  final OrderRepository _repository;
  final _admin = VendorAdminRepository();
  final String vendorId;
  StreamSubscription<List<AppOrder>>? _subscription;
  Set<String> _knownPendingIds = {};

  /// When enabled, freshly-arrived pending orders are accepted automatically.
  bool _autoAccept;
  set autoAccept(bool value) => _autoAccept = value;

  void _onOrders(List<AppOrder> orders) {
    final sorted = List<AppOrder>.of(orders)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final pendingIds = sorted
        .where((o) => o.status == OrderStatus.pending)
        .map((o) => o.id)
        .toSet();
    final freshPending = pendingIds.difference(_knownPendingIds);
    final hasNew = !state.loading && freshPending.isNotEmpty;
    _knownPendingIds = pendingIds;
    emit(state.copyWith(
        loading: false,
        orders: sorted,
        newOrderArrived: hasNew,
        clearError: true));

    if (_autoAccept && freshPending.isNotEmpty) {
      for (final order
          in sorted.where((o) => freshPending.contains(o.id))) {
        accept(order);
      }
    }
  }

  /// Pull-to-refresh: re-fetch the vendor's orders once, covering a missed
  /// realtime event. Does not fire the "new order" alert.
  Future<void> refresh() async {
    try {
      final orders = await _repository.fetchVendorOrders(vendorId);
      final sorted = List<AppOrder>.of(orders)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _knownPendingIds = sorted
          .where((o) => o.status == OrderStatus.pending)
          .map((o) => o.id)
          .toSet();
      emit(state.copyWith(
          loading: false,
          orders: sorted,
          newOrderArrived: false,
          clearError: true));
    } catch (error) {
      emit(state.copyWith(
          loading: false, error: error.toString(), newOrderArrived: false));
    }
  }

  /// Appends the next page of finished orders. Rows already held are skipped:
  /// an order finishing shifts every offset, so pages can overlap.
  Future<void> loadMoreHistory() async {
    if (state.loadingHistory || !state.hasMoreHistory) return;
    emit(state.copyWith(loadingHistory: true));
    try {
      final page = await _admin.fetchVendorOrdersPage(
        vendorId: vendorId,
        limit: kPageSize,
        offset: state.history.length,
      );
      if (isClosed) return;
      final known = state.history.map((o) => o.id).toSet();
      emit(state.copyWith(
        loadingHistory: false,
        hasMoreHistory: page.length == kPageSize,
        history: [
          ...state.history,
          ...page.where((o) => !known.contains(o.id)),
        ],
      ));
    } catch (error) {
      if (isClosed) return;
      emit(state.copyWith(
          loadingHistory: false,
          error: error.toString(),
          newOrderArrived: false));
    }
  }

  Future<void> accept(AppOrder order) =>
      _update(order, OrderStatus.accepted);

  Future<void> reject(AppOrder order, String reason) =>
      _update(order, OrderStatus.rejected, reason: reason);

  Future<void> startPreparing(AppOrder order) =>
      _update(order, OrderStatus.preparing);

  Future<void> markReady(AppOrder order) =>
      _update(order, OrderStatus.readyForPickup);

  Future<void> _update(AppOrder order, OrderStatus status,
      {String? reason}) async {
    try {
      await _repository.updateStatus(order.id, status, reason: reason);
    } catch (error) {
      emit(state.copyWith(
          loading: false, error: error.toString(), newOrderArrived: false));
    }
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
