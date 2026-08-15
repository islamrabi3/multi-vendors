import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/supabase_client.dart';

/// Whether this device has ever been told which language to use.
///
/// Read once before `runApp` so the router can decide its very first route
/// synchronously — the same shape as `AppOnboarding.seen`. Deliberately not
/// "is the locale English": English is also the fallback when nothing is
/// stored, so the two cases must stay distinguishable or a first launch would
/// silently keep a default nobody picked.
class AppLanguage {
  static const String key = 'app_locale';

  /// Optimistic until [load] says otherwise, so a failure to read preferences
  /// skips the picker rather than trapping the app on it.
  ///
  /// A [ValueNotifier] rather than a plain bool because GoRouter needs
  /// something to listen to — it is merged into the router's
  /// `refreshListenable` beside `SplashGate.introDone`, so committing a
  /// language re-runs the redirect and the picker sends itself onward.
  static final ValueNotifier<bool> chosen = ValueNotifier(true);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      chosen.value = prefs.getString(key) != null;
    } catch (_) {
      chosen.value = true;
    }
  }

  /// Called once a language is committed, so the router's next redirect moves
  /// past the picker without waiting on another disk read.
  static void markChosen() => chosen.value = true;
}

class LocaleCubit extends Cubit<Locale> {
  static const String _localeKey = AppLanguage.key;

  LocaleCubit() : super(const Locale('en')) {
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_localeKey);
      if (code != null) {
        emit(Locale(code));
        _publishLocale(code);
      }
    } catch (_) {
      // Fallback silently if shared preferences fails
    }
  }

  /// Mirrors the choice onto the profile so the server can compose push
  /// notifications in the right language — it has no other way to know.
  Future<void> _publishLocale(String languageCode) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await supabase
          .from('profiles')
          .update({'locale': languageCode})
          .eq('id', userId);
    } catch (_) {
      // Best effort: a stale locale only affects notification language.
    }
  }

  Future<void> setLocale(Locale locale) async {
    emit(locale);
    AppLanguage.markChosen();
    _publishLocale(locale.languageCode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localeKey, locale.languageCode);
    } catch (_) {}
  }

  void toggleLocale() {
    if (state.languageCode == 'en') {
      setLocale(const Locale('ar'));
    } else {
      setLocale(const Locale('en'));
    }
  }
}
