import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/order.dart';
import '../../../core/repositories/order_repository.dart';

class OrdersState extends Equatable {
  const OrdersState({
    this.loadingActive = true,
    this.loadingPast = false,
    this.activeOrders = const [],
    this.pastOrders = const [],
    this.hasMorePast = true,
    this.vendorLabels = const {},
  });

  final bool loadingActive;
  final bool loadingPast;
  final List<AppOrder> activeOrders;
  final List<AppOrder> pastOrders;
  final bool hasMorePast;
  final Map<String, ({String name, String? logoUrl})> vendorLabels;

  OrdersState copyWith({
    bool? loadingActive,
    bool? loadingPast,
    List<AppOrder>? activeOrders,
    List<AppOrder>? pastOrders,
    bool? hasMorePast,
    Map<String, ({String name, String? logoUrl})>? vendorLabels,
  }) =>
      OrdersState(
        loadingActive: loadingActive ?? this.loadingActive,
        loadingPast: loadingPast ?? this.loadingPast,
        activeOrders: activeOrders ?? this.activeOrders,
        pastOrders: pastOrders ?? this.pastOrders,
        hasMorePast: hasMorePast ?? this.hasMorePast,
        vendorLabels: vendorLabels ?? this.vendorLabels,
      );

  @override
  List<Object?> get props => [
        loadingActive,
        loadingPast,
        activeOrders,
        pastOrders,
        hasMorePast,
        vendorLabels,
      ];
}

class OrdersCubit extends Cubit<OrdersState> {
  OrdersCubit(this._repository) : super(const OrdersState()) {
    _activeSubscription = _repository.myActiveOrdersStream().listen(_onActiveOrders,
        onError: (_) => emit(state.copyWith(loadingActive: false)));
    loadNextPastPage();
  }

  final OrderRepository _repository;
  StreamSubscription<List<AppOrder>>? _activeSubscription;
  static const _limit = 10;

  Future<void> _onActiveOrders(List<AppOrder> orders) async {
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
    emit(state.copyWith(
      loadingActive: false,
      activeOrders: sorted,
      vendorLabels: labels,
    ));
  }

  Future<void> loadNextPastPage() async {
    if (state.loadingPast || !state.hasMorePast) return;
    emit(state.copyWith(loadingPast: true));
    try {
      final offset = state.pastOrders.length;
      final newPast = await _repository.fetchCustomerPastOrders(limit: _limit, offset: offset);
      
      var labels = state.vendorLabels;
      final missing = newPast
          .map((o) => o.vendorId)
          .where((id) => !labels.containsKey(id))
          .toSet();
      if (missing.isNotEmpty) {
        try {
          labels = {...labels, ...await _repository.vendorLabels(missing)};
        } catch (_) {}
      }

      emit(state.copyWith(
        loadingPast: false,
        pastOrders: [...state.pastOrders, ...newPast],
        hasMorePast: newPast.length == _limit,
        vendorLabels: labels,
      ));
    } catch (_) {
      emit(state.copyWith(loadingPast: false));
    }
  }

  Future<void> refresh() async {
    emit(state.copyWith(
      loadingPast: false,
      pastOrders: const [],
      hasMorePast: true,
    ));
    await loadNextPastPage();
  }

  @override
  Future<void> close() {
    _activeSubscription?.cancel();
    return super.close();
  }
}
