import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/app/app.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/features/editor/application/meta_op_capabilities_provider.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/application/photo_preview_renderer.dart';
import 'package:yingjian/features/editor/application/photo_sharer.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/editing_resource.dart';
import 'package:yingjian/features/editor/domain/content_sha256.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/editor/domain/meta_op_availability.dart';
import 'package:yingjian/features/editor/domain/platform_meta_op_capabilities.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/photo_analysis/application/photo_analysis_cache.dart';
import 'package:yingjian/features/photo_analysis/domain/photo_analysis.dart';
import 'package:yingjian/observability/analytics_event.dart';
import 'package:yingjian/observability/app_observability.dart';
import 'package:yingjian/observability/observability_backend.dart';
import 'package:yingjian/review/review_manager.dart';

import 'memory_photo_analysis_cache.dart';

Widget buildTestApp(
  AppSettings settings, {
  PhotoImporter? photoImporter,
  PhotoProjectStore? photoProjectStore,
  PhotoExporter? photoExporter,
  PhotoPreviewRenderer? photoPreviewRenderer,
  PhotoSharer? photoSharer,
  PhotoAnalyzer? photoAnalyzer,
  PhotoAnalysisCache? photoAnalysisCache,
  PlatformMetaOpCapabilities? metaOpCapabilities,
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
      Provider<MetaOpCapabilitiesProvider>.value(
        value: StaticMetaOpCapabilitiesProvider(
          metaOpCapabilities ?? androidMetaOpCapabilities,
        ),
      ),
      Provider<PhotoPreviewRenderer>.value(
        value: photoPreviewRenderer ?? FakePhotoPreviewRenderer.supported(),
      ),
      Provider<PhotoSharer>.value(value: photoSharer ?? FakePhotoSharer()),
      Provider<PhotoAnalyzer>.value(
        value: photoAnalyzer ?? const MetadataSafePhotoAnalyzer(),
      ),
      Provider<PhotoAnalysisCache>.value(
        value: photoAnalysisCache ?? MemoryPhotoAnalysisCache(),
      ),
    ],
    child: const YingjianApp(),
  );
}

final class FakePhotoPreviewRenderer implements PhotoPreviewRenderer {
  FakePhotoPreviewRenderer.unsupported() : unsupported = true;

  FakePhotoPreviewRenderer.supported() : unsupported = false;

  final bool unsupported;
  final List<ImagePipeline> creates = [];
  final List<ImagePipeline> updates = [];
  final List<int> maxEdges = [];
  int disposeCount = 0;

  @override
  Future<PhotoPreviewHandle> create({
    required String sourcePath,
    required ImagePipeline pipeline,
    int maxEdge = 2048,
  }) async {
    creates.add(pipeline);
    maxEdges.add(maxEdge);
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
    return const ExportedPhoto(
      assetId: 'asset-42',
      width: 4032,
      height: 3024,
      sharePath: '/tmp/Yingjian_fixture.jpg',
    );
  }
}

final class FakePhotoSharer implements PhotoSharer {
  FakePhotoSharer({
    this.outcome = PhotoShareOutcome.completed,
    this.error,
    this.discardError,
  });

  final PhotoShareOutcome outcome;
  final Object? error;
  final Object? discardError;
  List<String>? sharedPaths;
  List<String>? discardedPaths;

  @override
  Future<PhotoShareOutcome> share({required List<String> localPaths}) async {
    sharedPaths = List.unmodifiable(localPaths);
    if (error case final error?) throw error;
    return outcome;
  }

  @override
  Future<void> discard({required List<String> localPaths}) async {
    discardedPaths = List.unmodifiable(localPaths);
    if (discardError case final error?) throw error;
  }
}

final class FakePhotoImporter implements EditingResourceImporter {
  FakePhotoImporter([this.photos = const [], this.failures = const []]);

  final List<ProjectPhoto> photos;
  final List<PhotoImportFailure> failures;
  int editingResourceImportCount = 0;
  ImportedEditingResource? lastImportedEditingResource;
  final List<String> discardedEditingResourceIds = [];

  @override
  Future<PhotoImportBatch> importPhotos({required int limit}) async {
    return PhotoImportBatch(
      photos: photos.take(limit).toList(),
      failures: failures,
    );
  }

  @override
  Future<ImportedEditingResource?> importEditingResource(
    EditingResourceKind kind,
  ) async {
    editingResourceImportCount += 1;
    if (photos.isEmpty) return null;
    final photo = photos.first;
    final sha = photo.contentSha256;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha)) return null;
    final extension = photo.localPath.toLowerCase().endsWith('.png')
        ? '.png'
        : '.jpg';
    return lastImportedEditingResource = ImportedEditingResource(
      descriptor: EditingResourceDescriptor(
        id: 'resource-v1-$sha',
        kind: kind,
        relativePath: 'resources/${sha.substring(0, 2)}/$sha$extension',
        contentSha256: sha,
        byteLength: File(photo.localPath).lengthSync(),
      ),
      localPath: photo.localPath,
    );
  }

  @override
  Future<ImportedEditingResource> storeEditingResource({
    required EditingResourceKind kind,
    required List<int> bytes,
    String extension = '.json',
    Object? payload,
  }) async {
    editingResourceImportCount += 1;
    final sha = ContentSha256.ofBytes(bytes);
    return lastImportedEditingResource = ImportedEditingResource(
      descriptor: EditingResourceDescriptor(
        id: 'resource-v1-$sha',
        kind: kind,
        relativePath: 'resources/${sha.substring(0, 2)}/$sha$extension',
        contentSha256: sha,
        byteLength: bytes.length,
      ),
      localPath: photos.isEmpty
          ? '/tmp/$sha$extension'
          : photos.first.localPath,
      payload: payload,
    );
  }

  @override
  Future<void> discardEditingResource(ImportedEditingResource resource) async {
    discardedEditingResourceIds.add(resource.descriptor.id);
  }
}

final class MemoryPhotoProjectStore implements PhotoProjectCatalogStore {
  MemoryPhotoProjectStore([PhotoProject? project])
    : _projects = project == null ? [] : [project],
      _activeProjectId = project?.id;

  MemoryPhotoProjectStore.withProjects(List<PhotoProject> projects)
    : _projects = List.of(projects),
      _activeProjectId = projects.firstOrNull?.id {
    _sortProjects();
  }

  final List<PhotoProject> _projects;
  String? _activeProjectId;
  String? _projectBeforeNewId;
  bool _startingNewProject = false;

  List<PhotoProject> get projects => List.unmodifiable(_projects);

  PhotoProject? get project {
    if (_startingNewProject) return null;
    final active = _projects
        .where((candidate) => candidate.id == _activeProjectId)
        .firstOrNull;
    return active ?? _projects.firstOrNull;
  }

  @override
  Future<PhotoProject?> loadLatest() async => project;

  @override
  Future<List<PhotoProject>> loadProjects() async => projects;

  @override
  Future<PhotoProject?> loadProject(String projectId) async =>
      _projects.where((project) => project.id == projectId).firstOrNull;

  @override
  Future<void> activateProject(String projectId) async {
    if (!_projects.any((project) => project.id == projectId)) {
      throw StateError('Photo project does not exist');
    }
    _activeProjectId = projectId;
    _projectBeforeNewId = null;
    _startingNewProject = false;
  }

  @override
  Future<void> startNewProject() async {
    if (_startingNewProject) return;
    _projectBeforeNewId = _activeProjectId ?? _projects.firstOrNull?.id;
    _activeProjectId = null;
    _startingNewProject = true;
  }

  @override
  Future<void> cancelNewProject() async {
    if (!_startingNewProject && _projectBeforeNewId == null) return;
    _activeProjectId = _projectBeforeNewId;
    _projectBeforeNewId = null;
    _startingNewProject = false;
  }

  @override
  Future<void> save(PhotoProject project) async {
    final completingNewProject = _startingNewProject;
    _projects.removeWhere((candidate) => candidate.id == project.id);
    _projects.add(project);
    _sortProjects();
    _activeProjectId = project.id;
    if (!completingNewProject) _projectBeforeNewId = null;
    _startingNewProject = false;
  }

  @override
  Future<void> deletePhotoCopy(ProjectPhoto photo) async {}

  @override
  Future<void> deleteProject(PhotoProject project) async {
    _projects.removeWhere((candidate) => candidate.id == project.id);
    if (_activeProjectId == project.id) _activeProjectId = null;
  }

  void _sortProjects() {
    _projects.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
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
