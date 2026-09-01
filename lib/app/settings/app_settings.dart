import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppExportQuality { high, standard, compact }

class AppSettings extends ChangeNotifier {
  AppSettings._(this._preferences) {
    _themeMode = _readThemeMode();
    _locale = _readLocale();
    _diagnosticsEnabled = _preferences.getBool(_diagnosticsEnabledKey) ?? false;
    _exportQuality = _readExportQuality();
    _developerLogsUnlocked =
        _preferences.getBool(_developerLogsUnlockedKey) ?? false;
    _onboardingComplete =
        _preferences.getBool(_onboardingCompleteKey) ??
        _hasExistingAppPreference();
  }

  static const _themeModeKey = 'app.theme_mode';
  static const _localeKey = 'app.locale';
  static const _diagnosticsEnabledKey = 'privacy.diagnostics_enabled';
  static const _onboardingCompleteKey = 'app.onboarding_complete';
  static const _exportQualityKey = 'export.default_quality';
  static const _developerLogsUnlockedKey = 'developer.logs_unlocked';

  final SharedPreferences _preferences;
  late ThemeMode _themeMode;
  late Locale? _locale;
  late bool _diagnosticsEnabled;
  late bool _onboardingComplete;
  late AppExportQuality _exportQuality;
  late bool _developerLogsUnlocked;

  static Future<AppSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    return AppSettings._(preferences);
  }

  ThemeMode get themeMode => _themeMode;
  Locale? get locale => _locale;
  bool get diagnosticsEnabled => _diagnosticsEnabled;
  bool get onboardingComplete => _onboardingComplete;
  AppExportQuality get exportQuality => _exportQuality;
  bool get developerLogsUnlocked => _developerLogsUnlocked;

  Future<void> completeOnboarding() async {
    if (_onboardingComplete) return;
    final saved = await _preferences.setBool(_onboardingCompleteKey, true);
    if (!saved) {
      throw StateError('Unable to persist onboarding completion');
    }
    _onboardingComplete = true;
    notifyListeners();
  }

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

  Future<void> setDiagnosticsEnabled(bool value) async {
    if (_diagnosticsEnabled == value) {
      return;
    }
    final saved = await _preferences.setBool(_diagnosticsEnabledKey, value);
    if (!saved) {
      throw StateError('Unable to persist diagnostics preference');
    }
    _diagnosticsEnabled = value;
    notifyListeners();
  }

  Future<void> setExportQuality(AppExportQuality value) async {
    if (_exportQuality == value) return;
    final saved = await _preferences.setString(_exportQualityKey, value.name);
    if (!saved) throw StateError('Unable to persist export quality');
    _exportQuality = value;
    notifyListeners();
  }

  Future<void> unlockDeveloperLogs() async {
    if (_developerLogsUnlocked) return;
    final saved = await _preferences.setBool(_developerLogsUnlockedKey, true);
    if (!saved) throw StateError('Unable to persist developer log access');
    _developerLogsUnlocked = true;
    notifyListeners();
  }

  ThemeMode _readThemeMode() {
    final stored = _preferences.getString(_themeModeKey);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => ThemeMode.dark,
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

  AppExportQuality _readExportQuality() {
    final stored = _preferences.getString(_exportQualityKey);
    return AppExportQuality.values.firstWhere(
      (value) => value.name == stored,
      orElse: () => AppExportQuality.high,
    );
  }

  bool _hasExistingAppPreference() {
    return _preferences.containsKey(_themeModeKey) ||
        _preferences.containsKey(_localeKey) ||
        _preferences.containsKey(_diagnosticsEnabledKey);
  }
}
