import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._(this._preferences) {
    _themeMode = _readThemeMode();
    _locale = _readLocale();
  }

  static const _themeModeKey = 'app.theme_mode';
  static const _localeKey = 'app.locale';

  final SharedPreferences _preferences;
  late ThemeMode _themeMode;
  late Locale? _locale;

  static Future<AppSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    return AppSettings._(preferences);
  }

  ThemeMode get themeMode => _themeMode;
  Locale? get locale => _locale;

  Future<void> setThemeMode(ThemeMode value) async {
    if (_themeMode == value) {
      return;
    }
    final saved = await _preferences.setString(_themeModeKey, value.name);
    if (!saved) {
      throw StateError('Unable to persist theme mode');
    }
    _themeMode = value;
    notifyListeners();
  }

  Future<void> setLocale(Locale? value) async {
    if (_locale == value) {
      return;
    }
    if (value == null) {
      final removed = await _preferences.remove(_localeKey);
      if (!removed) {
        throw StateError('Unable to clear locale override');
      }
    } else {
      final saved = await _preferences.setString(
        _localeKey,
        value.toLanguageTag(),
      );
      if (!saved) {
        throw StateError('Unable to persist locale override');
      }
    }
    _locale = value;
    notifyListeners();
  }

  ThemeMode _readThemeMode() {
    final stored = _preferences.getString(_themeModeKey);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => ThemeMode.system,
    );
  }

  Locale? _readLocale() {
    final stored = _preferences.getString(_localeKey);
    if (stored == null || stored.isEmpty) {
      return null;
    }
    final parts = stored.replaceAll('_', '-').split('-');
    final second = parts.length > 1 ? parts[1] : null;
    final third = parts.length > 2 ? parts[2] : null;
    return Locale.fromSubtags(
      languageCode: parts.first,
      scriptCode: second?.length == 4 ? second : null,
      countryCode: second?.length == 4 ? third : second,
    );
  }
}
