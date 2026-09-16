import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/coupon.dart';
import '../../core/repositories/admin_repository.dart';
import '../../core/repositories/coupons_repository.dart';

class AdminCouponsState extends Equatable {
  const AdminCouponsState({
    this.loading = true,
    this.coupons = const [],
    this.error,
    this.storeNames = const {},
  });

  final bool loading;
  final List<Coupon> coupons;
  final String? error;

  /// Names of the stores that store-scoped codes belong to, by vendor id.
  final Map<String, String> storeNames;

  AdminCouponsState copyWith({
    bool? loading,
    List<Coupon>? coupons,
    String? error,
    bool clearError = false,
    Map<String, String>? storeNames,
  }) => AdminCouponsState(
    loading: loading ?? this.loading,
    coupons: coupons ?? this.coupons,
    error: clearError ? null : (error ?? this.error),
    storeNames: storeNames ?? this.storeNames,
  );

  @override
  List<Object?> get props => [loading, coupons, error, storeNames];
}

class AdminCouponsCubit extends Cubit<AdminCouponsState> {
  AdminCouponsCubit(this._repository) : super(const AdminCouponsState()) {
    load();
  }

  final CouponsRepository _repository;
  final _admin = AdminRepository();

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final coupons = await _repository.fetchAll();
      final ids = {for (final c in coupons) ?c.vendorId};
      var names = state.storeNames;
      try {
        final labels = await _admin.vendorLabels(ids);
        names = {for (final e in labels.entries) e.key: e.value.name};
      } catch (_) {
        // Names are a label only; the list still works without them.
      }
      emit(state.copyWith(loading: false, coupons: coupons, storeNames: names));
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
    int? perUserLimit,
    DateTime? startsAt,
    DateTime? expiresAt,
    bool firstOrderOnly = false,
    bool isPublic = false,
    String? title,
    String? vendorId,
    String fundedBy = 'platform',
  }) async {
    try {
      await _repository.create(
        code: code,
        discountType: discountType,
        value: value,
        minOrderAmount: minOrderAmount,
        maxDiscount: maxDiscount,
        usageLimit: usageLimit,
        perUserLimit: perUserLimit,
        startsAt: startsAt,
        expiresAt: expiresAt,
        firstOrderOnly: firstOrderOnly,
        isPublic: isPublic,
        title: title,
        vendorId: vendorId,
        fundedBy: fundedBy,
      );
      await load();
      return true;
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
      return false;
    }
  }

  Future<bool> edit({
    required String id,
    required String code,
    required String discountType,
    required double value,
    double minOrderAmount = 0,
    double? maxDiscount,
    int? usageLimit,
    int? perUserLimit,
    DateTime? startsAt,
    DateTime? expiresAt,
    bool firstOrderOnly = false,
    bool isPublic = false,
    String? title,
    String? vendorId,
    String fundedBy = 'platform',
  }) async {
    try {
      await _repository.edit(
        id: id,
        code: code,
        discountType: discountType,
        value: value,
        minOrderAmount: minOrderAmount,
        maxDiscount: maxDiscount,
        usageLimit: usageLimit,
        perUserLimit: perUserLimit,
        startsAt: startsAt,
        expiresAt: expiresAt,
        firstOrderOnly: firstOrderOnly,
        isPublic: isPublic,
        title: title,
        vendorId: vendorId,
        fundedBy: fundedBy,
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
