import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/app/theme.dart';
import 'package:multi_vendor/core/models/finance.dart';
import 'package:multi_vendor/core/widgets/finance_widgets.dart';
import 'package:multi_vendor/l10n/app_localizations.dart';

/// The shared money widgets every wallet and finance screen is built from,
/// pumped on a narrow phone in both languages and at a large text scale —
/// where a long Arabic label or a six-figure amount would overflow first.
void main() {
  void narrowPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(340 * 3, 720 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget host(Locale locale, double scale, Widget child) => MaterialApp(
    theme: buildTheme(),
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('ar')],
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: ListView(padding: const EdgeInsets.all(16), children: [child]),
        ),
      ),
    ),
  );

  final entries = [
    LedgerEntry(
      id: '1',
      type: 'cash_collection',
      amount: 123456.78,
      isCredit: false,
      status: 'posted',
      createdAt: DateTime.now(),
      reference: 'ORD-2026-000123-LONG-REFERENCE',
    ),
    LedgerEntry(
      id: '2',
      type: 'driver_deposit',
      amount: 850,
      isCredit: true,
      status: 'reversed',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ];

  for (final locale in const [Locale('en'), Locale('ar')]) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('kit lays out in ${locale.languageCode} at ${scale}x', (
        tester,
      ) async {
        narrowPhone(tester);
        await tester.pumpWidget(
          host(
            locale,
            scale,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WalletHero(
                  wallet: const WalletSummary(
                    ownerType: LedgerOwner.driver,
                    cashDue: 98765.43,
                  ),
                  onHandOver: () {},
                ),
                WalletHero(
                  wallet: const WalletSummary(
                    ownerType: LedgerOwner.vendor,
                    payable: 1234567.89,
                  ),
                  onWithdraw: () {},
                ),
                InReviewCard(
                  children: [
                    InReviewRow(
                      icon: Icons.move_to_inbox_rounded,
                      title: 'A fairly long hand-over title for the row',
                      subtitle: 'Bank transfer · 12/9/2026',
                      amount: '-EGP 123,456.78',
                    ),
                  ],
                ),
                FinanceSection(
                  title: 'Summary',
                  child: FinanceCard(
                    children: [
                      FinanceRow(
                        icon: Icons.two_wheeler_rounded,
                        label: 'Discounts funded by the platform this period',
                        note: '1,234 orders',
                        value: 'EGP 123,456.78',
                        onTap: () {},
                      ),
                      const FinanceRow(
                        label: 'Platform earnings',
                        value: '+EGP 9,876,543.21',
                        emphasis: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FinanceSegments<int>(
                  values: const [0, 1, 2, 3],
                  selected: 1,
                  labelOf: (i) => 'Last 30 days $i',
                  onChanged: (_) {},
                ),
                LedgerActivity(entries: entries),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
