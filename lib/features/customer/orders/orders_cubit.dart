import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/order.dart';
import '../../../core/repositories/order_repository.dart';

class OrdersState extends Equatable {
  const OrdersState({
    this.loading = true,
    this.orders = const [],
    this.vendorLabels = const {},
  });

  final bool loading;
  final List<AppOrder> orders;
  final Map<String, ({String name, String? logoUrl})> vendorLabels;

  @override
  List<Object?> get props => [loading, orders, vendorLabels];
}

/// Realtime list of the customer's orders, enriched with vendor name/logo
/// (realtime streams cannot embed joins).
class OrdersCubit extends Cubit<OrdersState> {
  OrdersCubit(this._repository) : super(const OrdersState()) {
    _subscription = _repository.myOrdersStream().listen(_onOrders,
        onError: (_) => emit(const OrdersState(loading: false)));
  }

  final OrderRepository _repository;
  StreamSubscription<List<AppOrder>>? _subscription;

  Future<void> _onOrders(List<AppOrder> orders) async {
    final sorted = List<AppOrder>.of(orders)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    var labels = state.vendorLabels;
    final missing = sorted
        .map((o) => o.vendorId)
        .where((id) => !labels.containsKey(id))
        .toSet();
    if (missing.isNotEmpty) {
      try {
        labels = {...labels, ...await _repository.vendorLabels(missing)};
      } catch (_) {}
    }
    emit(OrdersState(loading: false, orders: sorted, vendorLabels: labels));
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
