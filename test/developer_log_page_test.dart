import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/observability/local_diagnostic_log.dart';

import 'support/test_services.dart';

void main() {
  testWidgets('five version taps unlock a durable diagnostic log viewer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final settings = await AppSettings.load();
    final log = MemoryDiagnosticLog()
      ..record(
        const DiagnosticLogEvent(
          level: DiagnosticLogLevel.error,
          component: 'photo_import',
          operation: 'pick_photos',
          result: 'failed',
          reason: 'platform_pickerfailed',
        ),
      );
    await tester.pumpWidget(buildTestApp(settings, diagnosticLog: log));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-settings')));
    await tester.pumpAndSettle();
    final version = find.byKey(const ValueKey('settings-version'));
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    for (var tap = 0; tap < 5; tap++) {
      await tester.tap(version);
    }
    await tester.pumpAndSettle();

    expect(settings.developerLogsUnlocked, isTrue);
    expect(find.byKey(const ValueKey('developer-log-page')), findsOneWidget);
    expect(find.textContaining('photo_import.pick_photos'), findsOneWidget);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.tap(find.byKey(const ValueKey('developer-log-copy-all')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('日志已复制'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-developer-logs')),
      findsOneWidget,
    );
  });
}
