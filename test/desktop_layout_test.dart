import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/app/tokens.dart';
import 'package:multi_vendor/core/widgets/web/phone_frame.dart';

/// A layout measured against the window is right on a phone and wrong
/// everywhere else: the window is not the box the widget was given, and on a
/// monitor the two differ by most of the screen. These pin the two rules that
/// were being broken — prose stops at a readable measure, and a phone-shaped
/// app stays phone-shaped instead of being pulled across a desktop.
void main() {
  group('bubbleWidth', () {
    test('takes its share of a narrow column', () {
      expect(AppBreakpoints.bubbleWidth(400), 300);
    });

    test('stops at a readable measure however much space there is', () {
      expect(AppBreakpoints.bubbleWidth(1920), AppBreakpoints.readable);
      expect(AppBreakpoints.bubbleWidth(4000), AppBreakpoints.readable);
    });

    test('never returns a negative width', () {
      // A pane can be measured at zero for a frame while it settles.
      expect(AppBreakpoints.bubbleWidth(0), 0);
    });
  });

  group('PhoneFrame', () {
    const childKey = Key('framed-app');
    Widget frame() => const MaterialApp(
      home: PhoneFrame(
        child: ColoredBox(key: childKey, color: Color(0xFF000000)),
      ),
    );

    testWidgets('leaves a phone exactly as it was', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(frame());

      // The phone gets the full width, exactly as before.
      expect(tester.getSize(find.byKey(childKey)).width, 400);
    });

    testWidgets('holds the app to a readable column on a desktop', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(frame());

      final child = tester.getSize(find.byKey(childKey));
      expect(child.width, lessThanOrEqualTo(620));
      expect(
        child.width,
        lessThan(1920),
        reason: 'a phone layout must not be stretched across a monitor',
      );
    });
  });
}
