import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/app/theme.dart';
import 'package:multi_vendor/features/vendor/widgets/store_state_controls.dart';
import 'package:multi_vendor/l10n/app_localizations.dart';

/// The vendor dashboard rendered as a blank white pane on desktop web, twice.
///
/// `StoreOpenToggle` holds a flex child. In the mobile header it is a child of
/// a Column, which hands it a bounded width, and a tight flex child is fine.
/// The desktop strip puts it at the end of a Row instead — and a Row measures
/// its **non-flex** children with an unbounded width before it divides the
/// remainder among the flex ones. A tight flex child under an unbounded width
/// is a hard layout error, not an overflow stripe: it takes the whole subtree
/// down, which is why the screen went blank rather than merely ugly.
///
/// `flutter analyze` and `flutter build web` both pass on the broken version —
/// neither one lays anything out — and the web branch that reaches this is
/// gated on `kIsWeb`, so no test can reach it through the screen. Pumping the
/// widget directly in both parent shapes is the coverage that exists.
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: buildTheme(),
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('ar')],
    home: Scaffold(body: child),
  );

  StoreOpenToggle openToggle({required bool expand, String? closingTime}) =>
      StoreOpenToggle(
        isOpen: true,
        busy: false,
        onChanged: (_) {},
        closingTime: closingTime,
        expand: expand,
      );

  /// The `_WebVendorStrip` composition, as the dashboard builds it.
  Widget strip() => Row(
    children: [
      // The store-name column. Its flex is what forces the Row to measure
      // every non-flex sibling with an unbounded width first.
      const Expanded(child: Text('A store with quite a long name')),
      const SizedBox(width: 12),
      Flexible(
        child: StoreBusyToggle(
          isBusy: false,
          pending: false,
          onChanged: (_) {},
        ),
      ),
      const SizedBox(width: 8),
      Flexible(child: openToggle(expand: false, closingTime: '23:00')),
    ],
  );

  testWidgets('shrink-wraps as a non-flex child of a Row (the web strip)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Row(
          children: [
            const Expanded(child: Text('A store with quite a long name')),
            const SizedBox(width: 12),
            StoreBusyToggle(isBusy: false, pending: false, onChanged: (_) {}),
            const SizedBox(width: 8),
            openToggle(expand: false, closingTime: '23:00'),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the real strip survives every width it can be given', (
    tester,
  ) async {
    // 1160 is what a maximised window gives it; 420 is far below the 900px
    // floor for the web layout and is here as headroom. A bare non-flex pill
    // overflowed by 78px at the low end, which is why the strip wraps both
    // toggles in a loose Flexible.
    for (final width in [1160.0, 900.0, 640.0, 420.0]) {
      await tester.pumpWidget(host(SizedBox(width: width, child: strip())));
      expect(tester.takeException(), isNull, reason: 'width: $width');
    }
  });

  testWidgets('expand: true still fills a Column (the mobile header)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(Column(children: [openToggle(expand: true, closingTime: '23:00')])),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shrink-wrapped pill is narrower than the full-width one', (
    tester,
  ) async {
    // Guards the fix from being "corrected" back to a tight flex child, which
    // would compile, pass the smoke tests above in a Column, and crash again
    // in the Row.
    await tester.pumpWidget(
      host(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 600,
              child: openToggle(expand: true, closingTime: '23:00'),
            ),
            SizedBox(
              width: 600,
              child: Row(
                children: [openToggle(expand: false, closingTime: '23:00')],
              ),
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final sizes = tester
        .widgetList<StoreOpenToggle>(find.byType(StoreOpenToggle))
        .map((w) => tester.getSize(find.byWidget(w)).width)
        .toList();
    expect(sizes, hasLength(2));
    expect(sizes.first, 600, reason: 'expand: true fills its 600px parent');
    expect(
      sizes.last,
      lessThan(600),
      reason: 'expand: false sizes to its content',
    );
  });

  testWidgets('a long label ellipsises rather than overflowing the Row', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 220,
          child: Row(
            children: [
              const Expanded(child: Text('Name')),
              Flexible(child: openToggle(expand: false, closingTime: '23:00')),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy toggle is safe as a bare Row child in both states', (
    tester,
  ) async {
    for (final busy in [true, false]) {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 260,
            child: Row(
              children: [
                const Expanded(child: Text('Name')),
                Flexible(
                  child: StoreBusyToggle(
                    isBusy: busy,
                    pending: busy,
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'isBusy: $busy');
    }
  });
}
