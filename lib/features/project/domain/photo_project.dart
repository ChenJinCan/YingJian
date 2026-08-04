import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';

const Object _notProvided = Object();

enum PhotoInputFormat { jpeg, png, heic, unknown }

enum PhotoColorSpace { srgb, displayP3, unknown }

enum PhotoSupportState { supported, legacyUnknown }

@immutable
class ProjectPhoto {
  const ProjectPhoto({
    required this.id,
    required this.localPath,
    required this.originalName,
    this.contentSha256 = '',
    this.pixelWidth = 0,
    this.pixelHeight = 0,
    this.orientation = 1,
    this.colorSpace = PhotoColorSpace.unknown,
    this.inputFormat = PhotoInputFormat.unknown,
    this.supportState = PhotoSupportState.legacyUnknown,
  });

  final String id;
  final String localPath;
  final String originalName;
  final String contentSha256;
  final int pixelWidth;
  final int pixelHeight;
  final int orientation;
  final PhotoColorSpace colorSpace;
  final PhotoInputFormat inputFormat;
  final PhotoSupportState supportState;

  Map<String, Object> toJson() => {
    'id': id,
    'localPath': localPath,
    'originalName': originalName,
    'contentSha256': contentSha256,
    'pixelWidth': pixelWidth,
    'pixelHeight': pixelHeight,
    'orientation': orientation,
    'colorSpace': colorSpace.name,
    'inputFormat': inputFormat.name,
    'supportState': supportState.name,
  };

  factory ProjectPhoto.fromJson(Map<String, Object?> json) {
    final orientation = (json['orientation'] as num?)?.toInt() ?? 1;
    if (orientation < 1 || orientation > 8) {
      throw FormatException('Unsupported photo orientation $orientation');
    }
    return ProjectPhoto(
      id: json['id']! as String,
      localPath: json['localPath']! as String,
      originalName: json['originalName']! as String,
      contentSha256: json['contentSha256'] as String? ?? '',
      pixelWidth: (json['pixelWidth'] as num?)?.toInt() ?? 0,
      pixelHeight: (json['pixelHeight'] as num?)?.toInt() ?? 0,
      orientation: orientation,
      colorSpace: _enumValue(
        json['colorSpace'],
        PhotoColorSpace.values,
        PhotoColorSpace.unknown,
      ),
      inputFormat: _enumValue(
        json['inputFormat'],
        PhotoInputFormat.values,
        PhotoInputFormat.unknown,
      ),
      supportState: _enumValue(
        json['supportState'],
        PhotoSupportState.values,
        PhotoSupportState.legacyUnknown,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectPhoto &&
        other.id == id &&
        other.localPath == localPath &&
        other.originalName == originalName &&
        other.contentSha256 == contentSha256 &&
        other.pixelWidth == pixelWidth &&
        other.pixelHeight == pixelHeight &&
        other.orientation == orientation &&
        other.colorSpace == colorSpace &&
        other.inputFormat == inputFormat &&
        other.supportState == supportState;
  }

  @override
  int get hashCode => Object.hash(
    id,
    localPath,
    originalName,
    contentSha256,
    pixelWidth,
    pixelHeight,
    orientation,
    colorSpace,
    inputFormat,
    supportState,
  );

  static T _enumValue<T extends Enum>(Object? raw, List<T> values, T fallback) {
    if (raw == null) return fallback;
    return values.where((value) => value.name == raw).firstOrNull ?? fallback;
  }
}

enum PhotoProjectFlowState {
  empty,
  importing,
  analyzing,
  choosingRecommendation,
  editing,
  exporting,
  exported,
}

enum PhotoAnalysisState { pending, running, ready, fallback, failed }

enum PhotoExportState { notQueued, queued, running, saved, failed, cancelled }

extension PhotoAnalysisStateTransitions on PhotoAnalysisState {
  bool canTransitionTo(PhotoAnalysisState next) {
    if (next == this) return true;
    return switch (this) {
      PhotoAnalysisState.pending => next == PhotoAnalysisState.running,
      PhotoAnalysisState.running =>
        next == PhotoAnalysisState.ready ||
            next == PhotoAnalysisState.fallback ||
            next == PhotoAnalysisState.failed,
      PhotoAnalysisState.ready ||
      PhotoAnalysisState.fallback ||
      PhotoAnalysisState.failed => next == PhotoAnalysisState.running,
    };
  }
}

extension PhotoExportStateTransitions on PhotoExportState {
  bool canTransitionTo(PhotoExportState next) {
    if (next == this) return true;
    return switch (this) {
      PhotoExportState.notQueued => next == PhotoExportState.queued,
      PhotoExportState.queued =>
        next == PhotoExportState.running || next == PhotoExportState.cancelled,
      PhotoExportState.running =>
        next == PhotoExportState.saved ||
            next == PhotoExportState.failed ||
            next == PhotoExportState.cancelled,
      PhotoExportState.failed ||
      PhotoExportState.cancelled => next == PhotoExportState.queued,
      PhotoExportState.saved => false,
    };
  }
}

enum ProjectEditingScope { group, currentPhoto }

enum ProjectEditOperationKind { scopedEdit, syncCurrentPhotoToGroup }

@immutable
class ProjectEditOperation {
  const ProjectEditOperation({
    this.kind = ProjectEditOperationKind.scopedEdit,
    required this.scope,
    required this.beforeRecipe,
    required this.afterRecipe,
    this.beforeSharedIntensity = 1,
    this.afterSharedIntensity = 1,
    this.photoId,
    this.beforePhotoOverrideRecipe,
    this.afterPhotoOverrideRecipe,
  });

  final ProjectEditOperationKind kind;
  final ProjectEditingScope scope;
  final String? photoId;
  final EditRecipe beforeRecipe;
  final EditRecipe afterRecipe;
  final double beforeSharedIntensity;
  final double afterSharedIntensity;
  final EditRecipe? beforePhotoOverrideRecipe;
  final EditRecipe? afterPhotoOverrideRecipe;

  Map<String, Object> toJson() {
    final value = <String, Object>{
      'kind': kind.name,
      'scope': scope.name,
      'beforeRecipe': beforeRecipe.toJson(),
      'afterRecipe': afterRecipe.toJson(),
      'beforeSharedIntensity': beforeSharedIntensity,
      'afterSharedIntensity': afterSharedIntensity,
    };
    if (photoId != null) value['photoId'] = photoId!;
    if (beforePhotoOverrideRecipe != null) {
      value['beforePhotoOverrideRecipe'] = beforePhotoOverrideRecipe!.toJson();
    }
    if (afterPhotoOverrideRecipe != null) {
      value['afterPhotoOverrideRecipe'] = afterPhotoOverrideRecipe!.toJson();
    }
    return value;
  }

  factory ProjectEditOperation.fromJson(Map<String, Object?> json) {
    final scope = PhotoProject._enumValue(
      json['scope'],
      ProjectEditingScope.values,
      'edit operation scope',
    );
    return ProjectEditOperation(
      kind: json['kind'] == null
          ? ProjectEditOperationKind.scopedEdit
          : PhotoProject._enumValue(
              json['kind'],
              ProjectEditOperationKind.values,
              'edit operation kind',
            ),
      scope: scope,
      photoId: json['photoId'] as String?,
      beforeRecipe: EditRecipe.fromJson(
        json['beforeRecipe']! as Map<String, Object?>,
      ),
      afterRecipe: EditRecipe.fromJson(
        json['afterRecipe']! as Map<String, Object?>,
      ),
      beforeSharedIntensity:
          (json['beforeSharedIntensity'] as num?)?.toDouble() ?? 1,
      afterSharedIntensity:
          (json['afterSharedIntensity'] as num?)?.toDouble() ?? 1,
      beforePhotoOverrideRecipe:
          json['beforePhotoOverrideRecipe'] is Map<String, Object?>
          ? EditRecipe.fromJson(
              json['beforePhotoOverrideRecipe']! as Map<String, Object?>,
            )
          : null,
      afterPhotoOverrideRecipe:
          json['afterPhotoOverrideRecipe'] is Map<String, Object?>
          ? EditRecipe.fromJson(
              json['afterPhotoOverrideRecipe']! as Map<String, Object?>,
            )
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProjectEditOperation &&
      other.kind == kind &&
      other.scope == scope &&
      other.photoId == photoId &&
      other.beforeRecipe == beforeRecipe &&
      other.afterRecipe == afterRecipe &&
      other.beforeSharedIntensity == beforeSharedIntensity &&
      other.afterSharedIntensity == afterSharedIntensity &&
      other.beforePhotoOverrideRecipe == beforePhotoOverrideRecipe &&
      other.afterPhotoOverrideRecipe == afterPhotoOverrideRecipe;

  @override
  int get hashCode => Object.hash(
    kind,
    scope,
    photoId,
    beforeRecipe,
    afterRecipe,
    beforeSharedIntensity,
    afterSharedIntensity,
    beforePhotoOverrideRecipe,
    afterPhotoOverrideRecipe,
  );
}

extension PhotoProjectFlowStateTransitions on PhotoProjectFlowState {
  bool canTransitionTo(PhotoProjectFlowState next) {
    if (next == this) return true;
    return switch (this) {
      PhotoProjectFlowState.empty => next == PhotoProjectFlowState.importing,
      PhotoProjectFlowState.importing =>
        next == PhotoProjectFlowState.analyzing,
      PhotoProjectFlowState.analyzing =>
        next == PhotoProjectFlowState.choosingRecommendation,
      PhotoProjectFlowState.choosingRecommendation =>
        next == PhotoProjectFlowState.editing,
      PhotoProjectFlowState.editing => next == PhotoProjectFlowState.exporting,
      PhotoProjectFlowState.exporting =>
        next == PhotoProjectFlowState.exported ||
            next == PhotoProjectFlowState.editing,
      PhotoProjectFlowState.exported => next == PhotoProjectFlowState.editing,
    };
  }
}

enum SharedStyleFamily { naturalClean, atmosphericColor, texturedStyle, manual }

@immutable
class SharedStyle {
  factory SharedStyle({
    required EditRecipe recipe,
    SharedStyleFamily family = SharedStyleFamily.manual,
    double intensity = 1,
  }) {
    _validateUnitValue(intensity, 'intensity');
    return SharedStyle._(recipe: recipe, family: family, intensity: intensity);
  }

  const SharedStyle._({
    required this.recipe,
    required this.family,
    required this.intensity,
  });

  final EditRecipe recipe;
  final SharedStyleFamily family;
  final double intensity;

  Map<String, Object> toJson() => {
    'recipe': recipe.toJson(),
    'family': family.name,
    'intensity': intensity,
  };

  factory SharedStyle.fromJson(Map<String, Object?> json) {
    return SharedStyle(
      recipe: EditRecipe.fromJson(json['recipe']! as Map<String, Object?>),
      family: json['family'] == null
          ? SharedStyleFamily.manual
          : PhotoProject._enumValue(
              json['family'],
              SharedStyleFamily.values,
              'shared style family',
            ),
      intensity: (json['intensity'] as num?)?.toDouble() ?? 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SharedStyle &&
      other.recipe == recipe &&
      other.family == family &&
      other.intensity == intensity;

  @override
  int get hashCode => Object.hash(recipe, family, intensity);
}

enum AdaptiveCompensationSource {
  localAnalysisV1,
  safeFallbackV1,
  legacyMigration,
}

@immutable
class AdaptiveCompensation {
  factory AdaptiveCompensation({
    required EditRecipe recipe,
    required AdaptiveCompensationSource source,
    double safeSharedIntensity = 1,
    double skinProtection = 0,
  }) {
    _validateUnitValue(safeSharedIntensity, 'safeSharedIntensity');
    _validateUnitValue(skinProtection, 'skinProtection');
    return AdaptiveCompensation._(
      recipe: recipe,
      source: source,
      safeSharedIntensity: safeSharedIntensity,
      skinProtection: skinProtection,
    );
  }

  const AdaptiveCompensation._({
    required this.recipe,
    required this.source,
    required this.safeSharedIntensity,
    required this.skinProtection,
  });

  final EditRecipe recipe;
  final AdaptiveCompensationSource source;
  final double safeSharedIntensity;
  final double skinProtection;

  Map<String, Object> toJson() => {
    'recipe': recipe.toJson(),
    'source': source.name,
    'safeSharedIntensity': safeSharedIntensity,
    'skinProtection': skinProtection,
  };

  factory AdaptiveCompensation.fromJson(Map<String, Object?> json) {
    return AdaptiveCompensation(
      recipe: EditRecipe.fromJson(json['recipe']! as Map<String, Object?>),
      source: json['source'] == null
          ? AdaptiveCompensationSource.legacyMigration
          : PhotoProject._enumValue(
              json['source'],
              AdaptiveCompensationSource.values,
              'adaptive compensation source',
            ),
      safeSharedIntensity:
          (json['safeSharedIntensity'] as num?)?.toDouble() ?? 1,
      skinProtection: (json['skinProtection'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AdaptiveCompensation &&
      other.recipe == recipe &&
      other.source == source &&
      other.safeSharedIntensity == safeSharedIntensity &&
      other.skinProtection == skinProtection;

  @override
  int get hashCode =>
      Object.hash(recipe, source, safeSharedIntensity, skinProtection);
}

void _validateUnitValue(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw RangeError.range(value, 0, 1, name);
  }
}

@immutable
class PhotoOverride {
  const PhotoOverride({required this.recipe});

  final EditRecipe recipe;

  Map<String, Object> toJson() => {'recipe': recipe.toJson()};

  factory PhotoOverride.fromJson(Map<String, Object?> json) {
    return PhotoOverride(
      recipe: EditRecipe.fromJson(json['recipe']! as Map<String, Object?>),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PhotoOverride && other.recipe == recipe;

  @override
  int get hashCode => recipe.hashCode;
}

@immutable
class PhotoGroupSyncPlan {
  const PhotoGroupSyncPlan({
    required this.sharedStyle,
    required this.remainingPhotoOverride,
  });

  final SharedStyle sharedStyle;
  final EditRecipe remainingPhotoOverride;
}

@immutable
class PhotoProject {
  PhotoProject({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required List<ProjectPhoto> photos,
    EditRecipe? recipe,
    SharedStyle? sharedStyle,
    Map<String, AdaptiveCompensation> adaptiveCompensations = const {},
    Map<String, PhotoOverride> photoOverrides = const {},
    Map<String, PhotoAnalysisState> analysisStates = const {},
    Map<String, PhotoExportState> exportStates = const {},
    ProjectEditingScope? editingScope,
    List<ProjectEditOperation> undoHistory = const [],
    List<ProjectEditOperation> redoHistory = const [],
    this.flowState = PhotoProjectFlowState.editing,
    this.focusPhotoId,
    this.selectedRecommendationId,
    this.groupScrollOffset = 0,
  }) : photos = List.unmodifiable(photos),
       sharedStyle =
           sharedStyle ?? SharedStyle(recipe: recipe ?? EditRecipe.neutral),
       adaptiveCompensations = Map.unmodifiable(adaptiveCompensations),
       photoOverrides = Map.unmodifiable(photoOverrides),
       analysisStates = Map.unmodifiable({
         for (final photo in photos)
           photo.id: analysisStates[photo.id] ?? PhotoAnalysisState.pending,
       }),
       exportStates = Map.unmodifiable({
         for (final photo in photos)
           photo.id: exportStates[photo.id] ?? PhotoExportState.notQueued,
       }),
       undoHistory = List.unmodifiable(undoHistory),
       redoHistory = List.unmodifiable(redoHistory),
       editingScope =
           editingScope ??
           (photos.length == 1
               ? ProjectEditingScope.currentPhoto
               : ProjectEditingScope.group) {
    if (photos.isEmpty || photos.length > maxPhotoCount) {
      throw RangeError.range(photos.length, 1, maxPhotoCount, 'photos.length');
    }
    if (flowState == PhotoProjectFlowState.empty) {
      throw ArgumentError.value(
        flowState,
        'flowState',
        'Empty is a session state and cannot contain project photos',
      );
    }
    if (!groupScrollOffset.isFinite || groupScrollOffset < 0) {
      throw ArgumentError.value(
        groupScrollOffset,
        'groupScrollOffset',
        'Group scroll offset must be finite and non-negative',
      );
    }
    final photoIds = photos.map((photo) => photo.id).toSet();
    if (photoIds.length != photos.length) {
      throw ArgumentError.value(photos, 'photos', 'Photo ids must be unique');
    }
    for (final photo in photos) {
      if (photo.orientation < 1 || photo.orientation > 8) {
        throw ArgumentError.value(
          photo.orientation,
          'photo.orientation',
          'Orientation must be between 1 and 8',
        );
      }
      if (photo.supportState == PhotoSupportState.supported &&
          (!RegExp(r'^[a-f0-9]{64}$').hasMatch(photo.contentSha256) ||
              photo.pixelWidth <= 0 ||
              photo.pixelHeight <= 0 ||
              photo.inputFormat == PhotoInputFormat.unknown)) {
        throw ArgumentError.value(
          photo,
          'photos',
          'Supported photos require complete content identity',
        );
      }
    }
    if (focusPhotoId != null && !photoIds.contains(focusPhotoId)) {
      throw ArgumentError.value(
        focusPhotoId,
        'focusPhotoId',
        'Focus photo must belong to the project',
      );
    }
    if (photos.length == 1 &&
        this.editingScope != ProjectEditingScope.currentPhoto) {
      throw ArgumentError.value(
        this.editingScope,
        'editingScope',
        'A single-photo project always edits the current photo',
      );
    }
    final foreignLayerIds = {
      ...adaptiveCompensations.keys,
      ...photoOverrides.keys,
      ...analysisStates.keys,
      ...exportStates.keys,
    }.difference(photoIds);
    if (foreignLayerIds.isNotEmpty) {
      throw ArgumentError.value(
        foreignLayerIds,
        'layers',
        'Every layer must reference a project photo',
      );
    }
    for (final operation in [...undoHistory, ...redoHistory]) {
      final photoId = operation.photoId;
      final isValidVariant = switch (operation.kind) {
        ProjectEditOperationKind.scopedEdit =>
          operation.beforePhotoOverrideRecipe == null &&
              operation.afterPhotoOverrideRecipe == null &&
              ((operation.scope == ProjectEditingScope.group &&
                      photoId == null &&
                      (operation.beforeRecipe != operation.afterRecipe ||
                          operation.beforeSharedIntensity !=
                              operation.afterSharedIntensity)) ||
                  (operation.scope == ProjectEditingScope.currentPhoto &&
                      photoId != null &&
                      photoIds.contains(photoId) &&
                      operation.beforeRecipe != operation.afterRecipe &&
                      operation.beforeSharedIntensity ==
                          operation.afterSharedIntensity)),
        ProjectEditOperationKind.syncCurrentPhotoToGroup =>
          operation.scope == ProjectEditingScope.group &&
              photoId != null &&
              photoIds.contains(photoId) &&
              operation.beforePhotoOverrideRecipe != null &&
              operation.afterPhotoOverrideRecipe != null &&
              operation.beforeSharedIntensity ==
                  operation.afterSharedIntensity &&
              (operation.beforeRecipe != operation.afterRecipe ||
                  operation.beforePhotoOverrideRecipe !=
                      operation.afterPhotoOverrideRecipe),
      };
      if (!operation.beforeSharedIntensity.isFinite ||
          operation.beforeSharedIntensity < 0 ||
          operation.beforeSharedIntensity > 1 ||
          !operation.afterSharedIntensity.isFinite ||
          operation.afterSharedIntensity < 0 ||
          operation.afterSharedIntensity > 1 ||
          !isValidVariant) {
        throw ArgumentError.value(
          operation,
          'editHistory',
          'Edit operations must describe a changed valid project scope',
        );
      }
    }
  }

  static const maxPhotoCount = 6;
  static const schemaVersion = 5;

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ProjectPhoto> photos;
  final SharedStyle sharedStyle;
  final Map<String, AdaptiveCompensation> adaptiveCompensations;
  final Map<String, PhotoOverride> photoOverrides;
  final Map<String, PhotoAnalysisState> analysisStates;
  final Map<String, PhotoExportState> exportStates;
  final ProjectEditingScope editingScope;
  final List<ProjectEditOperation> undoHistory;
  final List<ProjectEditOperation> redoHistory;
  final PhotoProjectFlowState flowState;
  final String? focusPhotoId;
  final String? selectedRecommendationId;
  final double groupScrollOffset;

  /// Compatibility view for the current editor while it migrates from one
  /// global recipe to explicit group/current-photo scopes.
  EditRecipe get recipe => sharedStyle.recipe;

  bool canTransitionTo(PhotoProjectFlowState nextState) {
    if (!flowState.canTransitionTo(nextState)) return false;
    if (flowState == nextState) return true;
    if (flowState == PhotoProjectFlowState.analyzing &&
        nextState == PhotoProjectFlowState.choosingRecommendation) {
      return analysisStates.values.every(
        (state) =>
            state != PhotoAnalysisState.pending &&
            state != PhotoAnalysisState.running,
      );
    }
    if (flowState == PhotoProjectFlowState.choosingRecommendation &&
        nextState == PhotoProjectFlowState.editing) {
      return selectedRecommendationId != null;
    }
    if (flowState == PhotoProjectFlowState.editing &&
        nextState == PhotoProjectFlowState.exporting) {
      return exportStates.values.any(
            (state) => state == PhotoExportState.queued,
          ) &&
          exportStates.values.every(
            (state) =>
                state == PhotoExportState.queued ||
                state == PhotoExportState.saved,
          );
    }
    if (flowState == PhotoProjectFlowState.exporting &&
        nextState == PhotoProjectFlowState.exported) {
      return exportStates.values.every(
        (state) =>
            state == PhotoExportState.saved ||
            state == PhotoExportState.failed ||
            state == PhotoExportState.cancelled,
      );
    }
    return true;
  }

  bool canTransitionPhotoAnalysis(
    String photoId,
    PhotoAnalysisState nextState,
  ) {
    return flowState == PhotoProjectFlowState.analyzing &&
        analysisStates[photoId]?.canTransitionTo(nextState) == true;
  }

  bool canTransitionPhotoExport(String photoId, PhotoExportState nextState) {
    final previous = exportStates[photoId];
    if (previous == null || !previous.canTransitionTo(nextState)) return false;
    if (flowState == PhotoProjectFlowState.editing) {
      return nextState == PhotoExportState.queued;
    }
    return flowState == PhotoProjectFlowState.exporting;
  }

  bool get canMutateInputs => flowState != PhotoProjectFlowState.exporting;

  PhotoGroupSyncPlan? planPhotoAdjustmentsToGroup(String photoId) {
    if (!photos.any((photo) => photo.id == photoId)) {
      throw ArgumentError.value(photoId, 'photoId', 'Photo is not in project');
    }
    final override = photoOverrides[photoId]?.recipe;
    if (override == null || !override.hasColorAdjustments) return null;

    final safeSharedIntensity = sharedStyle.intensity
        .clamp(0.0, adaptiveCompensations[photoId]?.safeSharedIntensity ?? 1.0)
        .toDouble();
    if (safeSharedIntensity <= 0) return null;

    double? promote(double sharedValue, double overrideValue) {
      final value = sharedValue + overrideValue / safeSharedIntensity;
      return value.isFinite && value >= -1 && value <= 1 ? value : null;
    }

    final exposure = promote(sharedStyle.recipe.exposure, override.exposure);
    final highlights = promote(
      sharedStyle.recipe.highlights,
      override.highlights,
    );
    final shadows = promote(sharedStyle.recipe.shadows, override.shadows);
    final contrast = promote(sharedStyle.recipe.contrast, override.contrast);
    final warmth = promote(sharedStyle.recipe.warmth, override.warmth);
    final tint = promote(sharedStyle.recipe.tint, override.tint);
    final saturation = promote(
      sharedStyle.recipe.saturation,
      override.saturation,
    );
    final clarity = promote(sharedStyle.recipe.clarity, override.clarity);
    if ([
      exposure,
      highlights,
      shadows,
      contrast,
      warmth,
      tint,
      saturation,
      clarity,
    ].any((value) => value == null)) {
      return null;
    }

    return PhotoGroupSyncPlan(
      sharedStyle: SharedStyle(
        family: sharedStyle.family,
        intensity: sharedStyle.intensity,
        recipe: EditRecipe(
          exposure: exposure!,
          highlights: highlights!,
          shadows: shadows!,
          contrast: contrast!,
          warmth: warmth!,
          tint: tint!,
          saturation: saturation!,
          clarity: clarity!,
          crop: sharedStyle.recipe.crop,
        ),
      ),
      remainingPhotoOverride: override.crop.isOriginal
          ? EditRecipe.neutral
          : EditRecipe(crop: override.crop),
    );
  }

  PhotoProject replacePhotosAndInvalidateDerivedState({
    required List<ProjectPhoto> photos,
    required DateTime updatedAt,
    String? focusPhotoId,
  }) {
    if (!canMutateInputs) {
      throw StateError('Project inputs cannot change while exporting');
    }
    return PhotoProject(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt,
      photos: photos,
      flowState: PhotoProjectFlowState.analyzing,
      focusPhotoId: focusPhotoId,
      sharedStyle: SharedStyle(recipe: EditRecipe.neutral),
    );
  }

  EditRecipe effectiveRecipeFor(
    String photoId, {
    EditRecipe? sharedRecipe,
    EditRecipe? photoOverride,
  }) {
    if (!photos.any((photo) => photo.id == photoId)) {
      throw ArgumentError.value(photoId, 'photoId', 'Photo is not in project');
    }
    final adaptiveLayer = adaptiveCompensations[photoId];
    final adaptive = adaptiveLayer?.recipe;
    final shared = sharedRecipe ?? sharedStyle.recipe;
    final sharedIntensity = sharedStyle.intensity
        .clamp(0.0, adaptiveLayer?.safeSharedIntensity ?? 1.0)
        .toDouble();
    final override = photoOverride ?? photoOverrides[photoId]?.recipe;
    return EditRecipe(
      exposure: _sumAndClamp(
        shared.exposure * sharedIntensity,
        adaptive?.exposure,
        override?.exposure,
      ),
      highlights: _sumAndClamp(
        shared.highlights * sharedIntensity,
        adaptive?.highlights,
        override?.highlights,
      ),
      shadows: _sumAndClamp(
        shared.shadows * sharedIntensity,
        adaptive?.shadows,
        override?.shadows,
      ),
      contrast: _sumAndClamp(
        shared.contrast * sharedIntensity,
        adaptive?.contrast,
        override?.contrast,
      ),
      warmth: _sumAndClamp(
        shared.warmth * sharedIntensity,
        adaptive?.warmth,
        override?.warmth,
      ),
      tint: _sumAndClamp(
        shared.tint * sharedIntensity,
        adaptive?.tint,
        override?.tint,
      ),
      saturation: _sumAndClamp(
        shared.saturation * sharedIntensity,
        adaptive?.saturation,
        override?.saturation,
      ),
      clarity: _sumAndClamp(
        shared.clarity * sharedIntensity,
        adaptive?.clarity,
        override?.clarity,
      ),
      crop: photoOverride != null || photoOverrides.containsKey(photoId)
          ? override!.crop
          : shared.crop,
    );
  }

  PhotoProject copyWith({
    DateTime? updatedAt,
    List<ProjectPhoto>? photos,
    EditRecipe? recipe,
    SharedStyle? sharedStyle,
    Map<String, AdaptiveCompensation>? adaptiveCompensations,
    Map<String, PhotoOverride>? photoOverrides,
    Map<String, PhotoAnalysisState>? analysisStates,
    Map<String, PhotoExportState>? exportStates,
    ProjectEditingScope? editingScope,
    List<ProjectEditOperation>? undoHistory,
    List<ProjectEditOperation>? redoHistory,
    PhotoProjectFlowState? flowState,
    Object? focusPhotoId = _notProvided,
    Object? selectedRecommendationId = _notProvided,
    double? groupScrollOffset,
  }) {
    return PhotoProject(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      photos: photos ?? this.photos,
      sharedStyle:
          sharedStyle ??
          (recipe == null
              ? this.sharedStyle
              : SharedStyle(
                  recipe: recipe,
                  family: this.sharedStyle.family,
                  intensity: this.sharedStyle.intensity,
                )),
      adaptiveCompensations:
          adaptiveCompensations ?? this.adaptiveCompensations,
      photoOverrides: photoOverrides ?? this.photoOverrides,
      analysisStates: analysisStates ?? this.analysisStates,
      exportStates: exportStates ?? this.exportStates,
      editingScope: editingScope ?? this.editingScope,
      undoHistory: undoHistory ?? this.undoHistory,
      redoHistory: redoHistory ?? this.redoHistory,
      flowState: flowState ?? this.flowState,
      focusPhotoId: focusPhotoId == _notProvided
          ? this.focusPhotoId
          : focusPhotoId as String?,
      selectedRecommendationId: selectedRecommendationId == _notProvided
          ? this.selectedRecommendationId
          : selectedRecommendationId as String?,
      groupScrollOffset: groupScrollOffset ?? this.groupScrollOffset,
    );
  }

  Map<String, Object> toJson() {
    final value = <String, Object>{
      'schemaVersion': schemaVersion,
      'id': id,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'photos': photos.map((photo) => photo.toJson()).toList(),
      'flowState': flowState.name,
      'sharedStyle': sharedStyle.toJson(),
      'adaptiveCompensations': adaptiveCompensations.map(
        (photoId, layer) => MapEntry(photoId, layer.toJson()),
      ),
      'photoOverrides': photoOverrides.map(
        (photoId, layer) => MapEntry(photoId, layer.toJson()),
      ),
      'analysisStates': analysisStates.map(
        (photoId, state) => MapEntry(photoId, state.name),
      ),
      'exportStates': exportStates.map(
        (photoId, state) => MapEntry(photoId, state.name),
      ),
      'editingScope': editingScope.name,
      'groupScrollOffset': groupScrollOffset,
      'undoHistory': undoHistory
          .map((operation) => operation.toJson())
          .toList(),
      'redoHistory': redoHistory
          .map((operation) => operation.toJson())
          .toList(),
    };
    if (focusPhotoId != null) {
      value['focusPhotoId'] = focusPhotoId!;
    }
    if (selectedRecommendationId != null) {
      value['selectedRecommendationId'] = selectedRecommendationId!;
    }
    return value;
  }

  factory PhotoProject.fromJson(Map<String, Object?> json) {
    final photoValues = json['photos']! as List<Object?>;
    final storedVersion = (json['schemaVersion'] as num?)?.toInt() ?? 1;
    if (storedVersion < 1 || storedVersion > schemaVersion) {
      throw FormatException('Unsupported photo project schema $storedVersion');
    }
    if (storedVersion == 1) {
      return PhotoProject(
        id: json['id']! as String,
        createdAt: DateTime.parse(json['createdAt']! as String),
        updatedAt: DateTime.parse(json['updatedAt']! as String),
        photos: photoValues
            .map(
              (value) => ProjectPhoto.fromJson(value! as Map<String, Object?>),
            )
            .toList(),
        recipe: json['recipe'] == null
            ? EditRecipe.neutral
            : EditRecipe.fromJson(json['recipe']! as Map<String, Object?>),
      );
    }
    final flowStateName = json['flowState']! as String;
    final flowState = PhotoProjectFlowState.values
        .where((value) => value.name == flowStateName)
        .firstOrNull;
    if (flowState == null) {
      throw FormatException('Unsupported project flow state $flowStateName');
    }
    return PhotoProject(
      id: json['id']! as String,
      createdAt: DateTime.parse(json['createdAt']! as String),
      updatedAt: DateTime.parse(json['updatedAt']! as String),
      photos: photoValues
          .map((value) => ProjectPhoto.fromJson(value! as Map<String, Object?>))
          .toList(),
      flowState: flowState,
      focusPhotoId: json['focusPhotoId'] as String?,
      selectedRecommendationId: json['selectedRecommendationId'] as String?,
      sharedStyle: SharedStyle.fromJson(
        json['sharedStyle']! as Map<String, Object?>,
      ),
      adaptiveCompensations: _layerMap(
        json['adaptiveCompensations'],
        AdaptiveCompensation.fromJson,
      ),
      photoOverrides: _layerMap(json['photoOverrides'], PhotoOverride.fromJson),
      analysisStates: storedVersion < 3
          ? const {}
          : _enumMap(json['analysisStates'], PhotoAnalysisState.values),
      exportStates: storedVersion < 3
          ? const {}
          : _enumMap(json['exportStates'], PhotoExportState.values),
      editingScope: storedVersion < 4
          ? null
          : _enumValue(
              json['editingScope'],
              ProjectEditingScope.values,
              'project editing scope',
            ),
      undoHistory: storedVersion < 4
          ? const []
          : _operationList(json['undoHistory']),
      redoHistory: storedVersion < 4
          ? const []
          : _operationList(json['redoHistory']),
      groupScrollOffset: storedVersion < 5
          ? 0
          : (json['groupScrollOffset'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PhotoProject &&
        other.id == id &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.sharedStyle == sharedStyle &&
        mapEquals(other.adaptiveCompensations, adaptiveCompensations) &&
        mapEquals(other.photoOverrides, photoOverrides) &&
        mapEquals(other.analysisStates, analysisStates) &&
        mapEquals(other.exportStates, exportStates) &&
        other.editingScope == editingScope &&
        listEquals(other.undoHistory, undoHistory) &&
        listEquals(other.redoHistory, redoHistory) &&
        other.flowState == flowState &&
        other.focusPhotoId == focusPhotoId &&
        other.selectedRecommendationId == selectedRecommendationId &&
        other.groupScrollOffset == groupScrollOffset &&
        listEquals(other.photos, photos);
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    sharedStyle,
    Object.hashAllUnordered(adaptiveCompensations.entries),
    Object.hashAllUnordered(photoOverrides.entries),
    Object.hashAllUnordered(analysisStates.entries),
    Object.hashAllUnordered(exportStates.entries),
    editingScope,
    Object.hashAll(undoHistory),
    Object.hashAll(redoHistory),
    flowState,
    focusPhotoId,
    selectedRecommendationId,
    groupScrollOffset,
    Object.hashAll(photos),
  );

  static double _sumAndClamp(double first, double? second, double? third) {
    return (first + (second ?? 0) + (third ?? 0)).clamp(-1.0, 1.0);
  }

  static Map<String, T> _layerMap<T>(
    Object? raw,
    T Function(Map<String, Object?>) decode,
  ) {
    if (raw == null) {
      return const {};
    }
    final values = raw as Map<String, Object?>;
    return values.map(
      (photoId, value) =>
          MapEntry(photoId, decode(value! as Map<String, Object?>)),
    );
  }

  static Map<String, T> _enumMap<T extends Enum>(Object? raw, List<T> values) {
    if (raw == null) {
      return const {};
    }
    final stored = raw as Map<String, Object?>;
    return stored.map((photoId, name) {
      final state = values.where((value) => value.name == name).firstOrNull;
      if (state == null) {
        throw FormatException('Unsupported per-photo state $name');
      }
      return MapEntry(photoId, state);
    });
  }

  static T _enumValue<T extends Enum>(
    Object? raw,
    List<T> values,
    String description,
  ) {
    final state = values.where((value) => value.name == raw).firstOrNull;
    if (state == null) {
      throw FormatException('Unsupported $description $raw');
    }
    return state;
  }

  static List<ProjectEditOperation> _operationList(Object? raw) {
    if (raw == null) return const [];
    return (raw as List<Object?>)
        .map(
          (value) =>
              ProjectEditOperation.fromJson(value! as Map<String, Object?>),
        )
        .toList();
  }
}
