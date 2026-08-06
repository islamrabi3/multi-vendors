import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
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
      .where(
        (o) =>
            o.status == OrderStatus.accepted ||
            o.status == OrderStatus.preparing ||
            o.status == OrderStatus.readyForPickup ||
            o.status == OrderStatus.outForDelivery,
      )
      .toList();

  List<AppOrder> get past => orders.where((o) => o.status.isTerminal).toList();

  List<AppOrder> get preparing => orders
      .where(
        (o) =>
            o.status == OrderStatus.accepted ||
            o.status == OrderStatus.preparing,
      )
      .toList();

  List<AppOrder> get ready => orders
      .where(
        (o) =>
            o.status == OrderStatus.readyForPickup ||
            o.status == OrderStatus.outForDelivery,
      )
      .toList();

  /// Today's item sales from non-cancelled / non-rejected orders.
  ///
  /// `subtotal`, not `total`: the delivery fee inside `total` is collected from
  /// the customer and paid to the driver and the platform, so counting it here
  /// showed the store money it never receives. Commission is not deducted —
  /// this is the top line, and the settled figure lives on the analytics page.
  double get todayRevenue {
    final now = DateTime.now();
    return orders
        .where(
          (o) =>
              !_isVoided(o.status) &&
              o.createdAt.year == now.year &&
              o.createdAt.month == now.month &&
              o.createdAt.day == now.day,
        )
        .fold(0.0, (sum, o) => sum + o.subtotal);
  }

  /// Today's order count (excludes cancelled / rejected).
  int get todayOrderCount {
    final now = DateTime.now();
    return orders
        .where(
          (o) =>
              !_isVoided(o.status) &&
              o.createdAt.year == now.year &&
              o.createdAt.month == now.month &&
              o.createdAt.day == now.day,
        )
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
  }) => VendorOrdersState(
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
///
/// The socket alone is not enough to call this live. It drops on every network
/// change, screen lock and background/foreground cycle, and a dropped socket
/// looked exactly like a quiet evening: the list simply stopped moving and the
/// store found out about an order when the customer rang. Three things keep it
/// honest — the subscription is rebuilt after any stream error, it is rebuilt
/// when the app comes back to the foreground, and a slow poll reconciles
/// underneath both so a silently dead socket costs at most one interval.
class VendorOrdersCubit extends Cubit<VendorOrdersState>
    with WidgetsBindingObserver {
  VendorOrdersCubit(this._repository, this.vendorId, {bool autoAccept = false})
    : _autoAccept = autoAccept,
      super(const VendorOrdersState()) {
    WidgetsBinding.instance.addObserver(this);
    _subscribe();
    _poll = Timer.periodic(_pollInterval, (_) => _reconcile());
  }

  final OrderRepository _repository;
  final _admin = VendorAdminRepository();
  final String vendorId;
  StreamSubscription<List<AppOrder>>? _subscription;
  Timer? _poll;
  Timer? _retry;
  int _retryAttempt = 0;
  Set<String> _knownPendingIds = {};

  /// Slow on purpose: this is the safety net under the socket, not the way
  /// orders normally arrive. Frequent enough that a dead socket costs the
  /// store under a minute, rare enough to be free.
  static const _pollInterval = Duration(seconds: 45);

  void _subscribe() {
    _subscription?.cancel();
    _subscription = _repository
        .vendorOrdersStream(vendorId)
        .listen(
          (orders) {
            _retryAttempt = 0;
            _onOrders(orders);
          },
          // A broken socket is not something to show the store: the list they
          // are looking at is still valid, and the poll below keeps it fresh
          // while the subscription is rebuilt.
          onError: (Object _) => _scheduleResubscribe(),
          onDone: _scheduleResubscribe,
        );
  }

  /// Backs off to a minute so a server that is genuinely down is not hammered
  /// by every open dashboard.
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

  /// Re-reads the orders without firing the new-order alert twice: whichever
  /// of the socket and the poll sees a pending order first owns the alert.
  Future<void> _reconcile() async {
    if (isClosed) return;
    try {
      final orders = await _repository.fetchVendorOrders(vendorId);
      if (isClosed) return;
      _onOrders(orders);
    } catch (_) {
      // Offline. The next tick tries again; nothing to tell the store.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the background is the moment the socket is most likely
    // to be dead and the store most likely to have missed something.
    if (state == AppLifecycleState.resumed) {
      _subscribe();
      _reconcile();
    }
  }

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
    emit(
      state.copyWith(
        loading: false,
        orders: sorted,
        newOrderArrived: hasNew,
        clearError: true,
      ),
    );

    if (_autoAccept && freshPending.isNotEmpty) {
      for (final order in sorted.where((o) => freshPending.contains(o.id))) {
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
      emit(
        state.copyWith(
          loading: false,
          orders: sorted,
          newOrderArrived: false,
          clearError: true,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          loading: false,
          error: error.toString(),
          newOrderArrived: false,
        ),
      );
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
      emit(
        state.copyWith(
          loadingHistory: false,
          hasMoreHistory: page.length == kPageSize,
          history: [
            ...state.history,
            ...page.where((o) => !known.contains(o.id)),
          ],
        ),
      );
    } catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(
          loadingHistory: false,
          error: error.toString(),
          newOrderArrived: false,
        ),
      );
    }
  }

  Future<void> accept(AppOrder order) => _update(order, OrderStatus.accepted);

  Future<void> reject(AppOrder order, String reason) =>
      _update(order, OrderStatus.rejected, reason: reason);

  Future<void> startPreparing(AppOrder order) =>
      _update(order, OrderStatus.preparing);

  Future<void> markReady(AppOrder order) =>
      _update(order, OrderStatus.readyForPickup);

  /// Closes a collection order. No driver is coming, so the store is the only
  /// party who can say the food was handed over — the server allows this
  /// transition for pickup orders only.
  Future<void> markCollected(AppOrder order) =>
      _update(order, OrderStatus.delivered);

  Future<void> _update(
    AppOrder order,
    OrderStatus status, {
    String? reason,
  }) async {
    try {
      await _repository.updateStatus(order.id, status, reason: reason);
    } catch (error) {
      emit(
        state.copyWith(
          loading: false,
          error: error.toString(),
          newOrderArrived: false,
        ),
      );
    }
  }

  @override
  Future<void> close() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _retry?.cancel();
    _subscription?.cancel();
    return super.close();
  }
}
