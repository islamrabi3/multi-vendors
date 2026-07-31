import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/address.dart';
import '../../../core/repositories/address_repository.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/repositories/payment_repository.dart';

import '../../../core/repositories/wallet_repository.dart';

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
    this.walletBalance = 0.0,
  });

  final bool loading;
  final CheckoutStep step;
  final List<Address> addresses;
  final String? selectedAddressId;
  final String paymentMethod; // 'cod' | 'paymob' | 'wallet'
  final String couponCode;
  final double? couponDiscount;
  final String? couponError;
  final String? error;
  final String? placedOrderId;
  final String? paymobCheckoutUrl;
  final double walletBalance;

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
    double? walletBalance,
    bool clearCoupon = false,
    bool clearError = false,
    bool clearPlacedOrder = false,
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
        placedOrderId:
            clearPlacedOrder ? null : (placedOrderId ?? this.placedOrderId),
        paymobCheckoutUrl: clearPlacedOrder
            ? null
            : (paymobCheckoutUrl ?? this.paymobCheckoutUrl),
        walletBalance: walletBalance ?? this.walletBalance,
      );

  @override
  List<Object?> get props => [
        loading, step, addresses, selectedAddressId, paymentMethod,
        couponCode, couponDiscount, couponError, error, placedOrderId,
        paymobCheckoutUrl, walletBalance,
      ];
}

class CheckoutCubit extends Cubit<CheckoutState> {
  // The Paymob session is created by the view once the order row exists, so
  // the cubit takes the repository only to keep the call sites unchanged.
  CheckoutCubit(this._addresses, this._orders, PaymentRepository payments,
      [WalletRepository? wallet])
      : _wallet = wallet ?? WalletRepository(),
        super(const CheckoutState()) {
    loadAddresses();
  }

  final AddressRepository _addresses;
  final OrderRepository _orders;
  final WalletRepository _wallet;

  Future<void> loadAddresses() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final addresses = await _addresses.fetchAddresses();
      final walletBalance = await _wallet.getBalance();
      emit(state.copyWith(
        loading: false,
        addresses: addresses,
        walletBalance: walletBalance,
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

      // For 'paymob' the order is created unpaid and stays hidden from the
      // restaurant until the webhook confirms payment. The view drives the
      // gateway from here.
      emit(state.copyWith(
        step: CheckoutStep.placed,
        placedOrderId: orderId,
      ));
    } catch (error) {
      emit(state.copyWith(
          step: CheckoutStep.editing, error: error.toString()));
    }
  }

  /// The card payment did not go through and the draft order was discarded —
  /// put the form back so the customer can retry or switch payment method.
  void resetAfterFailedPayment() => emit(state.copyWith(
        step: CheckoutStep.editing,
        clearPlacedOrder: true,
      ));
}
