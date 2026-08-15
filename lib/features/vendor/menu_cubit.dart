import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/product.dart';
import '../../core/repositories/catalog_repository.dart';
import '../../core/repositories/vendor_admin_repository.dart';

/// How the item list is ordered on screen.
///
/// Manual is the vendor's own arrangement — the one customers see — so it is
/// the default and the only mode where dragging is allowed.
enum MenuSort { manual, nameAsc, priceAsc, priceDesc }

class MenuState extends Equatable {
  const MenuState({
    this.loading = true,
    this.error,
    this.categories = const [],
    this.products = const [],
    this.query = '',
    this.selectedCategoryId,
    this.showUncategorized = false,
    this.sort = MenuSort.manual,
    this.busy = false,
  });

  final bool loading;
  final String? error;
  final List<ProductCategory> categories;
  final List<Product> products;

  /// Free-text filter over item and section names, both languages.
  final String query;

  /// null with [showUncategorized] false means "everything".
  final String? selectedCategoryId;

  /// The bucket for items whose section was deleted. It is not a category, so
  /// it cannot be a [selectedCategoryId].
  final bool showUncategorized;

  final MenuSort sort;

  /// A write is in flight. Kept separate from [loading] so the list stays on
  /// screen while a toggle or a reorder settles.
  final bool busy;

  List<Product> productsIn(String categoryId) =>
      products.where((p) => p.categoryId == categoryId).toList();

  List<Product> get uncategorized => products
      .where(
        (p) =>
            p.categoryId == null ||
            !categories.any((c) => c.id == p.categoryId),
      )
      .toList();

  int get soldOutCount => products.where((p) => !p.isAvailable).length;

  bool get isFiltered =>
      query.trim().isNotEmpty ||
      selectedCategoryId != null ||
      showUncategorized;

  /// What the list actually shows: the section filter, then the search, then
  /// the sort.
  List<Product> visibleProducts(String languageCode) {
    var items = showUncategorized
        ? uncategorized
        : selectedCategoryId == null
        ? products
        : productsIn(selectedCategoryId!);

    final needle = query.trim().toLowerCase();
    if (needle.isNotEmpty) {
      items = items.where((p) {
        final haystack = [
          p.name,
          p.nameAr ?? '',
          p.description ?? '',
          p.descriptionAr ?? '',
        ].join(' ').toLowerCase();
        return haystack.contains(needle);
      }).toList();
    }

    final sorted = [...items];
    switch (sort) {
      case MenuSort.manual:
        sorted.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      case MenuSort.nameAsc:
        sorted.sort(
          (a, b) => a
              .displayName(languageCode)
              .compareTo(b.displayName(languageCode)),
        );
      case MenuSort.priceAsc:
        sorted.sort((a, b) => a.price.compareTo(b.price));
      case MenuSort.priceDesc:
        sorted.sort((a, b) => b.price.compareTo(a.price));
    }
    return sorted;
  }

  MenuState copyWith({
    bool? loading,
    String? error,
    List<ProductCategory>? categories,
    List<Product>? products,
    String? query,
    String? selectedCategoryId,
    bool? showUncategorized,
    MenuSort? sort,
    bool? busy,
    bool clearError = false,
    bool clearCategoryFilter = false,
  }) => MenuState(
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    categories: categories ?? this.categories,
    products: products ?? this.products,
    query: query ?? this.query,
    selectedCategoryId: clearCategoryFilter
        ? null
        : (selectedCategoryId ?? this.selectedCategoryId),
    showUncategorized: showUncategorized ?? this.showUncategorized,
    sort: sort ?? this.sort,
    busy: busy ?? this.busy,
  );

  @override
  List<Object?> get props => [
    loading,
    error,
    categories,
    products,
    query,
    selectedCategoryId,
    showUncategorized,
    sort,
    busy,
  ];
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
      if (isClosed) return;
      emit(
        state.copyWith(
          loading: false,
          busy: false,
          clearError: true,
          categories: results[0] as List<ProductCategory>,
          products: results[1] as List<Product>,
        ),
      );
    } catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(loading: false, busy: false, error: error.toString()),
      );
    }
  }

  // -------------------------------------------------------------------------
  // View state. None of this touches the server.
  // -------------------------------------------------------------------------

  void search(String query) => emit(state.copyWith(query: query));

  void selectCategory(String? categoryId) => emit(
    state.copyWith(
      selectedCategoryId: categoryId,
      clearCategoryFilter: categoryId == null,
      showUncategorized: false,
    ),
  );

  void selectUncategorized() =>
      emit(state.copyWith(clearCategoryFilter: true, showUncategorized: true));

  void setSort(MenuSort sort) => emit(state.copyWith(sort: sort));

  void clearFilters() => emit(
    state.copyWith(
      query: '',
      clearCategoryFilter: true,
      showUncategorized: false,
    ),
  );

  // -------------------------------------------------------------------------
  // Writes.
  // -------------------------------------------------------------------------

  /// Every mutation goes through here.
  ///
  /// These used to `await` the write bare: a failure — an RLS refusal on a
  /// suspended store, a dropped connection — escaped as an unhandled
  /// exception, so the vendor got an error with no message and no way to
  /// retry. The state already carried an `error` field; only `load()` was ever
  /// setting it.
  Future<bool> _mutate(Future<void> Function() action) async {
    emit(state.copyWith(clearError: true, busy: true));
    try {
      await action();
      await load();
      return true;
    } catch (error) {
      if (isClosed) return false;
      // Keep the menu on screen: a failed write is not a reason to blank the
      // list the vendor is looking at.
      emit(
        state.copyWith(loading: false, busy: false, error: error.toString()),
      );
      return false;
    }
  }

  Future<bool> saveCategory(String name, {String? nameAr, String? id}) =>
      _mutate(
        () => _admin.saveCategory(
          vendorId: vendorId,
          name: name,
          nameAr: nameAr,
          id: id,
        ),
      );

  Future<bool> deleteCategory(String id) async {
    // The filter cannot outlive the section it points at, or the list comes
    // back empty with no way to tell why.
    if (state.selectedCategoryId == id) selectCategory(null);
    return _mutate(() => _admin.deleteCategory(id));
  }

  Future<bool> toggleAvailability(Product product) => _mutate(
    () => _admin.setProductAvailability(product.id, !product.isAvailable),
  );

  Future<bool> deleteProduct(String id) =>
      _mutate(() => _admin.deleteProduct(id));

  Future<bool> duplicateProduct(String id) =>
      _mutate(() => _admin.duplicateProduct(id));

  Future<bool> moveProduct(String productId, String? categoryId) =>
      _mutate(() => _admin.setProductCategory(productId, categoryId));

  /// Applies a drag immediately and writes the new order behind it.
  ///
  /// Reordering through [_mutate] would reload the list from the server on
  /// every drop, and the row would visibly jump back to where it was until the
  /// round trip finished. The local list is authoritative until the write
  /// either confirms it or fails, at which point the reload puts it right.
  Future<bool> reorderProducts(List<Product> ordered) async {
    final renumbered = [
      for (var i = 0; i < ordered.length; i++)
        ordered[i].copyWith(sortOrder: i),
    ];
    final byId = {for (final p in renumbered) p.id: p};
    emit(
      state.copyWith(
        clearError: true,
        products: [for (final p in state.products) byId[p.id] ?? p],
      ),
    );
    try {
      await _admin.reorderProducts(
        vendorId,
        renumbered.map((p) => p.id).toList(),
      );
      return true;
    } catch (error) {
      if (isClosed) return false;
      emit(state.copyWith(error: error.toString()));
      await load();
      return false;
    }
  }

  Future<bool> reorderCategories(List<ProductCategory> ordered) async {
    emit(state.copyWith(clearError: true, categories: ordered));
    try {
      await _admin.reorderCategories(
        vendorId,
        ordered.map((c) => c.id).toList(),
      );
      return true;
    } catch (error) {
      if (isClosed) return false;
      emit(state.copyWith(error: error.toString()));
      await load();
      return false;
    }
  }

  /// Marks a whole section — or the whole menu, with a null [categoryId] —
  /// available or sold out.
  Future<bool> setSectionAvailability({
    required String? categoryId,
    required bool available,
  }) => _mutate(
    () => _admin.setSectionAvailability(
      vendorId: vendorId,
      categoryId: categoryId,
      available: available,
    ),
  );
}
