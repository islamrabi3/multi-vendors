import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/models/order.dart';
import 'package:multi_vendor/core/utils/money.dart';
import 'package:multi_vendor/core/widgets/common.dart';

import 'package:multi_vendor/l10n/app_localizations.dart';

void main() {
  group('OrderStatusChip renders all statuses', () {
    for (final status in OrderStatus.values) {
      testWidgets(status.wireName, (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: OrderStatusChip(status: status)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(OrderStatusChip), findsOneWidget);
      });
    }
  });

  testWidgets('QuantityStepper increments and decrements', (tester) async {
    int value = 3;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => QuantityStepper(
              quantity: value,
              onChanged: (q) => setState(() => value = q),
            ),
          ),
        ),
      ),
    );
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(value, 4);

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(value, 3);
  });

  testWidgets('EmptyView shows message and icon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyView(message: 'No items', icon: Icons.inbox),
        ),
      ),
    );
    expect(find.text('No items'), findsOneWidget);
    expect(find.byIcon(Icons.inbox), findsOneWidget);
  });

  test('formatMoney formats EGP correctly', () {
    final result = formatMoney(125.5);
    expect(result, contains('125'));
    expect(result, contains('EGP'));
  });

  test('readableError maps known errors', () {
    expect(readableError('CART_EMPTY'), 'Your cart is empty.');
    expect(readableError('VENDOR_CLOSED'), 'This store is currently closed.');
    expect(readableError('unknown_xyz'), 'Something went wrong. Please try again.');
  });
}
