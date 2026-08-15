import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/banner_item.dart';
import '../../core/repositories/offers_repository.dart';

class AdminOffersState extends Equatable {
  const AdminOffersState({
    this.loading = true,
    this.offers = const [],
    this.error,
  });

  final bool loading;
  final List<BannerItem> offers;
  final String? error;

  AdminOffersState copyWith({
    bool? loading,
    List<BannerItem>? offers,
    String? error,
    bool clearError = false,
  }) => AdminOffersState(
    loading: loading ?? this.loading,
    offers: offers ?? this.offers,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [loading, offers, error];
}

class AdminOffersCubit extends Cubit<AdminOffersState> {
  AdminOffersCubit(this._repository) : super(const AdminOffersState()) {
    load();
  }

  final OffersRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final offers = await _repository.fetchAll();
      emit(state.copyWith(loading: false, offers: offers));
    } catch (error) {
      emit(state.copyWith(loading: false, error: error.toString()));
    }
  }

  Future<bool> create({
    required String imageUrl,
    required BannerType type,
    String? title,
    String? subtitle,
    String? code,
    String? vendorId,
  }) async {
    try {
      final nextSort = state.offers.isEmpty
          ? 1
          : state.offers
                    .map((o) => o.sortOrder)
                    .reduce((a, b) => a > b ? a : b) +
                1;
      await _repository.create(
        imageUrl: imageUrl,
        type: type,
        title: title,
        subtitle: subtitle,
        code: code,
        vendorId: vendorId,
        sortOrder: nextSort,
      );
      await load();
      return true;
    } catch (error) {
      emit(state.copyWith(error: error.toString()));
      return false;
    }
  }

  Future<void> toggleActive(BannerItem offer) async {
    try {
      await _repository.setActive(offer.id, !offer.isActive);
      await load();
    } catch (error) {
      emit(state.copyWith(error: error.toString()));
    }
  }

  Future<void> delete(BannerItem offer) async {
    try {
      await _repository.delete(offer.id);
      await load();
    } catch (error) {
      emit(state.copyWith(error: error.toString()));
    }
  }
}
