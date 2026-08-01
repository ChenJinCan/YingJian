import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/observability/analytics_event.dart';
import 'package:yingjian/observability/app_observability.dart';

import '../support/test_services.dart';

void main() {
  test('is disabled by default and drops telemetry', () async {
    final backend = FakeObservabilityBackend();
    final observability = AppObservability(backend);

    await observability.track(AnalyticsEvent(AnalyticsEventName.appOpened));
    await observability.recordError(
      StateError('private message'),
      StackTrace.current,
      fatal: false,
      reason: 'test_error',
    );

    expect(observability.status, ObservabilityStatus.disabled);
    expect(backend.events, isEmpty);
    expect(backend.errors, isEmpty);
  });

  test('enables the backend and records only allowlisted events', () async {
    final backend = FakeObservabilityBackend();
    final observability = AppObservability(backend);

    expect(await observability.setCollectionEnabled(true), isTrue);
    await observability.trackScreen('editor');
    await observability.track(
      AnalyticsEvent(
        AnalyticsEventName.editorOpened,
        parameters: const {AnalyticsParameter.source: 'home'},
      ),
    );

    expect(backend.collectionEnabled, isTrue);
    expect(backend.events, containsAll(['app_opened', 'editor_opened']));
    expect(backend.screens, ['editor']);
  });

  test(
    'reports unavailable when native Firebase configuration is absent',
    () async {
      final backend = FakeObservabilityBackend(canInitialize: false);
      final observability = AppObservability(backend);

      expect(await observability.setCollectionEnabled(true), isFalse);
      expect(observability.status, ObservabilityStatus.unavailable);
    },
  );

  test('custom trace does not change the operation result', () async {
    final backend = FakeObservabilityBackend();
    final observability = AppObservability(backend);
    await observability.setCollectionEnabled(true);

    final result = await observability.traceOperation(
      operation: 'export_preview',
      action: () async => 42,
    );

    expect(result, 42);
    expect(backend.traces.single.name, 'operation_export_preview');
    expect(backend.traces.single.attributes['result'], 'success');
    expect(backend.traces.single.stopped, isTrue);
  });

  test('event constructor rejects unapproved names and parameter keys', () {
    expect(() => AnalyticsEvent('raw_event'), throwsArgumentError);
    expect(
      () => AnalyticsEvent(
        AnalyticsEventName.appOpened,
        parameters: const {'file_path': '/private/photo.jpg'},
      ),
      throwsArgumentError,
    );
  });
}
