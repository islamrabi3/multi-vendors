import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/address.dart';
import '../../../core/repositories/address_repository.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/repositories/payment_repository.dart';

enum CheckoutStep { editing, placing, placed }

class CheckoutState extends Equatable {
  const CheckoutState({
    this.loading = true,
    this.step = CheckoutStep.editing,
    this.addresses = const [],
    this.selectedAddressId,
    this.paymentMethod = 'cod',
    this.couponCode = '',
    this.couponDiscount,
    this.couponError,
    this.error,
    this.placedOrderId,
    this.paymobCheckoutUrl,
  });

  final bool loading;
  final CheckoutStep step;
  final List<Address> addresses;
  final String? selectedAddressId;
  final String paymentMethod; // 'cod' | 'paymob'
  final String couponCode;
  final double? couponDiscount;
  final String? couponError;
  final String? error;
  final String? placedOrderId;
  final String? paymobCheckoutUrl;

  Address? get selectedAddress => addresses
      .where((address) => address.id == selectedAddressId)
      .firstOrNull;

  CheckoutState copyWith({
    bool? loading,
    CheckoutStep? step,
    List<Address>? addresses,
    String? selectedAddressId,
    String? paymentMethod,
    String? couponCode,
    double? couponDiscount,
    String? couponError,
    String? error,
    String? placedOrderId,
    String? paymobCheckoutUrl,
    bool clearCoupon = false,
    bool clearError = false,
  }) =>
      CheckoutState(
        loading: loading ?? this.loading,
        step: step ?? this.step,
        addresses: addresses ?? this.addresses,
        selectedAddressId: selectedAddressId ?? this.selectedAddressId,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        couponCode: clearCoupon ? '' : (couponCode ?? this.couponCode),
        couponDiscount:
            clearCoupon ? null : (couponDiscount ?? this.couponDiscount),
        couponError: clearCoupon ? null : couponError,
        error: clearError ? null : error,
        placedOrderId: placedOrderId ?? this.placedOrderId,
        paymobCheckoutUrl: paymobCheckoutUrl ?? this.paymobCheckoutUrl,
      );

  @override
  List<Object?> get props => [
        loading, step, addresses, selectedAddressId, paymentMethod,
        couponCode, couponDiscount, couponError, error, placedOrderId,
        paymobCheckoutUrl,
      ];
}

class CheckoutCubit extends Cubit<CheckoutState> {
  CheckoutCubit(this._addresses, this._orders, this._payments)
      : super(const CheckoutState()) {
    loadAddresses();
  }

  final AddressRepository _addresses;
  final OrderRepository _orders;
  final PaymentRepository _payments;

  Future<void> loadAddresses() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final addresses = await _addresses.fetchAddresses();
      emit(state.copyWith(
        loading: false,
        addresses: addresses,
        selectedAddressId: state.selectedAddressId ??
            (addresses.isEmpty ? null : addresses.first.id),
      ));
    } catch (error) {
      emit(state.copyWith(loading: false, error: error.toString()));
    }
  }

  void selectAddress(String addressId) =>
      emit(state.copyWith(selectedAddressId: addressId));

  void selectPaymentMethod(String method) =>
      emit(state.copyWith(paymentMethod: method));

  void clearCoupon() => emit(state.copyWith(clearCoupon: true));

  Future<void> applyCoupon(
      String code, String vendorId, double subtotal) async {
    if (code.trim().isEmpty) return;
    try {
      final discount = await _orders.validateCoupon(
          code: code.trim().toUpperCase(),
          vendorId: vendorId,
          subtotal: subtotal);
      emit(state.copyWith(
          couponCode: code.trim().toUpperCase(), couponDiscount: discount));
    } catch (error) {
      emit(state.copyWith(
          couponError: error.toString(), couponDiscount: null));
    }
  }

  Future<void> placeOrder({String? notes}) async {
    final addressId = state.selectedAddressId;
    if (addressId == null) {
      emit(state.copyWith(error: 'ADDRESS_NOT_FOUND'));
      return;
    }
    emit(state.copyWith(step: CheckoutStep.placing, clearError: true));
    try {
      final orderId = await _orders.placeOrder(
        addressId: addressId,
        paymentMethod: state.paymentMethod,
        couponCode: state.couponCode.isEmpty ? null : state.couponCode,
        notes: notes,
      );

      String? checkoutUrl;
      if (state.paymentMethod == 'paymob') {
        // The order already exists; if the gateway call fails the user can
        // retry payment from the order details screen.
        try {
          checkoutUrl = await _payments.createPaymobCheckout(orderId);
        } catch (_) {}
      }
      emit(state.copyWith(
        step: CheckoutStep.placed,
        placedOrderId: orderId,
        paymobCheckoutUrl: checkoutUrl,
      ));
    } catch (error) {
      emit(state.copyWith(
          step: CheckoutStep.editing, error: error.toString()));
    }
  }
}
