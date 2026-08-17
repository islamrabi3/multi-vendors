import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/models/finance.dart';
import 'package:multi_vendor/core/utils/money.dart';

/// The admin can now set the early-payout fee, and the edit dialog previews
/// what a schedule would cost before it is saved. That preview is a second
/// implementation of a rule that already lives in Postgres, which is exactly
/// the kind of duplication that drifts.
///
/// Every expectation below was produced by running the server's own
/// expression — `greatest(round(payable * percent / 100, 2), min)`, then its
/// `if fee >= payable then fee := 0` refusal — against the live database, and
/// pasted in. If someone changes either side, this fails.
void main() {
  ({double fee, double net, bool available}) quote(
    double payable,
    double percent,
    double min,
  ) {
    final q = EarlySettlementQuote.preview(
      payable: payable,
      percent: percent,
      min: min,
    );
    return (fee: q.fee, net: q.netPayout, available: q.available);
  }

  group('early payout preview matches the server', () {
    test('the percent decides it once the balance is large enough', () {
      expect(quote(2000, 1.5, 10), (fee: 30.0, net: 1970.0, available: true));
      expect(
        quote(10000, 1.5, 10),
        (fee: 150.0, net: 9850.0, available: true),
      );
    });

    test('the floor decides it on small balances', () {
      // 1.5% of 500 is 7.50, below the 10 floor — so the floor is the fee and
      // the percent is doing nothing.
      expect(quote(500, 1.5, 10), (fee: 10.0, net: 490.0, available: true));
      expect(quote(333.33, 2.75, 10), (fee: 10.0, net: 323.33, available: true));
      // 0% still costs the floor.
      expect(quote(500, 0, 10), (fee: 10.0, net: 490.0, available: true));
    });

    test('no offer when the fee would swallow the balance', () {
      expect(quote(5, 1.5, 10), (fee: 0.0, net: 5.0, available: false));
      // Exactly equal counts as swallowed: the party would receive nothing.
      expect(quote(10, 1.5, 10), (fee: 0.0, net: 10.0, available: false));
      expect(quote(500, 100, 10), (fee: 0.0, net: 500.0, available: false));
    });

    test('a free schedule is no offer, not a free one', () {
      // The trap: 0% with no floor prices the payout at nothing, and
      // `available` is false server-side because it tests `fee > 0`. A preview
      // that reported "available, fee EGP 0" would advertise something the
      // server then refuses.
      expect(quote(1000, 0, 0), (fee: 0.0, net: 1000.0, available: false));
    });

    test('an empty wallet is never an offer', () {
      expect(quote(0, 1.5, 10), (fee: 0.0, net: 0.0, available: false));
    });
  });

  group('trimZeros', () {
    test('drops padding without dropping digits', () {
      expect(trimZeros(1.5), '1.5');
      expect(trimZeros(2), '2');
      expect(trimZeros(0.25), '0.25');
      expect(trimZeros(0), '0');
      expect(trimZeros(10.00), '10');
      // Rates are stored to two places server-side, so this is the limit of
      // what a round trip through the edit field can preserve.
      expect(trimZeros(1.256), '1.26');
    });
  });
}
