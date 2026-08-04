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
  PhotoProjectFlowState get flowState => _isImporting
      ? PhotoProjectFlowState.importing
      : _project?.flowState ?? PhotoProjectFlowState.empty;
  List<PhotoImportFailure> get importFailures => _importFailures;
  bool get canUndo => _project?.undoHistory.isNotEmpty ?? false;
  bool get canRedo => _project?.redoHistory.isNotEmpty ?? false;
  bool get canEdit => _project?.flowState == PhotoProjectFlowState.editing;

  EditRecipe get editableRecipe {
    final current = _project;
    if (current == null) return EditRecipe.neutral;
    if (current.editingScope == ProjectEditingScope.group) {
      return current.sharedStyle.recipe;
    }
    final photoId = current.focusPhotoId ?? current.photos.first.id;
    return current.photoOverrides[photoId]?.recipe ?? EditRecipe.neutral;
  }

  EditRecipe effectiveRecipeFor(String photoId) {
    return _requirePhoto(photoId).effectiveRecipeFor(photoId);
  }

  EditRecipe previewRecipeFor(String photoId, EditRecipe editableRecipe) {
    final current = _requirePhoto(photoId);
    return current.editingScope == ProjectEditingScope.group
        ? current.effectiveRecipeFor(photoId, sharedRecipe: editableRecipe)
        : current.effectiveRecipeFor(photoId, photoOverride: editableRecipe);
  }

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
    if (_isImporting) {
      throw StateError('A photo import is already active');
    }
    if (_project?.canMutateInputs == false) {
      throw StateError('Project inputs cannot change while exporting');
    }
    final remaining = PhotoProject.maxPhotoCount - photos.length;
    if (remaining == 0) {
      return PhotoImportResult.limitReached;
    }

    _isImporting = true;
    notifyListeners();
    try {
      return await _performImport(remaining);
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  Future<PhotoImportResult> _performImport(int remaining) async {
    final batch = await _importer.importPhotos(limit: remaining);
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
        : existing.replacePhotosAndInvalidateDerivedState(
            photos: [...existing.photos, ...imported],
            updatedAt: timestamp,
            focusPhotoId: existing.focusPhotoId,
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
    if (!current.canTransitionTo(nextState)) {
      throw StateError(
        'Project cannot transition from ${current.flowState.name} '
        'to ${nextState.name}',
      );
    }
    if (current.flowState == nextState) return;
    final next = current.copyWith(updatedAt: _now(), flowState: nextState);
    await _saveAndPublish(next);
  }

  Future<void> selectRecommendation({
    required String recommendationId,
    required SharedStyle sharedStyle,
    Map<String, AdaptiveCompensation> adaptiveCompensations = const {},
  }) async {
    final current = _project;
    if (current == null) {
      throw StateError(
        'A project is required before selecting a recommendation',
      );
    }
    if (current.flowState != PhotoProjectFlowState.choosingRecommendation) {
      throw StateError('Recommendations can only be selected while choosing');
    }
    if (recommendationId.trim().isEmpty) {
      throw ArgumentError.value(
        recommendationId,
        'recommendationId',
        'Recommendation id must not be empty',
      );
    }
    final next = current.copyWith(
      updatedAt: _now(),
      flowState: PhotoProjectFlowState.editing,
      selectedRecommendationId: recommendationId,
      sharedStyle: sharedStyle,
      adaptiveCompensations: adaptiveCompensations,
      photoOverrides: const {},
      exportStates: {
        for (final photo in current.photos)
          photo.id: PhotoExportState.notQueued,
      },
      editingScope: current.photos.length == 1
          ? ProjectEditingScope.currentPhoto
          : ProjectEditingScope.group,
      undoHistory: const [],
      redoHistory: const [],
    );
    await _saveAndPublish(next);
  }

  Future<void> setEditingScope(
    ProjectEditingScope scope, {
    String? photoId,
  }) async {
    final current = _project;
    if (current == null) {
      throw StateError('A project is required before changing editing scope');
    }
    if (current.flowState != PhotoProjectFlowState.editing) {
      throw StateError('Editing scope can only change while editing');
    }
    if (scope == ProjectEditingScope.group && current.photos.length == 1) {
      throw StateError('A single-photo project has no group editing scope');
    }
    if (scope == ProjectEditingScope.currentPhoto) {
      if (photoId == null ||
          !current.photos.any((photo) => photo.id == photoId)) {
        throw ArgumentError.value(
          photoId,
          'photoId',
          'Current-photo scope requires a project photo',
        );
      }
    }
    final focusPhotoId = scope == ProjectEditingScope.currentPhoto
        ? photoId
        : current.focusPhotoId;
    if (current.editingScope == scope && current.focusPhotoId == focusPhotoId) {
      return;
    }
    final next = current.copyWith(
      updatedAt: _now(),
      editingScope: scope,
      focusPhotoId: focusPhotoId,
    );
    await _saveAndPublish(next);
  }

  Future<void> commitEdit(EditRecipe recipe) async {
    final current = _project;
    if (current == null) {
      throw StateError('A project is required before committing an edit');
    }
    if (current.flowState != PhotoProjectFlowState.editing) {
      throw StateError('Edits can only be committed while editing');
    }
    final photoId = current.editingScope == ProjectEditingScope.currentPhoto
        ? current.focusPhotoId ?? current.photos.first.id
        : null;
    final beforeRecipe = photoId == null
        ? current.sharedStyle.recipe
        : current.photoOverrides[photoId]?.recipe ?? EditRecipe.neutral;
    if (beforeRecipe == recipe) return;
    final operation = ProjectEditOperation(
      scope: current.editingScope,
      photoId: photoId,
      beforeRecipe: beforeRecipe,
      afterRecipe: recipe,
      beforeSharedIntensity: current.sharedStyle.intensity,
      afterSharedIntensity: current.sharedStyle.intensity,
    );
    final next = _applyOperation(
      current,
      operation,
      recipe,
      sharedIntensity: current.sharedStyle.intensity,
      undoHistory: [...current.undoHistory, operation],
      redoHistory: const [],
    );
    await _saveAndPublish(next);
  }

  Future<void> commitSharedIntensity(double intensity) async {
    final current = _project;
    if (current == null) {
      throw StateError('A project is required before committing an edit');
    }
    if (current.flowState != PhotoProjectFlowState.editing ||
        current.editingScope != ProjectEditingScope.group) {
      throw StateError('Shared intensity can only change in group editing');
    }
    final nextStyle = SharedStyle(
      recipe: current.sharedStyle.recipe,
      family: current.sharedStyle.family,
      intensity: intensity,
    );
    if (nextStyle == current.sharedStyle) return;
    final operation = ProjectEditOperation(
      scope: ProjectEditingScope.group,
      beforeRecipe: current.sharedStyle.recipe,
      afterRecipe: current.sharedStyle.recipe,
      beforeSharedIntensity: current.sharedStyle.intensity,
      afterSharedIntensity: intensity,
    );
    final next = _applyOperation(
      current,
      operation,
      operation.afterRecipe,
      sharedIntensity: operation.afterSharedIntensity,
      undoHistory: [...current.undoHistory, operation],
      redoHistory: const [],
    );
    await _saveAndPublish(next);
  }

  Future<void> undoEdit() async {
    final current = _project;
    if (current == null || current.undoHistory.isEmpty) return;
    if (current.flowState != PhotoProjectFlowState.editing) {
      throw StateError('Edit history can only change while editing');
    }
    final operation = current.undoHistory.last;
    final next = _applyOperation(
      current,
      operation,
      operation.beforeRecipe,
      sharedIntensity: operation.beforeSharedIntensity,
      undoHistory: current.undoHistory.sublist(
        0,
        current.undoHistory.length - 1,
      ),
      redoHistory: [...current.redoHistory, operation],
    );
    await _saveAndPublish(next);
  }

  Future<void> redoEdit() async {
    final current = _project;
    if (current == null || current.redoHistory.isEmpty) return;
    if (current.flowState != PhotoProjectFlowState.editing) {
      throw StateError('Edit history can only change while editing');
    }
    final operation = current.redoHistory.last;
    final next = _applyOperation(
      current,
      operation,
      operation.afterRecipe,
      sharedIntensity: operation.afterSharedIntensity,
      undoHistory: [...current.undoHistory, operation],
      redoHistory: current.redoHistory.sublist(
        0,
        current.redoHistory.length - 1,
      ),
    );
    await _saveAndPublish(next);
  }

  Future<void> movePhoto({
    required String photoId,
    required int toIndex,
  }) async {
    final current = _project;
    if (current == null) {
      throw StateError('A project is required before moving a photo');
    }
    if (!current.canMutateInputs) {
      throw StateError('Project inputs cannot change while exporting');
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
    await _saveAndPublish(next);
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
    await _saveAndPublish(next);
  }

  Future<void> setPhotoAnalysisState(
    String photoId,
    PhotoAnalysisState state,
  ) async {
    final current = _requirePhoto(photoId);
    final previous = current.analysisStates[photoId]!;
    if (previous == state) return;
    if (!current.canTransitionPhotoAnalysis(photoId, state)) {
      throw StateError(
        'Photo analysis cannot transition from ${previous.name} to ${state.name}',
      );
    }
    final states = Map.of(current.analysisStates)..[photoId] = state;
    final next = current.copyWith(updatedAt: _now(), analysisStates: states);
    await _saveAndPublish(next);
  }

  Future<void> setPhotoExportState(
    String photoId,
    PhotoExportState state,
  ) async {
    final current = _requirePhoto(photoId);
    final previous = current.exportStates[photoId]!;
    if (previous == state) return;
    if (!current.canTransitionPhotoExport(photoId, state)) {
      throw StateError(
        'Photo export cannot transition from ${previous.name} to ${state.name}',
      );
    }
    final states = Map.of(current.exportStates)..[photoId] = state;
    final next = current.copyWith(updatedAt: _now(), exportStates: states);
    await _saveAndPublish(next);
  }

  Future<void> removePhoto(String photoId) async {
    final current = _project;
    if (current == null) {
      throw StateError('A project is required before removing a photo');
    }
    if (!current.canMutateInputs) {
      throw StateError('Project inputs cannot change while exporting');
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
    final focusPhotoId = current.focusPhotoId == photoId
        ? remainingPhotos[photoIndex.clamp(0, remainingPhotos.length - 1)].id
        : current.focusPhotoId;
    final next = current.replacePhotosAndInvalidateDerivedState(
      updatedAt: _now(),
      photos: remainingPhotos,
      focusPhotoId: focusPhotoId,
    );
    await _saveAndPublish(next);
    await lifecycleStore.deletePhotoCopy(removedPhoto);
  }

  Future<void> deleteProject() async {
    final current = _project;
    if (current == null) {
      return;
    }
    if (!current.canMutateInputs) {
      throw StateError('Project cannot be deleted while exporting');
    }
    final lifecycleStore = _store;
    if (lifecycleStore is! PhotoProjectLifecycleStore) {
      throw StateError('The project store does not support project deletion');
    }
    await lifecycleStore.deleteProject(current);
    _project = null;
    notifyListeners();
  }

  PhotoProject _applyOperation(
    PhotoProject current,
    ProjectEditOperation operation,
    EditRecipe recipe, {
    required double sharedIntensity,
    required List<ProjectEditOperation> undoHistory,
    required List<ProjectEditOperation> redoHistory,
  }) {
    final exportStates = Map.of(current.exportStates);
    if (operation.scope == ProjectEditingScope.group) {
      for (final photo in current.photos) {
        exportStates[photo.id] = PhotoExportState.notQueued;
      }
      return current.copyWith(
        updatedAt: _now(),
        editingScope: ProjectEditingScope.group,
        sharedStyle: SharedStyle(
          recipe: recipe,
          family: current.sharedStyle.family,
          intensity: sharedIntensity,
        ),
        exportStates: exportStates,
        undoHistory: undoHistory,
        redoHistory: redoHistory,
      );
    }

    final photoId = operation.photoId!;
    final overrides = Map.of(current.photoOverrides);
    if (recipe == EditRecipe.neutral) {
      overrides.remove(photoId);
    } else {
      overrides[photoId] = PhotoOverride(recipe: recipe);
    }
    exportStates[photoId] = PhotoExportState.notQueued;
    return current.copyWith(
      updatedAt: _now(),
      editingScope: ProjectEditingScope.currentPhoto,
      focusPhotoId: photoId,
      photoOverrides: overrides,
      exportStates: exportStates,
      undoHistory: undoHistory,
      redoHistory: redoHistory,
    );
  }

  Future<void> _saveAndPublish(PhotoProject next) async {
    await _store.save(next);
    _project = next;
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
