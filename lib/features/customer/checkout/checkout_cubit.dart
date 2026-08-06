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
    this.couponFreeDelivery = false,
    this.couponTitle,
    this.orderType = 'delivery',
    this.scheduledAt,
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

  /// The applied code waives delivery. The discount already equals the fee —
  /// this is only so the summary can name the line honestly.
  final bool couponFreeDelivery;

  /// The campaign's own name, shown instead of the raw code once applied.
  final String? couponTitle;

  /// `delivery` | `pickup` | `scheduled`. Pickup drops the delivery fee;
  /// scheduled needs [scheduledAt] and may be placed while the store is shut.
  final String orderType;
  final DateTime? scheduledAt;

  bool get isPickup => orderType == 'pickup';
  bool get isScheduled => orderType == 'scheduled';

  /// Nothing to deliver, nothing to charge for it. Mirrors the server, which
  /// is what actually decides the total.
  bool get chargesDelivery => !isPickup;
  final String? error;
  final String? placedOrderId;
  final String? paymobCheckoutUrl;
  final double walletBalance;

  Address? get selectedAddress =>
      addresses.where((address) => address.id == selectedAddressId).firstOrNull;

  CheckoutState copyWith({
    bool? loading,
    CheckoutStep? step,
    List<Address>? addresses,
    String? selectedAddressId,
    String? paymentMethod,
    String? couponCode,
    double? couponDiscount,
    String? couponError,
    bool? couponFreeDelivery,
    String? couponTitle,
    String? orderType,
    DateTime? scheduledAt,
    bool clearSchedule = false,
    String? error,
    String? placedOrderId,
    String? paymobCheckoutUrl,
    double? walletBalance,
    bool clearCoupon = false,
    bool clearError = false,
    bool clearPlacedOrder = false,
  }) => CheckoutState(
    loading: loading ?? this.loading,
    step: step ?? this.step,
    addresses: addresses ?? this.addresses,
    selectedAddressId: selectedAddressId ?? this.selectedAddressId,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    couponCode: clearCoupon ? '' : (couponCode ?? this.couponCode),
    couponDiscount: clearCoupon
        ? null
        : (couponDiscount ?? this.couponDiscount),
    couponError: clearCoupon ? null : couponError,
    couponFreeDelivery: clearCoupon
        ? false
        : (couponFreeDelivery ?? this.couponFreeDelivery),
    couponTitle: clearCoupon ? null : (couponTitle ?? this.couponTitle),
    orderType: orderType ?? this.orderType,
    scheduledAt: clearSchedule ? null : (scheduledAt ?? this.scheduledAt),
    error: clearError ? null : error,
    placedOrderId: clearPlacedOrder
        ? null
        : (placedOrderId ?? this.placedOrderId),
    paymobCheckoutUrl: clearPlacedOrder
        ? null
        : (paymobCheckoutUrl ?? this.paymobCheckoutUrl),
    walletBalance: walletBalance ?? this.walletBalance,
  );

  @override
  List<Object?> get props => [
    loading,
    step,
    addresses,
    selectedAddressId,
    paymentMethod,
    couponCode,
    couponDiscount,
    couponError,
    couponFreeDelivery,
    couponTitle,
    orderType,
    scheduledAt,
    error,
    placedOrderId,
    paymobCheckoutUrl,
    walletBalance,
  ];
}

class CheckoutCubit extends Cubit<CheckoutState> {
  // The Paymob session is created by the view once the order row exists, so
  // the cubit takes the repository only to keep the call sites unchanged.
  CheckoutCubit(
    this._addresses,
    this._orders,
    PaymentRepository payments, [
    WalletRepository? wallet,
  ]) : _wallet = wallet ?? WalletRepository(),
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
      emit(
        state.copyWith(
          loading: false,
          addresses: addresses,
          walletBalance: walletBalance,
          selectedAddressId:
              state.selectedAddressId ??
              (addresses.isEmpty ? null : addresses.first.id),
        ),
      );
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
    String code,
    String vendorId,
    double subtotal,
  ) async {
    if (code.trim().isEmpty) return;
    try {
      final preview = await _orders.previewCoupon(
        code: code.trim().toUpperCase(),
        vendorId: vendorId,
        subtotal: subtotal,
      );
      emit(
        state.copyWith(
          couponCode: code.trim().toUpperCase(),
          couponDiscount: preview.discount,
          couponFreeDelivery: preview.freeDelivery,
          couponTitle: preview.title,
        ),
      );
    } catch (error) {
      // The server names the rule that failed; the screen translates it.
      emit(state.copyWith(couponError: error.toString(), couponDiscount: null));
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
        orderType: state.orderType,
        scheduledAt: state.scheduledAt,
      );

      // For 'paymob' the order is created unpaid and stays hidden from the
      // restaurant until the webhook confirms payment. The view drives the
      // gateway from here.
      emit(state.copyWith(step: CheckoutStep.placed, placedOrderId: orderId));
    } catch (error) {
      emit(state.copyWith(step: CheckoutStep.editing, error: error.toString()));
    }
  }

  /// The card payment did not go through and the draft order was discarded —
  /// put the form back so the customer can retry or switch payment method.
  void resetAfterFailedPayment() =>
      emit(state.copyWith(step: CheckoutStep.editing, clearPlacedOrder: true));

  /// Switching away from a scheduled order drops the slot with it — leaving a
  /// time set on a delivery order would send it to the server to be rejected.
  void setOrderType(String type) =>
      emit(state.copyWith(orderType: type, clearSchedule: type != 'scheduled'));

  void setScheduledAt(DateTime? when) => emit(
    when == null
        ? state.copyWith(clearSchedule: true)
        : state.copyWith(orderType: 'scheduled', scheduledAt: when),
  );
}
