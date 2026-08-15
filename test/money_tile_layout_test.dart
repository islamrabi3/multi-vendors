import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/app/theme.dart';
import 'package:multi_vendor/core/widgets/finance_widgets.dart';
import 'package:multi_vendor/l10n/app_localizations.dart';

/// `MoneyTile` sits in a fixed-ratio grid, so the grid decides its height and
/// the content has to fit whatever it is given. A two-line label plus a value
/// overflowed a cell sized for one line — and the finance screens are exactly
/// where a striped bar across a number destroys trust fastest.
///
/// These pump it at the real geometry the dashboards use.
void main() {
  /// A real phone. The default 800pt test surface makes each grid cell about
  /// four times the area it has on a device, which hides exactly this class of
  /// bug — the first version of this test passed against the broken widget.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget host({
    required String label,
    required String value,
    double aspectRatio = 1.95,
    double scale = 1.0,
  }) => MaterialApp(
    theme: buildTheme(),
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('ar')],
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: GridView.count(
          crossAxisCount: 2,
          childAspectRatio: aspectRatio,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [MoneyTile(label: label, value: value)],
        ),
      ),
    ),
  );

  // The label that actually overflowed on the admin dashboard.
  const longLabel = 'Discounts funded by platform';

  testWidgets('a two-line label does not overflow its grid cell', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(host(label: longLabel, value: '-EGP 20.00'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('it survives the 1.3x text scale the app allows', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      host(label: longLabel, value: '-EGP 20.00', scale: 1.3),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long value is scaled down rather than clipped', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      host(label: 'Store payables', value: 'EGP 1,234,567.89'),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('EGP 1,234,567.89'), findsOneWidget);
  });

  testWidgets('it also works standalone in a list, where height is unbounded', (
    tester,
  ) async {
    // The reconciliation tab uses it this way. Flexing a child under an
    // unbounded height is a hard error, not an overflow warning, so this is
    // the case that took the whole screen down.
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: ListView(
            children: const [
              MoneyTile(label: 'Difference', value: '-EGP 2,265.64'),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('-EGP 2,265.64'), findsOneWidget);
  });

  testWidgets('it still fits a cell squeezed tighter than the dashboards use', (
    tester,
  ) async {
    // Deliberately starved. Flexing has to hold even when the arithmetic does
    // not, because the next label somebody adds will be longer than this one.
    phone(tester);
    await tester.pumpWidget(
      host(label: longLabel, value: '-EGP 20.00', aspectRatio: 3.2),
    );
    expect(tester.takeException(), isNull);
  });
}
