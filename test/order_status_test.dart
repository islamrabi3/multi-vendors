import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/models/order.dart';

void main() {
  test('order status round-trips through wire names', () {
    for (final status in OrderStatus.values) {
      expect(OrderStatus.fromName(status.wireName), status);
    }
  });

  test('unknown wire name falls back to pending', () {
    expect(OrderStatus.fromName('bogus'), OrderStatus.pending);
    expect(OrderStatus.fromName(null), OrderStatus.pending);
  });

  test('terminal statuses', () {
    expect(OrderStatus.delivered.isTerminal, isTrue);
    expect(OrderStatus.cancelled.isTerminal, isTrue);
    expect(OrderStatus.rejected.isTerminal, isTrue);
    expect(OrderStatus.outForDelivery.isTerminal, isFalse);
    expect(OrderStatus.pending.isTerminal, isFalse);
  });
}
