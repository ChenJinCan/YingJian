import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';

const Object _notProvided = Object();

@immutable
class ProjectPhoto {
  const ProjectPhoto({
    required this.id,
    required this.localPath,
    required this.originalName,
  });

  final String id;
  final String localPath;
  final String originalName;

  Map<String, Object> toJson() => {
    'id': id,
    'localPath': localPath,
    'originalName': originalName,
  };

  factory ProjectPhoto.fromJson(Map<String, Object?> json) {
    return ProjectPhoto(
      id: json['id']! as String,
      localPath: json['localPath']! as String,
      originalName: json['originalName']! as String,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectPhoto &&
        other.id == id &&
        other.localPath == localPath &&
        other.originalName == originalName;
  }

  @override
  int get hashCode => Object.hash(id, localPath, originalName);
}

enum PhotoProjectFlowState {
  importing,
  analyzing,
  choosingRecommendation,
  editing,
  exporting,
  exported,
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
    this.flowState = PhotoProjectFlowState.editing,
    this.focusPhotoId,
    this.selectedRecommendationId,
  }) : photos = List.unmodifiable(photos),
       sharedStyle =
           sharedStyle ?? SharedStyle(recipe: recipe ?? EditRecipe.neutral),
       adaptiveCompensations = Map.unmodifiable(adaptiveCompensations),
       photoOverrides = Map.unmodifiable(photoOverrides) {
    if (photos.isEmpty || photos.length > maxPhotoCount) {
      throw RangeError.range(photos.length, 1, maxPhotoCount, 'photos.length');
    }
    final photoIds = photos.map((photo) => photo.id).toSet();
    if (photoIds.length != photos.length) {
      throw ArgumentError.value(photos, 'photos', 'Photo ids must be unique');
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
  static const schemaVersion = 2;

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ProjectPhoto> photos;
  final SharedStyle sharedStyle;
  final Map<String, AdaptiveCompensation> adaptiveCompensations;
  final Map<String, PhotoOverride> photoOverrides;
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
    if (storedVersion != 1 && storedVersion != schemaVersion) {
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
}
