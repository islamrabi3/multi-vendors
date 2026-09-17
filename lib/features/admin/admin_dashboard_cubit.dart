import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/finance.dart';
import '../../core/models/order.dart';
import '../../core/repositories/admin_repository.dart';
import '../../core/repositories/finance_repository.dart';
import '../../core/utils/live_feed.dart';

class AdminDashboardState extends Equatable {
  const AdminDashboardState({
    this.loading = true,
    this.stats = const AdminStats(),
    this.liveOrders = const [],
    this.vendorLabels = const {},
    this.today,
    this.vendorBalances = const [],
    this.driverBalances = const [],
    this.moneyDenied = false,
    this.error,
  });

  final bool loading;
  final AdminStats stats;

  /// Most recent non-terminal orders for the "Live orders" feed.
  final List<AppOrder> liveOrders;
  final Map<String, ({String name, String? logoUrl})> vendorLabels;

  /// Today's takings and what the platform kept of them. Null until the first
  /// read finishes, or when this admin may not see money at all.
  final FinanceOverview? today;

  /// What each store and each rider is owed, newest balance first. Not
  /// today's figures: what somebody is owed is everything not yet settled,
  /// and paying them today's share alone would be wrong.
  final List<PartyBalance> vendorBalances;
  final List<PartyBalance> driverBalances;

  /// This admin has no reports permission; the money panel stays off rather
  /// than showing an error where the numbers would be.
  final bool moneyDenied;
  final String? error;

  AdminDashboardState copyWith({
    bool? loading,
    AdminStats? stats,
    List<AppOrder>? liveOrders,
    Map<String, ({String name, String? logoUrl})>? vendorLabels,
    FinanceOverview? today,
    List<PartyBalance>? vendorBalances,
    List<PartyBalance>? driverBalances,
    bool? moneyDenied,
    String? error,
    bool clearError = false,
  }) => AdminDashboardState(
    loading: loading ?? this.loading,
    stats: stats ?? this.stats,
    liveOrders: liveOrders ?? this.liveOrders,
    vendorLabels: vendorLabels ?? this.vendorLabels,
    today: today ?? this.today,
    vendorBalances: vendorBalances ?? this.vendorBalances,
    driverBalances: driverBalances ?? this.driverBalances,
    moneyDenied: moneyDenied ?? this.moneyDenied,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [
    loading,
    stats,
    liveOrders,
    vendorLabels,
    today,
    vendorBalances,
    driverBalances,
    moneyDenied,
    error,
  ];
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
  final _finance = FinanceRepository();
  late final LiveFeed<List<AppOrder>> _feed;

  Future<void> refreshStats() async {
    try {
      final stats = await _repository.fetchStats();
      emit(state.copyWith(stats: stats, clearError: true));
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
    await refreshMoney();
  }

  /// Today's money, and who is owed what.
  ///
  /// Three reads rather than one: the day's takings are a period, while what a
  /// store or a rider is owed is a running balance that has nothing to do with
  /// today. Conflating them would have the operator pay a shop its lunchtime
  /// share and think the account was clear.
  ///
  /// A failure here never disturbs the board: the live orders are the reason
  /// this screen is open, and money is what it also happens to show.
  Future<void> refreshMoney() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    try {
      final results = await Future.wait([
        _finance.overview(start: startOfDay, end: now),
        _finance.vendorBalances(),
        _finance.driverBalances(),
      ]);
      if (isClosed) return;
      emit(
        state.copyWith(
          today: results[0] as FinanceOverview,
          vendorBalances: (results[1] as List<PartyBalance>)
              .where((party) => party.payable > 0)
              .toList(),
          driverBalances: results[2] as List<PartyBalance>,
          moneyDenied: false,
        ),
      );
    } catch (error) {
      if (isClosed) return;
      // A Finance-less admin role is refused by the RPC itself; that is not an
      // error to shout about, it is a panel this person does not get.
      if ('$error'.contains('FORBIDDEN')) {
        emit(state.copyWith(moneyDenied: true));
      }
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
