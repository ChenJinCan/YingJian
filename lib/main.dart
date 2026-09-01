import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/app/app.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/features/creation/application/local_reference_style_analyzer.dart';
import 'package:yingjian/features/editor/application/meta_op_capabilities_provider.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/application/photo_preview_renderer.dart';
import 'package:yingjian/features/editor/application/photo_sharer.dart';
import 'package:yingjian/features/editor/application/speech_transcriber.dart';
import 'package:yingjian/features/editor/infrastructure/method_channel_photo_exporter.dart';
import 'package:yingjian/features/editor/infrastructure/method_channel_meta_op_capabilities.dart';
import 'package:yingjian/features/editor/infrastructure/method_channel_photo_preview_renderer.dart';
import 'package:yingjian/features/editor/infrastructure/method_channel_photo_sharer.dart';
import 'package:yingjian/features/editor/infrastructure/method_channel_speech_transcriber.dart';
import 'package:yingjian/features/generation/application/generation_coordinator.dart';
import 'package:yingjian/features/generation/application/generated_media_actions.dart';
import 'package:yingjian/features/generation/application/generation_session_credential.dart';
import 'package:yingjian/features/generation/application/mask_removal_input_builder.dart';
import 'package:yingjian/features/generation/application/motion_photo_generator.dart';
import 'package:yingjian/features/generation/application/upscale_photo_generator.dart';
import 'package:yingjian/features/generation/infrastructure/explicit_refresh_generation_provider.dart';
import 'package:yingjian/features/generation/infrastructure/json_generation_job_store.dart';
import 'package:yingjian/features/generation/infrastructure/method_channel_generated_media_actions.dart';
import 'package:yingjian/features/generation/infrastructure/first_party_generation_provider.dart';
import 'package:yingjian/features/generation/infrastructure/method_channel_generation_session_credential_source.dart';
import 'package:yingjian/features/generation/infrastructure/method_channel_motion_photo_generator.dart';
import 'package:yingjian/features/generation/infrastructure/method_channel_upscale_photo_generator.dart';
import 'package:yingjian/features/generation/infrastructure/unavailable_generation_provider.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/infrastructure/app_owned_photo_importer.dart';
import 'package:yingjian/features/project/infrastructure/image_picker_photo_source.dart';
import 'package:yingjian/features/project/infrastructure/json_photo_project_store.dart';
import 'package:yingjian/features/project/infrastructure/method_channel_photo_source.dart';
import 'package:yingjian/features/photo_analysis/application/photo_analysis_cache.dart';
import 'package:yingjian/features/photo_analysis/domain/photo_analysis.dart';
import 'package:yingjian/features/photo_analysis/infrastructure/json_photo_analysis_cache.dart';
import 'package:yingjian/features/photo_analysis/infrastructure/method_channel_photo_analyzer.dart';
import 'package:yingjian/observability/app_observability.dart';
import 'package:yingjian/observability/firebase_observability_backend.dart';
import 'package:yingjian/observability/local_diagnostic_log.dart';
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
  late MetaOpCapabilitiesProvider metaOpCapabilitiesProvider;
  late PhotoPreviewRenderer photoPreviewRenderer;
  late PhotoSharer photoSharer;
  late PhotoAnalyzer photoAnalyzer;
  late PhotoAnalysisCache photoAnalysisCache;
  late DiagnosticLog diagnosticLog;
  late SpeechTranscriber speechTranscriber;
  late ReferenceStyleAnalyzer referenceStyleAnalyzer;
  late GenerationCoordinator generationCoordinator;
  GeneratedMediaActions? generatedMediaActions;
  late MaskRemovalInputCreator maskRemovalInputCreator;
  MotionPhotoGenerator? motionPhotoGenerator;
  UpscalePhotoGenerator? upscalePhotoGenerator;

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
      diagnosticLog = FileDiagnosticLog(
        directoryProvider: getApplicationSupportDirectory,
      );
      reviewManager = ReviewManager.production(observability);
      photoImporter = AppOwnedPhotoImporter(
        source: Platform.isIOS
            ? const MethodChannelPhotoSource()
            : ImagePickerPhotoSource(),
        mediaDirectory: () async {
          final root = await getApplicationSupportDirectory();
          return Directory('${root.path}/media');
        },
        diagnosticLog: diagnosticLog,
      );
      photoProjectStore = JsonPhotoProjectStore(
        directory: getApplicationSupportDirectory,
      );
      photoExporter = MethodChannelPhotoExporter();
      metaOpCapabilitiesProvider = MethodChannelMetaOpCapabilities();
      photoPreviewRenderer = MethodChannelPhotoPreviewRenderer();
      photoSharer = const MethodChannelPhotoSharer();
      photoAnalyzer = const MethodChannelPhotoAnalyzer();
      photoAnalysisCache = JsonPhotoAnalysisCache(
        directory: getApplicationSupportDirectory,
      );
      speechTranscriber = const MethodChannelSpeechTranscriber();
      referenceStyleAnalyzer = const LocalReferenceStyleAnalyzer();
      final generationProvider = await _createGenerationProvider();
      generationCoordinator = GenerationCoordinator(
        provider: generationProvider,
        store: JsonGenerationJobStore(
          directory: getApplicationSupportDirectory,
        ),
      );
      generatedMediaActions = Platform.isIOS
          ? const MethodChannelGeneratedMediaActions()
          : null;
      maskRemovalInputCreator = MaskRemovalInputBuilder();
      motionPhotoGenerator = Platform.isIOS
          ? MethodChannelMotionPhotoGenerator()
          : null;
      upscalePhotoGenerator = Platform.isIOS
          ? MethodChannelUpscalePhotoGenerator()
          : null;
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
            Provider<MetaOpCapabilitiesProvider>.value(
              value: metaOpCapabilitiesProvider,
            ),
            Provider<PhotoPreviewRenderer>.value(value: photoPreviewRenderer),
            Provider<PhotoSharer>.value(value: photoSharer),
            Provider<PhotoAnalyzer>.value(value: photoAnalyzer),
            Provider<PhotoAnalysisCache>.value(value: photoAnalysisCache),
            Provider<DiagnosticLog>.value(value: diagnosticLog),
            Provider<SpeechTranscriber>.value(value: speechTranscriber),
            Provider<ReferenceStyleAnalyzer>.value(
              value: referenceStyleAnalyzer,
            ),
            Provider<GenerationCoordinator>.value(value: generationCoordinator),
            Provider<GeneratedMediaActions?>.value(
              value: generatedMediaActions,
            ),
            Provider<MaskRemovalInputCreator>.value(
              value: maskRemovalInputCreator,
            ),
            Provider<MotionPhotoGenerator?>.value(value: motionPhotoGenerator),
            Provider<UpscalePhotoGenerator?>.value(
              value: upscalePhotoGenerator,
            ),
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

Future<GenerationProvider> _createGenerationProvider({
  GenerationSessionCredentialSource? sessionCredentialSource,
}) async {
  const baseUrl = String.fromEnvironment(
    'GENERATION_API_BASE_URL',
    defaultValue:
        'https://yingjian-generation-api.baby-animals-ai-cjc.workers.dev',
  );
  if (baseUrl.trim().isEmpty) return const UnavailableGenerationProvider();

  try {
    final baseUri = Uri.parse(baseUrl);
    if (!kDebugMode && _isLoopback(baseUri)) {
      return const UnavailableGenerationProvider();
    }
    final resolvedCredentialSource =
        sessionCredentialSource ??
        MethodChannelGenerationSessionCredentialSource(baseUri: baseUri);
    final bearerTokenProvider = _generationBearerTokenProvider(
      baseUri: baseUri,
      sessionCredentialSource: resolvedCredentialSource,
    );
    Future<GenerationProvider> connect() =>
        FirstPartyGenerationProvider.connect(
          baseUri: baseUri,
          bearerTokenProvider: bearerTokenProvider,
          resultDirectoryProvider: getApplicationSupportDirectory,
        );

    return ExplicitRefreshGenerationProvider(connector: connect);
  } on Object {
    return const UnavailableGenerationProvider();
  }
}

GenerationBearerTokenProvider _generationBearerTokenProvider({
  required Uri baseUri,
  required GenerationSessionCredentialSource sessionCredentialSource,
}) {
  if (kDebugMode && _isLoopback(baseUri)) {
    const localBearerToken = String.fromEnvironment(
      'GENERATION_API_LOCAL_BEARER_TOKEN',
    );
    if (localBearerToken.trim().isNotEmpty) {
      return () async => localBearerToken;
    }
  }

  return () async {
    final credential = await sessionCredentialSource.currentCredential();
    return credential?.bearerTokenAt(DateTime.now());
  };
}

bool _isLoopback(Uri uri) =>
    uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';

void _reportStartupError(Object error, StackTrace stackTrace) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'application_startup',
    ),
  );
}
