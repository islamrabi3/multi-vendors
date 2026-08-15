import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/models/cart_item.dart';
import 'package:multi_vendor/core/models/coupon.dart';
import 'package:multi_vendor/core/models/order.dart';
import 'package:multi_vendor/core/models/product.dart';
import 'package:multi_vendor/core/models/review.dart';
import 'package:multi_vendor/features/auth/auth_cubit.dart';
import 'package:multi_vendor/features/customer/cart/cart_cubit.dart';

/// The rules that decide money, and who is allowed to move it.
///
/// The server owns every one of these decisions — totals, coupon validity and
/// permissions are all recomputed there, and these tests do not reach it. What
/// they pin down is the app's copy of the same rules, which is what a customer
/// reads before they commit and what the console hides buttons on. The two
/// disagreeing is how somebody is shown one price and charged another.
Product _product({
  String id = 'p1',
  double price = 10,
  bool available = true,
}) => Product(
  id: id,
  vendorId: 'v1',
  name: 'Item $id',
  price: price,
  isAvailable: available,
);

Coupon _coupon({
  String type = 'percentage',
  double value = 10,
  double? maxDiscount,
  int? usageLimit,
  int usedCount = 0,
  int? perUserLimit = 1,
  bool isActive = true,
  DateTime? startsAt,
  DateTime? expiresAt,
}) => Coupon(
  id: 'c1',
  code: 'SAVE',
  discountType: type,
  value: value,
  minOrderAmount: 0,
  usedCount: usedCount,
  isActive: isActive,
  maxDiscount: maxDiscount,
  usageLimit: usageLimit,
  perUserLimit: perUserLimit,
  startsAt: startsAt,
  expiresAt: expiresAt,
);

void main() {
  group('cart totals', () {
    test('option price deltas are added per unit, not per line', () {
      final item = CartItem(
        product: _product(price: 10),
        quantity: 3,
        selectedOptions: const [
          ProductOption(id: 'o1', groupId: 'g1', name: 'Large', priceDelta: 2),
          ProductOption(id: 'o2', groupId: 'g2', name: 'Extra', priceDelta: 1),
        ],
      );

      expect(item.unitPrice, 13);
      // 13 x 3, not 10 x 3 + 3.
      expect(item.lineTotal, 39);
    });

    test('an unavailable line is excluded from the subtotal', () {
      final gone = _product(id: 'gone');
      final ok = _product(id: 'ok', price: 25);
      final state = CartState(
        items: [
          CartItem(product: gone, quantity: 2),
          CartItem(product: ok, quantity: 1),
        ],
        unavailable: const ['gone'],
      );

      // The number under the button has to be the number that gets charged.
      expect(state.subtotal, 25);
      expect(state.canCheckout, isFalse);
    });

    test('identical items merge only when options and notes match', () {
      final base = CartItem(product: _product(), quantity: 1);
      final withNote = CartItem(
        product: _product(),
        quantity: 1,
        notes: 'no onions',
      );
      final withOption = CartItem(
        product: _product(),
        quantity: 1,
        selectedOptions: const [
          ProductOption(id: 'o1', groupId: 'g1', name: 'Large', priceDelta: 2),
        ],
      );

      expect(base.signature, isNot(withNote.signature));
      expect(base.signature, isNot(withOption.signature));
      expect(
        base.signature,
        CartItem(product: _product(), quantity: 9).signature,
      );
    });
  });

  group('coupon rules', () {
    test('a code past its expiry is not live', () {
      final coupon = _coupon(
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(coupon.isExpired, isTrue);
      expect(coupon.isLive, isFalse);
    });

    test('a code before its start date is scheduled, not live', () {
      final coupon = _coupon(
        startsAt: DateTime.now().add(const Duration(days: 1)),
      );
      expect(coupon.isScheduled, isTrue);
      expect(coupon.isLive, isFalse);
    });

    test('a fully claimed campaign is exhausted and not live', () {
      final coupon = _coupon(usageLimit: 100, usedCount: 100);
      expect(coupon.isExhausted, isTrue);
      expect(coupon.isLive, isFalse);
    });

    test('an inactive code is never live even inside its window', () {
      expect(_coupon(isActive: false).isLive, isFalse);
    });

    test('a live code is live', () {
      final coupon = _coupon(
        startsAt: DateTime.now().subtract(const Duration(days: 1)),
        expiresAt: DateTime.now().add(const Duration(days: 1)),
        usageLimit: 10,
        usedCount: 3,
      );
      expect(coupon.isLive, isTrue);
    });

    test('free delivery carries no value of its own', () {
      final coupon = _coupon(type: 'free_delivery', value: 0);
      expect(coupon.isFreeDelivery, isTrue);
      expect(coupon.isPercentage, isFalse);
    });

    test('a null per-user limit means unlimited, which is not the default', () {
      // Every code created before the limit existed is unlimited, and the
      // admin form defaults new ones to 1. Confusing the two either lets a
      // code be spent repeatedly or silently tightens a live campaign.
      expect(_coupon(perUserLimit: null).perUserLimit, isNull);
      expect(_coupon().perUserLimit, 1);
    });
  });

  group('order type rules', () {
    AppOrder order({
      String type = 'delivery',
      String? driverId,
      double tip = 0,
      DateTime? releasedAt,
    }) => AppOrder(
      id: 'o1',
      orderNumber: '#1',
      customerId: 'c1',
      vendorId: 'v1',
      driverId: driverId,
      status: OrderStatus.delivered,
      subtotal: 100,
      deliveryFee: 15,
      discount: 0,
      total: 115,
      paymentMethod: 'cod',
      paymentStatus: 'paid',
      createdAt: DateTime.now(),
      deliveryAddress: const {},
      orderType: type,
      driverTip: tip,
      releasedAt: releasedAt,
    );

    test('a pickup order is recognised as one', () {
      expect(order(type: 'pickup').isPickup, isTrue);
      expect(order().isPickup, isFalse);
    });

    test('a scheduled order is withheld from the store until released', () {
      expect(order(type: 'scheduled').isReleased, isFalse);
      expect(order(releasedAt: DateTime.now()).isReleased, isTrue);
    });

    test('an already-tipped order is distinguishable from an untipped one', () {
      // The tip card keys off this; showing the form twice invites a second
      // tip the server would refuse.
      expect(order(tip: 20).driverTip, greaterThan(0));
      expect(order().driverTip, 0);
    });
  });

  group('admin permissions', () {
    AppAuthState withPermissions(List<String> permissions) => AppAuthState(
      status: AuthStatus.authenticated,
      permissions: permissions,
    );

    test('an unrestricted admin holds everything', () {
      final owner = withPermissions(['*']);
      expect(owner.can('users.block'), isTrue);
      expect(owner.can('payments.refund'), isTrue);
      expect(owner.can('anything.at.all'), isTrue);
    });

    test('a limited role holds only what it lists', () {
      final catalogue = withPermissions(['catalog.manage', 'promos.manage']);
      expect(catalogue.can('catalog.manage'), isTrue);
      expect(catalogue.can('users.block'), isFalse);
      expect(catalogue.can('payments.refund'), isFalse);
    });

    test('a non-admin holds nothing', () {
      expect(withPermissions(const []).can('orders.view'), isFalse);
    });
  });

  group('rating breakdown', () {
    test('an unrated store divides by zero nowhere', () {
      expect(RatingBreakdown.empty.share(5), 0);
      expect(RatingBreakdown.empty.total, 0);
    });

    test('shares are a fraction of the total', () {
      const breakdown = RatingBreakdown(
        total: 10,
        average: 4.2,
        counts: {5: 5, 4: 3, 3: 2, 2: 0, 1: 0},
      );
      expect(breakdown.share(5), 0.5);
      expect(breakdown.share(3), closeTo(0.2, 0.0001));
      expect(breakdown.share(1), 0);
    });
  });
}
