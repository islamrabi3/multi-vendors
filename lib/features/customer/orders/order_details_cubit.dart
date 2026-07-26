import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/order.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/repositories/payment_repository.dart';
import '../../../core/repositories/review_repository.dart';
import '../../../core/supabase_client.dart';

class OrderDetailsState extends Equatable {
  const OrderDetailsState({
    this.loading = true,
    this.order,
    this.items = const [],
    this.driverLocation,
    this.driverContact,
    this.hasReview = false,
    this.error,
    this.busy = false,
  });

  final bool loading;
  final AppOrder? order;
  final List<OrderItem> items;
  final LatLng? driverLocation;
  final DriverContact? driverContact;
  final bool hasReview;
  final String? error;
  final bool busy;

  OrderDetailsState copyWith({
    bool? loading,
    AppOrder? order,
    List<OrderItem>? items,
    LatLng? driverLocation,
    DriverContact? driverContact,
    bool? hasReview,
    String? error,
    bool? busy,
    bool clearError = false,
  }) =>
      OrderDetailsState(
        loading: loading ?? this.loading,
        order: order ?? this.order,
        items: items ?? this.items,
        driverLocation: driverLocation ?? this.driverLocation,
        driverContact: driverContact ?? this.driverContact,
        hasReview: hasReview ?? this.hasReview,
        error: clearError ? null : (error ?? this.error),
        busy: busy ?? this.busy,
      );

  @override
  List<Object?> get props => [
        loading,
        order,
        items,
        driverLocation,
        driverContact,
        hasReview,
        error,
        busy,
      ];
}

/// Streams a single order in realtime and, while it is out for delivery,
/// listens to the driver's GPS broadcasts on `order-tracking:{orderId}`.
class OrderDetailsCubit extends Cubit<OrderDetailsState> {
  OrderDetailsCubit(
    this._orders,
    this._reviews,
    this._payments,
    this.orderId,
  ) : super(const OrderDetailsState()) {
    _load();
  }

  final OrderRepository _orders;
  final ReviewRepository _reviews;
  final PaymentRepository _payments;
  final String orderId;

  StreamSubscription<AppOrder?>? _orderSubscription;
  RealtimeChannel? _trackingChannel;

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        _orders.fetchOrder(orderId),
        _reviews.hasReview(orderId),
      ]);
      final order = results[0] as AppOrder;
      emit(state.copyWith(
        loading: false,
        order: order,
        items: order.items,
        hasReview: results[1] as bool,
      ));
      _maybeTrack(order);
    } catch (error) {
      emit(state.copyWith(loading: false, error: error.toString()));
      return;
    }

    _orderSubscription = _orders.orderStream(orderId).listen((order) {
      if (order == null) return;
      emit(state.copyWith(order: order));
      _maybeTrack(order);
    });
  }

  void _maybeTrack(AppOrder order) {
    if (order.status == OrderStatus.outForDelivery &&
        _trackingChannel == null) {
      _loadDriverContact();
      _trackingChannel = supabase.channel('order-tracking:$orderId')
        ..onBroadcast(
          event: 'location',
          callback: (payload) {
            final lat = (payload['lat'] as num?)?.toDouble();
            final lng = (payload['lng'] as num?)?.toDouble();
            if (lat != null && lng != null) {
              emit(state.copyWith(driverLocation: LatLng(lat, lng)));
            }
          },
        )
        ..subscribe();
    } else if (order.status.isTerminal && _trackingChannel != null) {
      _trackingChannel?.unsubscribe();
      _trackingChannel = null;
    }
  }

  Future<void> _loadDriverContact() async {
    if (state.driverContact != null) return;
    try {
      final contact = await _orders.fetchDriverContact(orderId);
      if (contact != null && !isClosed) {
        emit(state.copyWith(driverContact: contact));
      }
    } catch (_) {
      // Non-critical: the call button just stays hidden.
    }
  }

  Future<void> cancelOrder() async {
    emit(state.copyWith(busy: true, clearError: true));
    try {
      await _orders.updateStatus(orderId, OrderStatus.cancelled);
      emit(state.copyWith(busy: false));
    } catch (error) {
      emit(state.copyWith(busy: false, error: error.toString()));
    }
  }

  /// Retry payment for an unpaid Paymob order. Returns the checkout URL.
  Future<String?> retryPayment() async {
    emit(state.copyWith(busy: true, clearError: true));
    try {
      final url = await _payments.createPaymobCheckout(orderId);
      emit(state.copyWith(busy: false));
      return url;
    } catch (error) {
      emit(state.copyWith(busy: false, error: error.toString()));
      return null;
    }
  }

  Future<bool> submitReview(int rating, String? comment) async {
    final order = state.order;
    if (order == null) return false;
    try {
      await _reviews.submitReview(
        orderId: orderId,
        vendorId: order.vendorId,
        rating: rating,
        comment: comment,
      );
      emit(state.copyWith(hasReview: true));
      return true;
    } catch (error) {
      emit(state.copyWith(error: error.toString()));
      return false;
    }
  }

  @override
  Future<void> close() {
    _orderSubscription?.cancel();
    _trackingChannel?.unsubscribe();
    return super.close();
  }
}
