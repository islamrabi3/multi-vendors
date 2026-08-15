import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:multi_vendor/app/theme.dart';
import 'package:multi_vendor/features/auth/screens/app_onboarding_screen.dart';
import 'package:multi_vendor/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The onboarding is the first thing a new user sees, in a language that runs
/// long, on whatever phone they own. It packs a lockup, a hero tile with
/// floating chips, a title, a body, dots and two actions into one column —
/// exactly the shape that overflows silently.
///
/// Note the `pump(duration)` rather than `pumpAndSettle`: the backdrop drifts
/// on a repeating controller, so the tree never goes quiet and settling would
/// simply time out.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // `AppOnboarding.seen` defaults to true so a failed read never traps a
    // returning user in the intro; the test has to load the (empty) prefs to
    // get the first-launch value.
    await AppOnboarding.load();
  });

  /// Advances the frames without settling — the backdrop never stops.
  Future<void> advance(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Widget host() {
    final router = GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => const AppOnboardingScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('login')),
        ),
      ],
    );
    addTearDown(router.dispose);
    return MaterialApp.router(
      theme: buildTheme(),
      routerConfig: router,
      locale: const Locale('ar'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar')],
    );
  }

  /// A small phone with text scaled to the 1.3x the app clamps to — the worst
  /// case the app actually ships to.
  void small(WidgetTester tester) {
    tester.view.physicalSize = const Size(320 * 3, 568 * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  testWidgets('every page lays out on a small phone at 1.3x text', (
    tester,
  ) async {
    small(tester);
    await tester.pumpWidget(host());
    await advance(tester);

    // Four pages, walked with the button rather than a swipe so the test also
    // covers "Next" advancing.
    for (var i = 0; i < 3; i++) {
      expect(tester.takeException(), isNull, reason: 'page $i');
      await tester.tap(find.byType(FilledButton));
      await advance(tester);
    }
    expect(tester.takeException(), isNull, reason: 'last page');
  });

  testWidgets('the last page swaps Next for Get started and hides Skip', (
    tester,
  ) async {
    small(tester);
    await tester.pumpWidget(host());
    await advance(tester);

    final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
    expect(find.text(l10n.next), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byType(FilledButton));
      await advance(tester);
    }

    expect(find.text(l10n.getStarted), findsOneWidget);
    expect(find.text(l10n.next), findsNothing);
    // Skip stays in the tree to hold the layout, but must not be tappable.
    // Scoped to the button: a Flutter tree is full of IgnorePointers.
    final skipGuard = find.ancestor(
      of: find.text(l10n.skip),
      matching: find.byType(IgnorePointer),
    );
    expect(tester.widget<IgnorePointer>(skipGuard.first).ignoring, isTrue);
  });

  testWidgets('finishing marks the intro seen so it never returns', (
    tester,
  ) async {
    small(tester);
    await tester.pumpWidget(host());
    await advance(tester);

    expect(AppOnboarding.seen, isFalse);

    final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
    await tester.tap(find.text(l10n.skip));
    await advance(tester);

    expect(AppOnboarding.seen, isTrue);
    expect(find.text('login'), findsOneWidget);
  });
}
