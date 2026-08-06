import 'package:flutter/foundation.dart';

@immutable
final class FaceSlimRecipe {
  factory FaceSlimRecipe({
    List<double> targetStrengths = const [0],
    int selectedTargetIndex = 0,
  }) {
    if (targetStrengths.isEmpty ||
        targetStrengths.length > maximumTargetCount) {
      throw RangeError.range(
        targetStrengths.length,
        1,
        maximumTargetCount,
        'targetStrengths.length',
      );
    }
    for (final strength in targetStrengths) {
      if (!strength.isFinite) {
        throw ArgumentError.value(strength, 'targetStrengths');
      }
      if (strength < 0 || strength > 1) {
        throw RangeError.range(strength, 0, 1, 'targetStrengths');
      }
    }
    if (selectedTargetIndex < 0 ||
        selectedTargetIndex >= targetStrengths.length) {
      throw RangeError.range(
        selectedTargetIndex,
        0,
        targetStrengths.length - 1,
        'selectedTargetIndex',
      );
    }
    return FaceSlimRecipe._(
      targetStrengths: List<double>.unmodifiable(targetStrengths),
      selectedTargetIndex: selectedTargetIndex,
    );
  }

  const FaceSlimRecipe._({
    required this.targetStrengths,
    required this.selectedTargetIndex,
  });

  static const recipeVersion = 1;
  static const maximumTargetCount = 3;
  static const neutral = FaceSlimRecipe._(
    targetStrengths: <double>[0],
    selectedTargetIndex: 0,
  );

  final List<double> targetStrengths;
  final int selectedTargetIndex;

  double get selectedStrength => targetStrengths[selectedTargetIndex];
  bool get isNeutral => targetStrengths.every((value) => value == 0);

  FaceSlimRecipe selectTarget(int index) => FaceSlimRecipe(
    targetStrengths: targetStrengths,
    selectedTargetIndex: index,
  );

  FaceSlimRecipe setSelectedStrength(double strength) {
    final next = targetStrengths.toList();
    next[selectedTargetIndex] = strength;
    return FaceSlimRecipe(
      targetStrengths: next,
      selectedTargetIndex: selectedTargetIndex,
    );
  }

  FaceSlimRecipe withTargetCount(int count) {
    if (count < 1 || count > maximumTargetCount) {
      throw RangeError.range(count, 1, maximumTargetCount, 'count');
    }
    final next = <double>[
      ...targetStrengths.take(count),
      ...List<double>.filled(
        (count - targetStrengths.length).clamp(0, count),
        0,
      ),
    ];
    return FaceSlimRecipe(
      targetStrengths: next,
      selectedTargetIndex: selectedTargetIndex.clamp(0, count - 1),
    );
  }

  Map<String, Object> toJson() => {
    'recipeVersion': recipeVersion,
    'selectedTargetIndex': selectedTargetIndex,
    'targetStrengths': targetStrengths,
  };

  factory FaceSlimRecipe.fromJson(Map<String, Object?> json) {
    if (json.keys.toSet().difference({
          'recipeVersion',
          'selectedTargetIndex',
          'targetStrengths',
        }).isNotEmpty ||
        json['recipeVersion'] != recipeVersion ||
        json['selectedTargetIndex'] is! int ||
        json['targetStrengths'] is! List) {
      throw const FormatException('Invalid face slim recipe');
    }
    final raw = json['targetStrengths']! as List;
    if (raw.any((value) => value is! num || value is bool)) {
      throw const FormatException('Invalid face slim target strength');
    }
    try {
      return FaceSlimRecipe(
        targetStrengths: raw
            .cast<num>()
            .map((value) => value.toDouble())
            .toList(),
        selectedTargetIndex: json['selectedTargetIndex']! as int,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid face slim recipe: $error');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is FaceSlimRecipe &&
      other.selectedTargetIndex == selectedTargetIndex &&
      listEquals(other.targetStrengths, targetStrengths);

  @override
  int get hashCode =>
      Object.hash(selectedTargetIndex, Object.hashAll(targetStrengths));
}
