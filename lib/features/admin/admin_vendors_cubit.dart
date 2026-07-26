import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/vendor.dart';
import '../../core/repositories/admin_repository.dart';

enum VendorFilter { all, pending, active, suspended }

class AdminVendorsState extends Equatable {
  const AdminVendorsState({
    this.loading = true,
    this.vendors = const [],
    this.filter = VendorFilter.all,
    this.error,
  });

  final bool loading;
  final List<Vendor> vendors;
  final VendorFilter filter;
  final String? error;

  List<Vendor> get pending =>
      vendors.where((v) => v.isPending).toList();
  List<Vendor> get active =>
      vendors.where((v) => v.isApproved).toList();
  List<Vendor> get suspended =>
      vendors.where((v) => v.isSuspended).toList();

  List<Vendor> get visible => switch (filter) {
        VendorFilter.all => vendors,
        VendorFilter.pending => pending,
        VendorFilter.active => active,
        VendorFilter.suspended => suspended,
      };

  AdminVendorsState copyWith({
    bool? loading,
    List<Vendor>? vendors,
    VendorFilter? filter,
    String? error,
    bool clearError = false,
  }) =>
      AdminVendorsState(
        loading: loading ?? this.loading,
        vendors: vendors ?? this.vendors,
        filter: filter ?? this.filter,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  List<Object?> get props => [loading, vendors, filter, error];
}

class AdminVendorsCubit extends Cubit<AdminVendorsState> {
  AdminVendorsCubit(this._repository) : super(const AdminVendorsState()) {
    load();
  }

  final AdminRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final vendors = await _repository.fetchVendors();
      emit(state.copyWith(loading: false, vendors: vendors));
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  void setFilter(VendorFilter filter) => emit(state.copyWith(filter: filter));

  Future<bool> setStatus(String vendorId, String status) async {
    try {
      await _repository.setVendorStatus(vendorId, status);
      await load();
      return true;
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
      return false;
    }
  }
}
