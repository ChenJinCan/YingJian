import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';

@immutable
final class DirectionalLightingAdjustment {
  factory DirectionalLightingAdjustment({
    required String targetId,
    required NormalizedEditRegion region,
    double azimuth = 0,
    int intensity = 0,
  }) {
    if (!RegExp(r'^target-v1-[0-9a-f]{8}$').hasMatch(targetId)) {
      throw ArgumentError.value(targetId, 'targetId', 'Invalid target id');
    }
    if (!azimuth.isFinite || azimuth < -90 || azimuth > 90) {
      throw RangeError.range(azimuth, -90, 90, 'azimuth');
    }
    if (intensity < 0 || intensity > 100) {
      throw RangeError.range(intensity, 0, 100, 'intensity');
    }
    return DirectionalLightingAdjustment._(
      targetId: targetId,
      region: region,
      azimuth: azimuth,
      intensity: intensity,
    );
  }

  const DirectionalLightingAdjustment._({
    required this.targetId,
    required this.region,
    required this.azimuth,
    required this.intensity,
  });

  final String targetId;
  final NormalizedEditRegion region;
  final double azimuth;
  final int intensity;

  bool get isNeutral => intensity == 0;

  Map<String, Object> toJson() => {
    'targetId': targetId,
    'region': region.toJson(),
    'azimuth': azimuth,
    'intensity': intensity,
  };

  factory DirectionalLightingAdjustment.fromJson(Map<String, Object?> json) {
    final region = json['region'];
    final azimuth = json['azimuth'];
    final intensity = json['intensity'];
    if (json['targetId'] is! String ||
        region is! Map ||
        azimuth is! num ||
        intensity is! int) {
      throw const FormatException('Invalid directional lighting adjustment');
    }
    try {
      return DirectionalLightingAdjustment(
        targetId: json['targetId']! as String,
        region: NormalizedEditRegion.fromJson(
          Map<String, Object?>.from(region),
        ),
        azimuth: azimuth.toDouble(),
        intensity: intensity,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid directional lighting adjustment: $error');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DirectionalLightingAdjustment &&
      other.targetId == targetId &&
      other.region == region &&
      other.azimuth == azimuth &&
      other.intensity == intensity;

  @override
  int get hashCode => Object.hash(targetId, region, azimuth, intensity);
}

@immutable
final class DirectionalLightingRecipe {
  factory DirectionalLightingRecipe({
    Map<String, DirectionalLightingAdjustment> adjustments = const {},
  }) {
    if (adjustments.length > maximumTargetCount) {
      throw RangeError.range(
        adjustments.length,
        0,
        maximumTargetCount,
        'adjustments.length',
      );
    }
    final sorted = <String, DirectionalLightingAdjustment>{};
    final ids = adjustments.keys.toList()..sort();
    for (final id in ids) {
      final value = adjustments[id]!;
      if (id != value.targetId) {
        throw ArgumentError('Lighting map key must equal target id');
      }
      if (!value.isNeutral) sorted[id] = value;
    }
    return sorted.isEmpty
        ? neutral
        : DirectionalLightingRecipe._(Map.unmodifiable(sorted));
  }

  const DirectionalLightingRecipe._(this.adjustments);

  static const schemaVersion = 1;
  static const maximumTargetCount = 6;
  static const neutral = DirectionalLightingRecipe._({});

  final Map<String, DirectionalLightingAdjustment> adjustments;

  bool get isNeutral => adjustments.isEmpty;

  DirectionalLightingRecipe update({
    required String targetId,
    required NormalizedEditRegion region,
    required double azimuth,
    required int intensity,
  }) {
    final values = Map<String, DirectionalLightingAdjustment>.of(adjustments);
    final next = DirectionalLightingAdjustment(
      targetId: targetId,
      region: region,
      azimuth: azimuth,
      intensity: intensity,
    );
    if (next.isNeutral) {
      values.remove(targetId);
    } else {
      values[targetId] = next;
    }
    return DirectionalLightingRecipe(adjustments: values);
  }

  DirectionalLightingRecipe retainTargets(Set<String> targetIds) =>
      DirectionalLightingRecipe(
        adjustments: {
          for (final entry in adjustments.entries)
            if (targetIds.contains(entry.key)) entry.key: entry.value,
        },
      );

  Map<String, Object> toJson() => {
    'schemaVersion': schemaVersion,
    'adjustments': adjustments.values
        .map((value) => value.toJson())
        .toList(growable: false),
  };

  factory DirectionalLightingRecipe.fromJson(Map<String, Object?> json) {
    final raw = json['adjustments'];
    if (json['schemaVersion'] != schemaVersion || raw is! List) {
      throw const FormatException('Invalid directional lighting recipe');
    }
    final values = <String, DirectionalLightingAdjustment>{};
    for (final entry in raw) {
      if (entry is! Map) throw const FormatException('Invalid lighting entry');
      final value = DirectionalLightingAdjustment.fromJson(
        Map<String, Object?>.from(entry),
      );
      if (values.containsKey(value.targetId)) {
        throw const FormatException('Duplicate lighting target');
      }
      values[value.targetId] = value;
    }
    return DirectionalLightingRecipe(adjustments: values);
  }

  @override
  bool operator ==(Object other) =>
      other is DirectionalLightingRecipe &&
      mapEquals(other.adjustments, adjustments);

  @override
  int get hashCode => Object.hashAll(
    adjustments.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );
}
