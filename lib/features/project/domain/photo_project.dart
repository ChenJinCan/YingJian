import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:yingjian/features/creation/domain/creation_intent.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/directional_lighting_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/editing_resource.dart';
import 'package:yingjian/features/editor/domain/legacy_edit_recipe_adapter.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/portrait_retouch_recipe.dart';
import 'package:yingjian/features/editor/domain/targeted_geometry_recipe.dart';
import 'package:yingjian/features/editor/domain/targeted_portrait_recipe.dart';

const Object _notProvided = Object();

List<ProjectEditOperation> _boundedHistory(
  List<ProjectEditOperation> operations,
) => operations.length <= PhotoProject.maxEditHistoryCount
    ? operations
    : operations.sublist(operations.length - PhotoProject.maxEditHistoryCount);

List<Map<String, Object?>> _copyUnknownMetaOps(
  Iterable<Map<String, Object?>> values,
) => List.unmodifiable(
  values.map(
    (value) => Map<String, Object?>.unmodifiable(
      Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map),
    ),
  ),
);

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

enum PhotoProjectFlowState { empty, importing, editing, exporting, exported }

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
      PhotoExportState.saved => next == PhotoExportState.queued,
    };
  }
}

enum ProjectEditingScope { group, currentPhoto }

enum ProjectEditOperationKind {
  scopedEdit,
  syncCurrentPhotoToGroup,
  resetCurrentPhotoOverride,
  targetRebind,
}

@immutable
class ProjectEditOperation {
  ProjectEditOperation({
    this.kind = ProjectEditOperationKind.scopedEdit,
    this.source = EditSource.manual,
    required this.scope,
    required this.beforeRecipe,
    required this.afterRecipe,
    this.beforeSharedIntensity = 1,
    this.afterSharedIntensity = 1,
    this.photoId,
    this.beforePhotoOverrideRecipe,
    this.afterPhotoOverrideRecipe,
    this.beforeTargetRegistry,
    this.afterTargetRegistry,
    this.beforeSnapshot,
    this.afterSnapshot,
    List<OpAddress> changedAddresses = const [],
  }) : changedAddresses = List.unmodifiable(changedAddresses);

  final ProjectEditOperationKind kind;
  final EditSource source;
  final ProjectEditingScope scope;
  final String? photoId;
  final EditRecipe beforeRecipe;
  final EditRecipe afterRecipe;
  final double beforeSharedIntensity;
  final double afterSharedIntensity;
  final EditRecipe? beforePhotoOverrideRecipe;
  final EditRecipe? afterPhotoOverrideRecipe;
  final EditTargetRegistry? beforeTargetRegistry;
  final EditTargetRegistry? afterTargetRegistry;
  final ProjectEditSnapshot? beforeSnapshot;
  final ProjectEditSnapshot? afterSnapshot;
  final List<OpAddress> changedAddresses;

  ProjectEditOperation withSnapshots({
    required ProjectEditSnapshot before,
    required ProjectEditSnapshot after,
  }) => ProjectEditOperation(
    kind: kind,
    source: source,
    scope: scope,
    beforeRecipe: beforeRecipe,
    afterRecipe: afterRecipe,
    beforeSharedIntensity: beforeSharedIntensity,
    afterSharedIntensity: afterSharedIntensity,
    photoId: photoId,
    beforePhotoOverrideRecipe: beforePhotoOverrideRecipe,
    afterPhotoOverrideRecipe: afterPhotoOverrideRecipe,
    beforeTargetRegistry: beforeTargetRegistry,
    afterTargetRegistry: afterTargetRegistry,
    beforeSnapshot: before,
    afterSnapshot: after,
    changedAddresses: changedAddresses,
  );

  Map<String, Object> toJson() {
    final value = <String, Object>{
      'kind': kind.name,
      'source': source.name,
      'scope': scope.name,
      'beforeRecipe': beforeRecipe.toJson(),
      'afterRecipe': afterRecipe.toJson(),
      'beforeSharedIntensity': beforeSharedIntensity,
      'afterSharedIntensity': afterSharedIntensity,
      'changedAddresses': changedAddresses
          .map((address) => address.toJson())
          .toList(),
    };
    if (photoId != null) value['photoId'] = photoId!;
    if (beforePhotoOverrideRecipe != null) {
      value['beforePhotoOverrideRecipe'] = beforePhotoOverrideRecipe!.toJson();
    }
    if (afterPhotoOverrideRecipe != null) {
      value['afterPhotoOverrideRecipe'] = afterPhotoOverrideRecipe!.toJson();
    }
    if (beforeTargetRegistry != null) {
      value['beforeTargetRegistry'] = beforeTargetRegistry!.toJson();
    }
    if (afterTargetRegistry != null) {
      value['afterTargetRegistry'] = afterTargetRegistry!.toJson();
    }
    if (beforeSnapshot != null) {
      value['beforeSnapshot'] = beforeSnapshot!.toJson();
      value['afterSnapshot'] = afterSnapshot!.toJson();
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
      source: json['source'] == null || json['source'] == 'recommendation'
          ? EditSource.migration
          : PhotoProject._enumValue(
              json['source'],
              EditSource.values,
              'edit operation source',
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
      beforeTargetRegistry: json['beforeTargetRegistry'] is Map
          ? EditTargetRegistry.fromJson(
              Map<String, Object?>.from(json['beforeTargetRegistry']! as Map),
            )
          : null,
      afterTargetRegistry: json['afterTargetRegistry'] is Map
          ? EditTargetRegistry.fromJson(
              Map<String, Object?>.from(json['afterTargetRegistry']! as Map),
            )
          : null,
      beforeSnapshot: json['beforeSnapshot'] is Map
          ? ProjectEditSnapshot.fromJson(
              Map<String, Object?>.from(json['beforeSnapshot']! as Map),
            )
          : null,
      afterSnapshot: json['afterSnapshot'] is Map
          ? ProjectEditSnapshot.fromJson(
              Map<String, Object?>.from(json['afterSnapshot']! as Map),
            )
          : null,
      changedAddresses: json['changedAddresses'] is List
          ? (json['changedAddresses']! as List)
                .map(
                  (value) => OpAddress.fromJson(
                    Map<String, Object?>.from(value! as Map),
                  ),
                )
                .toList()
          : const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProjectEditOperation &&
      other.kind == kind &&
      other.source == source &&
      other.scope == scope &&
      other.photoId == photoId &&
      other.beforeRecipe == beforeRecipe &&
      other.afterRecipe == afterRecipe &&
      other.beforeSharedIntensity == beforeSharedIntensity &&
      other.afterSharedIntensity == afterSharedIntensity &&
      other.beforePhotoOverrideRecipe == beforePhotoOverrideRecipe &&
      other.afterPhotoOverrideRecipe == afterPhotoOverrideRecipe &&
      other.beforeTargetRegistry == beforeTargetRegistry &&
      other.afterTargetRegistry == afterTargetRegistry &&
      other.beforeSnapshot == beforeSnapshot &&
      other.afterSnapshot == afterSnapshot &&
      listEquals(other.changedAddresses, changedAddresses);

  @override
  int get hashCode => Object.hash(
    kind,
    source,
    scope,
    photoId,
    beforeRecipe,
    afterRecipe,
    beforeSharedIntensity,
    afterSharedIntensity,
    beforePhotoOverrideRecipe,
    afterPhotoOverrideRecipe,
    beforeTargetRegistry,
    afterTargetRegistry,
    beforeSnapshot,
    afterSnapshot,
    Object.hashAll(changedAddresses),
  );
}

extension PhotoProjectFlowStateTransitions on PhotoProjectFlowState {
  bool canTransitionTo(PhotoProjectFlowState next) {
    if (next == this) return true;
    return switch (this) {
      PhotoProjectFlowState.empty => next == PhotoProjectFlowState.importing,
      PhotoProjectFlowState.importing => next == PhotoProjectFlowState.editing,
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
    double portraitStrength = 0,
    PortraitRetouchRecipe? portraitRecipe,
  }) {
    _validateUnitValue(safeSharedIntensity, 'safeSharedIntensity');
    _validateUnitValue(skinProtection, 'skinProtection');
    _validateUnitValue(portraitStrength, 'portraitStrength');
    return AdaptiveCompensation._(
      recipe: recipe,
      source: source,
      safeSharedIntensity: safeSharedIntensity,
      skinProtection: skinProtection,
      portraitRecipe:
          portraitRecipe ??
          PortraitRetouchRecipe.migrateLegacy(
            portraitStrength: portraitStrength,
            faceSlimStrength: 0,
            bodySlimStrength: 0,
          ),
    );
  }

  const AdaptiveCompensation._({
    required this.recipe,
    required this.source,
    required this.safeSharedIntensity,
    required this.skinProtection,
    required this.portraitRecipe,
  });

  final EditRecipe recipe;
  final AdaptiveCompensationSource source;
  final double safeSharedIntensity;
  final double skinProtection;
  final PortraitRetouchRecipe portraitRecipe;

  double get portraitStrength => portraitRecipe.textureSmoothing / 100;

  Map<String, Object> toJson() => {
    'recipe': recipe.toJson(),
    'source': source.name,
    'safeSharedIntensity': safeSharedIntensity,
    'skinProtection': skinProtection,
    'portraitRecipe': portraitRecipe.toJson(),
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
      portraitStrength: (json['portraitStrength'] as num?)?.toDouble() ?? 0,
      portraitRecipe: json['portraitRecipe'] is Map
          ? PortraitRetouchRecipe.fromJson(
              Map<String, Object?>.from(json['portraitRecipe']! as Map),
            )
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AdaptiveCompensation &&
      other.recipe == recipe &&
      other.source == source &&
      other.safeSharedIntensity == safeSharedIntensity &&
      other.skinProtection == skinProtection &&
      other.portraitRecipe == portraitRecipe;

  @override
  int get hashCode => Object.hash(
    recipe,
    source,
    safeSharedIntensity,
    skinProtection,
    portraitRecipe,
  );
}

void _validateUnitValue(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw RangeError.range(value, 0, 1, name);
  }
}

@immutable
class PhotoOverride {
  factory PhotoOverride({
    required EditRecipe recipe,
    bool? overridesBasicLook,
    @Deprecated('Use overridesBasicLook') bool? overridesBasicEditing,
    bool? overridesCrop,
  }) => PhotoOverride._(
    recipe: recipe,
    overridesBasicLook:
        overridesBasicLook ??
        overridesBasicEditing ??
        !_sameBasicLook(recipe.basicEditingRecipe, BasicEditingRecipe.neutral),
    overridesCrop: overridesCrop ?? !recipe.crop.isOriginal,
  );

  const PhotoOverride._({
    required this.recipe,
    required this.overridesBasicLook,
    required this.overridesCrop,
  });

  final EditRecipe recipe;
  final bool overridesBasicLook;
  final bool overridesCrop;

  Map<String, Object> toJson() => {
    'recipe': recipe.toJson(),
    'overridesBasicLook': overridesBasicLook,
    'overridesCrop': overridesCrop,
  };

  factory PhotoOverride.fromJson(Map<String, Object?> json) {
    final recipe = EditRecipe.fromJson(json['recipe']! as Map<String, Object?>);
    return PhotoOverride(
      recipe: recipe,
      overridesBasicLook:
          json['overridesBasicLook'] as bool? ??
          json['overridesBasicEditing'] as bool?,
      overridesCrop: json['overridesCrop'] as bool?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PhotoOverride &&
      other.recipe == recipe &&
      other.overridesBasicLook == overridesBasicLook &&
      other.overridesCrop == overridesCrop;

  @override
  int get hashCode => Object.hash(recipe, overridesBasicLook, overridesCrop);
}

bool _sameBasicLook(BasicEditingRecipe first, BasicEditingRecipe second) =>
    first.filter == second.filter &&
    first.filterStrength == second.filterStrength &&
    mapEquals(first.hsl, second.hsl);

BasicEditingRecipe _basicLookOnly(BasicEditingRecipe recipe) =>
    BasicEditingRecipe(
      filter: recipe.filter,
      filterStrength: recipe.filterStrength,
      hsl: recipe.hsl,
    );

BasicEditingRecipe? _promoteBasicLook(
  BasicEditingRecipe recipe,
  double effectiveIntensity,
) {
  final filterStrength = recipe.filterStrength / effectiveIntensity;
  final scaledHsl = <HslChannel, HslAdjustment>{};
  if (!filterStrength.isFinite || filterStrength > 100) return null;
  for (final entry in recipe.hsl.entries) {
    final hue = entry.value.hue / effectiveIntensity;
    final saturation = entry.value.saturation / effectiveIntensity;
    final lightness = entry.value.lightness / effectiveIntensity;
    if ([
      hue,
      saturation,
      lightness,
    ].any((value) => !value.isFinite || value < -100 || value > 100)) {
      return null;
    }
    scaledHsl[entry.key] = HslAdjustment(
      hue: hue,
      saturation: saturation,
      lightness: lightness,
    );
  }
  return BasicEditingRecipe(
    filter: recipe.filter,
    filterStrength: filterStrength,
    hsl: scaledHsl,
  );
}

BasicEditingRecipe _composeBasicEditing({
  required BasicEditingRecipe geometry,
  required BasicEditingRecipe look,
}) => BasicEditingRecipe(
  flipHorizontal: geometry.flipHorizontal,
  flipVertical: geometry.flipVertical,
  perspectiveHorizontal: geometry.perspectiveHorizontal,
  perspectiveVertical: geometry.perspectiveVertical,
  filter: look.filter,
  filterStrength: look.filterStrength,
  hsl: look.hsl,
);

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
final class ProjectEditSnapshot {
  ProjectEditSnapshot({
    required this.sharedStyle,
    Map<String, AdaptiveCompensation> adaptiveCompensations = const {},
    required Map<String, PhotoOverride> photoOverrides,
    required Map<String, EditTargetRegistry> targetRegistries,
    EditState? editState,
  }) : adaptiveCompensations = Map.unmodifiable(adaptiveCompensations),
       photoOverrides = Map.unmodifiable(photoOverrides),
       targetRegistries = Map.unmodifiable(targetRegistries),
       editState =
           editState ??
           PhotoProject.deriveEditState(
             sharedStyle: sharedStyle,
             photoOverrides: photoOverrides,
             targetRegistries: targetRegistries,
           );

  factory ProjectEditSnapshot.fromProject(PhotoProject project) =>
      ProjectEditSnapshot(
        sharedStyle: project.sharedStyle,
        adaptiveCompensations: project.adaptiveCompensations,
        photoOverrides: project.photoOverrides,
        targetRegistries: project.targetRegistries,
        editState: project.editState,
      );

  final SharedStyle sharedStyle;
  final Map<String, AdaptiveCompensation> adaptiveCompensations;
  final Map<String, PhotoOverride> photoOverrides;
  final Map<String, EditTargetRegistry> targetRegistries;
  final EditState editState;

  Map<String, Object> toJson() => {
    'sharedStyle': sharedStyle.toJson(),
    'adaptiveCompensations': adaptiveCompensations.map(
      (photoId, layer) => MapEntry(photoId, layer.toJson()),
    ),
    'photoOverrides': photoOverrides.map(
      (photoId, layer) => MapEntry(photoId, layer.toJson()),
    ),
    'targetRegistries': targetRegistries.map(
      (photoId, registry) => MapEntry(photoId, registry.toJson()),
    ),
    'editState': editState.toJson(),
  };

  factory ProjectEditSnapshot.fromJson(Map<String, Object?> json) =>
      ProjectEditSnapshot(
        sharedStyle: SharedStyle.fromJson(
          Map<String, Object?>.from(json['sharedStyle']! as Map),
        ),
        adaptiveCompensations: PhotoProject._layerMap(
          json['adaptiveCompensations'],
          AdaptiveCompensation.fromJson,
        ),
        photoOverrides: PhotoProject._layerMap(
          json['photoOverrides'],
          PhotoOverride.fromJson,
        ),
        targetRegistries: PhotoProject._layerMap(
          json['targetRegistries'],
          EditTargetRegistry.fromJson,
        ),
        editState: json['editState'] is Map
            ? EditState.fromJson(
                Map<String, Object?>.from(json['editState']! as Map),
              )
            : null,
      );

  @override
  bool operator ==(Object other) =>
      other is ProjectEditSnapshot &&
      other.sharedStyle == sharedStyle &&
      mapEquals(other.adaptiveCompensations, adaptiveCompensations) &&
      mapEquals(other.photoOverrides, photoOverrides) &&
      mapEquals(other.targetRegistries, targetRegistries) &&
      other.editState == editState;

  @override
  int get hashCode => Object.hash(
    sharedStyle,
    Object.hashAllUnordered(adaptiveCompensations.entries),
    Object.hashAllUnordered(
      photoOverrides.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
    Object.hashAllUnordered(
      targetRegistries.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
    editState,
  );
}

@immutable
final class ProjectEditCheckpoint {
  const ProjectEditCheckpoint({
    required this.editCount,
    required this.snapshot,
  });

  final int editCount;
  final ProjectEditSnapshot snapshot;

  Map<String, Object> toJson() => {
    'editCount': editCount,
    'snapshot': snapshot.toJson(),
  };

  factory ProjectEditCheckpoint.fromJson(Map<String, Object?> json) =>
      ProjectEditCheckpoint(
        editCount: (json['editCount']! as num).toInt(),
        snapshot: ProjectEditSnapshot.fromJson(
          Map<String, Object?>.from(json['snapshot']! as Map),
        ),
      );

  @override
  bool operator ==(Object other) =>
      other is ProjectEditCheckpoint &&
      other.editCount == editCount &&
      other.snapshot == snapshot;

  @override
  int get hashCode => Object.hash(editCount, snapshot);
}

@immutable
final class StaticStyleResultIdentity {
  StaticStyleResultIdentity({
    required this.sourcePhotoId,
    required this.editStateVersion,
    required this.styleId,
    required this.recipe,
    this.styleName,
  }) {
    if (sourcePhotoId.isEmpty || sourcePhotoId.length > 160) {
      throw ArgumentError.value(
        sourcePhotoId,
        'sourcePhotoId',
        'A static style result requires a bounded source photo id',
      );
    }
    if (editStateVersion < 0) {
      throw RangeError.value(editStateVersion, 'editStateVersion');
    }
    if (styleId.isEmpty ||
        styleId.length > 64 ||
        !RegExp(r'^[a-z0-9-]+$').hasMatch(styleId)) {
      throw ArgumentError.value(
        styleId,
        'styleId',
        'Static style ids must be lowercase stable identifiers',
      );
    }
    if (styleName case final name?
        when name.trim().isEmpty ||
            name != name.trim() ||
            name.length > 120 ||
            RegExp(r'[\x00-\x1F\x7F]').hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'styleName',
        'Static style names must be trimmed printable text up to 120 chars',
      );
    }
  }

  final String sourcePhotoId;
  final int editStateVersion;
  final String styleId;
  final String? styleName;
  final EditRecipe recipe;

  Map<String, Object> toJson() => {
    'sourcePhotoId': sourcePhotoId,
    'editStateVersion': editStateVersion,
    'styleId': styleId,
    'styleName': ?styleName,
    'recipe': recipe.toJson(),
  };

  factory StaticStyleResultIdentity.fromJson(Map<String, Object?> json) =>
      StaticStyleResultIdentity(
        sourcePhotoId: json['sourcePhotoId']! as String,
        editStateVersion: (json['editStateVersion']! as num).toInt(),
        styleId: json['styleId']! as String,
        styleName: json['styleName'] as String?,
        recipe: EditRecipe.fromJson(
          Map<String, Object?>.from(json['recipe']! as Map),
        ),
      );

  @override
  bool operator ==(Object other) =>
      other is StaticStyleResultIdentity &&
      other.sourcePhotoId == sourcePhotoId &&
      other.editStateVersion == editStateVersion &&
      other.styleId == styleId &&
      other.styleName == styleName &&
      other.recipe == recipe;

  @override
  int get hashCode =>
      Object.hash(sourcePhotoId, editStateVersion, styleId, styleName, recipe);
}

@immutable
class PhotoProject {
  PhotoProject({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required List<ProjectPhoto> photos,
    this.creationIntent = CreationIntent.apply,
    this.creationStyleId,
    this.creationStyleName,
    this.creationStyleRecipe,
    this.creationResult,
    bool? creationResultActive,
    EditRecipe? recipe,
    SharedStyle? sharedStyle,
    Map<String, AdaptiveCompensation> adaptiveCompensations = const {},
    Map<String, PhotoOverride> photoOverrides = const {},
    Map<String, EditTargetRegistry> targetRegistries = const {},
    Map<String, PhotoAnalysisState> analysisStates = const {},
    Map<String, PhotoExportState> exportStates = const {},
    EditingResourceRegistry? editingResources,
    EditState? editState,
    ProjectEditingScope? editingScope,
    List<ProjectEditOperation> undoHistory = const [],
    List<ProjectEditOperation> redoHistory = const [],
    this.foldedEditCount = 0,
    this.historyBaseSnapshot,
    List<ProjectEditCheckpoint> editCheckpoints = const [],
    List<Map<String, Object?>> unknownMetaOps = const [],
    List<String> recentTransactionIds = const [],
    this.flowState = PhotoProjectFlowState.editing,
    this.focusPhotoId,
    this.groupScrollOffset = 0,
    this.lastSuccessfulExportEditStateVersion,
  }) : creationResultActive = creationResultActive ?? (creationResult != null),
       photos = List.unmodifiable(photos),
       sharedStyle =
           sharedStyle ?? SharedStyle(recipe: recipe ?? EditRecipe.neutral),
       adaptiveCompensations = Map.unmodifiable(adaptiveCompensations),
       photoOverrides = Map.unmodifiable(photoOverrides),
       targetRegistries = Map.unmodifiable(targetRegistries),
       analysisStates = Map.unmodifiable({
         for (final photo in photos)
           photo.id: analysisStates[photo.id] ?? PhotoAnalysisState.pending,
       }),
       exportStates = Map.unmodifiable({
         for (final photo in photos)
           photo.id: exportStates[photo.id] ?? PhotoExportState.notQueued,
       }),
       editingResources = editingResources ?? EditingResourceRegistry.empty,
       editState =
           editState ??
           deriveEditState(
             sharedStyle:
                 sharedStyle ??
                 SharedStyle(recipe: recipe ?? EditRecipe.neutral),
             photoOverrides: photoOverrides,
             targetRegistries: targetRegistries,
           ),
       undoHistory = List.unmodifiable(_boundedHistory(undoHistory)),
       redoHistory = List.unmodifiable(_boundedHistory(redoHistory)),
       editCheckpoints = List.unmodifiable(editCheckpoints),
       unknownMetaOps = _copyUnknownMetaOps(unknownMetaOps),
       recentTransactionIds = List.unmodifiable(
         recentTransactionIds.length <= maxEditHistoryCount
             ? recentTransactionIds
             : recentTransactionIds.sublist(
                 recentTransactionIds.length - maxEditHistoryCount,
               ),
       ),
       editingScope =
           editingScope ??
           (photos.length == 1
               ? ProjectEditingScope.currentPhoto
               : ProjectEditingScope.group) {
    if (photos.isEmpty || photos.length > maxPhotoCount) {
      throw RangeError.range(photos.length, 1, maxPhotoCount, 'photos.length');
    }
    if (creationStyleId case final styleId?
        when styleId.isEmpty ||
            styleId.length > 64 ||
            !RegExp(r'^[a-z0-9-]+$').hasMatch(styleId)) {
      throw ArgumentError.value(
        styleId,
        'creationStyleId',
        'Creation style ids must be lowercase stable identifiers',
      );
    }
    if (creationStyleName case final styleName?
        when styleName.trim().isEmpty ||
            styleName != styleName.trim() ||
            styleName.length > 120 ||
            RegExp(r'[\x00-\x1F\x7F]').hasMatch(styleName)) {
      throw ArgumentError.value(
        styleName,
        'creationStyleName',
        'Creation style names must be trimmed printable text up to 120 chars',
      );
    }
    if (creationResult case final result?) {
      if (!photos.any((photo) => photo.id == result.sourcePhotoId)) {
        throw ArgumentError.value(
          result.sourcePhotoId,
          'creationResult.sourcePhotoId',
          'The static result source must belong to the project',
        );
      }
      if (result.editStateVersion > this.editState.version) {
        throw ArgumentError.value(
          result.editStateVersion,
          'creationResult.editStateVersion',
          'A static result cannot reference a future edit state',
        );
      }
    }
    if (this.creationResultActive && creationResult == null) {
      throw ArgumentError(
        'An active static result requires a persisted result identity',
      );
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
    if (foldedEditCount < 0) {
      throw RangeError.value(foldedEditCount, 'foldedEditCount');
    }
    if (recentTransactionIds.any((id) => id.trim().isEmpty) ||
        recentTransactionIds.toSet().length != recentTransactionIds.length) {
      throw ArgumentError.value(
        recentTransactionIds,
        'recentTransactionIds',
        'Transaction ids must be non-empty and unique',
      );
    }
    if (historyBaseSnapshot == null && editCheckpoints.isNotEmpty) {
      throw ArgumentError(
        'Checkpoints require a history base snapshot and vice versa',
      );
    }
    var previousCheckpoint = foldedEditCount;
    for (final checkpoint in editCheckpoints) {
      if (checkpoint.editCount <= previousCheckpoint ||
          checkpoint.editCount % checkpointInterval != 0) {
        throw ArgumentError.value(
          checkpoint,
          'editCheckpoints',
          'Checkpoints must be ordered twenty-edit boundaries',
        );
      }
      previousCheckpoint = checkpoint.editCount;
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
      ...targetRegistries.keys,
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
    for (final entry in targetRegistries.entries) {
      if (entry.value.targets.values.any(
        (target) => target.photoId != entry.key,
      )) {
        throw ArgumentError.value(
          entry,
          'targetRegistries',
          'Every stable target must belong to its registry photo',
        );
      }
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
        ProjectEditOperationKind.resetCurrentPhotoOverride =>
          operation.scope == ProjectEditingScope.currentPhoto &&
              photoId != null &&
              photoIds.contains(photoId) &&
              operation.beforePhotoOverrideRecipe != null &&
              operation.afterPhotoOverrideRecipe == null &&
              operation.beforeRecipe == operation.beforePhotoOverrideRecipe &&
              operation.beforeSharedIntensity == operation.afterSharedIntensity,
        ProjectEditOperationKind.targetRebind =>
          operation.scope == ProjectEditingScope.currentPhoto &&
              photoId != null &&
              photoIds.contains(photoId) &&
              operation.beforeRecipe == operation.afterRecipe &&
              operation.beforeSharedIntensity ==
                  operation.afterSharedIntensity &&
              operation.beforePhotoOverrideRecipe == null &&
              operation.afterPhotoOverrideRecipe == null &&
              operation.beforeTargetRegistry != null &&
              operation.afterTargetRegistry != null &&
              operation.beforeTargetRegistry != operation.afterTargetRegistry,
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

  /// New projects are single-photo only. The higher persisted limit remains
  /// solely so older multi-photo snapshots can be decoded and migrated.
  static const maxSelectablePhotoCount = 1;
  static const maxPhotoCount = 6;
  static const maxEditHistoryCount = 100;
  // V9 separates the shareable filter/HSL look from per-photo basic geometry,
  // so flips and perspective never freeze later group-style edits. V8's
  // broader overridesBasicEditing flag is accepted as a conservative look
  // override during migration.
  static const schemaVersion = 17;
  static const checkpointInterval = 20;

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ProjectPhoto> photos;
  final CreationIntent creationIntent;
  final String? creationStyleId;
  final String? creationStyleName;
  final EditRecipe? creationStyleRecipe;
  final StaticStyleResultIdentity? creationResult;
  final bool creationResultActive;
  final SharedStyle sharedStyle;
  final Map<String, AdaptiveCompensation> adaptiveCompensations;
  final Map<String, PhotoOverride> photoOverrides;
  final Map<String, EditTargetRegistry> targetRegistries;
  final Map<String, PhotoAnalysisState> analysisStates;
  final Map<String, PhotoExportState> exportStates;
  final EditingResourceRegistry editingResources;
  final EditState editState;
  final ProjectEditingScope editingScope;
  final List<ProjectEditOperation> undoHistory;
  final List<ProjectEditOperation> redoHistory;
  final int foldedEditCount;
  final ProjectEditSnapshot? historyBaseSnapshot;
  final List<ProjectEditCheckpoint> editCheckpoints;
  final List<Map<String, Object?>> unknownMetaOps;
  final List<String> recentTransactionIds;
  final PhotoProjectFlowState flowState;
  final String? focusPhotoId;
  final double groupScrollOffset;
  final int? lastSuccessfulExportEditStateVersion;

  /// Compatibility view for the current editor while it migrates from one
  /// global recipe to explicit group/current-photo scopes.
  EditRecipe get recipe => sharedStyle.recipe;

  bool get requiresUpdate =>
      unknownMetaOps.isNotEmpty ||
      [...undoHistory, ...redoHistory].any(
        (operation) => operation.changedAddresses.any((address) {
          final definition = MetaOpCatalog.standard.find(address.metaOpId);
          return definition == null ||
              definition.version != address.metaOpVersion;
        }),
      );
  bool get isReadOnly => requiresUpdate;
  bool get canExport => !requiresUpdate;
  int get editStateVersion => editState.version;

  StaticStyleResultIdentity? get recoverableStaticStyleResult {
    final result = creationResult;
    if (creationIntent != CreationIntent.apply ||
        result == null ||
        requiresUpdate) {
      return null;
    }
    if (result.editStateVersion != editStateVersion ||
        !photos.any((photo) => photo.id == result.sourcePhotoId) ||
        effectiveRecipeFor(result.sourcePhotoId) != result.recipe) {
      return null;
    }
    return result;
  }

  StaticStyleResultIdentity? get currentStaticStyleResult {
    final result = recoverableStaticStyleResult;
    if (!creationResultActive ||
        result == null ||
        result.styleId != creationStyleId ||
        result.styleName != creationStyleName ||
        result.recipe != creationStyleRecipe) {
      return null;
    }
    return result;
  }

  bool get hasConsistentEditState {
    final derived = deriveEditState(
      sharedStyle: sharedStyle,
      photoOverrides: photoOverrides,
      targetRegistries: targetRegistries,
    );
    return mapEquals(derived.values, editState.values);
  }

  static EditState deriveEditState({
    required SharedStyle sharedStyle,
    required Map<String, PhotoOverride> photoOverrides,
    required Map<String, EditTargetRegistry> targetRegistries,
  }) {
    const adapter = LegacyEditRecipeAdapter();
    final values = <OpAddress, Object>{
      ...adapter.read(sharedStyle.recipe).values,
    };
    for (final entry in photoOverrides.entries) {
      final photoValues = adapter
          .read(
            entry.value.recipe,
            photoId: entry.key,
            targetRegistry: targetRegistries[entry.key],
          )
          .values;
      values.addEntries(
        photoValues.entries.where(
          (entry) => entry.key.scope == EditScope.currentPhoto,
        ),
      );
    }
    return EditState(values: Map.unmodifiable(values));
  }

  EditState renderStateFor(String photoId, {EditRecipe? recipe}) {
    if (!photos.any((photo) => photo.id == photoId)) {
      throw ArgumentError.value(photoId, 'photoId', 'Unknown project photo');
    }
    final projected = const LegacyEditRecipeAdapter().read(
      recipe ?? effectiveRecipeFor(photoId),
      photoId: photoId,
      targetRegistry: targetRegistries[photoId],
    );
    return EditState(version: editState.version, values: projected.values);
  }

  bool canTransitionTo(PhotoProjectFlowState nextState) {
    if (requiresUpdate && nextState != flowState) return false;
    if (!flowState.canTransitionTo(nextState)) return false;
    if (flowState == nextState) return true;
    if (flowState == PhotoProjectFlowState.editing &&
        nextState == PhotoProjectFlowState.exporting) {
      return exportStates.values.any(
            (state) => state == PhotoExportState.queued,
          ) &&
          exportStates.values.every(
            (state) =>
                state == PhotoExportState.queued ||
                state == PhotoExportState.saved ||
                state == PhotoExportState.notQueued,
          );
    }
    if (flowState == PhotoProjectFlowState.exporting &&
        nextState == PhotoProjectFlowState.exported) {
      return exportStates.values.every(
        (state) =>
            state == PhotoExportState.saved ||
            state == PhotoExportState.failed ||
            state == PhotoExportState.cancelled ||
            state == PhotoExportState.notQueued,
      );
    }
    return true;
  }

  bool canTransitionPhotoAnalysis(
    String photoId,
    PhotoAnalysisState nextState,
  ) {
    return flowState == PhotoProjectFlowState.editing &&
        analysisStates[photoId]?.canTransitionTo(nextState) == true;
  }

  bool canTransitionPhotoExport(String photoId, PhotoExportState nextState) {
    if (!canExport) return false;
    final previous = exportStates[photoId];
    if (previous == null || !previous.canTransitionTo(nextState)) return false;
    if (flowState == PhotoProjectFlowState.editing) {
      return nextState == PhotoExportState.queued;
    }
    return flowState == PhotoProjectFlowState.exporting;
  }

  bool get canMutateInputs =>
      !requiresUpdate && flowState != PhotoProjectFlowState.exporting;

  bool get hasValidHistoryReplay {
    final base = historyBaseSnapshot;
    if (base == null) {
      return foldedEditCount == 0 &&
          editCheckpoints.isEmpty &&
          undoHistory.isEmpty &&
          redoHistory.isEmpty;
    }
    var cursor = base;
    var editCount = foldedEditCount;
    final checkpoints = {
      for (final checkpoint in editCheckpoints)
        checkpoint.editCount: checkpoint.snapshot,
    };
    for (final operation in undoHistory) {
      if (operation.beforeSnapshot != cursor ||
          operation.afterSnapshot == null) {
        return false;
      }
      cursor = operation.afterSnapshot!;
      editCount += 1;
      final checkpoint = checkpoints[editCount];
      if (checkpoint != null && checkpoint != cursor) return false;
    }
    return cursor == ProjectEditSnapshot.fromProject(this);
  }

  PhotoGroupSyncPlan? planPhotoAdjustmentsToGroup(String photoId) {
    if (!photos.any((photo) => photo.id == photoId)) {
      throw ArgumentError.value(photoId, 'photoId', 'Photo is not in project');
    }
    final overrideLayer = photoOverrides[photoId];
    final override = overrideLayer?.recipe;
    if (override == null ||
        (!override.hasColorAdjustments && !overrideLayer!.overridesBasicLook)) {
      return null;
    }
    final safeSharedIntensity = sharedStyle.intensity
        .clamp(0.0, adaptiveCompensations[photoId]?.safeSharedIntensity ?? 1.0)
        .toDouble();
    if (safeSharedIntensity <= 0) return null;
    final promotedBasicLook = overrideLayer!.overridesBasicLook
        ? _promoteBasicLook(
            _basicLookOnly(override.basicEditingRecipe),
            safeSharedIntensity,
          )
        : _basicLookOnly(sharedStyle.recipe.basicEditingRecipe);
    if (promotedBasicLook == null) return null;
    final referenceBasicLook = _scaledSharedBasic(
      promotedBasicLook,
      safeSharedIntensity,
    );

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
          basicEditingRecipe: promotedBasicLook,
          crop: sharedStyle.recipe.crop,
        ),
      ),
      remainingPhotoOverride: EditRecipe(
        portraitStrength: override.portraitStrength,
        faceSlimRecipe: override.faceSlimRecipe,
        bodySlimStrength: override.bodySlimStrength,
        portraitRecipe: override.portraitRecipe,
        qualityEnhancementRecipe: override.qualityEnhancementRecipe,
        basicEditingRecipe: _composeBasicEditing(
          geometry: override.basicEditingRecipe,
          look: referenceBasicLook,
        ),
        portraitGeometryRecipe: override.portraitGeometryRecipe,
        semanticEditingRecipe: override.semanticEditingRecipe,
        crop: overrideLayer.overridesCrop
            ? override.crop
            : sharedStyle.recipe.crop,
      ),
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
      creationIntent: creationIntent,
      creationStyleId: creationStyleId,
      creationStyleName: creationStyleName,
      creationStyleRecipe: creationStyleRecipe,
      flowState: PhotoProjectFlowState.editing,
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
    final storedOverride = photoOverrides[photoId];
    final override = photoOverride ?? storedOverride?.recipe;
    final sharedBasic = _scaledSharedBasic(
      shared.basicEditingRecipe,
      sharedIntensity,
    );
    final overridesBasicLook =
        photoOverride != null || (storedOverride?.overridesBasicLook ?? false);
    final overridesCrop =
        photoOverride != null || (storedOverride?.overridesCrop ?? false);
    final activeTargetIds =
        targetRegistries[photoId]?.targets.values
            .where((target) => target.status == EditTargetStatus.active)
            .map((target) => target.id)
            .toSet() ??
        const <String>{};
    final storedTargetedGeometry =
        override?.targetedGeometryRecipe ?? TargetedGeometryRecipe.neutral;
    final activeTargetedGeometry = storedTargetedGeometry.retainTargets(
      activeTargetIds,
    );
    final portraitGeometry = storedTargetedGeometry.isNeutral
        ? override?.portraitGeometryRecipe ??
              EditRecipe.neutral.portraitGeometryRecipe
        : activeTargetedGeometry.project(
            targetRegistries[photoId],
            selectedFaceIndex:
                override?.portraitGeometryRecipe.selectedFaceIndex ?? 0,
            selectedBodyIndex:
                override?.portraitGeometryRecipe.selectedBodyIndex ?? 0,
          );
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
      // Portrait retouch is deliberately a per-photo semantic adjustment. It
      // must not inherit from or be promoted into the group's shared style.
      portraitStrength: 0,
      // Geometry is also explicit and per-photo. Automatic analysis and group
      // synchronization must never enable it on the user's behalf.
      faceSlimRecipe: override?.faceSlimRecipe,
      bodySlimStrength: override?.bodySlimStrength ?? 0,
      portraitRecipe: override?.portraitRecipe ?? adaptiveLayer?.portraitRecipe,
      // Quality restoration is a deliberate per-photo correction, like
      // portrait retouch. It must never be copied across a group implicitly.
      qualityEnhancementRecipe:
          override?.qualityEnhancementRecipe ??
          EditRecipe.neutral.qualityEnhancementRecipe,
      // Flip and perspective are always per-photo, while filter/HSL follow the
      // shared look unless this photo explicitly replaces or clears it.
      basicEditingRecipe: _composeBasicEditing(
        geometry: override?.basicEditingRecipe ?? BasicEditingRecipe.neutral,
        look: overridesBasicLook ? override!.basicEditingRecipe : sharedBasic,
      ),
      portraitGeometryRecipe: portraitGeometry,
      semanticEditingRecipe:
          override?.semanticEditingRecipe ??
          EditRecipe.neutral.semanticEditingRecipe,
      targetedPortraitRecipe:
          (override?.targetedPortraitRecipe ?? TargetedPortraitRecipe.neutral)
              .retainTargets(activeTargetIds),
      targetedGeometryRecipe: activeTargetedGeometry,
      directionalLightingRecipe:
          (override?.directionalLightingRecipe ??
                  DirectionalLightingRecipe.neutral)
              .retainTargets(activeTargetIds),
      crop: overridesCrop ? override!.crop : shared.crop,
    );
  }

  EditRecipe photoOverrideBaselineFor(String photoId) {
    if (!photos.any((photo) => photo.id == photoId)) {
      throw ArgumentError.value(photoId, 'photoId', 'Photo is not in project');
    }
    final adaptiveLayer = adaptiveCompensations[photoId];
    final sharedIntensity = sharedStyle.intensity
        .clamp(0.0, adaptiveLayer?.safeSharedIntensity ?? 1.0)
        .toDouble();
    return EditRecipe(
      portraitRecipe: adaptiveLayer?.portraitRecipe,
      targetedPortraitRecipe: TargetedPortraitRecipe.neutral,
      basicEditingRecipe: _scaledSharedBasic(
        sharedStyle.recipe.basicEditingRecipe,
        sharedIntensity,
      ),
      crop: sharedStyle.recipe.crop,
    );
  }

  static BasicEditingRecipe _scaledSharedBasic(
    BasicEditingRecipe recipe,
    double intensity,
  ) => BasicEditingRecipe(
    filter: recipe.filter,
    filterStrength: recipe.filterStrength * intensity,
    hsl: {
      for (final entry in recipe.hsl.entries)
        entry.key: HslAdjustment(
          hue: entry.value.hue * intensity,
          saturation: entry.value.saturation * intensity,
          lightness: entry.value.lightness * intensity,
        ),
    },
  );

  PhotoProject copyWith({
    DateTime? updatedAt,
    List<ProjectPhoto>? photos,
    CreationIntent? creationIntent,
    Object? creationStyleId = _notProvided,
    Object? creationStyleName = _notProvided,
    Object? creationStyleRecipe = _notProvided,
    Object? creationResult = _notProvided,
    bool? creationResultActive,
    EditRecipe? recipe,
    SharedStyle? sharedStyle,
    Map<String, AdaptiveCompensation>? adaptiveCompensations,
    Map<String, PhotoOverride>? photoOverrides,
    Map<String, EditTargetRegistry>? targetRegistries,
    Map<String, PhotoAnalysisState>? analysisStates,
    Map<String, PhotoExportState>? exportStates,
    EditingResourceRegistry? editingResources,
    EditState? editState,
    ProjectEditingScope? editingScope,
    List<ProjectEditOperation>? undoHistory,
    List<ProjectEditOperation>? redoHistory,
    int? foldedEditCount,
    Object? historyBaseSnapshot = _notProvided,
    List<ProjectEditCheckpoint>? editCheckpoints,
    List<Map<String, Object?>>? unknownMetaOps,
    List<String>? recentTransactionIds,
    PhotoProjectFlowState? flowState,
    Object? focusPhotoId = _notProvided,
    double? groupScrollOffset,
    Object? lastSuccessfulExportEditStateVersion = _notProvided,
  }) {
    return PhotoProject(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      photos: photos ?? this.photos,
      creationIntent: creationIntent ?? this.creationIntent,
      creationStyleId: creationStyleId == _notProvided
          ? this.creationStyleId
          : creationStyleId as String?,
      creationStyleName: creationStyleName == _notProvided
          ? this.creationStyleName
          : creationStyleName as String?,
      creationStyleRecipe: creationStyleRecipe == _notProvided
          ? this.creationStyleRecipe
          : creationStyleRecipe as EditRecipe?,
      creationResult: creationResult == _notProvided
          ? this.creationResult
          : creationResult as StaticStyleResultIdentity?,
      creationResultActive: creationResultActive ?? this.creationResultActive,
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
      targetRegistries: targetRegistries ?? this.targetRegistries,
      analysisStates: analysisStates ?? this.analysisStates,
      exportStates: exportStates ?? this.exportStates,
      editingResources: editingResources ?? this.editingResources,
      editState: editState ?? this.editState,
      editingScope: editingScope ?? this.editingScope,
      undoHistory: undoHistory ?? this.undoHistory,
      redoHistory: redoHistory ?? this.redoHistory,
      foldedEditCount: foldedEditCount ?? this.foldedEditCount,
      historyBaseSnapshot: historyBaseSnapshot == _notProvided
          ? this.historyBaseSnapshot
          : historyBaseSnapshot as ProjectEditSnapshot?,
      editCheckpoints: editCheckpoints ?? this.editCheckpoints,
      unknownMetaOps: unknownMetaOps ?? this.unknownMetaOps,
      recentTransactionIds: recentTransactionIds ?? this.recentTransactionIds,
      flowState: flowState ?? this.flowState,
      focusPhotoId: focusPhotoId == _notProvided
          ? this.focusPhotoId
          : focusPhotoId as String?,
      groupScrollOffset: groupScrollOffset ?? this.groupScrollOffset,
      lastSuccessfulExportEditStateVersion:
          lastSuccessfulExportEditStateVersion == _notProvided
          ? this.lastSuccessfulExportEditStateVersion
          : lastSuccessfulExportEditStateVersion as int?,
    );
  }

  Map<String, Object> toJson() {
    final value = <String, Object>{
      'schemaVersion': schemaVersion,
      'id': id,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'photos': photos.map((photo) => photo.toJson()).toList(),
      'creationIntent': creationIntent.name,
      'creationStyleId': ?creationStyleId,
      'creationStyleName': ?creationStyleName,
      'creationStyleRecipe': ?creationStyleRecipe?.toJson(),
      'creationResult': ?creationResult?.toJson(),
      'creationResultActive': creationResultActive,
      'flowState': flowState.name,
      'sharedStyle': sharedStyle.toJson(),
      'adaptiveCompensations': adaptiveCompensations.map(
        (photoId, layer) => MapEntry(photoId, layer.toJson()),
      ),
      'photoOverrides': photoOverrides.map(
        (photoId, layer) => MapEntry(photoId, layer.toJson()),
      ),
      'targetRegistries': targetRegistries.map(
        (photoId, registry) => MapEntry(photoId, registry.toJson()),
      ),
      'analysisStates': analysisStates.map(
        (photoId, state) => MapEntry(photoId, state.name),
      ),
      'exportStates': exportStates.map(
        (photoId, state) => MapEntry(photoId, state.name),
      ),
      'editingResources': editingResources.toJson(),
      'editState': editState.toJson(),
      'editingScope': editingScope.name,
      'groupScrollOffset': groupScrollOffset,
      'lastSuccessfulExportEditStateVersion':
          ?lastSuccessfulExportEditStateVersion,
      'undoHistory': undoHistory
          .map((operation) => operation.toJson())
          .toList(),
      'redoHistory': redoHistory
          .map((operation) => operation.toJson())
          .toList(),
      'foldedEditCount': foldedEditCount,
      'editCheckpoints': editCheckpoints
          .map((checkpoint) => checkpoint.toJson())
          .toList(),
      if (unknownMetaOps.isNotEmpty) 'unknownMetaOps': unknownMetaOps,
      if (recentTransactionIds.isNotEmpty)
        'recentTransactionIds': recentTransactionIds,
    };
    if (focusPhotoId != null) {
      value['focusPhotoId'] = focusPhotoId!;
    }
    if (historyBaseSnapshot != null) {
      value['historyBaseSnapshot'] = historyBaseSnapshot!.toJson();
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
    final flowState = switch (flowStateName) {
      // Projects written before the direct-to-editor flow are migrated while
      // decoding. The obsolete intermediate states never enter runtime.
      'analyzing' || 'choosingRecommendation' => PhotoProjectFlowState.editing,
      _ =>
        PhotoProjectFlowState.values
            .where((value) => value.name == flowStateName)
            .firstOrNull,
    };
    if (flowState == null) {
      throw FormatException('Unsupported project flow state $flowStateName');
    }
    final project = PhotoProject(
      id: json['id']! as String,
      createdAt: DateTime.parse(json['createdAt']! as String),
      updatedAt: DateTime.parse(json['updatedAt']! as String),
      photos: photoValues
          .map((value) => ProjectPhoto.fromJson(value! as Map<String, Object?>))
          .toList(),
      creationIntent: storedVersion < 15
          ? CreationIntent.apply
          : _enumValue(
              json['creationIntent'],
              CreationIntent.values,
              'creation intent',
            ),
      creationStyleId: storedVersion < 15
          ? null
          : json['creationStyleId'] as String?,
      creationStyleName: storedVersion < 15
          ? null
          : json['creationStyleName'] as String?,
      creationStyleRecipe:
          storedVersion < 15 || json['creationStyleRecipe'] == null
          ? null
          : EditRecipe.fromJson(
              Map<String, Object?>.from(json['creationStyleRecipe']! as Map),
            ),
      creationResult: storedVersion < 16 || json['creationResult'] == null
          ? null
          : StaticStyleResultIdentity.fromJson(
              Map<String, Object?>.from(json['creationResult']! as Map),
            ),
      creationResultActive: storedVersion < 17
          ? storedVersion >= 16 && json['creationResult'] != null
          : json['creationResultActive']! as bool,
      flowState: flowState,
      focusPhotoId: json['focusPhotoId'] as String?,
      sharedStyle: SharedStyle.fromJson(
        json['sharedStyle']! as Map<String, Object?>,
      ),
      adaptiveCompensations: _layerMap(
        json['adaptiveCompensations'],
        AdaptiveCompensation.fromJson,
      ),
      photoOverrides: _layerMap(json['photoOverrides'], PhotoOverride.fromJson),
      targetRegistries: storedVersion < 10
          ? const {}
          : _layerMap(json['targetRegistries'], EditTargetRegistry.fromJson),
      analysisStates: storedVersion < 3
          ? const {}
          : _enumMap(json['analysisStates'], PhotoAnalysisState.values),
      exportStates: storedVersion < 3
          ? const {}
          : _enumMap(json['exportStates'], PhotoExportState.values),
      editingResources: storedVersion < 11
          ? EditingResourceRegistry.empty
          : EditingResourceRegistry.fromJson(
              Map<String, Object?>.from(json['editingResources']! as Map),
            ),
      editState: storedVersion < 13
          ? null
          : EditState.fromJson(
              Map<String, Object?>.from(json['editState']! as Map),
            ),
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
      foldedEditCount: storedVersion < 12
          ? 0
          : (json['foldedEditCount']! as num).toInt(),
      historyBaseSnapshot:
          storedVersion < 12 || json['historyBaseSnapshot'] == null
          ? null
          : ProjectEditSnapshot.fromJson(
              Map<String, Object?>.from(json['historyBaseSnapshot']! as Map),
            ),
      editCheckpoints: storedVersion < 12
          ? const []
          : (json['editCheckpoints']! as List)
                .map(
                  (value) => ProjectEditCheckpoint.fromJson(
                    Map<String, Object?>.from(value! as Map),
                  ),
                )
                .toList(),
      unknownMetaOps: json['unknownMetaOps'] is List
          ? (json['unknownMetaOps']! as List)
                .map((value) => Map<String, Object?>.from(value! as Map))
                .toList()
          : const [],
      recentTransactionIds: storedVersion < 13
          ? const []
          : (json['recentTransactionIds'] as List<Object?>? ?? const [])
                .cast<String>(),
      lastSuccessfulExportEditStateVersion: storedVersion < 14
          ? null
          : (json['lastSuccessfulExportEditStateVersion'] as num?)?.toInt(),
      groupScrollOffset: storedVersion < 5
          ? 0
          : (json['groupScrollOffset'] as num?)?.toDouble() ?? 0,
    );
    final migrated = storedVersion < 12
        ? _migrateLegacyHistory(project)
        : project;
    if (storedVersion >= 13 && !migrated.hasConsistentEditState) {
      throw const FormatException(
        'Photo project edit state does not match its render projection',
      );
    }
    if (storedVersion >= 12 && !migrated.hasValidHistoryReplay) {
      throw const FormatException(
        'Photo project history does not reproduce the current edit state',
      );
    }
    return storedVersion < 17
        ? _migrateLegacyStaticStyleResult(
            migrated,
            allowMissingSuccessfulExportVersion: storedVersion < 14,
          )
        : migrated;
  }

  static PhotoProject _migrateLegacyStaticStyleResult(
    PhotoProject project, {
    required bool allowMissingSuccessfulExportVersion,
  }) {
    if (project.creationIntent != CreationIntent.apply ||
        project.photos.length != 1 ||
        project.flowState != PhotoProjectFlowState.exported ||
        project.requiresUpdate) {
      return project;
    }
    final photo = project.photos.single;
    final successfulVersion = project.lastSuccessfulExportEditStateVersion;
    final hasTrustedExportVersion =
        successfulVersion == project.editStateVersion ||
        (allowMissingSuccessfulExportVersion && successfulVersion == null);
    if (project.exportStates[photo.id] != PhotoExportState.saved ||
        !hasTrustedExportVersion) {
      return project;
    }
    final effectiveRecipe = project.effectiveRecipeFor(photo.id);
    final selectedRecipe = project.creationStyleRecipe;
    if (selectedRecipe != null && selectedRecipe != effectiveRecipe) {
      return project;
    }
    final styleId = project.creationStyleId ?? 'saved-custom';
    final styleName = project.creationStyleName;
    final recipe = selectedRecipe ?? effectiveRecipe;
    return project.copyWith(
      creationStyleId: styleId,
      creationStyleName: styleName,
      creationStyleRecipe: recipe,
      creationResultActive: true,
      lastSuccessfulExportEditStateVersion:
          project.lastSuccessfulExportEditStateVersion ??
          project.editStateVersion,
      creationResult: StaticStyleResultIdentity(
        sourcePhotoId: photo.id,
        editStateVersion: project.editStateVersion,
        styleId: styleId,
        styleName: styleName,
        recipe: recipe,
      ),
    );
  }

  static PhotoProject _migrateLegacyHistory(PhotoProject project) {
    if (project.undoHistory.isEmpty && project.redoHistory.isEmpty) {
      return project;
    }
    final canReplay =
        project.redoHistory.isEmpty &&
        project.undoHistory.every(
          (operation) =>
              operation.kind == ProjectEditOperationKind.scopedEdit &&
              operation.scope == ProjectEditingScope.group &&
              operation.photoId == null,
        );
    if (!canReplay) return _freezeLegacyHistory(project);

    var cursor = ProjectEditSnapshot.fromProject(project);
    final reversed = <ProjectEditOperation>[];
    for (final operation in project.undoHistory.reversed) {
      if (cursor.sharedStyle.recipe != operation.afterRecipe ||
          cursor.sharedStyle.intensity != operation.afterSharedIntensity) {
        return _freezeLegacyHistory(project);
      }
      final before = ProjectEditSnapshot(
        sharedStyle: SharedStyle(
          recipe: operation.beforeRecipe,
          family: cursor.sharedStyle.family,
          intensity: operation.beforeSharedIntensity,
        ),
        adaptiveCompensations: cursor.adaptiveCompensations,
        photoOverrides: cursor.photoOverrides,
        targetRegistries: cursor.targetRegistries,
      );
      reversed.add(operation.withSnapshots(before: before, after: cursor));
      cursor = before;
    }
    final history = reversed.reversed.toList(growable: false);
    final checkpoints = <ProjectEditCheckpoint>[];
    for (
      var index = checkpointInterval;
      index <= history.length;
      index += checkpointInterval
    ) {
      checkpoints.add(
        ProjectEditCheckpoint(
          editCount: index,
          snapshot: history[index - 1].afterSnapshot!,
        ),
      );
    }
    final migrated = project.copyWith(
      undoHistory: history,
      redoHistory: const [],
      foldedEditCount: 0,
      historyBaseSnapshot: cursor,
      editCheckpoints: checkpoints,
    );
    return migrated.hasValidHistoryReplay
        ? migrated
        : _freezeLegacyHistory(project);
  }

  static PhotoProject _freezeLegacyHistory(PhotoProject project) =>
      project.copyWith(
        undoHistory: const [],
        redoHistory: const [],
        foldedEditCount:
            project.undoHistory.length + project.redoHistory.length,
        historyBaseSnapshot: ProjectEditSnapshot.fromProject(project),
        editCheckpoints: const [],
      );

  @override
  bool operator ==(Object other) {
    return other is PhotoProject &&
        other.id == id &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.creationIntent == creationIntent &&
        other.creationStyleId == creationStyleId &&
        other.creationStyleName == creationStyleName &&
        other.creationStyleRecipe == creationStyleRecipe &&
        other.creationResult == creationResult &&
        other.creationResultActive == creationResultActive &&
        other.sharedStyle == sharedStyle &&
        mapEquals(other.adaptiveCompensations, adaptiveCompensations) &&
        mapEquals(other.photoOverrides, photoOverrides) &&
        mapEquals(other.targetRegistries, targetRegistries) &&
        mapEquals(other.analysisStates, analysisStates) &&
        mapEquals(other.exportStates, exportStates) &&
        other.editingResources == editingResources &&
        other.editState == editState &&
        other.editingScope == editingScope &&
        listEquals(other.undoHistory, undoHistory) &&
        listEquals(other.redoHistory, redoHistory) &&
        other.foldedEditCount == foldedEditCount &&
        other.historyBaseSnapshot == historyBaseSnapshot &&
        listEquals(other.editCheckpoints, editCheckpoints) &&
        jsonEncode(other.unknownMetaOps) == jsonEncode(unknownMetaOps) &&
        listEquals(other.recentTransactionIds, recentTransactionIds) &&
        other.flowState == flowState &&
        other.focusPhotoId == focusPhotoId &&
        other.groupScrollOffset == groupScrollOffset &&
        other.lastSuccessfulExportEditStateVersion ==
            lastSuccessfulExportEditStateVersion &&
        listEquals(other.photos, photos);
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    createdAt,
    updatedAt,
    creationIntent,
    creationStyleId,
    creationStyleName,
    creationStyleRecipe,
    creationResult,
    creationResultActive,
    sharedStyle,
    Object.hashAllUnordered(adaptiveCompensations.entries),
    Object.hashAllUnordered(photoOverrides.entries),
    Object.hashAllUnordered(targetRegistries.entries),
    Object.hashAllUnordered(analysisStates.entries),
    Object.hashAllUnordered(exportStates.entries),
    editingResources,
    editState,
    editingScope,
    Object.hashAll(undoHistory),
    Object.hashAll(redoHistory),
    foldedEditCount,
    historyBaseSnapshot,
    Object.hashAll(editCheckpoints),
    jsonEncode(unknownMetaOps),
    Object.hashAll(recentTransactionIds),
    flowState,
    focusPhotoId,
    groupScrollOffset,
    lastSuccessfulExportEditStateVersion,
    Object.hashAll(photos),
  ]);

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
