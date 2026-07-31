import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/supabase_client.dart';

class LocaleCubit extends Cubit<Locale> {
  static const String _localeKey = 'app_locale';

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
          .update({'locale': languageCode}).eq('id', userId);
    } catch (_) {
      // Best effort: a stale locale only affects notification language.
    }
  }

  Future<void> setLocale(Locale locale) async {
    emit(locale);
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
