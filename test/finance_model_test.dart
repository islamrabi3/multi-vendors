import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/models/finance.dart';

/// The sign convention is the one thing in the financial system that a reader
/// can get backwards, and getting it backwards turns "the driver owes us 310"
/// into "we owe the driver 310". These pin it to the worked example in the
/// brief so it cannot drift.
void main() {
  group('wallet sign convention', () {
    test('a driver holding cash reads as cash due, not as a payable', () {
      // 340 collected, 30 earned -> -310.
      final wallet = WalletSummary.fromMap({
        'owner_type': 'driver',
        'balance': -310,
        'cash_due': 310,
        'payable': 0,
        'cash_collected': 340,
        'total_earnings': 30,
      });

      expect(wallet.owesMoney, isTrue);
      expect(wallet.cashDue, 310);
      expect(wallet.payable, 0);
      // The earnings are visible in their own right, and are *not* added to
      // the cash due — double-counting them is the specific bug the single
      // running account exists to prevent.
      expect(wallet.totalEarnings, 30);
      expect(wallet.cashCollected, 340);
    });

    test('a store that is owed money reads as a payable', () {
      final wallet = WalletSummary.fromMap({
        'owner_type': 'vendor',
        'balance': 2568.20,
        'cash_due': 0,
        'payable': 2568.20,
      });

      expect(wallet.ownerType, LedgerOwner.vendor);
      expect(wallet.owesMoney, isFalse);
      expect(wallet.payable, 2568.20);
    });

    test('numeric arriving as a string is still money', () {
      // PostgREST hands `numeric` back as a string over some transports.
      final wallet = WalletSummary.fromMap({
        'owner_type': 'driver',
        'balance': '-137.64',
        'cash_due': '137.64',
      });
      expect(wallet.balance, -137.64);
      expect(wallet.cashDue, 137.64);
    });
  });

  group('ledger entries', () {
    LedgerEntry entry(String direction, {String status = 'posted'}) =>
        LedgerEntry.fromMap({
          'id': 'a',
          'type': 'cash_collection',
          'amount': 544,
          'direction': direction,
          'status': status,
          'created_at': '2026-08-10T10:00:00Z',
        });

    test('direction carries the sign, and the amount stays positive', () {
      expect(entry('debit').amount, 544);
      expect(entry('debit').signedAmount, -544);
      expect(entry('credit').signedAmount, 544);
    });

    test('a reversed row is still a row', () {
      // It must remain readable rather than vanish: an audit trail that
      // deletes its mistakes is not one.
      final reversed = entry('debit', status: 'reversed');
      expect(reversed.isReversed, isTrue);
      expect(reversed.isPosted, isFalse);
      expect(reversed.amount, 544);
    });

    test('an unknown type renders as itself rather than throwing', () {
      // The server can gain an entry type before the app ships.
      final future = LedgerEntry.fromMap({
        'id': 'b',
        'type': 'some_future_type',
        'amount': 1,
        'direction': 'credit',
        'status': 'posted',
        'created_at': '2026-08-10T10:00:00Z',
      });
      expect(future.type, 'some_future_type');
    });
  });

  group('cash reconciliation', () {
    test('a mismatch is an exception needing a human', () {
      final r = CashReconciliation.fromMap({
        'expected_cash': 100000,
        'collected_cash': 98000,
        'settled_cash': 80000,
        'outstanding_cash': 18000,
        'difference': 2000,
      });
      expect(r.hasException, isTrue);
    });

    test('a matched day is clean', () {
      final r = CashReconciliation.fromMap({
        'expected_cash': 100000,
        'collected_cash': 100000,
        'difference': 0,
      });
      expect(r.hasException, isFalse);
    });
  });
}
