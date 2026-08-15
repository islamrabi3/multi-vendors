import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/models/cart_item.dart';
import 'package:multi_vendor/core/models/product.dart';
import 'package:multi_vendor/core/models/vendor.dart';
import 'package:multi_vendor/features/customer/cart/cart_cubit.dart';
import 'package:multi_vendor/features/customer/vendor_details/product_quantity_control.dart';

/// The + on a menu row, which becomes a stepper once the item is in the cart.
///
/// Worth a test rather than an eyeball: the control has three states and the
/// transitions between them are the whole feature. Getting stuck expanded at
/// zero, or never expanding, both look like the button is broken.
Vendor _vendor({String id = 'v1'}) => Vendor(
  id: id,
  ownerId: 'o1',
  name: 'Store $id',
  isOpen: true,
  isActive: true,
  approvalStatus: 'active',
  autoAccept: true,
  deliveryFee: 10,
  minOrderAmount: 0,
  avgPrepMinutes: 20,
  ratingAvg: 4.5,
  ratingCount: 10,
);

Product _product({
  String id = 'p1',
  String vendorId = 'v1',
  List<ProductOptionGroup> optionGroups = const [],
}) => Product(
  id: id,
  vendorId: vendorId,
  name: 'Item $id',
  price: 25,
  isAvailable: true,
  optionGroups: optionGroups,
);

Future<CartCubit> _pump(
  WidgetTester tester, {
  required Product product,
  Vendor? vendor,
  CartCubit? cubit,
}) async {
  final cart = cubit ?? CartCubit();
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<CartCubit>.value(
        value: cart,
        child: Scaffold(
          body: Center(
            child: ProductQuantityControl(
              vendor: vendor ?? _vendor(),
              product: product,
            ),
          ),
        ),
      ),
    ),
  );
  return cart;
}

void main() {
  testWidgets('starts collapsed: a plus, no count, no minus', (tester) async {
    await _pump(tester, product: _product());

    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsNothing);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('first tap adds one and expands the stepper', (tester) async {
    final cart = await _pump(tester, product: _product());

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(cart.state.items.single.quantity, 1);
    expect(find.text('1'), findsOneWidget);
    // At one, minus is a delete: the next press removes the line entirely, and
    // a bin says that where a minus implies going to zero.
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
  });

  testWidgets('tapping plus twice makes it two', (tester) async {
    final cart = await _pump(tester, product: _product());

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(cart.state.items.single.quantity, 2);
    expect(find.text('2'), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsOneWidget);
  });

  testWidgets('minus twice returns it to a plain plus', (tester) async {
    final cart = await _pump(tester, product: _product());

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    expect(cart.state.items.single.quantity, 1);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();

    expect(cart.state.items, isEmpty);
    expect(find.text('1'), findsNothing);
    expect(find.byIcon(Icons.remove), findsNothing);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('an item with options never steps inline', (tester) async {
    final withOptions = _product(
      optionGroups: const [
        ProductOptionGroup(
          id: 'g1',
          productId: 'p1',
          name: 'Size',
          minSelect: 1,
          maxSelect: 1,
        ),
      ],
    );
    var configureCalls = 0;
    final cart = CartCubit();

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<CartCubit>.value(
          value: cart,
          child: Scaffold(
            body: Center(
              child: ProductQuantityControl(
                vendor: _vendor(),
                product: withOptions,
                onConfigure: () => configureCalls++,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // The sheet decides what goes in; the + must not add anything by itself.
    expect(configureCalls, 1);
    expect(cart.state.items, isEmpty);
  });

  testWidgets('a cart from another store reads as empty here', (tester) async {
    // Otherwise the control would show the other store's quantity and offer to
    // step a line the customer is about to lose.
    final cart = CartCubit()
      ..addItem(
        _vendor(id: 'other'),
        CartItem(
          product: _product(id: 'p1', vendorId: 'other'),
          quantity: 3,
        ),
      );

    await _pump(tester, product: _product(), cubit: cart);

    expect(find.text('3'), findsNothing);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsNothing);
  });
}
