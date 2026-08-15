import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/models/cart_item.dart';
import 'package:multi_vendor/core/models/product.dart';
import 'package:multi_vendor/core/models/vendor.dart';

Vendor _vendor({double deliveryFee = 15}) => Vendor(
  id: 'v1',
  ownerId: 'owner',
  name: 'Store',
  isOpen: true,
  isActive: true,
  approvalStatus: 'active',
  autoAccept: false,
  deliveryFee: deliveryFee,
  minOrderAmount: 0,
  avgPrepMinutes: 20,
  ratingAvg: 0,
  ratingCount: 0,
);

Product _product(double price) => Product(
  id: 'p1',
  vendorId: 'v1',
  name: 'Item',
  price: price,
  isAvailable: true,
);

const _addon = ProductOption(
  id: 'o1',
  groupId: 'g1',
  name: 'Extra',
  priceDelta: 5,
);

void main() {
  group('Checkout total math', () {
    test('total = subtotal + delivery - discount', () {
      final items = [
        CartItem(product: _product(100), quantity: 2),
        CartItem(
          product: _product(50),
          quantity: 1,
          selectedOptions: const [_addon],
        ),
      ];
      final subtotal = items.fold<double>(0, (s, i) => s + i.lineTotal);
      expect(subtotal, 255); // (100*2) + (50+5)*1

      const discount = 20.0;
      final vendor = _vendor(deliveryFee: 15);
      final total = subtotal - discount + vendor.deliveryFee;
      expect(total, 250); // 255 - 20 + 15
    });

    test('zero discount leaves total = subtotal + delivery', () {
      final items = [CartItem(product: _product(80), quantity: 3)];
      final subtotal = items.fold<double>(0, (s, i) => s + i.lineTotal);
      expect(subtotal, 240);

      final vendor = _vendor(deliveryFee: 10);
      final total = subtotal + vendor.deliveryFee;
      expect(total, 250);
    });

    test('line total with multiple options sums correctly', () {
      const opt1 = ProductOption(
        id: 'o1',
        groupId: 'g1',
        name: 'Size L',
        priceDelta: 15,
      );
      const opt2 = ProductOption(
        id: 'o2',
        groupId: 'g2',
        name: 'Extra cheese',
        priceDelta: 10,
      );
      final item = CartItem(
        product: _product(60),
        quantity: 2,
        selectedOptions: const [opt1, opt2],
      );
      expect(item.unitPrice, 85); // 60 + 15 + 10
      expect(item.lineTotal, 170); // 85 * 2
    });
  });
}
