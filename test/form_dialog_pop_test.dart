import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/app/theme.dart';
import 'package:multi_vendor/core/widgets/app_dialogs.dart';
import 'package:multi_vendor/l10n/app_localizations.dart';

/// Cancelling an order from the admin console left a blank white page.
///
/// `showFormDialog` does not resolve itself — the caller pops from
/// `onPrimaryPressed`. `showDialog` puts the dialog on the **root** navigator,
/// but a screen rendered inside a `StatefulShellRoute` branch resolves
/// `Navigator.of(callerContext)` to that **branch's** navigator. Popping with
/// the caller's context therefore tore down the branch's own page and left the
/// shell showing nothing at all.
///
/// It looked fine on phones only by accident: there the same screens are
/// pushed onto the root navigator, so the caller's context and the dialog's
/// context resolve to the same navigator.
///
/// The nested `Navigator` below is the smallest faithful stand-in for a shell
/// branch. Nothing here depends on `kIsWeb`, so unlike the rest of the web
/// work this is genuinely covered.
void main() {
  const innerPageKey = Key('inner-page');

  /// A screen inside a nested navigator that opens the form dialog, exactly
  /// as the embedded admin order detail does inside the dashboard's branch.
  Widget host({
    required bool popWithDialogContext,
    required List<String?> out,
  }) {
    return MaterialApp(
      theme: buildTheme(),
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar')],
      home: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (innerContext) => Scaffold(
            key: innerPageKey,
            body: Center(
              child: ElevatedButton(
                child: const Text('open'),
                onPressed: () async {
                  final result = await AppDialogs.showFormDialog<String>(
                    context: innerContext,
                    title: 'Cancel order',
                    content: const SizedBox(height: 24),
                    primaryText: 'Confirm',
                    onPrimaryPressed: (dialogContext) => Navigator.pop(
                      // The whole point of the fix: the dialog's context,
                      // not the caller's.
                      popWithDialogContext ? dialogContext : innerContext,
                      'a reason',
                    ),
                  );
                  out.add(result);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openAndConfirm(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm'), findsOneWidget, reason: 'dialog should be up');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
  }

  testWidgets('popping with the dialog context closes only the dialog', (
    tester,
  ) async {
    final out = <String?>[];
    await tester.pumpWidget(host(popWithDialogContext: true, out: out));
    await openAndConfirm(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Confirm'), findsNothing, reason: 'dialog closed');
    expect(
      find.byKey(innerPageKey),
      findsOneWidget,
      reason: 'the branch page must survive — losing it is the blank screen',
    );
    expect(out, ['a reason'], reason: 'caller still receives the value');
  });

  testWidgets('popping with the caller context destroys the branch page', (
    tester,
  ) async {
    // Pins the actual defect. If this ever stops reproducing, the navigator
    // semantics this fix relies on have changed and the fix needs revisiting
    // rather than quietly becoming a no-op.
    final out = <String?>[];
    await tester.pumpWidget(host(popWithDialogContext: false, out: out));
    await openAndConfirm(tester);

    expect(
      find.byKey(innerPageKey),
      findsNothing,
      reason: 'the old code popped the branch page, leaving a blank shell',
    );
  });
}
