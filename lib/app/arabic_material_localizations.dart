import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

/// Arabic Material strings with the full words for the part of the day.
///
/// Flutter's Arabic set abbreviates them to "ص" / "م", which is what the time
/// picker's toggle and every `TimeOfDay.format` would otherwise show.
class ArabicMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const ArabicMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ar';

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    // The global delegate loads the Arabic date data the formats below need;
    // building them before it runs throws. Its future is synchronous.
    return GlobalMaterialLocalizations.delegate
        .load(locale)
        .then<MaterialLocalizations>((_) => _ArabicMaterialLocalizations());
  }

  @override
  bool shouldReload(ArabicMaterialLocalizationsDelegate old) => false;
}

class _ArabicMaterialLocalizations extends MaterialLocalizationAr {
  _ArabicMaterialLocalizations()
    : super(
        fullYearFormat: intl.DateFormat.y('ar'),
        compactDateFormat: intl.DateFormat.yMd('ar'),
        shortDateFormat: intl.DateFormat.yMMMd('ar'),
        mediumDateFormat: intl.DateFormat.MMMEd('ar'),
        longDateFormat: intl.DateFormat.yMMMMEEEEd('ar'),
        yearMonthFormat: intl.DateFormat.yMMMM('ar'),
        shortMonthDayFormat: intl.DateFormat.MMMd('ar'),
        decimalFormat: intl.NumberFormat.decimalPattern('ar'),
        twoDigitZeroPaddedFormat: intl.NumberFormat('00', 'ar'),
      );

  @override
  String get anteMeridiemAbbreviation => 'صباحًا';

  @override
  String get postMeridiemAbbreviation => 'مساءً';
}
