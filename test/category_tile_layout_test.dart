import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The category tiles live in a horizontal list, which has to be given a fixed
/// height — so a label one point taller than budgeted overflows the strip and
/// paints the yellow-and-black bars. It did: 71pt ring + 5pt gap + a 17pt
/// Arabic line came to 93 inside a 92pt box.
///
/// Both tiles now wrap their label in a `Flexible`, which makes the overflow
/// structurally impossible rather than a matter of the arithmetic staying
/// ahead of the font. This reproduces the geometry at the extremes the app
/// actually allows and asserts nothing overflows.
void main() {
  /// Mirrors the tile: a fixed-size circle, a gap, and a flexible label, all
  /// inside the strip's fixed height.
  Widget tile({
    required double stripHeight,
    required double circle,
    required String label,
  }) => Directionality(
    textDirection: TextDirection.rtl,
    child: Center(
      child: SizedBox(
        height: stripHeight,
        child: SizedBox(
          width: 72,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: circle, height: circle, color: Colors.grey),
              const SizedBox(height: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, height: 1.2),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  for (final scale in <double>[1.0, 1.3]) {
    testWidgets('category tile does not overflow at ${scale}x text', (
      tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: tile(stripHeight: 112, circle: 71, label: 'الكل'),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('label ellipsises rather than overflowing a short strip', (
    tester,
  ) async {
    // Deliberately starved: even with no room to spare, the flexible label
    // shrinks instead of painting past the strip.
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: tile(stripHeight: 80, circle: 71, label: 'مشروبات وعصائر'),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
