import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/utils/money.dart';

/// The tip presets rendered as `EGP 20.00` in a third of a card and were
/// ellipsised to `…EGP 2` — a tip button that cannot say what it is worth.
/// Dropping the decimals is what buys the room back, so the rule is pinned
/// here rather than left to whoever next touches the formatter.
void main() {
  test('whole amounts lose their decimals', () {
    expect(formatMoneyCompact(5), 'EGP 5');
    expect(formatMoneyCompact(10), 'EGP 10');
    expect(formatMoneyCompact(20), 'EGP 20');
    expect(formatMoneyCompact(1000), 'EGP 1,000');
  });

  test('fractional amounts keep them, because rounding money is a lie', () {
    expect(formatMoneyCompact(5.5), formatMoney(5.5));
    expect(formatMoneyCompact(85.82), 'EGP 85.82');
  });

  test('zero is still a whole number', () {
    expect(formatMoneyCompact(0), 'EGP 0');
  });

  test('it is shorter than the full form for every preset', () {
    // The actual defect: length. If a future change makes these equal again,
    // the chips go back to being truncated.
    for (final preset in [5.0, 10.0, 20.0]) {
      expect(
        formatMoneyCompact(preset).length,
        lessThan(formatMoney(preset).length),
        reason: 'preset $preset must be shorter than ${formatMoney(preset)}',
      );
    }
  });
}
