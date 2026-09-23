import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/models/order.dart';
import 'package:multi_vendor/core/models/order_flow.dart';
import 'package:multi_vendor/features/admin/admin_orders_cubit.dart';

AppOrder _order({
  required String flow,
  required String status,
  String? driverId,
  String paymentMethod = 'cod',
  String paymentStatus = 'unpaid',
  String? releasedAt = '2026-09-23T10:00:00Z',
}) => AppOrder.fromMap({
  'id': 'o1',
  'customer_id': 'c1',
  'vendor_id': 'v1',
  'driver_id': driverId,
  'status': status,
  'order_flow': flow,
  'payment_method': paymentMethod,
  'payment_status': paymentStatus,
  'released_at': releasedAt,
  'created_at': '2026-09-23T10:00:00Z',
});

void main() {
  test('an unknown or missing flow reads as the store running it', () {
    expect(OrderFlow.fromName(null), OrderFlow.vendor);
    expect(OrderFlow.fromName('something'), OrderFlow.vendor);
    expect(OrderFlow.fromName('platform'), OrderFlow.platform);
    expect(OrderFlow.fromName('direct'), OrderFlow.direct);
    expect(OrderFlow.vendor.runsThroughStore, isTrue);
    expect(OrderFlow.platform.runsThroughStore, isFalse);
    expect(OrderFlow.direct.runsThroughStore, isFalse);
  });

  test('the order carries the flow it was placed under', () {
    expect(
      _order(flow: 'direct', status: 'pending').orderFlow,
      OrderFlow.direct,
    );
  });

  group('customerCanCancel mirrors update_order_status', () {
    test('any flow while pending', () {
      for (final flow in ['vendor', 'platform', 'direct']) {
        expect(_order(flow: flow, status: 'pending').customerCanCancel, isTrue);
      }
    });

    test('a direct order until a rider takes it', () {
      expect(
        _order(flow: 'direct', status: 'ready_for_pickup').customerCanCancel,
        isTrue,
      );
      expect(
        _order(
          flow: 'direct',
          status: 'ready_for_pickup',
          driverId: 'd1',
        ).customerCanCancel,
        isFalse,
      );
    });

    test('never once a store or operator has moved it on', () {
      expect(
        _order(flow: 'vendor', status: 'ready_for_pickup').customerCanCancel,
        isFalse,
      );
      expect(
        _order(flow: 'platform', status: 'ready_for_pickup').customerCanCancel,
        isFalse,
      );
    });
  });

  group('awaitsUs: what the operator has to accept now', () {
    test('a released platform order waiting for someone', () {
      expect(
        AdminOrdersState.awaitsUs(_order(flow: 'platform', status: 'pending')),
        isTrue,
      );
    });

    test('not a store\'s own order, nor a direct one', () {
      expect(
        AdminOrdersState.awaitsUs(_order(flow: 'vendor', status: 'pending')),
        isFalse,
      );
      expect(
        AdminOrdersState.awaitsUs(_order(flow: 'direct', status: 'pending')),
        isFalse,
      );
    });

    test('not a scheduled order before its slot, nor an unpaid card draft', () {
      expect(
        AdminOrdersState.awaitsUs(
          _order(flow: 'platform', status: 'pending', releasedAt: null),
        ),
        isFalse,
      );
      expect(
        AdminOrdersState.awaitsUs(
          _order(flow: 'platform', status: 'pending', paymentMethod: 'paymob'),
        ),
        isFalse,
      );
    });
  });
}
