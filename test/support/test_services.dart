import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/app/app.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/application/photo_preview_renderer.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/observability/analytics_event.dart';
import 'package:yingjian/observability/app_observability.dart';
import 'package:yingjian/observability/observability_backend.dart';
import 'package:yingjian/review/review_manager.dart';

Widget buildTestApp(
  AppSettings settings, {
  PhotoImporter? photoImporter,
  PhotoProjectStore? photoProjectStore,
  PhotoExporter? photoExporter,
  PhotoPreviewRenderer? photoPreviewRenderer,
}) {
  final observability = AppObservability(FakeObservabilityBackend());
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppSettings>.value(value: settings),
      ChangeNotifierProvider<AppObservability>.value(value: observability),
      Provider<ReviewManager>.value(value: FakeReviewManager.create()),
      Provider<PhotoImporter>.value(
        value: photoImporter ?? FakePhotoImporter(),
      ),
      Provider<PhotoProjectStore>.value(
        value: photoProjectStore ?? MemoryPhotoProjectStore(),
      ),
      Provider<PhotoExporter>.value(
        value: photoExporter ?? FakePhotoExporter(),
      ),
      Provider<PhotoPreviewRenderer>.value(
        value: photoPreviewRenderer ?? FakePhotoPreviewRenderer.unsupported(),
      ),
    ],
    child: const YingjianApp(),
  );
}

final class FakePhotoPreviewRenderer implements PhotoPreviewRenderer {
  FakePhotoPreviewRenderer.unsupported() : unsupported = true;

  FakePhotoPreviewRenderer.supported() : unsupported = false;

  final bool unsupported;
  final List<ImagePipeline> updates = [];
  int disposeCount = 0;

  @override
  Future<PhotoPreviewHandle> create({
    required String sourcePath,
    required ImagePipeline pipeline,
    int maxEdge = 2048,
  }) async {
    if (unsupported) {
      throw UnsupportedError('Native preview is unavailable in widget tests');
    }
    return const PhotoPreviewHandle(
      textureId: 42,
      width: 1600,
      height: 1200,
      backend: 'fake',
    );
  }

  @override
  Future<void> update({
    required PhotoPreviewHandle handle,
    required ImagePipeline pipeline,
  }) async {
    updates.add(pipeline);
  }

  @override
  Future<void> dispose(PhotoPreviewHandle handle) async {
    disposeCount += 1;
  }
}

final class FakePhotoExporter implements PhotoExporter {
  ProjectPhoto? exportedPhoto;
  EditRecipe? exportedRecipe;

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) async {
    exportedPhoto = photo;
    exportedRecipe = recipe;
    return const ExportedPhoto(assetId: 'asset-42', width: 4032, height: 3024);
  }
}

final class FakePhotoImporter implements PhotoImporter {
  FakePhotoImporter([this.photos = const [], this.failures = const []]);

  final List<ProjectPhoto> photos;
  final List<PhotoImportFailure> failures;

  @override
  Future<PhotoImportBatch> importPhotos({required int limit}) async {
    return PhotoImportBatch(
      photos: photos.take(limit).toList(),
      failures: failures,
    );
  }
}

final class MemoryPhotoProjectStore implements PhotoProjectLifecycleStore {
  MemoryPhotoProjectStore([this.project]);

  PhotoProject? project;

  @override
  Future<PhotoProject?> loadLatest() async => project;

  @override
  Future<void> save(PhotoProject project) async {
    this.project = project;
  }

  @override
  Future<void> deletePhotoCopy(ProjectPhoto photo) async {}

  @override
  Future<void> deleteProject(PhotoProject project) async {
    this.project = null;
  }
}

final class FakeObservabilityBackend implements ObservabilityBackend {
  FakeObservabilityBackend({this.canInitialize = true});

  final bool canInitialize;
  bool collectionEnabled = false;
  final List<String> events = [];
  final List<String> screens = [];
  final List<Object> errors = [];
  final List<FakeObservabilityTrace> traces = [];

  @override
  Future<bool> initialize() async => canInitialize;

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    collectionEnabled = enabled;
  }

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {
    events.add(name);
  }

  @override
  Future<void> logScreenView(String screenName) async {
    screens.add(screenName);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    required bool fatal,
    required String reason,
  }) async {
    errors.add(error);
  }

  @override
  ObservabilityTrace createTrace(String name) {
    final trace = FakeObservabilityTrace(name);
    traces.add(trace);
    return trace;
  }
}

final class FakeObservabilityTrace implements ObservabilityTrace {
  FakeObservabilityTrace(this.name);

  final String name;
  final Map<String, String> attributes = {};
  bool started = false;
  bool stopped = false;

  @override
  void putAttribute(String name, String value) {
    attributes[name] = value;
  }

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }
}

final class FakeReviewManager {
  static ReviewManager create() => ReviewManager(
    stateStore: _MemoryReviewStateStore(),
    gateway: _FakeReviewGateway(),
    analytics: _FakeReviewAnalytics(),
    now: DateTime.now,
    version: () async => '0.1.0',
    requestDelay: Duration.zero,
  );
}

final class _MemoryReviewStateStore implements ReviewStateStore {
  ReviewState state = const ReviewState();

  @override
  Future<ReviewState> load() async => state;

  @override
  Future<void> save(ReviewState state) async {
    this.state = state;
  }
}

final class _FakeReviewGateway implements ReviewGateway {
  @override
  Future<bool> openStoreListing() async => false;

  @override
  Future<bool> requestReview() async => false;
}

final class _FakeReviewAnalytics implements ReviewAnalytics {
  @override
  Future<void> track(AnalyticsEvent event) async {}
}
