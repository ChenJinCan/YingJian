import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/observability/local_diagnostic_log.dart';

void main() {
  test(
    'persists structured entries without error messages or file paths',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'yingjian-diagnostic-log-',
      );
      addTearDown(() => root.delete(recursive: true));
      final log = FileDiagnosticLog(
        directoryProvider: () async => root,
        now: () => DateTime.utc(2026, 9, 1, 8, 53, 12),
      );

      log.record(
        DiagnosticLogEvent(
          level: DiagnosticLogLevel.error,
          component: 'Photo Import',
          operation: 'Pick Photos',
          result: 'Failed',
          reason: DiagnosticLogEvent.reasonFor(
            PlatformException(
              code: 'pickerFailed',
              message: '/private/secret/photo.jpg could not be read',
            ),
          ),
        ),
      );
      await log.flush();

      final entries = await log.readEntries();
      expect(entries, hasLength(1));
      expect(entries.single.component, 'photo_import');
      expect(entries.single.operation, 'pick_photos');
      expect(entries.single.reason, 'platform_pickerfailed');
      final stored = await File(
        '${root.path}/diagnostic-logs/2026-09-01.jsonl',
      ).readAsString();
      expect(stored, isNot(contains('/private/secret')));
      expect(stored, isNot(contains('photo.jpg')));
    },
  );

  test('clear removes durable entries', () async {
    final root = await Directory.systemTemp.createTemp(
      'yingjian-diagnostic-clear-',
    );
    addTearDown(() => root.delete(recursive: true));
    final log = FileDiagnosticLog(directoryProvider: () async => root);
    log.record(
      const DiagnosticLogEvent(
        level: DiagnosticLogLevel.info,
        component: 'home',
        operation: 'photo_import',
        result: 'started',
      ),
    );
    await log.flush();

    await log.clear();

    expect(await log.readEntries(), isEmpty);
  });
}
