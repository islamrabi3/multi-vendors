import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/order.dart';
import '../../core/repositories/admin_repository.dart';
import '../../core/utils/live_feed.dart';

class AdminDashboardState extends Equatable {
  const AdminDashboardState({
    this.loading = true,
    this.stats = const AdminStats(),
    this.liveOrders = const [],
    this.vendorLabels = const {},
    this.error,
  });

  final bool loading;
  final AdminStats stats;

  /// Most recent non-terminal orders for the "Live orders" feed.
  final List<AppOrder> liveOrders;
  final Map<String, ({String name, String? logoUrl})> vendorLabels;
  final String? error;

  AdminDashboardState copyWith({
    bool? loading,
    AdminStats? stats,
    List<AppOrder>? liveOrders,
    Map<String, ({String name, String? logoUrl})>? vendorLabels,
    String? error,
    bool clearError = false,
  }) => AdminDashboardState(
    loading: loading ?? this.loading,
    stats: stats ?? this.stats,
    liveOrders: liveOrders ?? this.liveOrders,
    vendorLabels: vendorLabels ?? this.vendorLabels,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [loading, stats, liveOrders, vendorLabels, error];
}

/// Control-room feed: headline stats (RPC) plus a realtime stream of live
/// orders, refreshed together.
/// The overview's live board.
///
/// Same rules as the orders screen: a socket that quietly dies must not leave
/// an operator looking at an order that was delivered half an hour ago.
class AdminDashboardCubit extends Cubit<AdminDashboardState> {
  AdminDashboardCubit(this._repository) : super(const AdminDashboardState()) {
    _feed = LiveFeed<List<AppOrder>>(
      stream: _repository.liveOrdersStream,
      fetch: _repository.fetchLiveOrders,
      onData: (orders) {
        if (!isClosed) _onOrders(orders);
      },
    )..start();
    refreshStats();
  }

  final AdminRepository _repository;
  late final LiveFeed<List<AppOrder>> _feed;

  Future<void> refreshStats() async {
    try {
      final stats = await _repository.fetchStats();
      emit(state.copyWith(stats: stats, clearError: true));
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onOrders(List<AppOrder> orders) async {
    final live = orders.where((o) => !o.status.isTerminal).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final top = live.take(15).toList();

    var labels = state.vendorLabels;
    final missing = top
        .map((o) => o.vendorId)
        .where((id) => !labels.containsKey(id))
        .toSet();
    if (missing.isNotEmpty) {
      try {
        labels = {...labels, ...await _repository.vendorLabels(missing)};
      } catch (_) {}
    }
    emit(state.copyWith(loading: false, liveOrders: top, vendorLabels: labels));
    // Keep headline counters in sync as orders move.
    refreshStats();
  }

  @override
  Future<void> close() {
    _feed.dispose();
    return super.close();
  }
}
