import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';

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

@immutable
class PhotoProject {
  PhotoProject({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required List<ProjectPhoto> photos,
    EditRecipe? recipe,
  }) : photos = List.unmodifiable(photos),
       recipe = recipe ?? EditRecipe.neutral {
    if (photos.isEmpty || photos.length > maxPhotoCount) {
      throw RangeError.range(photos.length, 1, maxPhotoCount, 'photos.length');
    }
  }

  static const maxPhotoCount = 9;

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ProjectPhoto> photos;
  final EditRecipe recipe;

  PhotoProject copyWith({
    DateTime? updatedAt,
    List<ProjectPhoto>? photos,
    EditRecipe? recipe,
  }) {
    return PhotoProject(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      photos: photos ?? this.photos,
      recipe: recipe ?? this.recipe,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'photos': photos.map((photo) => photo.toJson()).toList(),
    'recipe': recipe.toJson(),
  };

  factory PhotoProject.fromJson(Map<String, Object?> json) {
    final photoValues = json['photos']! as List<Object?>;
    return PhotoProject(
      id: json['id']! as String,
      createdAt: DateTime.parse(json['createdAt']! as String),
      updatedAt: DateTime.parse(json['updatedAt']! as String),
      photos: photoValues
          .map((value) => ProjectPhoto.fromJson(value! as Map<String, Object?>))
          .toList(),
      recipe: json['recipe'] == null
          ? EditRecipe.neutral
          : EditRecipe.fromJson(json['recipe']! as Map<String, Object?>),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PhotoProject &&
        other.id == id &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.recipe == recipe &&
        listEquals(other.photos, photos);
  }

  @override
  int get hashCode =>
      Object.hash(id, createdAt, updatedAt, recipe, Object.hashAll(photos));
}
