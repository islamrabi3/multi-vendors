import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/app/theme.dart';
import 'package:multi_vendor/core/widgets/app_dialogs.dart';
import 'package:multi_vendor/l10n/app_localizations.dart';

/// Dialog actions must survive a long label on a narrow phone.
///
/// Arabic routinely runs 2–3x the width of the English it translates, and the
/// action row splits an already-inset dialog between two buttons — so a caption
/// that fits in English has no room at all once translated. These pump the real
/// dialogs at the narrowest width the app supports and fail on any layout
/// overflow, which is otherwise invisible until someone screenshots it.
void main() {
  Widget host(void Function(BuildContext) open) => MaterialApp(
    // The real theme: its button styles set a 54pt minimum height, which is
    // exactly the kind of thing a bare MaterialApp would hide.
    theme: buildTheme(),
    locale: const Locale('ar'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('ar')],
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => open(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  /// A 320pt-wide phone — the narrowest the app targets — with text scaled to
  /// the 1.3x the app clamps to.
  Future<void> narrow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  const longConfirm = 'تأكيد حذف هذا العنصر نهائياً';
  const longCancel = 'الرجوع دون حفظ التغييرات';

  testWidgets('confirm dialog actions do not overflow', (tester) async {
    await narrow(tester);
    await tester.pumpWidget(
      host(
        (context) => showConfirmDialog(
          context: context,
          title: 'حذف',
          message: 'لا يمكن التراجع عن هذا الإجراء.',
          confirmLabel: longConfirm,
          cancelLabel: longCancel,
          tone: AppDialogTone.danger,
          icon: Icons.delete_outline_rounded,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text(longConfirm), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('form dialog actions and destructive row do not overflow', (
    tester,
  ) async {
    await narrow(tester);
    await tester.pumpWidget(
      host(
        (context) => showFormDialog<void>(
          context: context,
          title: 'تعديل',
          contentBuilder: (_) => const TextField(),
          submitLabel: longConfirm,
          cancelLabel: longCancel,
          destructiveLabel: 'حذف هذا العنصر نهائياً من القائمة',
          onDestructive: () async {},
          onSubmit: (_) async {},
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('raw AlertDialog actions do not overflow', (tester) async {
    await narrow(tester);
    await tester.pumpWidget(
      host(
        (context) => showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('حظر المستخدم'),
            content: const TextField(),
            actions: [
              TextButton(onPressed: () {}, child: const Text(longCancel)),
              FilledButton(onPressed: () {}, child: const Text(longConfirm)),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('info dialog dismiss does not overflow', (tester) async {
    await narrow(tester);
    await tester.pumpWidget(
      host(
        (context) => showInfoDialog(
          context: context,
          title: 'تنبيه',
          message: 'رسالة توضيحية.',
          dismissLabel: 'حسناً، فهمت ذلك تماماً وأوافق',
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
