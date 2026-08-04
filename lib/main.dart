import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/app/app.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/application/photo_preview_renderer.dart';
import 'package:yingjian/features/editor/infrastructure/method_channel_photo_exporter.dart';
import 'package:yingjian/features/editor/infrastructure/method_channel_photo_preview_renderer.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/infrastructure/app_owned_photo_importer.dart';
import 'package:yingjian/features/project/infrastructure/image_picker_photo_source.dart';
import 'package:yingjian/features/project/infrastructure/json_photo_project_store.dart';
import 'package:yingjian/features/recommendations/domain/photo_analysis.dart';
import 'package:yingjian/features/recommendations/infrastructure/method_channel_photo_analyzer.dart';
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
  late PhotoImporter photoImporter;
  late PhotoProjectStore photoProjectStore;
  late PhotoExporter photoExporter;
  late PhotoPreviewRenderer photoPreviewRenderer;
  late PhotoAnalyzer photoAnalyzer;

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
      photoImporter = AppOwnedPhotoImporter(
        source: ImagePickerPhotoSource(),
        mediaDirectory: () async {
          final root = await getApplicationSupportDirectory();
          return Directory('${root.path}/media');
        },
      );
      photoProjectStore = JsonPhotoProjectStore(
        directory: getApplicationSupportDirectory,
      );
      photoExporter = MethodChannelPhotoExporter();
      photoPreviewRenderer = MethodChannelPhotoPreviewRenderer();
      photoAnalyzer = const MethodChannelPhotoAnalyzer();
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
            Provider<PhotoImporter>.value(value: photoImporter),
            Provider<PhotoProjectStore>.value(value: photoProjectStore),
            Provider<PhotoExporter>.value(value: photoExporter),
            Provider<PhotoPreviewRenderer>.value(value: photoPreviewRenderer),
            Provider<PhotoAnalyzer>.value(value: photoAnalyzer),
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
