import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/models/vendor.dart';
import 'package:multi_vendor/core/widgets/vendor_card.dart';
import 'package:multi_vendor/l10n/app_localizations.dart';

/// An open store's photo must not be filtered at all.
///
/// The card greys out a closed store with a saturation matrix, and the "no
/// filter" branch was written as `ColorFilter.mode(Colors.transparent,
/// BlendMode.multiply)`. That is not a no-op: transparent is (0,0,0,0) once
/// premultiplied, so multiplying by it zeroes every channel and the photo
/// renders fully invisible. Every open store on the home, category and search
/// pages lost its image, and nothing in the analyzer or a build could see it.
void main() {
  Vendor vendor({required bool isOpen}) => Vendor(
    id: 'v1',
    ownerId: 'o1',
    name: 'Test Store',
    isOpen: isOpen,
    isActive: true,
    approvalStatus: 'active',
    autoAccept: false,
    deliveryFee: 20,
    minOrderAmount: 0,
    avgPrepMinutes: 20,
    ratingAvg: 4.5,
    ratingCount: 100,
    coverUrl: 'https://example.invalid/cover.jpg',
  );

  Widget host(Vendor v) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: VendorCard(vendor: v)),
  );

  testWidgets('an open store\'s image is not colour-filtered', (tester) async {
    await tester.pumpWidget(host(vendor(isOpen: true)));
    expect(find.byType(ColorFiltered), findsNothing);
  });

  testWidgets('a closed store\'s image is greyed out', (tester) async {
    await tester.pumpWidget(host(vendor(isOpen: false)));
    expect(find.byType(ColorFiltered), findsOneWidget);

    // And the filter it uses must actually preserve alpha — a matrix whose
    // alpha row zeroed out would be the same invisible-image bug in a
    // different costume.
    final filtered = tester.widget<ColorFiltered>(find.byType(ColorFiltered));
    expect(
      filtered.colorFilter,
      isNot(
        equals(const ColorFilter.mode(Colors.transparent, BlendMode.multiply)),
      ),
    );
  });
}
