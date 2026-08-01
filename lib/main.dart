import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/app/app.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/observability/app_observability.dart';
import 'package:yingjian/observability/firebase_observability_backend.dart';
import 'package:yingjian/review/review_manager.dart';
import 'package:yingjian/startup/startup_coordinator.dart';

void main() {
  runZonedGuarded(_startApplication, _reportStartupError);
}

Future<void> _startApplication() async {
  WidgetsFlutterBinding.ensureInitialized();
  late AppSettings settings;
  late AppObservability observability;
  late ReviewManager reviewManager;

  final startup = StartupCoordinator(
    prepareApp: () async {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
      );
      PaintingBinding.instance.imageCache.maximumSizeBytes = 100 * 1024 * 1024;
      settings = await AppSettings.load();
      observability = AppObservability(FirebaseObservabilityBackend());
      observability.installGlobalErrorHandlers();
      reviewManager = ReviewManager.production(observability);
    },
    showApp: () {
      runApp(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppSettings>.value(value: settings),
            ChangeNotifierProvider<AppObservability>.value(
              value: observability,
            ),
            Provider<ReviewManager>.value(value: reviewManager),
          ],
          child: const YingjianApp(),
        ),
      );
    },
    deferredInitializers: [
      () => observability.initialize(
        collectionEnabled: settings.diagnosticsEnabled,
      ),
    ],
    onDeferredError: (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError('Deferred startup task failed'),
          stack: stackTrace,
          library: 'application_startup',
        ),
      );
    },
  );

  await startup.start();
}

void _reportStartupError(Object error, StackTrace stackTrace) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'application_startup',
    ),
  );
}
