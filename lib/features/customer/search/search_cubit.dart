import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/product.dart' show ProductHit;
import '../../../core/models/vendor.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/repositories/favorites_repository.dart';

/// What the results pane is currently showing.
///
/// Distinguishing "nothing typed yet" from "typed and found nothing" matters:
/// the first is a blank slate that should offer recent searches, the second is
/// a dead end that should say so.
enum SearchStage { idle, searching, results, empty }

class SearchState extends Equatable {
  const SearchState({
    this.query = '',
    this.stage = SearchStage.idle,
    this.vendors = const [],
    this.products = const [],
    this.menuMatches = const {},
    this.recent = const [],
    this.favoriteVendorIds = const {},
    this.error,
  });

  final String query;
  final SearchStage stage;

  final List<Vendor> vendors;
  final List<ProductHit> products;

  /// Store id to the item names that matched — what explains a store appearing
  /// in results its own name has nothing to do with.
  final Map<String, List<String>> menuMatches;

  /// Previous queries, most recent first.
  final List<String> recent;

  /// Fetched once for the page rather than per card: the results are a list,
  /// and a card that asked for its own heart would fire one request per row.
  final Set<String> favoriteVendorIds;

  final String? error;

  bool get hasResults => vendors.isNotEmpty || products.isNotEmpty;

  SearchState copyWith({
    String? query,
    SearchStage? stage,
    List<Vendor>? vendors,
    List<ProductHit>? products,
    Map<String, List<String>>? menuMatches,
    List<String>? recent,
    Set<String>? favoriteVendorIds,
    String? error,
    bool clearError = false,
  }) => SearchState(
    query: query ?? this.query,
    stage: stage ?? this.stage,
    vendors: vendors ?? this.vendors,
    products: products ?? this.products,
    menuMatches: menuMatches ?? this.menuMatches,
    recent: recent ?? this.recent,
    favoriteVendorIds: favoriteVendorIds ?? this.favoriteVendorIds,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [
    query,
    stage,
    vendors,
    products,
    menuMatches,
    recent,
    favoriteVendorIds,
    error,
  ];
}

/// The search page's own state.
///
/// Search used to run inside [HomeCubit], which meant every keystroke rebuilt
/// the whole home page — banners, category rail, promoted rails and all — and
/// the results landed *underneath* three sections the customer had to scroll
/// past. Here it owns nothing but the query and its answers, so typing repaints
/// a list and nothing else.
class SearchCubit extends Cubit<SearchState> {
  SearchCubit(this._catalog, this._favorites) : super(const SearchState()) {
    _loadRecent();
    _loadFavorites();
  }

  final CatalogRepository _catalog;
  final FavoritesRepository _favorites;

  Timer? _debounce;

  /// Guards against an out-of-order answer: a slow request for "bur" must not
  /// overwrite the results for "burger" typed after it.
  int _requestId = 0;

  static const _recentKey = 'search_recent';
  static const _maxRecent = 8;

  /// Below the point a search feels laggy, well above a fast typist's gap
  /// between letters. Each run is two round trips.
  static const _debounceDelay = Duration(milliseconds: 300);

  Future<void> _loadRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (isClosed) return;
      emit(state.copyWith(recent: prefs.getStringList(_recentKey) ?? const []));
    } catch (_) {
      // A missing history is not worth telling anyone about.
    }
  }

  Future<void> _loadFavorites() async {
    try {
      final ids = await _favorites.fetchFavoriteVendorIds();
      if (isClosed) return;
      emit(state.copyWith(favoriteVendorIds: ids));
    } catch (_) {
      // The hearts stay hollow rather than the page failing over a decoration.
    }
  }

  /// Optimistic: the heart fills on tap and rolls back if the write fails, so
  /// the control never sits there doing nothing while a request is in flight.
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

  void setQuery(String query) {
    emit(
      state.copyWith(
        query: query,
        // An empty box is the blank slate again, not "no results" — and it
        // must cancel whatever was in flight, or the last answer lands on it.
        stage: query.trim().isEmpty ? SearchStage.idle : SearchStage.searching,
        clearError: true,
      ),
    );
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      _requestId++;
      emit(
        state.copyWith(
          vendors: const [],
          products: const [],
          menuMatches: const {},
        ),
      );
      return;
    }
    _debounce = Timer(_debounceDelay, () => _run(query));
  }

  /// Runs immediately, skipping the debounce — for the keyboard's search key
  /// and for tapping a recent term, where the customer has already committed.
  Future<void> submit(String query) async {
    _debounce?.cancel();
    emit(
      state.copyWith(
        query: query,
        stage: SearchStage.searching,
        clearError: true,
      ),
    );
    await _run(query);
  }

  Future<void> _run(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return;
    final id = ++_requestId;

    try {
      // Stores and dishes together: somebody typing "kofta" wants both "who
      // sells it" and "which one", and two sequential trips would show the
      // first list settle and then jump.
      final results = await Future.wait([
        _catalog.searchVendors(query: query),
        _catalog.searchProducts(query),
      ]);
      if (isClosed || id != _requestId) return;

      final vendorResult =
          results[0] as ({List<Vendor> vendors, Map<String, List<String>> matches});
      final products = results[1] as List<ProductHit>;
      final found = vendorResult.vendors.isNotEmpty || products.isNotEmpty;

      emit(
        state.copyWith(
          stage: found ? SearchStage.results : SearchStage.empty,
          vendors: vendorResult.vendors,
          products: products,
          menuMatches: vendorResult.matches,
        ),
      );
      // Only remembered once it found something: a half-typed word that
      // matched nothing is not a search anyone wants to repeat.
      if (found) unawaited(_remember(query));
    } catch (error) {
      if (isClosed || id != _requestId) return;
      emit(state.copyWith(stage: SearchStage.empty, error: error.toString()));
    }
  }

  Future<void> _remember(String query) async {
    final next = [
      query,
      ...state.recent.where((q) => q.toLowerCase() != query.toLowerCase()),
    ].take(_maxRecent).toList();
    if (!isClosed) emit(state.copyWith(recent: next));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentKey, next);
    } catch (_) {}
  }

  Future<void> clearRecent() async {
    emit(state.copyWith(recent: const []));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentKey);
    } catch (_) {}
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
