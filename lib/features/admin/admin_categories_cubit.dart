import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/vendor.dart';
import '../../core/repositories/admin_repository.dart';

/// What just succeeded, so the UI can localize its own toast instead of the
/// cubit carrying a hardcoded English sentence.
enum CategoryEvent { created, updated, deleted, reordered }

class AdminCategoriesState extends Equatable {
  const AdminCategoriesState({
    this.loading = true,
    this.categories = const [],
    this.error,
    this.event,
    this.eventCategoryName,
  });

  final bool loading;
  final List<VendorCategory> categories;
  final String? error;
  final CategoryEvent? event;

  /// The name to interpolate into [CategoryEvent.created]'s toast. Unused by
  /// every other event.
  final String? eventCategoryName;

  AdminCategoriesState copyWith({
    bool? loading,
    List<VendorCategory>? categories,
    String? error,
    CategoryEvent? event,
    String? eventCategoryName,
    bool clearError = false,
    bool clearEvent = false,
  }) => AdminCategoriesState(
    loading: loading ?? this.loading,
    categories: categories ?? this.categories,
    error: clearError ? null : (error ?? this.error),
    event: clearEvent ? null : (event ?? this.event),
    eventCategoryName: clearEvent
        ? null
        : (eventCategoryName ?? this.eventCategoryName),
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
  List<Object?> get props => [
    loading,
    categories,
    error,
    event,
    eventCategoryName,
  ];
}

class AdminCategoriesCubit extends Cubit<AdminCategoriesState> {
  AdminCategoriesCubit(this._repository) : super(const AdminCategoriesState()) {
    load();
  }

  final AdminRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
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
    emit(state.copyWith(loading: true, clearError: true, clearEvent: true));
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
        state.copyWith(event: CategoryEvent.created, eventCategoryName: name),
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
    emit(state.copyWith(loading: true, clearError: true, clearEvent: true));
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
      emit(state.copyWith(event: CategoryEvent.updated));
      await load();
      return true;
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
      return false;
    }
  }

  Future<bool> deleteCategory(String id) async {
    emit(state.copyWith(loading: true, clearError: true, clearEvent: true));
    try {
      await _repository.deleteVendorCategory(id);
      emit(state.copyWith(event: CategoryEvent.deleted));
      await load();
      return true;
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
      return false;
    }
  }

  /// Renumbers one sibling group — pass [state.topLevel] or a single
  /// parent's [state.childrenOf] result, reordered. Applied optimistically so
  /// the drag doesn't snap back while the write is in flight.
  Future<bool> reorderCategories(List<VendorCategory> ordered) async {
    final renumbered = [
      for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(sortOrder: i),
    ];
    final byId = {for (final c in renumbered) c.id: c};
    emit(
      state.copyWith(
        clearError: true,
        categories: [for (final c in state.categories) byId[c.id] ?? c],
      ),
    );
    try {
      await _repository.reorderVendorCategories(
        renumbered.map((c) => c.id).toList(),
      );
      emit(state.copyWith(event: CategoryEvent.reordered));
      return true;
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
      await load();
      return false;
    }
  }
}
