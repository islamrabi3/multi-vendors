import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/vendor.dart';
import '../../core/repositories/admin_repository.dart';

class AdminCategoriesState extends Equatable {
  const AdminCategoriesState({
    this.loading = true,
    this.categories = const [],
    this.error,
    this.successMessage,
  });

  final bool loading;
  final List<VendorCategory> categories;
  final String? error;
  final String? successMessage;

  AdminCategoriesState copyWith({
    bool? loading,
    List<VendorCategory>? categories,
    String? error,
    String? successMessage,
    bool clearError = false,
    bool clearSuccess = false,
  }) => AdminCategoriesState(
    loading: loading ?? this.loading,
    categories: categories ?? this.categories,
    error: clearError ? null : (error ?? this.error),
    successMessage: clearSuccess
        ? null
        : (successMessage ?? this.successMessage),
  );

  /// The kinds of shop — what the customer home page shows.
  List<VendorCategory> get topLevel {
    final tops = categories.where((c) => c.isTopLevel).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return tops;
  }

  List<VendorCategory> childrenOf(String parentId) {
    final children = categories.where((c) => c.parentId == parentId).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return children;
  }

  @override
  List<Object?> get props => [loading, categories, error, successMessage];
}

class AdminCategoriesCubit extends Cubit<AdminCategoriesState> {
  AdminCategoriesCubit(this._repository) : super(const AdminCategoriesState()) {
    load();
  }

  final AdminRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true, clearSuccess: true));
    try {
      final list = await _repository.fetchVendorCategories();
      emit(state.copyWith(loading: false, categories: list));
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  /// Top-level categories are the ones with no [parentId]. The database
  /// refuses a third level, so a category filed under a child comes back as an
  /// error rather than silently creating a depth the UI cannot navigate.
  Future<bool> createCategory({
    required String name,
    String? nameAr,
    String? parentId,
    List<int>? imageBytes,
    String? fileExtension,
  }) async {
    emit(state.copyWith(loading: true, clearError: true, clearSuccess: true));
    try {
      String? imageUrl;
      if (imageBytes != null && fileExtension != null) {
        final path =
            'categories/${name.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
        imageUrl = await _repository.uploadCategoryImage(
          path: path,
          bytes: imageBytes,
        );
      }
      await _repository.createVendorCategory(
        name: name,
        nameAr: nameAr,
        imageUrl: imageUrl,
        parentId: parentId,
      );
      emit(
        state.copyWith(
          successMessage: 'Category "$name" created successfully!',
        ),
      );
      await load();
      return true;
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
      return false;
    }
  }

  Future<bool> updateCategory({
    required String id,
    required String name,
    String? nameAr,
    String? parentId,
    List<int>? imageBytes,
    String? fileExtension,
    String? existingImageUrl,
  }) async {
    emit(state.copyWith(loading: true, clearError: true, clearSuccess: true));
    try {
      String? imageUrl = existingImageUrl;
      if (imageBytes != null && fileExtension != null) {
        final path =
            'categories/${name.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
        imageUrl = await _repository.uploadCategoryImage(
          path: path,
          bytes: imageBytes,
        );
      }
      await _repository.updateVendorCategory(
        id,
        name: name,
        nameAr: nameAr,
        imageUrl: imageUrl,
        parentId: parentId,
      );
      emit(state.copyWith(successMessage: 'Category updated successfully!'));
      await load();
      return true;
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
      return false;
    }
  }

  Future<bool> deleteCategory(String id) async {
    emit(state.copyWith(loading: true, clearError: true, clearSuccess: true));
    try {
      await _repository.deleteVendorCategory(id);
      emit(state.copyWith(successMessage: 'Category deleted successfully!'));
      await load();
      return true;
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
      return false;
    }
  }
}
