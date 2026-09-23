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
  }) => OrderDetailsState(
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
  OrderDetailsCubit(this._orders, this._reviews, this._payments, this.orderId)
    : super(const OrderDetailsState()) {
    _load();
  }

  final OrderRepository _orders;
  final ReviewRepository _reviews;
  final PaymentRepository _payments;
  final String orderId;

  StreamSubscription<AppOrder?>? _orderSubscription;
  RealtimeChannel? _trackingChannel;

  /// Re-reads the order. Used after an action that changes it outside the
  /// realtime stream's view — a tip stamps `driver_tip`, which the stream does
  /// carry, but the reload also refreshes the review flag in the same pass.
  Future<void> reload() => _load();

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        _orders.fetchOrder(orderId),
        _reviews.hasReview(orderId),
      ]);
      final order = results[0] as AppOrder;
      emit(
        state.copyWith(
          loading: false,
          order: order,
          items: order.items,
          hasReview: results[1] as bool,
        ),
      );
      _maybeTrack(order);
    } catch (error) {
      emit(state.copyWith(loading: false, error: error.toString()));
      return;
    }

    // Cancelled first: `reload()` runs this again, and without it every
    // reload would leave another live subscription emitting into the cubit.
    _orderSubscription?.cancel();
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
      // Draw something the moment the page opens, rather than waiting for the
      // driver's phone to broadcast — which may be a minute away, or never if
      // their app is asleep.
      _seedDriverPosition();
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

  /// Last position the driver's app stored, used until a live broadcast lands.
  Future<void> _seedDriverPosition() async {
    if (state.driverLocation != null) return;
    try {
      final position = await _orders.fetchDriverPosition(orderId);
      if (position == null || isClosed) return;
      // A broadcast that arrived while this was in flight is newer than the
      // stored row by definition, so it wins.
      if (state.driverLocation != null) return;
      emit(state.copyWith(driverLocation: LatLng(position.lat, position.lng)));
    } catch (_) {
      // Non-critical: the map falls back to the destination alone.
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

  /// Opens a fresh unified-checkout session for an unpaid Paymob order.
  Future<PaymobCheckout?> retryPayment() async {
    emit(state.copyWith(busy: true, clearError: true));
    try {
      final checkout = await _payments.createOrderCheckout(orderId);
      emit(state.copyWith(busy: false));
      return checkout;
    } catch (error) {
      emit(state.copyWith(busy: false, error: error.toString()));
      return null;
    }
  }

  /// One review covers the food and, when there was a driver, the delivery.
  /// A null [driverRating] means the customer skipped that half, and the
  /// driver's average never sees it.
  Future<bool> submitReview({
    required int rating,
    String? comment,
    int? driverRating,
    String? driverComment,
  }) async {
    final order = state.order;
    if (order == null) return false;
    try {
      await _reviews.submitReview(
        orderId: orderId,
        vendorId: order.vendorId,
        rating: rating,
        comment: comment,
        driverId: order.driverId,
        driverRating: order.driverId == null ? null : driverRating,
        driverComment: driverComment,
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
