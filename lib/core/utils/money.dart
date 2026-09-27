import 'package:intl/intl.dart';

import '../models/platform_config.dart';
import '../services/platform_config_service.dart';

// Pinned to `en`: the app sets `Intl.defaultLocale` to the UI language so
// dates read in Arabic, and amounts must not change separators with it.
//
// The currency is the platform's, read live from [PlatformConfigService]:
// the admin picks it, so nothing here may assume pounds.

AppCurrency get currentCurrency =>
    PlatformConfigService.instance.current.currency;

/// The symbol for the UI language in use, e.g. `EGP` or `SAR`.
String get currencySymbol {
  final language = (Intl.defaultLocale ?? 'en').split(RegExp('[_-]')).first;
  return currentCurrency.symbolFor(language);
}

final _formats = <String, NumberFormat>{};

NumberFormat _format(int decimals) {
  final symbol = currencySymbol;
  return _formats.putIfAbsent(
    '$symbol|$decimals',
    () => NumberFormat.currency(
      locale: 'en',
      symbol: '$symbol ',
      decimalDigits: decimals,
    ),
  );
}

String formatMoney(num amount) =>
    _format(currentCurrency.decimals).format(amount);

/// Drops the decimals when there are none to show: `EGP 5` rather than
/// `EGP 5.00`.
///
/// For figures that share a row with two others — tip presets, chips — those
/// three characters are the difference between the amount being readable and
/// being ellipsised away, which is worse than useless on a button whose whole
/// job is to say how much you are about to send.
String formatMoneyCompact(num amount) => amount == amount.roundToDouble()
    ? _format(0).format(amount)
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
