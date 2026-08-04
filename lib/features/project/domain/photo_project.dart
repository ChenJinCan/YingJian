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
  importing,
  analyzing,
  choosingRecommendation,
  editing,
  exporting,
  exported,
}

enum PhotoAnalysisState { pending, running, ready, fallback, failed }

enum PhotoExportState { notQueued, queued, running, saved, failed, cancelled }

extension PhotoProjectFlowStateTransitions on PhotoProjectFlowState {
  bool canTransitionTo(PhotoProjectFlowState next) {
    if (next == this) return true;
    return switch (this) {
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

@immutable
class SharedStyle {
  const SharedStyle({required this.recipe});

  final EditRecipe recipe;

  Map<String, Object> toJson() => {'recipe': recipe.toJson()};

  factory SharedStyle.fromJson(Map<String, Object?> json) {
    return SharedStyle(
      recipe: EditRecipe.fromJson(json['recipe']! as Map<String, Object?>),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SharedStyle && other.recipe == recipe;

  @override
  int get hashCode => recipe.hashCode;
}

@immutable
class AdaptiveCompensation {
  const AdaptiveCompensation({required this.recipe});

  final EditRecipe recipe;

  Map<String, Object> toJson() => {'recipe': recipe.toJson()};

  factory AdaptiveCompensation.fromJson(Map<String, Object?> json) {
    return AdaptiveCompensation(
      recipe: EditRecipe.fromJson(json['recipe']! as Map<String, Object?>),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AdaptiveCompensation && other.recipe == recipe;

  @override
  int get hashCode => recipe.hashCode;
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
    this.flowState = PhotoProjectFlowState.editing,
    this.focusPhotoId,
    this.selectedRecommendationId,
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
       }) {
    if (photos.isEmpty || photos.length > maxPhotoCount) {
      throw RangeError.range(photos.length, 1, maxPhotoCount, 'photos.length');
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
  }

  static const maxPhotoCount = 6;
  static const schemaVersion = 3;

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ProjectPhoto> photos;
  final SharedStyle sharedStyle;
  final Map<String, AdaptiveCompensation> adaptiveCompensations;
  final Map<String, PhotoOverride> photoOverrides;
  final Map<String, PhotoAnalysisState> analysisStates;
  final Map<String, PhotoExportState> exportStates;
  final PhotoProjectFlowState flowState;
  final String? focusPhotoId;
  final String? selectedRecommendationId;

  /// Compatibility view for the current editor while it migrates from one
  /// global recipe to explicit group/current-photo scopes.
  EditRecipe get recipe => sharedStyle.recipe;

  EditRecipe effectiveRecipeFor(String photoId) {
    if (!photos.any((photo) => photo.id == photoId)) {
      throw ArgumentError.value(photoId, 'photoId', 'Photo is not in project');
    }
    final adaptive = adaptiveCompensations[photoId]?.recipe;
    final override = photoOverrides[photoId]?.recipe;
    return EditRecipe(
      exposure: _sumAndClamp(
        sharedStyle.recipe.exposure,
        adaptive?.exposure,
        override?.exposure,
      ),
      contrast: _sumAndClamp(
        sharedStyle.recipe.contrast,
        adaptive?.contrast,
        override?.contrast,
      ),
      warmth: _sumAndClamp(
        sharedStyle.recipe.warmth,
        adaptive?.warmth,
        override?.warmth,
      ),
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
    PhotoProjectFlowState? flowState,
    Object? focusPhotoId = _notProvided,
    Object? selectedRecommendationId = _notProvided,
  }) {
    return PhotoProject(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      photos: photos ?? this.photos,
      sharedStyle:
          sharedStyle ??
          (recipe == null ? this.sharedStyle : SharedStyle(recipe: recipe)),
      adaptiveCompensations:
          adaptiveCompensations ?? this.adaptiveCompensations,
      photoOverrides: photoOverrides ?? this.photoOverrides,
      analysisStates: analysisStates ?? this.analysisStates,
      exportStates: exportStates ?? this.exportStates,
      flowState: flowState ?? this.flowState,
      focusPhotoId: focusPhotoId == _notProvided
          ? this.focusPhotoId
          : focusPhotoId as String?,
      selectedRecommendationId: selectedRecommendationId == _notProvided
          ? this.selectedRecommendationId
          : selectedRecommendationId as String?,
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
        other.flowState == flowState &&
        other.focusPhotoId == focusPhotoId &&
        other.selectedRecommendationId == selectedRecommendationId &&
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
    flowState,
    focusPhotoId,
    selectedRecommendationId,
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
}
