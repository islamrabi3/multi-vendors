import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/address.dart';
import '../../../core/models/banner_item.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/address_repository.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/repositories/favorites_repository.dart';

/// How the store list is ordered. `recommended` is the server's own order
/// (open first, then rating), which is what the list shows before the customer
/// expresses a preference.
enum VendorSort { recommended, rating, deliveryFee, prepTime }

/// The customer's store filters. Sorting and the toggles are applied on the
/// already-fetched list: the result set is one page of nearby stores, so
/// re-querying per toggle would cost a round trip and gain nothing.
class VendorFilters extends Equatable {
  const VendorFilters({
    this.sort = VendorSort.recommended,
    this.openOnly = false,
    this.freeDeliveryOnly = false,
    this.favoritesOnly = false,
    this.maxDeliveryFee,
    this.minRating,
  });

  final VendorSort sort;
  final bool openOnly;
  final bool freeDeliveryOnly;
  final bool favoritesOnly;

  /// Null means "any". Both are inclusive bounds.
  final double? maxDeliveryFee;
  final double? minRating;

  /// How many filters the customer has actually set — drives the badge on the
  /// filter button, so `recommended` and "no toggles" read as unfiltered.
  int get activeCount => [
        sort != VendorSort.recommended,
        openOnly,
        freeDeliveryOnly,
        favoritesOnly,
        maxDeliveryFee != null,
        minRating != null,
      ].where((on) => on).length;

  VendorFilters copyWith({
    VendorSort? sort,
    bool? openOnly,
    bool? freeDeliveryOnly,
    bool? favoritesOnly,
    double? maxDeliveryFee,
    double? minRating,
    bool clearMaxDeliveryFee = false,
    bool clearMinRating = false,
  }) =>
      VendorFilters(
        sort: sort ?? this.sort,
        openOnly: openOnly ?? this.openOnly,
        freeDeliveryOnly: freeDeliveryOnly ?? this.freeDeliveryOnly,
        favoritesOnly: favoritesOnly ?? this.favoritesOnly,
        maxDeliveryFee: clearMaxDeliveryFee
            ? null
            : (maxDeliveryFee ?? this.maxDeliveryFee),
        minRating: clearMinRating ? null : (minRating ?? this.minRating),
      );

  @override
  List<Object?> get props => [
        sort,
        openOnly,
        freeDeliveryOnly,
        favoritesOnly,
        maxDeliveryFee,
        minRating,
      ];
}

class HomeState extends Equatable {
  const HomeState({
    this.loading = true,
    this.error,
    this.banners = const [],
    this.categories = const [],
    this.vendors = const [],
    this.selectedCategoryId,
    this.search = '',
    this.deliverToAddress,
    this.addressLoaded = false,
    this.favoriteVendorIds = const {},
    this.filters = const VendorFilters(),
  });

  final bool loading;
  final String? error;
  final List<BannerItem> banners;
  final List<VendorCategory> categories;
  final List<Vendor> vendors;
  final String? selectedCategoryId;
  final String search;

  /// The address this order would go to — the user's default, or their most
  /// recent if none is flagged default. Null once [addressLoaded] means "the
  /// user genuinely has no address yet", which is a prompt, not a placeholder.
  final Address? deliverToAddress;
  final bool addressLoaded;

  final Set<String> favoriteVendorIds;
  final VendorFilters filters;

  /// The list the customer actually sees: [vendors] narrowed by [filters] and
  /// ordered by the chosen sort. Kept as a getter so the raw fetch result stays
  /// intact and clearing a filter never needs a refetch.
  List<Vendor> get visibleVendors {
    final result = vendors.where((v) {
      if (filters.openOnly && !v.isOpen) return false;
      if (filters.freeDeliveryOnly && v.deliveryFee > 0) return false;
      if (filters.favoritesOnly && !favoriteVendorIds.contains(v.id)) {
        return false;
      }
      final maxFee = filters.maxDeliveryFee;
      if (maxFee != null && v.deliveryFee > maxFee) return false;
      final minRating = filters.minRating;
      if (minRating != null && v.ratingAvg < minRating) return false;
      return true;
    }).toList();

    switch (filters.sort) {
      case VendorSort.recommended:
        break; // Already open-first, then rating, from the query.
      case VendorSort.rating:
        result.sort((a, b) => b.ratingAvg.compareTo(a.ratingAvg));
      case VendorSort.deliveryFee:
        result.sort((a, b) => a.deliveryFee.compareTo(b.deliveryFee));
      case VendorSort.prepTime:
        result.sort((a, b) => a.totalPrepMinutes.compareTo(b.totalPrepMinutes));
    }
    return result;
  }

  HomeState copyWith({
    bool? loading,
    String? error,
    List<BannerItem>? banners,
    List<VendorCategory>? categories,
    List<Vendor>? vendors,
    String? selectedCategoryId,
    String? search,
    Address? deliverToAddress,
    bool? addressLoaded,
    Set<String>? favoriteVendorIds,
    VendorFilters? filters,
    bool clearCategory = false,
    bool clearError = false,
    bool clearAddress = false,
  }) =>
      HomeState(
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        banners: banners ?? this.banners,
        categories: categories ?? this.categories,
        vendors: vendors ?? this.vendors,
        selectedCategoryId:
            clearCategory ? null : (selectedCategoryId ?? this.selectedCategoryId),
        search: search ?? this.search,
        deliverToAddress:
            clearAddress ? null : (deliverToAddress ?? this.deliverToAddress),
        addressLoaded: addressLoaded ?? this.addressLoaded,
        favoriteVendorIds: favoriteVendorIds ?? this.favoriteVendorIds,
        filters: filters ?? this.filters,
      );

  @override
  List<Object?> get props => [
        loading,
        error,
        banners,
        categories,
        vendors,
        selectedCategoryId,
        search,
        deliverToAddress,
        addressLoaded,
        favoriteVendorIds,
        filters,
      ];
}

class HomeCubit extends Cubit<HomeState> {
  HomeCubit(this._catalog, this._addresses, this._favorites)
      : super(const HomeState()) {
    _categoriesSubscription = _catalog.vendorCategoriesStream().listen((list) {
      emit(state.copyWith(categories: list));
    }, onError: (_) {});
    load();
  }

  final CatalogRepository _catalog;
  final AddressRepository _addresses;
  final FavoritesRepository _favorites;
  StreamSubscription<List<VendorCategory>>? _categoriesSubscription;

  /// Nothing here may leave the page on its skeleton forever, so the fetch is
  /// bounded and `loading` is cleared in a `finally` — a hung request then
  /// shows an error the user can retry instead of an endless shimmer.
  static const _fetchTimeout = Duration(seconds: 20);

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    // Address and favourites are decorations on the store list: a failure there
    // must not blank the page, so they are loaded beside the critical fetch and
    // their errors are swallowed.
    _loadDeliverToAddress();
    _loadFavorites();
    List<BannerItem>? banners;
    List<Vendor>? vendors;
    String? error;
    try {
      final results = await Future.wait([
        _catalog.fetchBanners(),
        _catalog.fetchVendors(
            categoryId: state.selectedCategoryId, search: state.search),
      ]).timeout(_fetchTimeout);
      banners = results[0] as List<BannerItem>;
      vendors = results[1] as List<Vendor>;
    } catch (e) {
      error = e.toString();
    } finally {
      if (!isClosed) {
        emit(state.copyWith(
          loading: false,
          banners: banners,
          vendors: vendors,
          error: error,
        ));
      }
    }
  }

  Future<void> _loadDeliverToAddress() async {
    try {
      final addresses = await _addresses.fetchAddresses();
      if (isClosed) return;
      // `fetchAddresses` already sorts default-first, then newest-first.
      emit(addresses.isEmpty
          ? state.copyWith(addressLoaded: true, clearAddress: true)
          : state.copyWith(
              addressLoaded: true, deliverToAddress: addresses.first));
    } catch (_) {
      if (!isClosed) emit(state.copyWith(addressLoaded: true));
    }
  }

  Future<void> _loadFavorites() async {
    try {
      final ids = await _favorites.fetchFavoriteVendorIds();
      if (isClosed) return;
      emit(state.copyWith(favoriteVendorIds: ids));
    } catch (_) {}
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

  /// Filters run over the fetched page, so applying them is instant — no
  /// refetch, and clearing one restores the list without a round trip.
  void applyFilters(VendorFilters filters) =>
      emit(state.copyWith(filters: filters));

  void clearFilters() => emit(state.copyWith(filters: const VendorFilters()));

  Future<void> selectCategory(String? categoryId) async {
    emit(categoryId == null
        ? state.copyWith(clearCategory: true)
        : state.copyWith(selectedCategoryId: categoryId));
    await _reloadVendors();
  }

  Future<void> setSearch(String search) async {
    emit(state.copyWith(search: search));
    await _reloadVendors();
  }

  Future<void> _reloadVendors() async {
    try {
      final vendors = await _catalog.fetchVendors(
          categoryId: state.selectedCategoryId, search: state.search);
      emit(state.copyWith(vendors: vendors));
    } catch (error) {
      emit(state.copyWith(error: error.toString()));
    }
  }

  @override
  Future<void> close() {
    _categoriesSubscription?.cancel();
    return super.close();
  }
}
