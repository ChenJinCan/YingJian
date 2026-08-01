import 'dart:async';

typedef StartupInitializer = Future<void> Function();
typedef StartupErrorHandler =
    void Function(Object error, StackTrace stackTrace);

/// Keeps first-frame requirements separate from optional platform work.
class StartupCoordinator {
  const StartupCoordinator({
    required this.prepareApp,
    required this.showApp,
    this.deferredInitializers = const [],
    this.onDeferredError,
  });

  final StartupInitializer prepareApp;
  final void Function() showApp;
  final List<StartupInitializer> deferredInitializers;
  final StartupErrorHandler? onDeferredError;

  Future<void> start() async {
    await prepareApp();
    showApp();
    unawaited(_initializeDeferredServices());
  }

  Future<void> _initializeDeferredServices() async {
    await Future.wait(
      deferredInitializers.map((initialize) async {
        try {
          await initialize();
        } catch (error, stackTrace) {
          onDeferredError?.call(error, stackTrace);
        }
      }),
    );
  }
}
