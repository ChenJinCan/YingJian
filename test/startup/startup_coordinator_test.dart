import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/startup/startup_coordinator.dart';

void main() {
  group('StartupCoordinator', () {
    test('prepares the app before showing it', () async {
      final events = <String>[];
      final coordinator = StartupCoordinator(
        prepareApp: () async => events.add('prepared'),
        showApp: () => events.add('shown'),
      );

      await coordinator.start();

      expect(events, ['prepared', 'shown']);
    });

    test('shows the app without waiting for deferred work', () async {
      final blockedWork = Completer<void>();
      var appWasShown = false;
      final coordinator = StartupCoordinator(
        prepareApp: () async {},
        showApp: () => appWasShown = true,
        deferredInitializers: [() => blockedWork.future],
      );

      await coordinator.start();

      expect(appWasShown, isTrue);
      expect(blockedWork.isCompleted, isFalse);
    });

    test('reports deferred failures without failing startup', () async {
      final errors = <Object>[];
      final coordinator = StartupCoordinator(
        prepareApp: () async {},
        showApp: () {},
        deferredInitializers: [() async => throw StateError('unavailable')],
        onDeferredError: (error, _) => errors.add(error),
      );

      await coordinator.start();
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
    });
  });
}
