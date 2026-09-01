import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yingjian/features/creation/domain/creation_intent.dart';
import 'package:yingjian/features/creation/domain/creation_task.dart';
import 'package:yingjian/features/editor/application/ai_edit_planner.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/editing_resource.dart';
import 'package:yingjian/features/editor/domain/legacy_edit_recipe_adapter.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

abstract interface class PhotoImporter {
  Future<PhotoImportBatch> importPhotos({required int limit});
}

abstract interface class CancelablePhotoImporter implements PhotoImporter {
  Future<void> cancelImport();
}

@immutable
final class ImportedEditingResource {
  const ImportedEditingResource({
    required this.descriptor,
    required this.localPath,
    this.payload,
  });

  final EditingResourceDescriptor descriptor;
  final String localPath;
  final Object? payload;
}

abstract interface class EditingResourceImporter implements PhotoImporter {
  Future<ImportedEditingResource?> importEditingResource(
    EditingResourceKind kind,
  );

  Future<ImportedEditingResource> storeEditingResource({
    required EditingResourceKind kind,
    required List<int> bytes,
    String extension = '.json',
    Object? payload,
  });

  Future<void> discardEditingResource(ImportedEditingResource resource);
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

abstract interface class PhotoProjectCatalogStore
    implements PhotoProjectLifecycleStore {
  Future<List<PhotoProject>> loadProjects();

  Future<PhotoProject?> loadProject(String projectId);

  Future<void> activateProject(String projectId);

  Future<void> startNewProject();

  Future<void> cancelNewProject();
}

enum PhotoImportResult { imported, canceled, rejected, limitReached }

@immutable
final class PreparedMetaOpPreview {
  const PreparedMetaOpPreview({
    required this.recipe,
    required this.scopedRecipe,
    required this.state,
    required this.context,
    required this.sourceId,
  });

  final EditRecipe recipe;
  final EditRecipe scopedRecipe;
  final EditState state;
  final EditContext context;
  final String sourceId;
}

@immutable
final class ManualEditCommit {
  const ManualEditCommit({required this.result, required this.appliedToGroup});

  final EditResult result;
  final bool appliedToGroup;
}

class PhotoProjectSession extends ChangeNotifier {
  factory PhotoProjectSession({
    required PhotoImporter importer,
    required PhotoProjectStore store,
    CreationIntent? creationIntent,
    CreationTask? creationTask,
    String? projectId,
    DateTime Function()? now,
    String Function()? createId,
  }) {
    final clock = now ?? DateTime.now;
    if (creationIntent != null &&
        creationTask != null &&
        creationTask.creationIntent != creationIntent) {
      throw ArgumentError.value(
        creationTask,
        'creationTask',
        'The task must use the same execution intent as its session',
      );
    }
    final resolvedIntent =
        creationTask?.creationIntent ?? creationIntent ?? CreationIntent.apply;
    final resolvedTask =
        creationTask ?? CreationTask.fromCreationIntent(resolvedIntent);
    return PhotoProjectSession._(
      importer,
      store,
      resolvedIntent,
      resolvedTask,
      projectId,
      () => clock().toUtc(),
      createId ?? _defaultId,
    );
  }

  PhotoProjectSession._(
    this._importer,
    this._store,
    this._creationIntent,
    this._creationTask,
    this._projectId,
    this._now,
    this._createId,
  );

  final PhotoImporter _importer;
  final PhotoProjectStore _store;
  final CreationIntent _creationIntent;
  final CreationTask _creationTask;
  final String? _projectId;
  final DateTime Function() _now;
  final String Function() _createId;

  static const _editingCore = EditingCore();
  static const _legacyAdapter = LegacyEditRecipeAdapter();

  PhotoProject? _project;
  Object? _restoreError;
  bool _isRestoring = false;
  bool _isImporting = false;
  bool _disposed = false;
  List<PhotoImportFailure> _importFailures = const [];

  void _notifyIfActive() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  PhotoProject? get project => _project;
  List<ProjectPhoto> get photos => _project?.photos ?? const [];
  Object? get restoreError => _restoreError;
  bool get isRestoring => _isRestoring;
  bool get isImporting => _isImporting;
  PhotoProjectFlowState get flowState => _isImporting
      ? PhotoProjectFlowState.importing
      : _project?.flowState ?? PhotoProjectFlowState.empty;
  List<PhotoImportFailure> get importFailures => _importFailures;
  bool get canUndo =>
      !(_project?.isReadOnly ?? true) &&
      (_project?.undoHistory.isNotEmpty ?? false);
  bool get canRedo =>
      !(_project?.isReadOnly ?? true) &&
      (_project?.redoHistory.isNotEmpty ?? false);
  bool get canEdit =>
      !(_project?.isReadOnly ?? true) &&
      _project?.flowState == PhotoProjectFlowState.editing;
  bool get canResetScopedEdit {
    final current = _project;
    if (current == null || current.flowState != PhotoProjectFlowState.editing) {
      return false;
    }
    if (current.editingScope == ProjectEditingScope.group) {
      return current.sharedStyle.recipe != EditRecipe.neutral;
    }
    final photoId = current.focusPhotoId ?? current.photos.first.id;
    return current.editState.values.keys.any(
      (address) =>
          address.scope == EditScope.currentPhoto && address.photoId == photoId,
    );
  }

  bool get canSyncCurrentPhotoAdjustmentsToGroup {
    final current = _project;
    if (current == null ||
        current.flowState != PhotoProjectFlowState.editing ||
        current.editingScope != ProjectEditingScope.currentPhoto) {
      return false;
    }
    final photoId = current.focusPhotoId ?? current.photos.first.id;
    return current.planPhotoAdjustmentsToGroup(photoId) != null;
  }

  EditRecipe get editableRecipe {
    final current = _project;
    if (current == null) return EditRecipe.neutral;
    final photoId = current.focusPhotoId ?? current.photos.first.id;
    return current.effectiveRecipeFor(photoId);
  }

  EditRecipe effectiveRecipeFor(String photoId) {
    return _requirePhoto(photoId).effectiveRecipeFor(photoId);
  }

  EditRecipe projectCreationStyle(EditRecipe style) {
    final current = _project;
    if (current == null) {
      throw StateError('A project is required before projecting a style');
    }
    if (current.creationIntent != CreationIntent.apply ||
        current.photos.length != 1) {
      throw StateError('A creation style requires one image-application photo');
    }
    final photoId = current.focusPhotoId ?? current.photos.single.id;
    final sharedRecipe = _replaceStyleOwned(current.sharedStyle.recipe, style);
    return current.effectiveRecipeFor(photoId, sharedRecipe: sharedRecipe);
  }

  EditRecipe previewRecipeFor(String photoId, EditRecipe editableRecipe) {
    final current = _requirePhoto(photoId);
    final focusedPhotoId = current.focusPhotoId ?? current.photos.first.id;
    return photoId == focusedPhotoId
        ? editableRecipe
        : current.effectiveRecipeFor(photoId);
  }

  Future<void> restore({bool enforceSinglePhoto = false}) async {
    _isRestoring = true;
    _restoreError = null;
    _notifyIfActive();
    try {
      final store = _store;
      _project = _projectId != null && store is PhotoProjectCatalogStore
          ? await store.loadProject(_projectId)
          : await store.loadLatest();
      final restored = _project;
      if (enforceSinglePhoto &&
          restored != null &&
          restored.photos.length > 1) {
        _project = null;
        throw StateError(
          'A legacy multi-photo project cannot be opened in a single-photo '
          'workspace without an explicit non-destructive migration',
        );
      }
    } on Object catch (error) {
      _restoreError = error;
    } finally {
      _isRestoring = false;
      _notifyIfActive();
    }
  }

  Future<PhotoImportResult> importPhotos({bool Function()? isCanceled}) async {
    if (_isImporting) {
      throw StateError('A photo import is already active');
    }
    if (_project?.canMutateInputs == false) {
      throw StateError('Project inputs cannot change while exporting');
    }
    final remaining = PhotoProject.maxSelectablePhotoCount - photos.length;
    if (remaining == 0) {
      return PhotoImportResult.limitReached;
    }

    _isImporting = true;
    _notifyIfActive();
    try {
      return await _performImport(remaining, isCanceled: isCanceled);
    } finally {
      _isImporting = false;
      _notifyIfActive();
    }
  }

  Future<PhotoImportResult> _performImport(
    int remaining, {
    bool Function()? isCanceled,
  }) async {
    final batch = await _importer.importPhotos(limit: remaining);
    _importFailures = List.unmodifiable(batch.failures);
    final imported = batch.photos;
    if (isCanceled?.call() == true) {
      await _discardImportedPhotos(imported);
      _importFailures = const [];
      return PhotoImportResult.canceled;
    }
    if (imported.isEmpty) {
      if (_importFailures.isNotEmpty) {
        _notifyIfActive();
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
            creationIntent: _creationIntent,
            creationTask: _creationTask,
            flowState: PhotoProjectFlowState.editing,
          )
        : existing.replacePhotosAndInvalidateDerivedState(
            photos: [...existing.photos, ...imported],
            updatedAt: timestamp,
            focusPhotoId: existing.focusPhotoId,
          );
    try {
      await _store.save(next);
    } on Object catch (error, stackTrace) {
      await _discardImportedPhotos(imported);
      Error.throwWithStackTrace(error, stackTrace);
    }
    _project = next;
    _notifyIfActive();
    return PhotoImportResult.imported;
  }

  Future<void> _discardImportedPhotos(List<ProjectPhoto> photos) async {
    final lifecycleStore = _store;
    if (lifecycleStore is! PhotoProjectLifecycleStore) return;
    for (final photo in photos) {
      try {
        await lifecycleStore.deletePhotoCopy(photo);
      } on Object {
        // Preserve the import outcome; orphan cleanup remains best-effort.
      }
    }
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

  Future<void> selectCreationStyle({
    required String styleId,
    required EditRecipe recipe,
    String? styleName,
  }) async {
    final current = _project;
    if (current == null) {
      throw StateError('A project is required before selecting a style');
    }
    if (current.flowState != PhotoProjectFlowState.editing) {
      throw StateError('A style can only be selected while editing');
    }
    if (current.creationStyleId == styleId &&
        current.creationStyleName == styleName &&
        current.creationStyleRecipe == recipe &&
        !current.creationResultActive) {
      return;
    }
    await _saveAndPublish(
      current.copyWith(
        updatedAt: _now(),
        creationStyleId: styleId,
        creationStyleName: styleName,
        creationStyleRecipe: recipe,
        creationResultActive: false,
      ),
    );
  }

  Future<void> resumeCreationStyleSelection() async {
    final current = _project;
    if (current == null) {
      throw StateError('A project is required before resuming style selection');
    }
    if (current.creationIntent != CreationIntent.apply ||
        (current.flowState != PhotoProjectFlowState.editing &&
            current.flowState != PhotoProjectFlowState.exported)) {
      throw StateError('Static style selection is unavailable in this state');
    }
    if (current.flowState == PhotoProjectFlowState.editing &&
        !current.creationResultActive) {
      return;
    }
    await _saveAndPublish(
      current.copyWith(
        updatedAt: _now(),
        flowState: PhotoProjectFlowState.editing,
        creationResultActive: false,
      ),
    );
  }

  Future<void> restorePreviousCreationResult() async {
    final current = _project;
    if (current == null || current.flowState != PhotoProjectFlowState.editing) {
      throw StateError('An editing project is required to restore a result');
    }
    final result = current.recoverableStaticStyleResult;
    if (result == null) {
      throw StateError('No recoverable static result is available');
    }
    final wasSaved =
        current.exportStates[result.sourcePhotoId] == PhotoExportState.saved &&
        current.lastSuccessfulExportEditStateVersion ==
            current.editStateVersion;
    await _saveAndPublish(
      current.copyWith(
        updatedAt: _now(),
        creationStyleId: result.styleId,
        creationStyleName: result.styleName,
        creationStyleRecipe: result.recipe,
        creationResultActive: true,
        flowState: wasSaved
            ? PhotoProjectFlowState.exported
            : PhotoProjectFlowState.editing,
      ),
    );
  }

  PhotoProject _withStaticStyleResult(
    PhotoProject project, {
    required String styleId,
    required String? styleName,
    required EditRecipe recipe,
  }) {
    if (project.creationIntent != CreationIntent.apply ||
        project.photos.length != 1 ||
        project.flowState != PhotoProjectFlowState.editing) {
      throw StateError('A static style result requires one editing photo');
    }
    final photoId = project.focusPhotoId ?? project.photos.single.id;
    if (project.effectiveRecipeFor(photoId) != recipe) {
      throw StateError('A static style result must match the rendered recipe');
    }
    final resultWasAlreadySaved =
        project.exportStates[photoId] == PhotoExportState.saved &&
        project.lastSuccessfulExportEditStateVersion ==
            project.editStateVersion;
    return project.copyWith(
      updatedAt: _now(),
      flowState: resultWasAlreadySaved
          ? PhotoProjectFlowState.exported
          : PhotoProjectFlowState.editing,
      creationStyleId: styleId,
      creationStyleName: styleName,
      creationStyleRecipe: recipe,
      creationResultActive: true,
      creationResult: StaticStyleResultIdentity(
        sourcePhotoId: photoId,
        editStateVersion: project.editStateVersion,
        styleId: styleId,
        styleName: styleName,
        recipe: recipe,
      ),
    );
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

  /// Test-only bridge for legacy project fixtures. Production editing paths
  /// must submit admitted MetaOp transactions through [commitMetaOps].
  @visibleForTesting
  Future<void> commitLegacyRecipeForTesting(EditRecipe recipe) async {
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
        : _editablePhotoRecipe(current, photoId);
    if (beforeRecipe == recipe) return;
    final operation = ProjectEditOperation(
      scope: current.editingScope,
      photoId: photoId,
      beforeRecipe: beforeRecipe,
      afterRecipe: recipe,
      beforeSharedIntensity: current.sharedStyle.intensity,
      afterSharedIntensity: current.sharedStyle.intensity,
    );
    final rawNext = _applyOperation(
      current,
      operation,
      recipe,
      sharedIntensity: operation.afterSharedIntensity,
      undoHistory: current.undoHistory,
      redoHistory: const [],
    );
    final next = _finalizeNewOperation(current, rawNext, operation);
    await _saveAndPublish(next);
  }

  Future<EditResult> commitMetaOp({
    required OpAddress address,
    required Object value,
    required EditContext context,
  }) => commitMetaOps(
    changes: [MetaOpChange(address: address, value: value)],
    source: EditSource.manual,
    context: context,
  );

  PreparedMetaOpPreview? prepareMetaOpsForPreview({
    required List<MetaOpChange> changes,
    required EditSource source,
    required EditContext context,
  }) {
    final current = _project;
    if (current == null || changes.isEmpty) return null;
    final firstAddress = changes.first.address;
    if (changes.any(
      (change) =>
          change.address.scope != firstAddress.scope ||
          change.address.photoId != firstAddress.photoId,
    )) {
      return null;
    }
    final focusPhotoId = current.focusPhotoId ?? current.photos.first.id;
    final resolvedPhotoId = firstAddress.scope == EditScope.currentPhoto
        ? firstAddress.photoId ?? focusPhotoId
        : null;
    final sourceRecipe = resolvedPhotoId == null
        ? current.sharedStyle.recipe
        : _editablePhotoRecipe(current, resolvedPhotoId);
    final targetRegistry = resolvedPhotoId == null
        ? null
        : current.targetRegistries[resolvedPhotoId];
    final activeTargetIds = targetRegistry?.targets.values
        .where((target) => target.status == EditTargetStatus.active)
        .map((target) => target.id)
        .toSet();
    final effectiveContext = EditContext(
      platform: context.platform,
      photoIds: context.photoIds,
      targetIds: activeTargetIds == null
          ? context.targetIds
          : context.targetIds.intersection(activeTargetIds),
      capabilities: context.capabilities,
      applicability: context.applicability,
      resourceIds: {
        ...context.resourceIds,
        ...current.editingResources.resources.keys,
      },
      resourceByteLengths: {
        ...context.resourceByteLengths,
        for (final resource in current.editingResources.resources.values)
          resource.id: resource.byteLength,
      },
      metaOpCapabilities: context.metaOpCapabilities,
    );
    final result = _editingCore.apply(
      state: current.editState,
      transaction: EditTransaction(
        id: 'preview-${current.id}-${current.editState.version + 1}',
        baseVersion: current.editState.version,
        source: source,
        changes: changes,
      ),
      context: effectiveContext,
    );
    if (result is! AcceptedEdit) return null;
    var recipe = sourceRecipe;
    for (final change in changes) {
      recipe = _legacyAdapter.writeKnownValue(
        recipe: recipe,
        address: change.address,
        state: result.state,
        targetRegistry: targetRegistry,
      );
    }
    final projectedProject = resolvedPhotoId == null
        ? current.copyWith(
            sharedStyle: SharedStyle(
              recipe: recipe,
              family: current.sharedStyle.family,
              intensity: current.sharedStyle.intensity,
            ),
            editState: result.state,
          )
        : current.copyWith(
            photoOverrides: {
              ...current.photoOverrides,
              resolvedPhotoId: PhotoOverride(
                recipe: recipe,
                overridesBasicLook:
                    current.photoOverrides[resolvedPhotoId]?.overridesBasicLook,
                overridesCrop:
                    current.photoOverrides[resolvedPhotoId]?.overridesCrop,
              ),
            },
            editState: result.state,
          );
    return PreparedMetaOpPreview(
      recipe: projectedProject.effectiveRecipeFor(focusPhotoId),
      scopedRecipe: recipe,
      state: result.state,
      context: effectiveContext,
      sourceId: focusPhotoId,
    );
  }

  Future<ManualEditCommit> commitManualRecipe({
    required EditRecipe desiredRecipe,
    required EditContext context,
    EditingResourceImporter? resourceImporter,
  }) => _commitManualRecipe(
    desiredRecipe: desiredRecipe,
    context: context,
    resourceImporter: resourceImporter,
  );

  Future<ManualEditCommit> applyCreationStyle({
    required String styleId,
    required EditRecipe recipe,
    required EditContext context,
    String? styleName,
  }) async {
    final current = _project;
    if (current == null) {
      throw StateError('A project is required before applying a style');
    }
    if (current.creationIntent != CreationIntent.apply) {
      throw StateError('Only an image-application project can apply a style');
    }
    if (current.photos.length != 1 ||
        current.flowState != PhotoProjectFlowState.editing) {
      throw StateError('A creation style requires one editing photo');
    }
    final photoId = current.focusPhotoId ?? current.photos.single.id;
    final beforeShared = current.sharedStyle.recipe;
    final afterShared = _replaceStyleOwned(beforeShared, recipe);
    final transition = _legacyAdapter.tryEncodeTransition(
      before: beforeShared,
      after: afterShared,
      photoId: photoId,
    );
    if (transition == null ||
        transition.changes.any(
          (change) => change.address.scope != EditScope.group,
        )) {
      throw StateError('Style projection has no admitted group transition');
    }
    if (transition.changes.isEmpty) {
      await _saveAndPublish(
        _withStaticStyleResult(
          current,
          styleId: styleId,
          styleName: styleName,
          recipe: current.effectiveRecipeFor(photoId),
        ),
      );
      return const ManualEditCommit(
        result: RejectedEdit(reason: EditRejection.emptyTransaction),
        appliedToGroup: false,
      );
    }
    final result = await commitMetaOps(
      changes: transition.changes,
      source: EditSource.manual,
      context: context,
      creationResultStyleId: styleId,
      creationResultStyleName: styleName,
    );
    if (result is RejectedEdit) {
      throw StateError('Style meta op rejected: ${result.reason.name}');
    }
    return ManualEditCommit(result: result, appliedToGroup: true);
  }

  EditRecipe _replaceStyleOwned(EditRecipe base, EditRecipe style) {
    final baseBasic = base.basicEditingRecipe;
    final styleBasic = style.basicEditingRecipe;
    return base.copyWith(
      exposure: style.exposure,
      highlights: style.highlights,
      shadows: style.shadows,
      contrast: style.contrast,
      warmth: style.warmth,
      tint: style.tint,
      saturation: style.saturation,
      clarity: style.clarity,
      basicEditingRecipe: baseBasic.copyWith(
        filter: styleBasic.filter,
        filterStrength: styleBasic.filterStrength,
        hsl: styleBasic.hsl,
      ),
    );
  }

  Future<ManualEditCommit> _commitManualRecipe({
    required EditRecipe desiredRecipe,
    required EditContext context,
    EditingResourceImporter? resourceImporter,
    String? creationResultStyleId,
    String? creationResultStyleName,
  }) async {
    final current = _project;
    if (current == null) {
      throw StateError('A project is required before committing an edit');
    }
    final photoId = current.focusPhotoId ?? current.photos.first.id;
    final beforeRecipe = editableRecipe;
    final beforeSemantic = beforeRecipe.semanticEditingRecipe;
    var afterSemantic = desiredRecipe.semanticEditingRecipe;
    final pendingResources = <ImportedEditingResource>[];

    Future<String?> storeMaskResource({
      required EditingResourceKind kind,
      required List<Object> payload,
    }) async {
      if (payload.isEmpty) return null;
      if (resourceImporter == null) {
        throw StateError('Editing resource storage is unavailable');
      }
      final imported = await resourceImporter.storeEditingResource(
        kind: kind,
        bytes: utf8.encode(
          jsonEncode({
            'schemaVersion': 1,
            'kind': kind.name,
            'strokes': payload,
          }),
        ),
        payload: payload,
      );
      pendingResources.add(imported);
      return imported.descriptor.id;
    }

    try {
      if (!listEquals(
        beforeSemantic.subjectMaskStrokes,
        afterSemantic.subjectMaskStrokes,
      )) {
        afterSemantic = afterSemantic.copyWith(
          subjectMaskResourceId: await storeMaskResource(
            kind: EditingResourceKind.subjectMask,
            payload: afterSemantic.subjectMaskStrokes
                .map<Object>((stroke) => stroke.toJson())
                .toList(growable: false),
          ),
        );
      }
      if (!listEquals(
        beforeSemantic.localAdjustmentStrokes,
        afterSemantic.localAdjustmentStrokes,
      )) {
        afterSemantic = afterSemantic.copyWith(
          localMaskResourceId: await storeMaskResource(
            kind: EditingResourceKind.localMask,
            payload: afterSemantic.localAdjustmentStrokes
                .map<Object>((stroke) => stroke.toJson())
                .toList(growable: false),
          ),
        );
      }
      if (!listEquals(
        beforeSemantic.eraseStrokes,
        afterSemantic.eraseStrokes,
      )) {
        afterSemantic = afterSemantic.copyWith(
          eraseMaskResourceId: await storeMaskResource(
            kind: EditingResourceKind.eraseMask,
            payload: afterSemantic.eraseStrokes
                .map<Object>((stroke) => stroke.toJson())
                .toList(growable: false),
          ),
        );
      }
      desiredRecipe = desiredRecipe.copyWith(
        semanticEditingRecipe: afterSemantic,
      );
      final transition = _legacyAdapter.tryEncodeTransition(
        before: beforeRecipe,
        after: desiredRecipe,
        photoId: photoId,
        targetRegistry: current.targetRegistries[photoId],
      );
      final imageResourceChanged =
          afterSemantic.background == BackgroundTreatment.image &&
          afterSemantic.backgroundImageResourceId != null &&
          (beforeSemantic.background != afterSemantic.background ||
              beforeSemantic.backgroundImageResourceId !=
                  afterSemantic.backgroundImageResourceId);
      final changes = imageResourceChanged
          ? [
              MetaOpChange(
                address: OpAddress(
                  metaOpId: MetaOpIds.semanticAdjustments,
                  metaOpVersion: 1,
                  parameterId: 'background',
                  scope: EditScope.currentPhoto,
                  photoId: photoId,
                ),
                value: BackgroundTreatment.image.name,
              ),
              MetaOpChange(
                address: OpAddress(
                  metaOpId: MetaOpIds.semanticAdjustments,
                  metaOpVersion: 1,
                  parameterId: 'backgroundImageResource',
                  scope: EditScope.currentPhoto,
                  photoId: photoId,
                ),
                value: afterSemantic.backgroundImageResourceId!,
              ),
            ]
          : transition?.changes;
      if (changes == null || changes.isEmpty) {
        if (desiredRecipe != beforeRecipe) {
          throw StateError('Manual edit has no admitted MetaOp transition');
        }
        if (creationResultStyleId != null) {
          await _saveAndPublish(
            _withStaticStyleResult(
              current,
              styleId: creationResultStyleId,
              styleName: creationResultStyleName,
              recipe: desiredRecipe,
            ),
          );
        }
        return const ManualEditCommit(
          result: RejectedEdit(reason: EditRejection.emptyTransaction),
          appliedToGroup: false,
        );
      }
      if (afterSemantic.background == BackgroundTreatment.image &&
          afterSemantic.backgroundImageResourceId != null &&
          afterSemantic.backgroundImagePath != null) {
        final resourceId = afterSemantic.backgroundImageResourceId!;
        final sha = resourceId.substring('resource-v1-'.length);
        final path = afterSemantic.backgroundImagePath!;
        final marker =
            '${Platform.pathSeparator}resources${Platform.pathSeparator}';
        final markerIndex = path.lastIndexOf(marker);
        final relativePath = markerIndex >= 0
            ? path.substring(markerIndex + 1)
            : 'resources/${sha.substring(0, 2)}/$sha${_resourceExtension(path)}';
        pendingResources.add(
          ImportedEditingResource(
            descriptor: EditingResourceDescriptor(
              id: resourceId,
              kind: EditingResourceKind.backgroundImage,
              relativePath: relativePath.replaceAll(
                Platform.pathSeparator,
                '/',
              ),
              contentSha256: sha,
              byteLength: File(path).lengthSync(),
            ),
            localPath: path,
          ),
        );
      }
      final result = await commitMetaOps(
        changes: changes,
        source: EditSource.manual,
        context: context,
        editingResources: pendingResources,
        creationResultStyleId: creationResultStyleId,
        creationResultStyleName: creationResultStyleName,
      );
      if (result is RejectedEdit) {
        throw StateError('Meta op rejected: ${result.reason.name}');
      }
      return ManualEditCommit(
        result: result,
        appliedToGroup: changes.any(
          (change) => change.address.scope == EditScope.group,
        ),
      );
    } on Object {
      final registeredIds =
          _project?.editingResources.resources.keys.toSet() ?? const <String>{};
      if (resourceImporter != null) {
        for (final resource in pendingResources) {
          if (!registeredIds.contains(resource.descriptor.id)) {
            try {
              await resourceImporter.discardEditingResource(resource);
            } on Object {
              // Cleanup is best effort; the project remains at its safe state.
            }
          }
        }
      }
      rethrow;
    }
  }

  static String _resourceExtension(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return '.jpg';
    final extension = name.substring(dot).toLowerCase();
    return const {'.jpg', '.jpeg', '.png', '.heic'}.contains(extension)
        ? extension
        : '.jpg';
  }

  Future<EditResult> commitAiProposal(
    AiEditProposal proposal, {
    required EditContext context,
    Iterable<ImportedEditingResource> editingResources = const [],
  }) {
    final current = _project;
    if (current == null) {
      throw StateError('A project is required before committing an AI edit');
    }
    if (current.recentTransactionIds.contains(proposal.idempotencyKey)) {
      return Future.value(
        const RejectedEdit(reason: EditRejection.duplicateTransaction),
      );
    }
    if (proposal.baseStateVersion != current.editStateVersion) {
      return Future.value(
        const RejectedEdit(reason: EditRejection.staleVersion),
      );
    }
    return commitMetaOps(
      changes: proposal.changes,
      source: EditSource.ai,
      context: context,
      editingResources: editingResources,
      transactionId: proposal.idempotencyKey,
    );
  }

  Future<EditResult> commitMetaOps({
    required List<MetaOpChange> changes,
    required EditSource source,
    required EditContext context,
    Iterable<ImportedEditingResource> editingResources = const [],
    String? transactionId,
    ProjectEditOperationKind operationKind =
        ProjectEditOperationKind.scopedEdit,
    EditRecipe? beforePhotoOverrideRecipe,
    double? afterSharedIntensity,
    String? creationResultStyleId,
    String? creationResultStyleName,
  }) async {
    final current = _project;
    if (current == null) {
      throw StateError('A project is required before committing an edit');
    }
    if (current.flowState != PhotoProjectFlowState.editing) {
      throw StateError('Edits can only be committed while editing');
    }
    if (changes.isEmpty) {
      return const RejectedEdit(reason: EditRejection.emptyTransaction);
    }
    final resolvedTransactionId =
        transactionId ??
        'project-${current.id}-${source.name}-${current.editState.version + 1}-${_createId()}';
    if (current.recentTransactionIds.contains(resolvedTransactionId)) {
      return const RejectedEdit(reason: EditRejection.duplicateTransaction);
    }
    final firstAddress = changes.first.address;
    final hasMixedDestinations = changes.any(
      (change) =>
          change.address.scope != firstAddress.scope ||
          change.address.photoId != firstAddress.photoId,
    );
    if (hasMixedDestinations) {
      return RejectedEdit(
        reason: EditRejection.invalidScope,
        address: firstAddress,
      );
    }
    final resolvedPhotoId = firstAddress.scope == EditScope.currentPhoto
        ? firstAddress.photoId ??
              current.focusPhotoId ??
              current.photos.first.id
        : null;
    final sourceRecipe = resolvedPhotoId == null
        ? current.sharedStyle.recipe
        : _editablePhotoRecipe(current, resolvedPhotoId);
    final targetRegistry = resolvedPhotoId == null
        ? null
        : current.targetRegistries[resolvedPhotoId];
    final activeTargetIds = targetRegistry?.targets.values
        .where((target) => target.status == EditTargetStatus.active)
        .map((target) => target.id)
        .toSet();
    final state = current.editState;
    final importedResources = editingResources.toList(growable: false);
    final registeredResourceIds = {
      ...current.editingResources.resources.keys,
      ...importedResources.map((resource) => resource.descriptor.id),
    };
    final resourceByteLengths = <String, int>{
      ...context.resourceByteLengths,
      for (final resource in current.editingResources.resources.values)
        resource.id: resource.byteLength,
      for (final resource in importedResources)
        resource.descriptor.id: resource.descriptor.byteLength,
    };
    final result = _editingCore.apply(
      state: state,
      transaction: EditTransaction(
        id: resolvedTransactionId,
        baseVersion: state.version,
        source: source,
        changes: changes,
      ),
      context: EditContext(
        platform: context.platform,
        photoIds: context.photoIds,
        targetIds: activeTargetIds == null
            ? context.targetIds
            : context.targetIds.intersection(activeTargetIds),
        capabilities: context.capabilities,
        applicability: context.applicability,
        resourceIds: {...context.resourceIds, ...registeredResourceIds},
        resourceByteLengths: resourceByteLengths,
        metaOpCapabilities: context.metaOpCapabilities,
      ),
    );
    if (result is! AcceptedEdit) return result;
    var recipe = sourceRecipe;
    final resourcePaths = <String, String>{
      if (sourceRecipe.semanticEditingRecipe case final semantic
          when semantic.backgroundImageResourceId != null &&
              semantic.backgroundImagePath != null)
        semantic.backgroundImageResourceId!: semantic.backgroundImagePath!,
      for (final resource in importedResources)
        resource.descriptor.id: resource.localPath,
    };
    final resourcePayloads = <String, Object>{
      for (final resource in importedResources)
        if (resource.payload != null) resource.descriptor.id: resource.payload!,
    };
    for (final change in changes) {
      recipe = _legacyAdapter.writeKnownValue(
        recipe: recipe,
        address: change.address,
        state: result.state,
        targetRegistry: targetRegistry,
        resourcePaths: resourcePaths,
        resourcePayloads: resourcePayloads,
      );
    }
    if (recipe == sourceRecipe) return result;

    final scope = firstAddress.scope == EditScope.group
        ? ProjectEditingScope.group
        : ProjectEditingScope.currentPhoto;
    final photoId = scope == ProjectEditingScope.currentPhoto
        ? resolvedPhotoId
        : null;
    final operation = ProjectEditOperation(
      kind: operationKind,
      source: source,
      scope: scope,
      photoId: photoId,
      beforeRecipe: sourceRecipe,
      afterRecipe: recipe,
      beforeSharedIntensity: current.sharedStyle.intensity,
      afterSharedIntensity:
          afterSharedIntensity ?? current.sharedStyle.intensity,
      beforePhotoOverrideRecipe: beforePhotoOverrideRecipe,
      changedAddresses: result.summary.changedAddresses,
    );
    var next = _applyOperation(
      current,
      operation,
      recipe,
      sharedIntensity: operation.afterSharedIntensity,
      undoHistory: current.undoHistory,
      redoHistory: const [],
    );
    var registry = current.editingResources;
    for (final resource in importedResources) {
      registry = registry.register(resource.descriptor);
    }
    next = next.copyWith(
      editingResources: registry,
      editState: result.state,
      recentTransactionIds: [
        ...current.recentTransactionIds,
        resolvedTransactionId,
      ],
    );
    next = _finalizeNewOperation(current, next, operation);
    if (creationResultStyleId != null) {
      final resultPhotoId = next.focusPhotoId ?? next.photos.first.id;
      next = _withStaticStyleResult(
        next,
        styleId: creationResultStyleId,
        styleName: creationResultStyleName,
        recipe: next.effectiveRecipeFor(resultPhotoId),
      );
    }
    await _saveAndPublish(next);
    return result;
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
    final rawNext = _applyOperation(
      current,
      operation,
      operation.afterRecipe,
      sharedIntensity: operation.afterSharedIntensity,
      undoHistory: current.undoHistory,
      redoHistory: const [],
    );
    final next = _finalizeNewOperation(current, rawNext, operation);
    await _saveAndPublish(next);
  }

  Future<void> resetScopedEdit({EditContext context = EditContext.ios}) async {
    final current = _project;
    if (current == null) {
      throw StateError('A project is required before resetting an edit');
    }
    if (current.flowState != PhotoProjectFlowState.editing) {
      throw StateError('Edits can only be reset while editing');
    }
    if (current.editingScope == ProjectEditingScope.group) {
      if (!canResetScopedEdit) return;
      final transition = _legacyAdapter.tryEncodeTransition(
        before: current.sharedStyle.recipe,
        after: EditRecipe.neutral,
        photoId: current.photos.first.id,
      );
      if (transition == null || transition.changes.isEmpty) return;
      final result = await commitMetaOps(
        changes: transition.changes,
        source: EditSource.manual,
        context: context,
        afterSharedIntensity: 1,
      );
      if (result is RejectedEdit) {
        throw StateError('Reset rejected: ${result.reason.name}');
      }
      return;
    }
    final photoId = current.focusPhotoId ?? current.photos.first.id;
    final override = current.photoOverrides[photoId]?.recipe;
    if (override == null) return;
    final baseline = _photoOverrideBaseline(current, photoId);
    final transition = _legacyAdapter.tryEncodeTransition(
      before: override,
      after: baseline,
      photoId: photoId,
      targetRegistry: current.targetRegistries[photoId],
    );
    if (transition == null) {
      throw StateError('Reset has no admitted MetaOp transition');
    }
    final localChanges = transition.changes
        .where((change) => change.address.scope == EditScope.currentPhoto)
        .toList(growable: false);
    if (localChanges.isEmpty) return;
    final result = await commitMetaOps(
      changes: localChanges,
      source: EditSource.manual,
      context: context,
      operationKind: ProjectEditOperationKind.resetCurrentPhotoOverride,
      beforePhotoOverrideRecipe: override,
    );
    if (result is RejectedEdit) {
      throw StateError('Reset rejected: ${result.reason.name}');
    }
  }

  Future<void> syncCurrentPhotoAdjustmentsToGroup() async {
    final current = _project;
    if (current == null) {
      throw StateError('A project is required before syncing an edit');
    }
    if (current.flowState != PhotoProjectFlowState.editing ||
        current.editingScope != ProjectEditingScope.currentPhoto) {
      throw StateError('Only current-photo adjustments can sync to the group');
    }
    final photoId = current.focusPhotoId ?? current.photos.first.id;
    final plan = current.planPhotoAdjustmentsToGroup(photoId);
    if (plan == null) return;
    final override = current.photoOverrides[photoId]!.recipe;
    final operation = ProjectEditOperation(
      kind: ProjectEditOperationKind.syncCurrentPhotoToGroup,
      scope: ProjectEditingScope.group,
      photoId: photoId,
      beforeRecipe: current.sharedStyle.recipe,
      afterRecipe: plan.sharedStyle.recipe,
      beforeSharedIntensity: current.sharedStyle.intensity,
      afterSharedIntensity: plan.sharedStyle.intensity,
      beforePhotoOverrideRecipe: override,
      afterPhotoOverrideRecipe: plan.remainingPhotoOverride,
    );
    final rawNext = _applyOperation(
      current,
      operation,
      plan.sharedStyle.recipe,
      sharedIntensity: plan.sharedStyle.intensity,
      syncedPhotoOverride: plan.remainingPhotoOverride,
      undoHistory: current.undoHistory,
      redoHistory: const [],
    );
    final next = _finalizeNewOperation(current, rawNext, operation);
    await _saveAndPublish(next);
  }

  Future<void> undoEdit() async {
    final current = _project;
    if (current == null || current.undoHistory.isEmpty) return;
    if (current.flowState != PhotoProjectFlowState.editing) {
      throw StateError('Edit history can only change while editing');
    }
    final operation = current.undoHistory.last;
    var next = _applyOperation(
      current,
      operation,
      operation.beforeRecipe,
      sharedIntensity: operation.beforeSharedIntensity,
      syncedPhotoOverride: operation.beforePhotoOverrideRecipe,
      targetRegistry: operation.beforeTargetRegistry,
      undoHistory: current.undoHistory.sublist(
        0,
        current.undoHistory.length - 1,
      ),
      redoHistory: [...current.redoHistory, operation],
    );
    next = next.copyWith(
      editState: operation.beforeSnapshot!.editState,
      adaptiveCompensations: operation.beforeSnapshot!.adaptiveCompensations,
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
    var next = _applyOperation(
      current,
      operation,
      operation.afterRecipe,
      sharedIntensity: operation.afterSharedIntensity,
      syncedPhotoOverride: operation.afterPhotoOverrideRecipe,
      targetRegistry: operation.afterTargetRegistry,
      undoHistory: [...current.undoHistory, operation],
      redoHistory: current.redoHistory.sublist(
        0,
        current.redoHistory.length - 1,
      ),
    );
    next = next.copyWith(
      editState: operation.afterSnapshot!.editState,
      adaptiveCompensations: operation.afterSnapshot!.adaptiveCompensations,
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

  Future<void> setGroupScrollOffset(double offset) async {
    final current = _project;
    if (current == null) {
      throw StateError('A project is required before saving group position');
    }
    if (!offset.isFinite || offset < 0) {
      throw ArgumentError.value(
        offset,
        'offset',
        'Group scroll offset must be finite and non-negative',
      );
    }
    if ((current.groupScrollOffset - offset).abs() < 0.5) return;
    final next = current.copyWith(updatedAt: _now(), groupScrollOffset: offset);
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

  Future<void> reconcileEditTargets(
    String photoId,
    Iterable<DetectedEditTarget> detections,
  ) async {
    final current = _requirePhoto(photoId);
    final incoming = detections.toList(growable: false);
    if (incoming.any((detection) => detection.photoId != photoId)) {
      throw ArgumentError.value(
        incoming,
        'detections',
        'Every detection must belong to the selected photo',
      );
    }
    final previous = current.targetRegistries[photoId];
    final nextRegistry = previous == null
        ? EditTargetRegistry.seed(incoming)
        : previous.reconcile(incoming);
    if (nextRegistry == previous ||
        (previous == null && nextRegistry.targets.isEmpty)) {
      return;
    }
    await _saveAndPublish(
      current.copyWith(
        updatedAt: _now(),
        targetRegistries: {...current.targetRegistries, photoId: nextRegistry},
      ),
    );
  }

  Future<void> rebindEditTarget({
    required String photoId,
    required String targetId,
    required DetectedEditTarget detection,
  }) async {
    final current = _requirePhoto(photoId);
    if (current.flowState != PhotoProjectFlowState.editing) {
      throw StateError('Targets can only be rebound while editing');
    }
    final before = current.targetRegistries[photoId];
    if (before == null) {
      throw StateError('A target registry is required before rebinding');
    }
    final rebound = before.rebind(targetId, detection);
    final after = rebound.withoutRebindRecord();
    if (after == before) return;
    final operation = ProjectEditOperation(
      kind: ProjectEditOperationKind.targetRebind,
      source: EditSource.targetRebind,
      scope: ProjectEditingScope.currentPhoto,
      photoId: photoId,
      beforeRecipe: EditRecipe.neutral,
      afterRecipe: EditRecipe.neutral,
      beforeSharedIntensity: current.sharedStyle.intensity,
      afterSharedIntensity: current.sharedStyle.intensity,
      beforeTargetRegistry: before,
      afterTargetRegistry: after,
    );
    final rawNext = _applyOperation(
      current,
      operation,
      operation.afterRecipe,
      sharedIntensity: operation.afterSharedIntensity,
      targetRegistry: after,
      undoHistory: current.undoHistory,
      redoHistory: const [],
    );
    final next = _finalizeNewOperation(current, rawNext, operation);
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
    final next = current.copyWith(
      updatedAt: _now(),
      exportStates: states,
      lastSuccessfulExportEditStateVersion: state == PhotoExportState.saved
          ? current.editStateVersion
          : current.lastSuccessfulExportEditStateVersion,
    );
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
      _notifyIfActive();
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
    _notifyIfActive();
  }

  PhotoProject _applyOperation(
    PhotoProject current,
    ProjectEditOperation operation,
    EditRecipe recipe, {
    required double sharedIntensity,
    EditRecipe? syncedPhotoOverride,
    EditTargetRegistry? targetRegistry,
    required List<ProjectEditOperation> undoHistory,
    required List<ProjectEditOperation> redoHistory,
  }) {
    final exportStates = Map.of(current.exportStates);
    if (operation.kind == ProjectEditOperationKind.targetRebind) {
      final photoId = operation.photoId!;
      final registries = Map.of(current.targetRegistries);
      if (targetRegistry == null) {
        registries.remove(photoId);
      } else {
        registries[photoId] = targetRegistry;
      }
      exportStates[photoId] = PhotoExportState.notQueued;
      return current.copyWith(
        updatedAt: _now(),
        editingScope: ProjectEditingScope.currentPhoto,
        focusPhotoId: photoId,
        targetRegistries: registries,
        exportStates: exportStates,
        undoHistory: undoHistory,
        redoHistory: redoHistory,
      );
    }
    if (operation.kind == ProjectEditOperationKind.syncCurrentPhotoToGroup) {
      final photoId = operation.photoId!;
      final overrides = Map.of(current.photoOverrides);
      final nextSharedStyle = SharedStyle(
        recipe: recipe,
        family: current.sharedStyle.family,
        intensity: sharedIntensity,
      );
      final projectWithNextSharedStyle = current.copyWith(
        sharedStyle: nextSharedStyle,
      );
      if (syncedPhotoOverride == null ||
          _canRemovePhotoOverride(
            projectWithNextSharedStyle,
            photoId,
            syncedPhotoOverride,
          )) {
        overrides.remove(photoId);
      } else {
        overrides[photoId] = _photoOverrideFor(
          projectWithNextSharedStyle,
          photoId,
          syncedPhotoOverride,
        );
      }
      for (final photo in current.photos) {
        exportStates[photo.id] = PhotoExportState.notQueued;
      }
      return current.copyWith(
        updatedAt: _now(),
        editingScope: ProjectEditingScope.currentPhoto,
        focusPhotoId: photoId,
        sharedStyle: nextSharedStyle,
        photoOverrides: overrides,
        exportStates: exportStates,
        undoHistory: undoHistory,
        redoHistory: redoHistory,
      );
    }
    if (operation.kind == ProjectEditOperationKind.resetCurrentPhotoOverride) {
      final photoId = operation.photoId!;
      final overrides = Map.of(current.photoOverrides);
      if (syncedPhotoOverride == null) {
        overrides.remove(photoId);
      } else {
        overrides[photoId] = _photoOverrideFor(
          current,
          photoId,
          syncedPhotoOverride,
        );
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
    if (operation.scope == ProjectEditingScope.group) {
      for (final photo in current.photos) {
        exportStates[photo.id] = PhotoExportState.notQueued;
      }
      return current.copyWith(
        updatedAt: _now(),
        editingScope: current.editingScope,
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
    if (_canRemovePhotoOverride(current, photoId, recipe)) {
      overrides.remove(photoId);
    } else {
      overrides[photoId] = _photoOverrideFor(current, photoId, recipe);
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
    if ((_project?.requiresUpdate ?? false) || next.requiresUpdate) {
      throw StateError(
        'A project with unknown meta operations is read-only until update',
      );
    }
    final synchronized = _synchronizeEditingResources(next);
    await _store.save(synchronized);
    _project = synchronized;
    _notifyIfActive();
  }

  PhotoProject _synchronizeEditingResources(PhotoProject project) {
    Iterable<String> recipeResources(EditRecipe recipe) sync* {
      final semantic = recipe.semanticEditingRecipe;
      for (final id in [
        semantic.backgroundImageResourceId,
        semantic.subjectMaskResourceId,
        semantic.localMaskResourceId,
        semantic.eraseMaskResourceId,
      ]) {
        if (id != null) yield id;
      }
    }

    Iterable<String> operationResources(ProjectEditOperation operation) sync* {
      yield* recipeResources(operation.beforeRecipe);
      yield* recipeResources(operation.afterRecipe);
      if (operation.beforePhotoOverrideRecipe case final recipe?) {
        yield* recipeResources(recipe);
      }
      if (operation.afterPhotoOverrideRecipe case final recipe?) {
        yield* recipeResources(recipe);
      }
    }

    Iterable<String> snapshotResources(ProjectEditSnapshot snapshot) sync* {
      yield* recipeResources(snapshot.sharedStyle.recipe);
      for (final layer in snapshot.photoOverrides.values) {
        yield* recipeResources(layer.recipe);
      }
    }

    var registry = project.editingResources
        .replaceReferences(EditingResourceOwner.currentState, [
          ...recipeResources(project.sharedStyle.recipe),
          for (final layer in project.adaptiveCompensations.values)
            ...recipeResources(layer.recipe),
          for (final layer in project.photoOverrides.values)
            ...recipeResources(layer.recipe),
        ])
        .replaceReferences(
          EditingResourceOwner.undoHistory,
          project.undoHistory.expand(operationResources),
        )
        .replaceReferences(
          EditingResourceOwner.redoHistory,
          project.redoHistory.expand(operationResources),
        )
        .replaceReferences(EditingResourceOwner.checkpoint, [
          if (project.historyBaseSnapshot case final snapshot?)
            ...snapshotResources(snapshot),
          for (final checkpoint in project.editCheckpoints)
            ...snapshotResources(checkpoint.snapshot),
        ]);
    registry = registry.removeReclaimable();
    return registry == project.editingResources
        ? project
        : project.copyWith(editingResources: registry);
  }

  PhotoProject _finalizeNewOperation(
    PhotoProject current,
    PhotoProject next,
    ProjectEditOperation operation,
  ) {
    if (next.editState == current.editState) {
      final derived = PhotoProject.deriveEditState(
        sharedStyle: next.sharedStyle,
        photoOverrides: next.photoOverrides,
        targetRegistries: next.targetRegistries,
      );
      next = next.copyWith(
        editState: EditState(
          version: current.editState.version + 1,
          values: derived.values,
        ),
      );
    }
    final before = ProjectEditSnapshot.fromProject(current);
    final after = ProjectEditSnapshot.fromProject(next);
    final enriched = operation.withSnapshots(before: before, after: after);
    var folded = current.foldedEditCount;
    var base = current.historyBaseSnapshot;
    var history = current.undoHistory;
    var checkpoints = current.editCheckpoints
        .where(
          (checkpoint) =>
              checkpoint.editCount <= folded + current.undoHistory.length,
        )
        .toList();
    if (base == null) {
      folded += history.length;
      history = const [];
      checkpoints = const [];
      base = before;
    }
    history = [...history, enriched];
    while (history.length > PhotoProject.maxEditHistoryCount) {
      base = history.first.afterSnapshot!;
      history = history.sublist(1);
      folded += 1;
    }
    checkpoints = checkpoints
        .where((checkpoint) => checkpoint.editCount > folded)
        .toList();
    final editCount = folded + history.length;
    if (editCount % PhotoProject.checkpointInterval == 0) {
      checkpoints = [
        ...checkpoints.where((checkpoint) => checkpoint.editCount != editCount),
        ProjectEditCheckpoint(editCount: editCount, snapshot: after),
      ]..sort((left, right) => left.editCount.compareTo(right.editCount));
    }
    return next.copyWith(
      undoHistory: history,
      redoHistory: const [],
      foldedEditCount: folded,
      historyBaseSnapshot: base,
      editCheckpoints: checkpoints,
    );
  }

  EditRecipe _editablePhotoRecipe(PhotoProject project, String photoId) {
    final stored = project.photoOverrides[photoId]?.recipe;
    if (stored != null) return stored;
    return _photoOverrideBaseline(project, photoId);
  }

  EditRecipe _photoOverrideBaseline(PhotoProject project, String photoId) {
    return project.photoOverrideBaselineFor(photoId);
  }

  bool _canRemovePhotoOverride(
    PhotoProject project,
    String photoId,
    EditRecipe recipe,
  ) => recipe == project.photoOverrideBaselineFor(photoId);

  PhotoOverride _photoOverrideFor(
    PhotoProject project,
    String photoId,
    EditRecipe recipe,
  ) {
    final baseline = project.photoOverrideBaselineFor(photoId);
    return PhotoOverride(
      recipe: recipe,
      overridesBasicLook: !_sameBasicLook(recipe, baseline),
      overridesCrop: recipe.crop != baseline.crop,
    );
  }

  bool _sameBasicLook(EditRecipe first, EditRecipe second) =>
      first.basicEditingRecipe.filter == second.basicEditingRecipe.filter &&
      first.basicEditingRecipe.filterStrength ==
          second.basicEditingRecipe.filterStrength &&
      mapEquals(first.basicEditingRecipe.hsl, second.basicEditingRecipe.hsl);

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
