import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';

enum TargetedPortraitParameter {
  textureSmoothing,
  skinToneLighting,
  blemishReduction,
}

@immutable
final class TargetedPortraitAdjustment {
  factory TargetedPortraitAdjustment({
    required String targetId,
    required NormalizedEditRegion region,
    int textureSmoothing = 0,
    int skinToneLighting = 0,
    int blemishReduction = 0,
  }) {
    if (!RegExp(r'^target-v1-[0-9a-f]{8}$').hasMatch(targetId)) {
      throw ArgumentError.value(targetId, 'targetId', 'Invalid target id');
    }
    for (final entry in {
      'textureSmoothing': textureSmoothing,
      'skinToneLighting': skinToneLighting,
      'blemishReduction': blemishReduction,
    }.entries) {
      if (entry.value < 0 || entry.value > 100) {
        throw RangeError.range(entry.value, 0, 100, entry.key);
      }
    }
    return TargetedPortraitAdjustment._(
      targetId: targetId,
      region: region,
      textureSmoothing: textureSmoothing,
      skinToneLighting: skinToneLighting,
      blemishReduction: blemishReduction,
    );
  }

  const TargetedPortraitAdjustment._({
    required this.targetId,
    required this.region,
    required this.textureSmoothing,
    required this.skinToneLighting,
    required this.blemishReduction,
  });

  final String targetId;
  final NormalizedEditRegion region;
  final int textureSmoothing;
  final int skinToneLighting;
  final int blemishReduction;

  bool get isNeutral =>
      textureSmoothing == 0 && skinToneLighting == 0 && blemishReduction == 0;

  TargetedPortraitAdjustment update(
    TargetedPortraitParameter parameter,
    int value, {
    required NormalizedEditRegion region,
  }) => TargetedPortraitAdjustment(
    targetId: targetId,
    region: region,
    textureSmoothing: parameter == TargetedPortraitParameter.textureSmoothing
        ? value
        : textureSmoothing,
    skinToneLighting: parameter == TargetedPortraitParameter.skinToneLighting
        ? value
        : skinToneLighting,
    blemishReduction: parameter == TargetedPortraitParameter.blemishReduction
        ? value
        : blemishReduction,
  );

  Map<String, Object> toJson() => {
    'targetId': targetId,
    'region': region.toJson(),
    'textureSmoothing': textureSmoothing,
    'skinToneLighting': skinToneLighting,
    'blemishReduction': blemishReduction,
  };

  factory TargetedPortraitAdjustment.fromJson(Map<String, Object?> json) {
    int value(String key) {
      final raw = json[key];
      if (raw is! int) throw FormatException('Invalid targeted $key');
      return raw;
    }

    final region = json['region'];
    if (json['targetId'] is! String || region is! Map) {
      throw const FormatException('Invalid targeted portrait adjustment');
    }
    try {
      return TargetedPortraitAdjustment(
        targetId: json['targetId']! as String,
        region: NormalizedEditRegion.fromJson(
          Map<String, Object?>.from(region),
        ),
        textureSmoothing: value('textureSmoothing'),
        skinToneLighting: value('skinToneLighting'),
        blemishReduction: value('blemishReduction'),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid targeted portrait adjustment: $error');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TargetedPortraitAdjustment &&
      other.targetId == targetId &&
      other.region == region &&
      other.textureSmoothing == textureSmoothing &&
      other.skinToneLighting == skinToneLighting &&
      other.blemishReduction == blemishReduction;

  @override
  int get hashCode => Object.hash(
    targetId,
    region,
    textureSmoothing,
    skinToneLighting,
    blemishReduction,
  );
}

@immutable
final class TargetedPortraitRecipe {
  factory TargetedPortraitRecipe({
    Map<String, TargetedPortraitAdjustment> adjustments = const {},
  }) {
    if (adjustments.length > maximumTargetCount) {
      throw RangeError.range(
        adjustments.length,
        0,
        maximumTargetCount,
        'adjustments.length',
      );
    }
    final sorted = <String, TargetedPortraitAdjustment>{};
    final ids = adjustments.keys.toList()..sort();
    for (final id in ids) {
      final adjustment = adjustments[id]!;
      if (id != adjustment.targetId) {
        throw ArgumentError.value(
          adjustment,
          'adjustments',
          'Map key must equal target id',
        );
      }
      if (!adjustment.isNeutral) sorted[id] = adjustment;
    }
    return sorted.isEmpty
        ? neutral
        : TargetedPortraitRecipe._(Map.unmodifiable(sorted));
  }

  const TargetedPortraitRecipe._(this.adjustments);

  static const schemaVersion = 1;
  static const maximumTargetCount = 6;
  static const neutral = TargetedPortraitRecipe._({});

  final Map<String, TargetedPortraitAdjustment> adjustments;

  bool get isNeutral => adjustments.isEmpty;

  TargetedPortraitRecipe update({
    required String targetId,
    required NormalizedEditRegion region,
    required TargetedPortraitParameter parameter,
    required int value,
  }) {
    final current =
        adjustments[targetId] ??
        TargetedPortraitAdjustment(targetId: targetId, region: region);
    final next = current.update(parameter, value, region: region);
    final values = Map<String, TargetedPortraitAdjustment>.of(adjustments);
    if (next.isNeutral) {
      values.remove(targetId);
    } else {
      values[targetId] = next;
    }
    return TargetedPortraitRecipe(adjustments: values);
  }

  TargetedPortraitRecipe retainTargets(Set<String> targetIds) =>
      TargetedPortraitRecipe(
        adjustments: {
          for (final entry in adjustments.entries)
            if (targetIds.contains(entry.key)) entry.key: entry.value,
        },
      );

  Map<String, Object> toJson() => {
    'schemaVersion': schemaVersion,
    'adjustments': adjustments.values
        .map((adjustment) => adjustment.toJson())
        .toList(growable: false),
  };

  factory TargetedPortraitRecipe.fromJson(Map<String, Object?> json) {
    final raw = json['adjustments'];
    if (json['schemaVersion'] != schemaVersion || raw is! List) {
      throw const FormatException('Invalid targeted portrait recipe');
    }
    final adjustments = <String, TargetedPortraitAdjustment>{};
    for (final value in raw) {
      if (value is! Map) {
        throw const FormatException('Invalid targeted portrait entry');
      }
      final adjustment = TargetedPortraitAdjustment.fromJson(
        Map<String, Object?>.from(value),
      );
      if (adjustments.containsKey(adjustment.targetId)) {
        throw const FormatException('Duplicate targeted portrait id');
      }
      adjustments[adjustment.targetId] = adjustment;
    }
    return TargetedPortraitRecipe(adjustments: adjustments);
  }

  @override
  bool operator ==(Object other) =>
      other is TargetedPortraitRecipe &&
      mapEquals(other.adjustments, adjustments);

  @override
  int get hashCode => Object.hashAll(
    adjustments.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );
}
