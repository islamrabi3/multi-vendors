import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/models/cart_item.dart';
import 'package:multi_vendor/core/models/product.dart';
import 'package:multi_vendor/core/models/vendor.dart';
import 'package:multi_vendor/features/customer/cart/cart_cubit.dart';

Vendor vendor(String id, {String name = 'Store'}) => Vendor(
      id: id,
      ownerId: 'owner',
      name: name,
      isOpen: true,
      isActive: true,
      deliveryFee: 20,
      minOrderAmount: 0,
      avgPrepMinutes: 20,
      ratingAvg: 0,
      ratingCount: 0,
    );

Product product(String id, double price, {String vendorId = 'v1'}) => Product(
      id: id,
      vendorId: vendorId,
      name: 'Product $id',
      price: price,
      isAvailable: true,
    );

const cheese = ProductOption(
    id: 'opt-cheese', groupId: 'g1', name: 'Extra Cheese', priceDelta: 10);
const bacon = ProductOption(
    id: 'opt-bacon', groupId: 'g1', name: 'Bacon', priceDelta: 20);

void main() {
  group('CartItem pricing', () {
    test('unit price includes option deltas', () {
      final item = CartItem(
        product: product('p1', 95),
        quantity: 2,
        selectedOptions: const [cheese, bacon],
      );
      expect(item.unitPrice, 125);
      expect(item.lineTotal, 250);
    });

    test('signature differs per option selection', () {
      final plain = CartItem(product: product('p1', 95), quantity: 1);
      final withCheese = CartItem(
          product: product('p1', 95),
          quantity: 1,
          selectedOptions: const [cheese]);
      expect(plain.signature, isNot(withCheese.signature));
    });
  });

  group('CartCubit', () {
    blocTest<CartCubit, CartState>(
      'adds items and merges identical selections',
      build: CartCubit.new,
      act: (cubit) {
        final v = vendor('v1');
        cubit.addItem(v,
            CartItem(product: product('p1', 50), quantity: 1));
        cubit.addItem(v,
            CartItem(product: product('p1', 50), quantity: 2));
        cubit.addItem(
            v,
            CartItem(
                product: product('p1', 50),
                quantity: 1,
                selectedOptions: const [cheese]));
      },
      verify: (cubit) {
        expect(cubit.state.items, hasLength(2));
        expect(cubit.state.items.first.quantity, 3);
        expect(cubit.state.itemCount, 4);
        expect(cubit.state.subtotal, 50 * 3 + 60);
      },
    );

    blocTest<CartCubit, CartState>(
      'updating quantity to zero removes the item and empties the cart',
      build: CartCubit.new,
      act: (cubit) {
        final item = CartItem(product: product('p1', 50), quantity: 2);
        cubit.addItem(vendor('v1'), item);
        cubit.updateQuantity(item, 0);
      },
      verify: (cubit) {
        expect(cubit.state.isEmpty, isTrue);
        expect(cubit.state.vendor, isNull);
      },
    );

    test('conflictsWithCart flags a different vendor', () {
      final cubit = CartCubit();
      cubit.addItem(
          vendor('v1'), CartItem(product: product('p1', 50), quantity: 1));
      expect(cubit.conflictsWithCart(vendor('v2')), isTrue);
      expect(cubit.conflictsWithCart(vendor('v1')), isFalse);
    });

    blocTest<CartCubit, CartState>(
      'startNewCart replaces the previous vendor cart',
      build: CartCubit.new,
      act: (cubit) {
        cubit.addItem(
            vendor('v1'), CartItem(product: product('p1', 50), quantity: 3));
        cubit.startNewCart(vendor('v2'),
            CartItem(product: product('p2', 80, vendorId: 'v2'), quantity: 1));
      },
      verify: (cubit) {
        expect(cubit.state.vendor!.id, 'v2');
        expect(cubit.state.items, hasLength(1));
        expect(cubit.state.subtotal, 80);
      },
    );
  });
}
