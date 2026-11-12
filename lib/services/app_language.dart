// Doner app language: English is the default, Urdu second. The choice is
// persisted in SharedPreferences (key 'doner_language_v1') and broadcast on
// AppLanguage.notifier so the shell rebuilds immediately; it also survives
// restarts because main() loads it before runApp().

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLanguage {
  static const String _key = 'doner_language_v1';

  /// 'en' (default) or 'ur'.
  static final ValueNotifier<String> notifier = ValueNotifier<String>('en');

  static String get code => notifier.value;

  static bool get isEnglish => notifier.value != 'ur';

  static Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String saved = prefs.getString(_key) ?? 'en';
      notifier.value = saved == 'ur' ? 'ur' : 'en';
    } catch (_) {
      // Keep the English default.
    }
  }

  static Future<void> setLanguage(String code) async {
    final String next = code == 'ur' ? 'ur' : 'en';
    if (notifier.value == next) return;
    notifier.value = next;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, next);
    } catch (_) {
      // The in-memory language still applies for this session.
    }
  }
}
