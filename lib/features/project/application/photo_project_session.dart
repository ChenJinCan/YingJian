import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

abstract interface class PhotoImporter {
  Future<PhotoImportBatch> importPhotos({required int limit});
}

enum PhotoImportFailureReason {
  unsupportedFormat,
  unsupportedColorSpace,
  animatedImage,
  fileTooLarge,
  dimensionsTooLarge,
  unreadable,
  copyFailed,
}

@immutable
class PhotoImportFailure {
  const PhotoImportFailure({required this.photoName, required this.reason});

  final String photoName;
  final PhotoImportFailureReason reason;

  @override
  bool operator ==(Object other) =>
      other is PhotoImportFailure &&
      other.photoName == photoName &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(photoName, reason);
}

@immutable
class PhotoImportBatch {
  const PhotoImportBatch({this.photos = const [], this.failures = const []});

  final List<ProjectPhoto> photos;
  final List<PhotoImportFailure> failures;
}

abstract interface class PhotoProjectStore {
  Future<PhotoProject?> loadLatest();

  Future<void> save(PhotoProject project);
}

abstract interface class PhotoProjectLifecycleStore
    implements PhotoProjectStore {
  Future<void> deletePhotoCopy(ProjectPhoto photo);

  Future<void> deleteProject(PhotoProject project);
}

enum PhotoImportResult { imported, canceled, rejected, limitReached }

class PhotoProjectSession extends ChangeNotifier {
  factory PhotoProjectSession({
    required PhotoImporter importer,
    required PhotoProjectStore store,
    DateTime Function()? now,
    String Function()? createId,
  }) {
    return PhotoProjectSession._(
      importer,
      store,
      now ?? DateTime.now,
      createId ?? _defaultId,
    );
  }

  PhotoProjectSession._(this._importer, this._store, this._now, this._createId);

  final PhotoImporter _importer;
  final PhotoProjectStore _store;
  final DateTime Function() _now;
  final String Function() _createId;

  PhotoProject? _project;
  Object? _restoreError;
  bool _isRestoring = false;
  bool _isImporting = false;
  List<PhotoImportFailure> _importFailures = const [];

  PhotoProject? get project => _project;
  List<ProjectPhoto> get photos => _project?.photos ?? const [];
  Object? get restoreError => _restoreError;
  bool get isRestoring => _isRestoring;
  bool get isImporting => _isImporting;
  List<PhotoImportFailure> get importFailures => _importFailures;

  Future<void> restore() async {
    _isRestoring = true;
    _restoreError = null;
    notifyListeners();
    try {
      _project = await _store.loadLatest();
    } on Object catch (error) {
      _restoreError = error;
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  Future<PhotoImportResult> importPhotos() async {
    final remaining = PhotoProject.maxPhotoCount - photos.length;
    if (remaining == 0) {
      return PhotoImportResult.limitReached;
    }

    _isImporting = true;
    notifyListeners();
    late final PhotoImportBatch batch;
    try {
      batch = await _importer.importPhotos(limit: remaining);
    } finally {
      _isImporting = false;
      notifyListeners();
    }
    _importFailures = List.unmodifiable(batch.failures);
    final imported = batch.photos;
    if (imported.isEmpty) {
      if (_importFailures.isNotEmpty) {
        notifyListeners();
        return PhotoImportResult.rejected;
      }
      return PhotoImportResult.canceled;
    }
    if (imported.length > remaining) {
      throw StateError('Photo importer returned more than the requested limit');
    }

    final timestamp = _now();
    final existing = _project;
    final next = existing == null
        ? PhotoProject(
            id: _createId(),
            createdAt: timestamp,
            updatedAt: timestamp,
            photos: imported,
            flowState: PhotoProjectFlowState.analyzing,
          )
        : existing.copyWith(
            updatedAt: timestamp,
            photos: [...existing.photos, ...imported],
            flowState: PhotoProjectFlowState.analyzing,
            selectedRecommendationId: null,
          );
    try {
      await _store.save(next);
    } on Object catch (error, stackTrace) {
      final lifecycleStore = _store;
      if (lifecycleStore is PhotoProjectLifecycleStore) {
        for (final photo in imported) {
          try {
            await lifecycleStore.deletePhotoCopy(photo);
          } on Object {
            // Preserve the save failure; cleanup remains best-effort.
          }
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    _project = next;
    notifyListeners();
    return PhotoImportResult.imported;
  }

  Future<void> transitionTo(PhotoProjectFlowState nextState) async {
    final current = _project;
    if (current == null) {
      throw StateError('A project is required before changing its flow state');
    }
    if (!current.flowState.canTransitionTo(nextState)) {
      throw StateError(
        'Project cannot transition from ${current.flowState.name} '
        'to ${nextState.name}',
      );
    }
    if (current.flowState == nextState) return;
    final next = current.copyWith(updatedAt: _now(), flowState: nextState);
    await _store.save(next);
    _project = next;
    notifyListeners();
  }

  Future<void> updateRecipe(EditRecipe recipe) async {
    final current = _project;
    if (current == null || current.recipe == recipe) {
      return;
    }
    final next = current.copyWith(updatedAt: _now(), recipe: recipe);
    await _store.save(next);
    _project = next;
    notifyListeners();
  }

  Future<void> movePhoto({
    required String photoId,
    required int toIndex,
  }) async {
    final current = _project;
    if (current == null) {
      throw StateError('A project is required before moving a photo');
    }
    if (toIndex < 0 || toIndex >= current.photos.length) {
      throw RangeError.index(toIndex, current.photos, 'toIndex');
    }
    final fromIndex = current.photos.indexWhere((photo) => photo.id == photoId);
    if (fromIndex < 0) {
      throw ArgumentError.value(photoId, 'photoId', 'Photo is not in project');
    }
    if (fromIndex == toIndex) {
      return;
    }
    final reordered = current.photos.toList();
    final photo = reordered.removeAt(fromIndex);
    reordered.insert(toIndex, photo);
    final next = current.copyWith(updatedAt: _now(), photos: reordered);
    await _store.save(next);
    _project = next;
    notifyListeners();
  }

  Future<void> setFocusPhoto(String photoId) async {
    final current = _project;
    if (current == null) {
      throw StateError('A project is required before selecting a focus photo');
    }
    if (!current.photos.any((photo) => photo.id == photoId)) {
      throw ArgumentError.value(photoId, 'photoId', 'Photo is not in project');
    }
    if (current.focusPhotoId == photoId) {
      return;
    }
    final next = current.copyWith(updatedAt: _now(), focusPhotoId: photoId);
    await _store.save(next);
    _project = next;
    notifyListeners();
  }

  Future<void> setPhotoAnalysisState(
    String photoId,
    PhotoAnalysisState state,
  ) async {
    final current = _requirePhoto(photoId);
    if (current.analysisStates[photoId] == state) return;
    final states = Map.of(current.analysisStates)..[photoId] = state;
    final next = current.copyWith(updatedAt: _now(), analysisStates: states);
    await _store.save(next);
    _project = next;
    notifyListeners();
  }

  Future<void> setPhotoExportState(
    String photoId,
    PhotoExportState state,
  ) async {
    final current = _requirePhoto(photoId);
    if (current.exportStates[photoId] == state) return;
    final states = Map.of(current.exportStates)..[photoId] = state;
    final next = current.copyWith(updatedAt: _now(), exportStates: states);
    await _store.save(next);
    _project = next;
    notifyListeners();
  }

  Future<void> removePhoto(String photoId) async {
    final current = _project;
    if (current == null) {
      throw StateError('A project is required before removing a photo');
    }
    final photoIndex = current.photos.indexWhere(
      (photo) => photo.id == photoId,
    );
    if (photoIndex < 0) {
      throw ArgumentError.value(photoId, 'photoId', 'Photo is not in project');
    }
    final lifecycleStore = _store;
    if (lifecycleStore is! PhotoProjectLifecycleStore) {
      throw StateError('The project store does not support photo removal');
    }
    final removedPhoto = current.photos[photoIndex];
    if (current.photos.length == 1) {
      await lifecycleStore.deleteProject(current);
      _project = null;
      notifyListeners();
      return;
    }

    final remainingPhotos = current.photos.toList()..removeAt(photoIndex);
    final adaptiveCompensations = Map.of(current.adaptiveCompensations)
      ..remove(photoId);
    final photoOverrides = Map.of(current.photoOverrides)..remove(photoId);
    final analysisStates = Map.of(current.analysisStates)..remove(photoId);
    final exportStates = Map.of(current.exportStates)..remove(photoId);
    final focusPhotoId = current.focusPhotoId == photoId
        ? remainingPhotos[photoIndex.clamp(0, remainingPhotos.length - 1)].id
        : current.focusPhotoId;
    final next = current.copyWith(
      updatedAt: _now(),
      photos: remainingPhotos,
      adaptiveCompensations: adaptiveCompensations,
      photoOverrides: photoOverrides,
      analysisStates: analysisStates,
      exportStates: exportStates,
      focusPhotoId: focusPhotoId,
    );
    await lifecycleStore.save(next);
    _project = next;
    notifyListeners();
    await lifecycleStore.deletePhotoCopy(removedPhoto);
  }

  Future<void> deleteProject() async {
    final current = _project;
    if (current == null) {
      return;
    }
    final lifecycleStore = _store;
    if (lifecycleStore is! PhotoProjectLifecycleStore) {
      throw StateError('The project store does not support project deletion');
    }
    await lifecycleStore.deleteProject(current);
    _project = null;
    notifyListeners();
  }

  PhotoProject _requirePhoto(String photoId) {
    final current = _project;
    if (current == null) {
      throw StateError('A project is required before updating a photo');
    }
    if (!current.photos.any((photo) => photo.id == photoId)) {
      throw ArgumentError.value(photoId, 'photoId', 'Photo is not in project');
    }
    return current;
  }

  static String _defaultId() {
    return 'project-${DateTime.now().toUtc().microsecondsSinceEpoch}';
  }
}
