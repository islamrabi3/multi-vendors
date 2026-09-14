import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/app/arabic_material_localizations.dart';
import 'package:multi_vendor/core/utils/time_format.dart';

Future<String> _render(
  WidgetTester tester,
  Locale locale,
  String Function(BuildContext) build,
) async {
  late String out;
  await tester.pumpWidget(
    Localizations(
      locale: locale,
      delegates: const [
        ArabicMaterialLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      child: Builder(
        builder: (context) {
          out = build(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return out;
}

void main() {
  testWidgets('Arabic times carry صباحًا / مساءً', (tester) async {
    const ar = Locale('ar');
    expect(
      await _render(tester, ar, (c) => formatClock(c, DateTime(2026, 1, 1, 3))),
      '3:00 صباحًا',
    );
    expect(
      await _render(
        tester,
        ar,
        (c) => formatClock(c, DateTime(2026, 1, 1, 15, 5)),
      ),
      '3:05 مساءً',
    );
    expect(
      await _render(tester, ar, (c) => formatClockText(c, '00:30')),
      '12:30 صباحًا',
    );
    expect(
      await _render(tester, ar, (c) => formatClockText(c, '12:00')),
      '12:00 مساءً',
    );
    expect(
      await _render(
        tester,
        ar,
        (c) => MaterialLocalizations.of(c).postMeridiemAbbreviation,
      ),
      'مساءً',
    );
  });

  testWidgets('English times carry AM / PM', (tester) async {
    const en = Locale('en');
    expect(
      await _render(tester, en, (c) => formatClockText(c, '23:00')),
      '11:00 PM',
    );
    expect(
      await _render(
        tester,
        en,
        (c) => formatClock(c, DateTime(2026, 1, 1, 9, 7)),
      ),
      '9:07 AM',
    );
  });
}
