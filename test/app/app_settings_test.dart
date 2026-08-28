import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yingjian/app/settings/app_settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to system appearance and device locale', () async {
    final settings = await AppSettings.load();

    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.locale, isNull);
    expect(settings.diagnosticsEnabled, isFalse);
    expect(settings.onboardingComplete, isFalse);
    expect(settings.exportQuality, AppExportQuality.high);
  });

  test('persists onboarding completion', () async {
    final settings = await AppSettings.load();

    await settings.completeOnboarding();
    final restored = await AppSettings.load();

    expect(restored.onboardingComplete, isTrue);
  });

  test('existing app preferences bypass one-time onboarding', () async {
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});

    final settings = await AppSettings.load();

    expect(settings.onboardingComplete, isTrue);
  });

  test('persists an explicit diagnostics choice', () async {
    final settings = await AppSettings.load();

    await settings.setDiagnosticsEnabled(true);
    final restored = await AppSettings.load();

    expect(restored.diagnosticsEnabled, isTrue);
  });

  test('persists theme and locale across instances', () async {
    final settings = await AppSettings.load();

    await settings.setThemeMode(ThemeMode.dark);
    await settings.setLocale(const Locale('en'));
    final restored = await AppSettings.load();

    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.locale, const Locale('en'));
  });

  test('persists the default export quality', () async {
    final settings = await AppSettings.load();

    await settings.setExportQuality(AppExportQuality.compact);
    final restored = await AppSettings.load();

    expect(restored.exportQuality, AppExportQuality.compact);
  });

  test('clears the locale override to follow the device again', () async {
    final settings = await AppSettings.load();
    await settings.setLocale(const Locale('en'));

    await settings.setLocale(null);

    expect(settings.locale, isNull);
    expect(
      (await SharedPreferences.getInstance()).containsKey('app.locale'),
      isFalse,
    );
  });

  test('restores language tags with script and country subtags', () async {
    SharedPreferences.setMockInitialValues({'app.locale': 'zh-Hant-TW'});

    final settings = await AppSettings.load();

    expect(
      settings.locale,
      const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
        countryCode: 'TW',
      ),
    );
  });
}
