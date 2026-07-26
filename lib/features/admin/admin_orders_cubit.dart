import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/order.dart';
import '../../core/repositories/admin_repository.dart';

enum OrderMonitorFilter { all, flagged, preparing, onTheWay }

/// An order is "flagged" when it has been sitting in a non-terminal state past
/// the platform SLA (stuck vendor / no driver).
const _stuckAfter = Duration(minutes: 20);

class AdminOrdersState extends Equatable {
  const AdminOrdersState({
    this.loading = true,
    this.orders = const [],
    this.vendorLabels = const {},
    this.filter = OrderMonitorFilter.all,
    this.error,
  });

  final bool loading;
  final List<AppOrder> orders;
  final Map<String, ({String name, String? logoUrl})> vendorLabels;
  final OrderMonitorFilter filter;
  final String? error;

  static bool isFlagged(AppOrder o) =>
      !o.status.isTerminal &&
      o.status != OrderStatus.outForDelivery &&
      DateTime.now().difference(o.createdAt) > _stuckAfter;

  int get liveCount => orders.where((o) => !o.status.isTerminal).length;
  int get flaggedCount => orders.where(isFlagged).length;

  List<AppOrder> get visible {
    final list = switch (filter) {
      OrderMonitorFilter.all => orders,
      OrderMonitorFilter.flagged => orders.where(isFlagged).toList(),
      OrderMonitorFilter.preparing => orders
          .where((o) =>
              o.status == OrderStatus.accepted ||
              o.status == OrderStatus.preparing ||
              o.status == OrderStatus.readyForPickup)
          .toList(),
      OrderMonitorFilter.onTheWay =>
        orders.where((o) => o.status == OrderStatus.outForDelivery).toList(),
    };
    return list..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  AdminOrdersState copyWith({
    bool? loading,
    List<AppOrder>? orders,
    Map<String, ({String name, String? logoUrl})>? vendorLabels,
    OrderMonitorFilter? filter,
    String? error,
    bool clearError = false,
  }) =>
      AdminOrdersState(
        loading: loading ?? this.loading,
        orders: orders ?? this.orders,
        vendorLabels: vendorLabels ?? this.vendorLabels,
        filter: filter ?? this.filter,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  List<Object?> get props => [loading, orders, vendorLabels, filter, error];
}

/// Realtime monitor of every order on the platform.
class AdminOrdersCubit extends Cubit<AdminOrdersState> {
  AdminOrdersCubit(this._repository) : super(const AdminOrdersState()) {
    _subscription = _repository.allOrdersStream().listen(_onOrders,
        onError: (Object e) =>
            emit(state.copyWith(loading: false, error: e.toString())));
  }

  final AdminRepository _repository;
  StreamSubscription<List<AppOrder>>? _subscription;

  Future<void> _onOrders(List<AppOrder> orders) async {
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
    emit(state.copyWith(loading: false, orders: orders, vendorLabels: labels));
  }

  void setFilter(OrderMonitorFilter filter) =>
      emit(state.copyWith(filter: filter));

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
