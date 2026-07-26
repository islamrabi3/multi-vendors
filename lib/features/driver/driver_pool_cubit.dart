import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/order.dart';
import '../../core/repositories/driver_repository.dart';
import '../../core/repositories/order_repository.dart';

class DriverPoolState extends Equatable {
  const DriverPoolState({
    this.loading = true,
    this.isOnline = false,
    this.orders = const [],
    this.vendorLabels = const {},
    this.todayEarnings = 0,
    this.todayTrips = 0,
    this.error,
    this.claimedOrderId,
  });

  final bool loading;
  final bool isOnline;
  final List<AppOrder> orders;
  final Map<String, ({String name, String? logoUrl})> vendorLabels;

  /// Delivery-fee payouts for orders delivered today.
  final double todayEarnings;
  final int todayTrips;
  final String? error;

  /// Set when a claim succeeds so the UI can navigate to the active tab.
  final String? claimedOrderId;

  DriverPoolState copyWith({
    bool? loading,
    bool? isOnline,
    List<AppOrder>? orders,
    Map<String, ({String name, String? logoUrl})>? vendorLabels,
    double? todayEarnings,
    int? todayTrips,
    String? error,
    String? claimedOrderId,
    bool clearTransient = false,
  }) =>
      DriverPoolState(
        loading: loading ?? this.loading,
        isOnline: isOnline ?? this.isOnline,
        orders: orders ?? this.orders,
        vendorLabels: vendorLabels ?? this.vendorLabels,
        todayEarnings: todayEarnings ?? this.todayEarnings,
        todayTrips: todayTrips ?? this.todayTrips,
        error: clearTransient ? null : error,
        claimedOrderId: clearTransient ? null : claimedOrderId,
      );

  @override
  List<Object?> get props => [
        loading,
        isOnline,
        orders,
        vendorLabels,
        todayEarnings,
        todayTrips,
        error,
        claimedOrderId,
      ];
}

/// Online/offline presence plus the realtime pool of unclaimed
/// ready_for_pickup orders (only streamed while online — RLS hides the pool
/// from offline drivers anyway).
class DriverPoolCubit extends Cubit<DriverPoolState> {
  DriverPoolCubit(this._orders, this._driver)
      : super(const DriverPoolState()) {
    _init();
  }

  final OrderRepository _orders;
  final DriverRepository _driver;
  StreamSubscription<List<AppOrder>>? _subscription;
  StreamSubscription<List<AppOrder>>? _mySubscription;
  Timer? _refreshTimer;

  Future<void> _init() async {
    _mySubscription = _orders.driverOrdersStream().listen(_onMyOrders,
        onError: (Object _) {});
    try {
      final online = await _driver.fetchIsOnline();
      emit(state.copyWith(loading: false, isOnline: online));
      if (online) {
        _listen();
        _startTimer();
      }
    } catch (_) {
      emit(state.copyWith(loading: false));
    }
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (state.isOnline) {
        refresh();
      }
    });
  }

  void _stopTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _onMyOrders(List<AppOrder> orders) {
    final now = DateTime.now();
    final today = orders.where((o) =>
        o.status == OrderStatus.delivered &&
        o.createdAt.year == now.year &&
        o.createdAt.month == now.month &&
        o.createdAt.day == now.day);
    // clearTransient so a consumed claim/error doesn't re-fire the listener.
    emit(state.copyWith(
      todayEarnings: today.fold<double>(0, (sum, o) => sum + o.deliveryFee),
      todayTrips: today.length,
      clearTransient: true,
    ));
  }

  void _listen() {
    _subscription?.cancel();
    _subscription = _orders.driverPoolStream().listen(_onOrders,
        onError: (Object error) =>
            emit(state.copyWith(error: error.toString())));
  }

  Future<void> _onOrders(List<AppOrder> orders) async {
    var labels = state.vendorLabels;
    final missing = orders
        .map((o) => o.vendorId)
        .where((id) => !labels.containsKey(id))
        .toSet();
    if (missing.isNotEmpty) {
      try {
        labels = {...labels, ...await _orders.vendorLabels(missing)};
      } catch (_) {}
    }
    emit(state.copyWith(
        orders: orders, vendorLabels: labels, clearTransient: true));
  }

  Future<void> setOnline(bool online) async {
    emit(state.copyWith(isOnline: online, clearTransient: true));
    try {
      await _driver.setOnline(online);
      if (online) {
        _listen();
        _startTimer();
      } else {
        await _subscription?.cancel();
        _subscription = null;
        _stopTimer();
        emit(state.copyWith(orders: const []));
      }
    } catch (error) {
      emit(state.copyWith(isOnline: !online, error: error.toString()));
    }
  }

  /// Pull-to-refresh: re-check presence and re-fetch the pool once, in case a
  /// realtime event was missed. Also (re)starts the live subscription.
  Future<void> refresh() async {
    try {
      final online = await _driver.fetchIsOnline();
      if (!online) {
        await _subscription?.cancel();
        _subscription = null;
        _stopTimer();
        emit(state.copyWith(
            isOnline: false, orders: const [], clearTransient: true));
        return;
      }
      final orders = await _orders.fetchDriverPool();
      final labels = {
        ...state.vendorLabels,
        for (final o in orders)
          if (o.vendorName != null)
            o.vendorId: (name: o.vendorName!, logoUrl: o.vendorLogoUrl),
      };
      emit(state.copyWith(
          isOnline: true,
          orders: orders,
          vendorLabels: labels,
          clearTransient: true));
      if (_subscription == null) _listen();
    } catch (error) {
      emit(state.copyWith(error: error.toString()));
    }
  }

  Future<void> claim(AppOrder order) async {
    try {
      final won = await _orders.claimDelivery(order.id);
      if (won) {
        emit(state.copyWith(claimedOrderId: order.id));
      } else {
        emit(state.copyWith(
            error: 'Another driver took this order.',
            orders: state.orders.where((o) => o.id != order.id).toList()));
      }
    } catch (error) {
      emit(state.copyWith(error: error.toString()));
    }
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    _mySubscription?.cancel();
    _stopTimer();
    return super.close();
  }
}
