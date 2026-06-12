import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/banner_item.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/catalog_repository.dart';

class HomeState extends Equatable {
  const HomeState({
    this.loading = true,
    this.error,
    this.banners = const [],
    this.categories = const [],
    this.vendors = const [],
    this.selectedCategoryId,
    this.search = '',
  });

  final bool loading;
  final String? error;
  final List<BannerItem> banners;
  final List<VendorCategory> categories;
  final List<Vendor> vendors;
  final String? selectedCategoryId;
  final String search;

  HomeState copyWith({
    bool? loading,
    String? error,
    List<BannerItem>? banners,
    List<VendorCategory>? categories,
    List<Vendor>? vendors,
    String? selectedCategoryId,
    String? search,
    bool clearCategory = false,
    bool clearError = false,
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
      );

  @override
  List<Object?> get props =>
      [loading, error, banners, categories, vendors, selectedCategoryId, search];
}

class HomeCubit extends Cubit<HomeState> {
  HomeCubit(this._catalog) : super(const HomeState()) {
    load();
  }

  final CatalogRepository _catalog;

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final results = await Future.wait([
        _catalog.fetchBanners(),
        _catalog.fetchVendorCategories(),
        _catalog.fetchVendors(
            categoryId: state.selectedCategoryId, search: state.search),
      ]);
      emit(state.copyWith(
        loading: false,
        banners: results[0] as List<BannerItem>,
        categories: results[1] as List<VendorCategory>,
        vendors: results[2] as List<Vendor>,
      ));
    } catch (error) {
      emit(state.copyWith(loading: false, error: error.toString()));
    }
  }

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
}
