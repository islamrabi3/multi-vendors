import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/order.dart';
import '../../core/repositories/driver_repository.dart';
import '../../core/repositories/order_repository.dart';

class ActiveDeliveryState extends Equatable {
  const ActiveDeliveryState({
    this.loading = true,
    this.order,
    this.vendorName,
    this.vendorLocation,
    this.myLocation,
    this.error,
    this.busy = false,
  });

  final bool loading;
  final AppOrder? order;
  final String? vendorName;
  final LatLng? vendorLocation;
  final LatLng? myLocation;
  final String? error;
  final bool busy;

  ActiveDeliveryState copyWith({
    bool? loading,
    AppOrder? order,
    String? vendorName,
    LatLng? vendorLocation,
    LatLng? myLocation,
    String? error,
    bool? busy,
    bool clearOrder = false,
    bool clearError = false,
  }) =>
      ActiveDeliveryState(
        loading: loading ?? this.loading,
        order: clearOrder ? null : (order ?? this.order),
        vendorName: vendorName ?? this.vendorName,
        vendorLocation: vendorLocation ?? this.vendorLocation,
        myLocation: myLocation ?? this.myLocation,
        error: clearError ? null : (error ?? this.error),
        busy: busy ?? this.busy,
      );

  @override
  List<Object?> get props =>
      [loading, order, vendorName, vendorLocation, myLocation, error, busy];
}

/// The driver's current out_for_delivery order. While active:
///  - streams GPS positions and broadcasts them on order-tracking:{orderId}
///    every few seconds (the customer's map listens there), and
///  - refreshes drivers.current_lat/lng on a slow cadence.
class ActiveDeliveryCubit extends Cubit<ActiveDeliveryState> {
  ActiveDeliveryCubit(this._orders, this._driver, this._supabase)
      : super(const ActiveDeliveryState()) {
    _init();
  }

  static const _storedLocationInterval = Duration(seconds: 30);

  final OrderRepository _orders;
  final DriverRepository _driver;
  final SupabaseClient _supabase;

  StreamSubscription<List<AppOrder>>? _ordersSubscription;
  StreamSubscription<Position>? _positionSubscription;
  RealtimeChannel? _trackingChannel;
  DateTime _lastStoredUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _init() async {
    _ordersSubscription = _orders.driverOrdersStream().listen((orders) {
      final active = orders
          .where((o) => o.status == OrderStatus.outForDelivery)
          .firstOrNull;
      if (active == null) {
        _stopTracking();
        emit(state.copyWith(loading: false, clearOrder: true));
        return;
      }
      final changedOrder = state.order?.id != active.id;
      emit(state.copyWith(loading: false, order: active));
      if (changedOrder) {
        _loadVendor(active.vendorId);
        _startTracking(active.id);
      }
    }, onError: (Object error) {
      emit(state.copyWith(loading: false, error: error.toString()));
    });
  }

  Future<void> _loadVendor(String vendorId) async {
    try {
      final data = await _supabase
          .from('vendors')
          .select('name, lat, lng')
          .eq('id', vendorId)
          .single();
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      emit(state.copyWith(
        vendorName: data['name'] as String?,
        vendorLocation: lat != null && lng != null ? LatLng(lat, lng) : null,
      ));
    } catch (_) {}
  }

  Future<void> _startTracking(String orderId) async {
    _stopTracking();
    _trackingChannel = _driver.trackingChannel(orderId)..subscribe();

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        emit(state.copyWith(
            error: 'LOCATION_PERMISSION_DENIED'));
        return;
      }
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(distanceFilter: 15),
      ).listen(_onPosition);
    } catch (error) {
      emit(state.copyWith(error: error.toString()));
    }
  }

  Future<void> _onPosition(Position position) async {
    final location = LatLng(position.latitude, position.longitude);
    emit(state.copyWith(myLocation: location));
    final channel = _trackingChannel;
    if (channel != null) {
      try {
        await _driver.broadcastLocation(
            channel, position.latitude, position.longitude);
      } catch (_) {}
    }
    if (DateTime.now().difference(_lastStoredUpdate) >
        _storedLocationInterval) {
      _lastStoredUpdate = DateTime.now();
      _driver
          .updateStoredLocation(position.latitude, position.longitude)
          .catchError((_) {});
    }
  }

  void _stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _trackingChannel?.unsubscribe();
    _trackingChannel = null;
  }

  /// Pull-to-refresh: re-fetch the driver's orders once and re-resolve the
  /// active (out_for_delivery) one, covering a missed realtime event (e.g. an
  /// admin just assigned this driver).
  Future<void> refresh() async {
    try {
      final orders = await _orders.fetchDriverOrders();
      final active = orders
          .where((o) => o.status == OrderStatus.outForDelivery)
          .firstOrNull;
      if (active == null) {
        _stopTracking();
        emit(state.copyWith(loading: false, clearOrder: true));
        return;
      }
      final changedOrder = state.order?.id != active.id;
      emit(state.copyWith(loading: false, order: active));
      if (changedOrder) {
        _loadVendor(active.vendorId);
        _startTracking(active.id);
      }
    } catch (error) {
      emit(state.copyWith(loading: false, error: error.toString()));
    }
  }

  Future<void> markDelivered({String? proofUrl}) async {
    final order = state.order;
    if (order == null) return;
    emit(state.copyWith(busy: true, clearError: true));
    try {
      await _orders.updateStatus(order.id, OrderStatus.delivered, proofUrl: proofUrl);
      emit(state.copyWith(busy: false));
    } catch (error) {
      emit(state.copyWith(busy: false, error: error.toString()));
    }
  }

  @override
  Future<void> close() {
    _ordersSubscription?.cancel();
    _stopTracking();
    return super.close();
  }
}
