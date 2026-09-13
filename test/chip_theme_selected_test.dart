import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/app/theme.dart';

/// A selected chip is a dark pill. Its label used to stay dark too, so the
/// "Open now" filter looked dead when tapped. The label has to flip to white.
void main() {
  Color labelColor(WidgetTester tester, String text) {
    final rich = tester.widget<RichText>(
      find.descendant(of: find.text(text), matching: find.byType(RichText)),
    );
    return rich.text.style!.color!;
  }

  testWidgets('selected FilterChip label is readable on the dark fill', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: const Scaffold(
          body: Row(
            children: [
              FilterChip(label: Text('on'), selected: true, onSelected: _noop),
              FilterChip(
                label: Text('off'),
                selected: false,
                onSelected: _noop,
              ),
            ],
          ),
        ),
      ),
    );
    expect(labelColor(tester, 'on'), Colors.white);
    expect(labelColor(tester, 'off'), isNot(Colors.white));
  });
}

void _noop(bool _) {}
