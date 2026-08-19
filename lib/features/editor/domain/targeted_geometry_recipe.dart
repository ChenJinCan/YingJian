import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';
import 'package:yingjian/features/editor/domain/portrait_geometry_recipe.dart';

@immutable
final class TargetedGeometryRecipe {
  factory TargetedGeometryRecipe({
    Map<String, FaceGeometryTarget> faces = const {},
    Map<String, BodyGeometryTarget> bodies = const {},
  }) {
    if (faces.length > maximumTargetCount ||
        bodies.length > maximumTargetCount) {
      throw RangeError('Too many targeted geometry entries');
    }
    void validateIds(Iterable<String> ids) {
      for (final id in ids) {
        if (!RegExp(r'^target-v1-[0-9a-f]{8}$').hasMatch(id)) {
          throw ArgumentError.value(id, 'targetId');
        }
      }
    }

    validateIds(faces.keys);
    validateIds(bodies.keys);
    return TargetedGeometryRecipe._(
      Map.unmodifiable({
        for (final entry in faces.entries)
          if (!entry.value.isNeutral) entry.key: entry.value,
      }),
      Map.unmodifiable({
        for (final entry in bodies.entries)
          if (!entry.value.isNeutral) entry.key: entry.value,
      }),
    );
  }

  const TargetedGeometryRecipe._(this.faces, this.bodies);

  static const schemaVersion = 1;
  static const maximumTargetCount = 3;
  static const neutral = TargetedGeometryRecipe._({}, {});

  final Map<String, FaceGeometryTarget> faces;
  final Map<String, BodyGeometryTarget> bodies;

  bool get isNeutral => faces.isEmpty && bodies.isEmpty;

  TargetedGeometryRecipe updateFace(
    String targetId,
    FaceGeometryTarget Function(FaceGeometryTarget target) update,
  ) {
    final values = Map<String, FaceGeometryTarget>.of(faces);
    final next = update(values[targetId] ?? FaceGeometryTarget.neutral);
    if (next.isNeutral) {
      values.remove(targetId);
    } else {
      values[targetId] = next;
    }
    return TargetedGeometryRecipe(faces: values, bodies: bodies);
  }

  TargetedGeometryRecipe updateBody(
    String targetId,
    BodyGeometryTarget Function(BodyGeometryTarget target) update,
  ) {
    final values = Map<String, BodyGeometryTarget>.of(bodies);
    final next = update(values[targetId] ?? BodyGeometryTarget.neutral);
    if (next.isNeutral) {
      values.remove(targetId);
    } else {
      values[targetId] = next;
    }
    return TargetedGeometryRecipe(faces: faces, bodies: values);
  }

  TargetedGeometryRecipe retainTargets(Set<String> targetIds) =>
      TargetedGeometryRecipe(
        faces: {
          for (final entry in faces.entries)
            if (targetIds.contains(entry.key)) entry.key: entry.value,
        },
        bodies: {
          for (final entry in bodies.entries)
            if (targetIds.contains(entry.key)) entry.key: entry.value,
        },
      );

  PortraitGeometryRecipe project(
    EditTargetRegistry? registry, {
    int selectedFaceIndex = 0,
    int selectedBodyIndex = 0,
  }) {
    if (registry == null) return PortraitGeometryRecipe.neutral;
    final faceTargets = _activeTargets(registry, EditTargetKind.face)
        .map((target) => faces[target.id] ?? FaceGeometryTarget.neutral)
        .toList(growable: false);
    final bodyTargets = _activeTargets(registry, EditTargetKind.body)
        .map((target) => bodies[target.id] ?? BodyGeometryTarget.neutral)
        .toList(growable: false);
    return PortraitGeometryRecipe(
      faceTargets: faceTargets.isEmpty
          ? const [FaceGeometryTarget.neutral]
          : faceTargets,
      selectedFaceIndex: faceTargets.isEmpty
          ? 0
          : selectedFaceIndex.clamp(0, faceTargets.length - 1),
      bodyTargets: bodyTargets.isEmpty
          ? const [BodyGeometryTarget.neutral]
          : bodyTargets,
      selectedBodyIndex: bodyTargets.isEmpty
          ? 0
          : selectedBodyIndex.clamp(0, bodyTargets.length - 1),
    );
  }

  Map<String, Object> toJson() => {
    'schemaVersion': schemaVersion,
    'faces': [
      for (final entry in faces.entries)
        {'targetId': entry.key, ...entry.value.toJson()},
    ],
    'bodies': [
      for (final entry in bodies.entries)
        {'targetId': entry.key, ...entry.value.toJson()},
    ],
  };

  factory TargetedGeometryRecipe.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException('Invalid targeted geometry schema');
    }
    Map<String, T> decode<T>(
      String key,
      T Function(Map<String, Object?> json) decodeValue,
    ) {
      final raw = json[key];
      if (raw is! List) throw FormatException('Invalid targeted $key');
      final values = <String, T>{};
      for (final item in raw) {
        if (item is! Map) throw FormatException('Invalid targeted $key item');
        final map = Map<String, Object?>.from(item);
        final targetId = map.remove('targetId');
        if (targetId is! String || values.containsKey(targetId)) {
          throw FormatException('Invalid targeted $key target');
        }
        values[targetId] = decodeValue(map);
      }
      return values;
    }

    return TargetedGeometryRecipe(
      faces: decode('faces', FaceGeometryTarget.fromJson),
      bodies: decode('bodies', BodyGeometryTarget.fromJson),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TargetedGeometryRecipe &&
      mapEquals(other.faces, faces) &&
      mapEquals(other.bodies, bodies);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(
      faces.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    Object.hashAll(
      bodies.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );
}

List<StableEditTarget> _activeTargets(
  EditTargetRegistry registry,
  EditTargetKind kind,
) =>
    registry.targets.values
        .where(
          (target) =>
              target.kind == kind && target.status == EditTargetStatus.active,
        )
        .toList()
      ..sort((left, right) {
        final horizontal = left.region.left.compareTo(right.region.left);
        return horizontal != 0
            ? horizontal
            : left.region.top.compareTo(right.region.top);
      });
