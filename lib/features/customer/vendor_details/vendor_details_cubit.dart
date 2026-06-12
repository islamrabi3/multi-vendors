import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/product.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/repositories/favorites_repository.dart';

class VendorDetailsState extends Equatable {
  const VendorDetailsState({
    this.loading = true,
    this.error,
    this.vendor,
    this.menuCategories = const [],
    this.products = const [],
    this.isFavorite = false,
  });

  final bool loading;
  final String? error;
  final Vendor? vendor;
  final List<ProductCategory> menuCategories;
  final List<Product> products;
  final bool isFavorite;

  List<Product> productsIn(String? categoryId) =>
      products.where((p) => p.categoryId == categoryId).toList();

  /// Products whose category was deleted still show under "Other".
  List<Product> get uncategorized => products
      .where((p) =>
          p.categoryId == null ||
          !menuCategories.any((c) => c.id == p.categoryId))
      .toList();

  VendorDetailsState copyWith({
    bool? loading,
    String? error,
    Vendor? vendor,
    List<ProductCategory>? menuCategories,
    List<Product>? products,
    bool? isFavorite,
  }) =>
      VendorDetailsState(
        loading: loading ?? this.loading,
        error: error,
        vendor: vendor ?? this.vendor,
        menuCategories: menuCategories ?? this.menuCategories,
        products: products ?? this.products,
        isFavorite: isFavorite ?? this.isFavorite,
      );

  @override
  List<Object?> get props =>
      [loading, error, vendor, menuCategories, products, isFavorite];
}

class VendorDetailsCubit extends Cubit<VendorDetailsState> {
  VendorDetailsCubit(this._catalog, this._favorites, this.vendorId)
      : super(const VendorDetailsState()) {
    load();
  }

  final CatalogRepository _catalog;
  final FavoritesRepository _favorites;
  final String vendorId;

  Future<void> load() async {
    emit(state.copyWith(loading: true));
    try {
      final results = await Future.wait([
        _catalog.fetchVendor(vendorId),
        _catalog.fetchMenuCategories(vendorId),
        _catalog.fetchProducts(vendorId),
        _favorites.fetchFavoriteVendorIds(),
      ]);
      emit(state.copyWith(
        loading: false,
        vendor: results[0] as Vendor,
        menuCategories: results[1] as List<ProductCategory>,
        products: results[2] as List<Product>,
        isFavorite: (results[3] as Set<String>).contains(vendorId),
      ));
    } catch (error) {
      emit(state.copyWith(loading: false, error: error.toString()));
    }
  }

  Future<void> toggleFavorite() async {
    final next = !state.isFavorite;
    emit(state.copyWith(isFavorite: next));
    try {
      await _favorites.setFavorite(vendorId, next);
    } catch (_) {
      emit(state.copyWith(isFavorite: !next));
    }
  }
}
