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
    this.error,
    this.claimedOrderId,
  });

  final bool loading;
  final bool isOnline;
  final List<AppOrder> orders;
  final Map<String, ({String name, String? logoUrl})> vendorLabels;
  final String? error;

  /// Set when a claim succeeds so the UI can navigate to the active tab.
  final String? claimedOrderId;

  DriverPoolState copyWith({
    bool? loading,
    bool? isOnline,
    List<AppOrder>? orders,
    Map<String, ({String name, String? logoUrl})>? vendorLabels,
    String? error,
    String? claimedOrderId,
    bool clearTransient = false,
  }) =>
      DriverPoolState(
        loading: loading ?? this.loading,
        isOnline: isOnline ?? this.isOnline,
        orders: orders ?? this.orders,
        vendorLabels: vendorLabels ?? this.vendorLabels,
        error: clearTransient ? null : error,
        claimedOrderId: clearTransient ? null : claimedOrderId,
      );

  @override
  List<Object?> get props =>
      [loading, isOnline, orders, vendorLabels, error, claimedOrderId];
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

  Future<void> _init() async {
    try {
      final online = await _driver.fetchIsOnline();
      emit(state.copyWith(loading: false, isOnline: online));
      if (online) _listen();
    } catch (_) {
      emit(state.copyWith(loading: false));
    }
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
      } else {
        await _subscription?.cancel();
        _subscription = null;
        emit(state.copyWith(orders: const []));
      }
    } catch (error) {
      emit(state.copyWith(isOnline: !online, error: error.toString()));
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
    return super.close();
  }
}
