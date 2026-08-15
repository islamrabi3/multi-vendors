import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/vendor.dart';
import '../../core/repositories/admin_repository.dart';
import '../../core/utils/paging.dart';

enum VendorFilter { all, pending, active, suspended }

/// Wire value each tab narrows the query to (`all` fetches every state).
const _filterStatus = {
  VendorFilter.all: null,
  VendorFilter.pending: 'pending',
  VendorFilter.active: 'active',
  VendorFilter.suspended: 'suspended',
};

class AdminVendorsState extends Equatable {
  const AdminVendorsState({
    this.loading = true,
    this.vendors = const [],
    this.filter = VendorFilter.all,
    this.loadingMore = false,
    this.hasMore = true,
    this.counts = const (all: 0, pending: 0, active: 0, suspended: 0),
    this.search = '',
    this.error,
  });

  final bool loading;

  /// The pages loaded so far for the current [filter].
  final List<Vendor> vendors;
  final VendorFilter filter;
  final bool loadingMore;
  final bool hasMore;

  /// Totals straight from the server — the list is paged, so loaded rows are
  /// not a count.
  final ({int all, int pending, int active, int suspended}) counts;

  /// The active name/phone search. Applied server-side, so the tab counts
  /// above the list still describe the whole platform, not the results.
  final String search;
  final String? error;

  List<Vendor> get pending => vendors.where((v) => v.isPending).toList();
  List<Vendor> get active => vendors.where((v) => v.isApproved).toList();
  List<Vendor> get suspended => vendors.where((v) => v.isSuspended).toList();

  /// Rows are already narrowed server-side by the active tab.
  List<Vendor> get visible => vendors;

  int countFor(VendorFilter filter) => switch (filter) {
    VendorFilter.all => counts.all,
    VendorFilter.pending => counts.pending,
    VendorFilter.active => counts.active,
    VendorFilter.suspended => counts.suspended,
  };

  AdminVendorsState copyWith({
    bool? loading,
    List<Vendor>? vendors,
    VendorFilter? filter,
    bool? loadingMore,
    bool? hasMore,
    ({int all, int pending, int active, int suspended})? counts,
    String? search,
    String? error,
    bool clearError = false,
  }) => AdminVendorsState(
    loading: loading ?? this.loading,
    vendors: vendors ?? this.vendors,
    filter: filter ?? this.filter,
    loadingMore: loadingMore ?? this.loadingMore,
    hasMore: hasMore ?? this.hasMore,
    counts: counts ?? this.counts,
    search: search ?? this.search,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [
    loading,
    vendors,
    filter,
    loadingMore,
    hasMore,
    counts,
    search,
    error,
  ];
}

class AdminVendorsCubit extends Cubit<AdminVendorsState> {
  AdminVendorsCubit(this._repository) : super(const AdminVendorsState()) {
    load();
  }

  final AdminRepository _repository;

  /// Reloads the first page of the active tab (also pull-to-refresh).
  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final vendors = await _repository.fetchVendorsPage(
        limit: kPageSize,
        offset: 0,
        status: _filterStatus[state.filter],
        search: state.search,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          loading: false,
          vendors: vendors,
          hasMore: vendors.length == kPageSize,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(loading: false, error: e.toString()));
    }
    await _refreshCounts();
  }

  /// Appends the next page. Rows already held are skipped: an approval flips a
  /// store between tabs and shifts every offset, so pages can overlap.
  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    emit(state.copyWith(loadingMore: true));
    try {
      final page = await _repository.fetchVendorsPage(
        limit: kPageSize,
        offset: state.vendors.length,
        status: _filterStatus[state.filter],
        search: state.search,
      );
      if (isClosed) return;
      final known = state.vendors.map((v) => v.id).toSet();
      emit(
        state.copyWith(
          loadingMore: false,
          hasMore: page.length == kPageSize,
          vendors: [
            ...state.vendors,
            ...page.where((v) => !known.contains(v.id)),
          ],
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(loadingMore: false, error: e.toString()));
    }
  }

  Future<void> _refreshCounts() async {
    try {
      final counts = await _repository.fetchVendorCounts();
      if (isClosed) return;
      emit(state.copyWith(counts: counts));
    } catch (_) {}
  }

  /// Debounced by the caller; this just reloads the first page.
  Future<void> setSearch(String search) async {
    if (search == state.search) return;
    emit(
      state.copyWith(
        search: search,
        vendors: const [],
        hasMore: true,
        loadingMore: false,
      ),
    );
    await load();
  }

  Future<void> setFilter(VendorFilter filter) async {
    if (filter == state.filter) return;
    emit(
      state.copyWith(
        filter: filter,
        vendors: const [],
        hasMore: true,
        loadingMore: false,
      ),
    );
    await load();
  }

  Future<bool> setStatus(String vendorId, String status) async {
    try {
      await _repository.setVendorStatus(vendorId, status);
      await load();
      return true;
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
      return false;
    }
  }
}
