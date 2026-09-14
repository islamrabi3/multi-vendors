import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Every clock time in the app goes through here, so a time always carries
/// its part of the day — "3:00 صباحًا" / "3:00 مساءً" in Arabic, "3:00 AM" /
/// "3:00 PM" in English — whatever the phone's 24-hour setting is.
///
/// The bare "ص" / "م" the platform formats use were easy to misread, and a
/// 24-hour "15:00" next to a 12-hour time elsewhere was worse.
String formatClock(BuildContext context, DateTime at) =>
    _clock(_language(context), at.hour, at.minute);

/// A stored `HH:MM` (store hours) in the same form. Unparseable text is
/// returned as it came.
String formatClockText(BuildContext context, String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return hhmm;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return hhmm;
  return _clock(_language(context), hour, minute);
}

/// Date and time together, e.g. "14 Sep 2026 · 3:05 مساءً".
String formatDateTime(BuildContext context, DateTime at, {DateFormat? date}) {
  final language = _language(context);
  final day = (date ?? DateFormat.yMMMd(language)).format(at);
  return '$day · ${_clock(language, at.hour, at.minute)}';
}

/// The period word alone, for pickers and anywhere a time is composed.
String periodWord(String language, int hour) {
  final morning = hour < 12;
  if (language == 'ar') return morning ? 'صباحًا' : 'مساءً';
  return morning ? 'AM' : 'PM';
}

String _language(BuildContext context) =>
    Localizations.localeOf(context).languageCode;

String _clock(String language, int hour, int minute) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  final m = minute.toString().padLeft(2, '0');
  return '$h:$m ${periodWord(language, hour)}';
}
