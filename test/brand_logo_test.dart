import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/widgets/brand_logo.dart';

/// The mark is painted rather than loaded from an SVG, so nothing but a test
/// notices if the geometry stops laying out. These cover the two things that
/// would be silently wrong: the mark not taking the size it was asked for (the
/// arch stroke is derived from it), and the wordmark losing the "KitchenIN"
/// spelling, or the accent green drifting off the brand value.
void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('the mark is square at every size and style', (tester) async {
    for (final style in KitchenInMarkStyle.values) {
      for (final size in <double>[24, 40, 104]) {
        await tester.pumpWidget(host(KitchenInMark(size: size, style: style)));
        expect(
          tester.getSize(find.byType(KitchenInMark)),
          Size.square(size),
          reason: '$style at $size',
        );
      }
    }
  });

  testWidgets('the wordmark reads "KitchenIN" as one word', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(const KitchenInWordmark()));

    // Solid, no space. The colour split between "Kitchen" and "IN" is the only
    // thing separating them, and it must not reach a screen reader as two
    // words.
    expect(find.bySemanticsLabel('KitchenIN'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('"IN" carries the brand green on both surfaces', (tester) async {
    for (final onDark in [false, true]) {
      await tester.pumpWidget(host(KitchenInWordmark(onDark: onDark)));
      final rich = tester.widget<Text>(find.byType(Text));
      final accent = (rich.textSpan! as TextSpan).children!.last as TextSpan;

      // #C3DE84 — one value, so the name reads the same wherever it appears.
      expect(
        accent.style?.color,
        const Color(0xFFC3DE84),
        reason: 'onDark=$onDark',
      );
      expect(accent.text, 'IN');
    }
  });

  testWidgets('the lockup is the mark plus the wordmark', (tester) async {
    await tester.pumpWidget(host(const KitchenInLockup()));

    expect(find.byType(KitchenInMark), findsOneWidget);
    expect(find.byType(KitchenInWordmark), findsOneWidget);
  });

  testWidgets('on dark, the lockup frosts the tile instead of filling it', (
    tester,
  ) async {
    await tester.pumpWidget(host(const KitchenInLockup(onDark: true)));

    expect(
      tester.widget<KitchenInMark>(find.byType(KitchenInMark)).style,
      KitchenInMarkStyle.glass,
    );
  });
}
