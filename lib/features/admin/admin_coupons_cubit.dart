import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/coupon.dart';
import '../../core/repositories/coupons_repository.dart';

class AdminCouponsState extends Equatable {
  const AdminCouponsState({
    this.loading = true,
    this.coupons = const [],
    this.error,
  });

  final bool loading;
  final List<Coupon> coupons;
  final String? error;

  AdminCouponsState copyWith({
    bool? loading,
    List<Coupon>? coupons,
    String? error,
    bool clearError = false,
  }) =>
      AdminCouponsState(
        loading: loading ?? this.loading,
        coupons: coupons ?? this.coupons,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  List<Object?> get props => [loading, coupons, error];
}

class AdminCouponsCubit extends Cubit<AdminCouponsState> {
  AdminCouponsCubit(this._repository) : super(const AdminCouponsState()) {
    load();
  }

  final CouponsRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final coupons = await _repository.fetchAll();
      emit(state.copyWith(loading: false, coupons: coupons));
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  Future<bool> create({
    required String code,
    required String discountType,
    required double value,
    double minOrderAmount = 0,
    double? maxDiscount,
    int? usageLimit,
  }) async {
    try {
      await _repository.create(
        code: code,
        discountType: discountType,
        value: value,
        minOrderAmount: minOrderAmount,
        maxDiscount: maxDiscount,
        usageLimit: usageLimit,
      );
      await load();
      return true;
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
      return false;
    }
  }

  Future<void> toggleActive(Coupon coupon) async {
    try {
      await _repository.setActive(coupon.id, !coupon.isActive);
      await load();
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> delete(Coupon coupon) async {
    try {
      await _repository.delete(coupon.id);
      await load();
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }
}
