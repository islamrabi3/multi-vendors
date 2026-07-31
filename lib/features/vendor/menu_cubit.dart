import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/product.dart';
import '../../core/repositories/catalog_repository.dart';
import '../../core/repositories/vendor_admin_repository.dart';

class MenuState extends Equatable {
  const MenuState({
    this.loading = true,
    this.error,
    this.categories = const [],
    this.products = const [],
  });

  final bool loading;
  final String? error;
  final List<ProductCategory> categories;
  final List<Product> products;

  List<Product> productsIn(String categoryId) =>
      products.where((p) => p.categoryId == categoryId).toList();

  List<Product> get uncategorized => products
      .where((p) =>
          p.categoryId == null || !categories.any((c) => c.id == p.categoryId))
      .toList();

  @override
  List<Object?> get props => [loading, error, categories, products];
}

class MenuCubit extends Cubit<MenuState> {
  MenuCubit(this._catalog, this._admin, this.vendorId)
      : super(const MenuState()) {
    load();
  }

  final CatalogRepository _catalog;
  final VendorAdminRepository _admin;
  final String vendorId;

  Future<void> load() async {
    try {
      final results = await Future.wait([
        _catalog.fetchMenuCategories(vendorId),
        _catalog.fetchProducts(vendorId, includeUnavailable: true),
      ]);
      emit(MenuState(
        loading: false,
        categories: results[0] as List<ProductCategory>,
        products: results[1] as List<Product>,
      ));
    } catch (error) {
      emit(MenuState(loading: false, error: error.toString()));
    }
  }

  Future<void> saveCategory(String name, {String? nameAr, String? id}) async {
    await _admin.saveCategory(
        vendorId: vendorId, name: name, nameAr: nameAr, id: id);
    await load();
  }

  Future<void> deleteCategory(String id) async {
    await _admin.deleteCategory(id);
    await load();
  }

  Future<void> toggleAvailability(Product product) async {
    await _admin.setProductAvailability(product.id, !product.isAvailable);
    await load();
  }

  Future<void> deleteProduct(String id) async {
    await _admin.deleteProduct(id);
    await load();
  }
}
