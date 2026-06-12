import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/order.dart';
import '../../core/repositories/order_repository.dart';

class VendorOrdersState extends Equatable {
  const VendorOrdersState({
    this.loading = true,
    this.orders = const [],
    this.error,
    this.newOrderArrived = false,
  });

  final bool loading;
  final List<AppOrder> orders;
  final String? error;

  /// Pulses true when a new pending order lands, so the UI can alert.
  final bool newOrderArrived;

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

  @override
  List<Object?> get props => [loading, orders, error, newOrderArrived];
}

/// Realtime feed of the vendor's orders, partitioned for the dashboard.
class VendorOrdersCubit extends Cubit<VendorOrdersState> {
  VendorOrdersCubit(this._repository, this.vendorId)
      : super(const VendorOrdersState()) {
    _subscription =
        _repository.vendorOrdersStream(vendorId).listen(_onOrders,
            onError: (Object error) => emit(VendorOrdersState(
                loading: false, error: error.toString())));
  }

  final OrderRepository _repository;
  final String vendorId;
  StreamSubscription<List<AppOrder>>? _subscription;
  Set<String> _knownPendingIds = {};

  void _onOrders(List<AppOrder> orders) {
    final sorted = List<AppOrder>.of(orders)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final pendingIds = sorted
        .where((o) => o.status == OrderStatus.pending)
        .map((o) => o.id)
        .toSet();
    final hasNew =
        !state.loading && pendingIds.difference(_knownPendingIds).isNotEmpty;
    _knownPendingIds = pendingIds;
    emit(VendorOrdersState(
        loading: false, orders: sorted, newOrderArrived: hasNew));
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
      emit(VendorOrdersState(
          loading: false, orders: state.orders, error: error.toString()));
    }
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
