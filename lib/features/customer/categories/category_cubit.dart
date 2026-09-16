import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/vendor.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/repositories/favorites_repository.dart';

class CategoryState extends Equatable {
  const CategoryState({
    this.loading = true,
    this.error,
    this.category,
    this.children = const [],
    this.recommended = const [],
    this.vendors = const [],
    this.favoriteVendorIds = const {},
    this.openOnly = false,
    this.selectedChildId,
    this.categoryId = '',
  });

  /// The page's own category id, needed to tell its picks from its
  /// sub-categories'.
  final String categoryId;

  final bool loading;
  final String? error;

  /// Null until the category row lands, and null forever if the id is stale —
  /// which the screen shows as "not found" rather than an empty list.
  final VendorCategory? category;

  /// The level below this one. Empty on a leaf category, which is what turns
  /// the page from a directory into a plain store list.
  final List<VendorCategory> children;

  /// Every category's admin picks, filtered to this page in
  /// [recommendedVisible].
  final List<({String categoryId, int rank, Vendor vendor})> recommended;

  /// Every store filed under this category or any of its children.
  final List<Vendor> vendors;

  final Set<String> favoriteVendorIds;
  final bool openOnly;

  /// Which sub-category the customer has narrowed to, or null for "everything
  /// under this parent". Narrowing filters the list already on screen rather
  /// than opening another page: the sub-categories are a filter bar, and
  /// pushing a route for one buried the customer a level deeper for a change
  /// they can already see the result of.
  final String? selectedChildId;

  /// The name of whatever is currently being shown, for the section header.
  VendorCategory? get selectedChild {
    for (final child in children) {
      if (child.id == selectedChildId) return child;
    }
    return null;
  }

  List<Vendor> get visibleVendors {
    // [vendors] already holds every store under the parent *and* its children,
    // so narrowing is a local filter — no round trip, and clearing it restores
    // the list instantly.
    final child = selectedChildId;
    final scoped = child == null
        ? vendors
        : vendors.where((v) => v.categoryId == child).toList();
    return openOnly ? scoped.where((v) => v.isOpenNow()).toList() : scoped;
  }

  /// The recommended row for what is on screen.
  ///
  /// On "All" it gathers every recommended store in this category: the picks
  /// made for the category itself, the picks made for each of its
  /// sub-categories, and stores the admin recommended overall that are filed
  /// here. With a sub-category selected it is the same, narrowed to that
  /// sub-category. Only stores an admin chose, never filler.
  List<Vendor> get recommendedVisible {
    final child = selectedChildId;
    final scopeIds = child == null
        ? {categoryId, for (final c in children) c.id}
        : {child};
    final inScope = child == null
        ? vendors
        : vendors.where((v) => v.categoryId == child).toList();
    final inScopeIds = {for (final v in inScope) v.id};

    final picks =
        recommended
            .where(
              (p) =>
                  scopeIds.contains(p.categoryId) ||
                  // A pick made on the parent still shows under the
                  // sub-category its store belongs to.
                  (child != null &&
                      p.categoryId == categoryId &&
                      inScopeIds.contains(p.vendor.id)),
            )
            .toList()
          ..sort((a, b) {
            // The page's own picks lead, then its sub-categories'.
            final aOwn = a.categoryId == (child ?? categoryId) ? 0 : 1;
            final bOwn = b.categoryId == (child ?? categoryId) ? 0 : 1;
            if (aOwn != bOwn) return aOwn - bOwn;
            return a.rank.compareTo(b.rank);
          });

    final overall = inScope.where((v) => v.isRecommended).toList()
      ..sort((a, b) => a.recommendedRank.compareTo(b.recommendedRank));

    final seen = <String>{};
    return [
      for (final v in [for (final p in picks) p.vendor, ...overall])
        if (seen.add(v.id)) v,
    ];
  }

  bool get isLeaf => children.isEmpty;

  CategoryState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    VendorCategory? category,
    List<VendorCategory>? children,
    List<({String categoryId, int rank, Vendor vendor})>? recommended,
    List<Vendor>? vendors,
    Set<String>? favoriteVendorIds,
    bool? openOnly,
    String? selectedChildId,
    bool clearSelectedChild = false,
  }) => CategoryState(
    categoryId: categoryId,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    category: category ?? this.category,
    children: children ?? this.children,
    recommended: recommended ?? this.recommended,
    vendors: vendors ?? this.vendors,
    favoriteVendorIds: favoriteVendorIds ?? this.favoriteVendorIds,
    openOnly: openOnly ?? this.openOnly,
    selectedChildId: clearSelectedChild
        ? null
        : (selectedChildId ?? this.selectedChildId),
  );

  @override
  List<Object?> get props => [
    loading,
    error,
    category,
    children,
    recommended,
    vendors,
    favoriteVendorIds,
    openOnly,
    selectedChildId,
    categoryId,
  ];
}

/// One category page: its sub-categories, the admin's picks for it, and every
/// store under it.
///
/// The three fetches go out together and a failure in the recommendations does
/// not blank the page — a promo rail is a decoration on a store list, and
/// losing it must not cost the customer the list.
class CategoryCubit extends Cubit<CategoryState> {
  CategoryCubit(this._catalog, this._favorites, this.categoryId)
    : super(CategoryState(categoryId: categoryId)) {
    load();
    _loadFavorites();
  }

  final CatalogRepository _catalog;
  final FavoritesRepository _favorites;
  final String categoryId;

  static const _fetchTimeout = Duration(seconds: 20);

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      // The picks go out with the page, not after it. Fetched second, they
      // landed a beat after the store list and the rail pushed every card
      // down under the customer's thumb. A failure still costs only the rail.
      final results = await Future.wait<Object>([
        _catalog.fetchVendorCategories(),
        _catalog.fetchVendorsInCategory(categoryId),
        _catalog.fetchAllCategoryRecommendations().then<Object>(
          (v) => v,
          onError: (_) =>
              const <({String categoryId, int rank, Vendor vendor})>[],
        ),
      ]).timeout(_fetchTimeout);
      if (isClosed) return;

      final categories = results[0] as List<VendorCategory>;
      final vendors = results[1] as List<Vendor>;
      final recommended =
          results[2] as List<({String categoryId, int rank, Vendor vendor})>;
      VendorCategory? category;
      for (final c in categories) {
        if (c.id == categoryId) category = c;
      }
      final children =
          categories.where((c) => c.parentId == categoryId).toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      emit(
        state.copyWith(
          loading: false,
          category: category,
          children: children,
          vendors: vendors,
          recommended: recommended,
        ),
      );
    } catch (error) {
      if (isClosed) return;
      emit(state.copyWith(loading: false, error: error.toString()));
    }
  }

  /// Narrows the list to one sub-category, or clears back to everything under
  /// the parent when [childId] is null or is the one already selected.
  ///
  /// The stores are filtered locally — they were all fetched with the page —
  /// so the list and the recommended row change on the same frame as the tap.
  void selectChild(String? childId) {
    final next = childId == state.selectedChildId ? null : childId;
    emit(
      next == null
          ? state.copyWith(clearSelectedChild: true)
          : state.copyWith(selectedChildId: next),
    );
  }

  Future<void> _loadFavorites() async {
    try {
      final ids = await _favorites.fetchFavoriteVendorIds();
      if (isClosed) return;
      emit(state.copyWith(favoriteVendorIds: ids));
    } catch (_) {}
  }

  void setOpenOnly(bool value) => emit(state.copyWith(openOnly: value));

  /// Optimistic: the heart fills on tap and rolls back if the write fails.
  Future<void> toggleFavorite(String vendorId) async {
    final wasFavorite = state.favoriteVendorIds.contains(vendorId);
    final next = {...state.favoriteVendorIds};
    if (wasFavorite) {
      next.remove(vendorId);
    } else {
      next.add(vendorId);
    }
    emit(state.copyWith(favoriteVendorIds: next));
    try {
      await _favorites.setFavorite(vendorId, !wasFavorite);
    } catch (_) {
      if (isClosed) return;
      final rolledBack = {...state.favoriteVendorIds};
      if (wasFavorite) {
        rolledBack.add(vendorId);
      } else {
        rolledBack.remove(vendorId);
      }
      emit(state.copyWith(favoriteVendorIds: rolledBack));
    }
  }
}
