import 'package:intl/intl.dart';

final _egp = NumberFormat.currency(symbol: 'EGP ', decimalDigits: 2);

String formatMoney(num amount) => _egp.format(amount);

final _egpWhole = NumberFormat.currency(symbol: 'EGP ', decimalDigits: 0);

/// Drops the decimals when there are none to show: `EGP 5` rather than
/// `EGP 5.00`.
///
/// For figures that share a row with two others — tip presets, chips — those
/// three characters are the difference between the amount being readable and
/// being ellipsised away, which is worse than useless on a button whose whole
/// job is to say how much you are about to send.
String formatMoneyCompact(num amount) => amount == amount.roundToDouble()
    ? _egpWhole.format(amount)
    : formatMoney(amount);

/// A bare number with no currency and no trailing `.0`: `1.5`, `2`, `0.25`.
///
/// For rates and percentages, where `1.50%` is noise and `1.5%` is the number
/// the operator typed in. Also used to seed the edit fields, so reopening the
/// form shows what was saved rather than a padded version of it.
String trimZeros(num value) {
  final text = value.toStringAsFixed(2);
  if (!text.contains('.')) return text;
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}
