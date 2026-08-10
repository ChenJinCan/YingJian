import 'dart:math';

import 'package:flutter/foundation.dart';

@immutable
final class FaceGeometryTarget {
  factory FaceGeometryTarget({
    double faceSlim = 0,
    double headSize = 0,
    double jaw = 0,
    double chin = 0,
    double eyes = 0,
    double nose = 0,
    double mouth = 0,
  }) {
    _bounded(faceSlim, 0, 100, 'faceSlim');
    _bounded(headSize, 0, 100, 'headSize');
    for (final entry in {
      'jaw': jaw,
      'chin': chin,
      'eyes': eyes,
      'nose': nose,
      'mouth': mouth,
    }.entries) {
      _bounded(entry.value, -100, 100, entry.key);
    }
    return FaceGeometryTarget._(
      faceSlim: faceSlim,
      headSize: headSize,
      jaw: jaw,
      chin: chin,
      eyes: eyes,
      nose: nose,
      mouth: mouth,
    );
  }

  const FaceGeometryTarget._({
    required this.faceSlim,
    required this.headSize,
    required this.jaw,
    required this.chin,
    required this.eyes,
    required this.nose,
    required this.mouth,
  });

  static const neutral = FaceGeometryTarget._(
    faceSlim: 0,
    headSize: 0,
    jaw: 0,
    chin: 0,
    eyes: 0,
    nose: 0,
    mouth: 0,
  );

  final double faceSlim;
  final double headSize;
  final double jaw;
  final double chin;
  final double eyes;
  final double nose;
  final double mouth;
  bool get isNeutral => this == neutral;

  FaceGeometryTarget copyWith({
    double? faceSlim,
    double? headSize,
    double? jaw,
    double? chin,
    double? eyes,
    double? nose,
    double? mouth,
  }) => FaceGeometryTarget(
    faceSlim: faceSlim ?? this.faceSlim,
    headSize: headSize ?? this.headSize,
    jaw: jaw ?? this.jaw,
    chin: chin ?? this.chin,
    eyes: eyes ?? this.eyes,
    nose: nose ?? this.nose,
    mouth: mouth ?? this.mouth,
  );

  Map<String, Object> toJson() => {
    'faceSlim': faceSlim,
    'headSize': headSize,
    'jaw': jaw,
    'chin': chin,
    'eyes': eyes,
    'nose': nose,
    'mouth': mouth,
  };

  factory FaceGeometryTarget.fromJson(Map<String, Object?> json) =>
      FaceGeometryTarget(
        faceSlim: (json['faceSlim'] as num?)?.toDouble() ?? 0,
        headSize: (json['headSize'] as num?)?.toDouble() ?? 0,
        jaw: (json['jaw'] as num?)?.toDouble() ?? 0,
        chin: (json['chin'] as num?)?.toDouble() ?? 0,
        eyes: (json['eyes'] as num?)?.toDouble() ?? 0,
        nose: (json['nose'] as num?)?.toDouble() ?? 0,
        mouth: (json['mouth'] as num?)?.toDouble() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is FaceGeometryTarget &&
      other.faceSlim == faceSlim &&
      other.headSize == headSize &&
      other.jaw == jaw &&
      other.chin == chin &&
      other.eyes == eyes &&
      other.nose == nose &&
      other.mouth == mouth;

  @override
  int get hashCode =>
      Object.hash(faceSlim, headSize, jaw, chin, eyes, nose, mouth);
}

@immutable
final class BodyGeometryTarget {
  factory BodyGeometryTarget({
    double slimming = 0,
    double height = 0,
    double shoulders = 0,
    double waist = 0,
    double legs = 0,
  }) {
    _bounded(slimming, 0, 100, 'slimming');
    _bounded(height, 0, 100, 'height');
    _bounded(legs, 0, 100, 'legs');
    _bounded(shoulders, -100, 100, 'shoulders');
    _bounded(waist, -100, 100, 'waist');
    return BodyGeometryTarget._(
      slimming: slimming,
      height: height,
      shoulders: shoulders,
      waist: waist,
      legs: legs,
    );
  }

  const BodyGeometryTarget._({
    required this.slimming,
    required this.height,
    required this.shoulders,
    required this.waist,
    required this.legs,
  });

  static const neutral = BodyGeometryTarget._(
    slimming: 0,
    height: 0,
    shoulders: 0,
    waist: 0,
    legs: 0,
  );

  final double slimming;
  final double height;
  final double shoulders;
  final double waist;
  final double legs;
  bool get isNeutral => this == neutral;

  BodyGeometryTarget copyWith({
    double? slimming,
    double? height,
    double? shoulders,
    double? waist,
    double? legs,
  }) => BodyGeometryTarget(
    slimming: slimming ?? this.slimming,
    height: height ?? this.height,
    shoulders: shoulders ?? this.shoulders,
    waist: waist ?? this.waist,
    legs: legs ?? this.legs,
  );

  Map<String, Object> toJson() => {
    'slimming': slimming,
    'height': height,
    'shoulders': shoulders,
    'waist': waist,
    'legs': legs,
  };

  factory BodyGeometryTarget.fromJson(Map<String, Object?> json) =>
      BodyGeometryTarget(
        slimming: (json['slimming'] as num?)?.toDouble() ?? 0,
        height: (json['height'] as num?)?.toDouble() ?? 0,
        shoulders: (json['shoulders'] as num?)?.toDouble() ?? 0,
        waist: (json['waist'] as num?)?.toDouble() ?? 0,
        legs: (json['legs'] as num?)?.toDouble() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is BodyGeometryTarget &&
      other.slimming == slimming &&
      other.height == height &&
      other.shoulders == shoulders &&
      other.waist == waist &&
      other.legs == legs;

  @override
  int get hashCode => Object.hash(slimming, height, shoulders, waist, legs);
}

@immutable
final class PortraitGeometryRecipe {
  factory PortraitGeometryRecipe({
    List<FaceGeometryTarget> faceTargets = const [FaceGeometryTarget.neutral],
    int selectedFaceIndex = 0,
    List<BodyGeometryTarget> bodyTargets = const [BodyGeometryTarget.neutral],
    int selectedBodyIndex = 0,
  }) {
    _validateTargets(faceTargets.length, selectedFaceIndex, 'faceTargets');
    _validateTargets(bodyTargets.length, selectedBodyIndex, 'bodyTargets');
    return PortraitGeometryRecipe._(
      faceTargets: List.unmodifiable(faceTargets),
      selectedFaceIndex: selectedFaceIndex,
      bodyTargets: List.unmodifiable(bodyTargets),
      selectedBodyIndex: selectedBodyIndex,
    );
  }

  const PortraitGeometryRecipe._({
    required this.faceTargets,
    required this.selectedFaceIndex,
    required this.bodyTargets,
    required this.selectedBodyIndex,
  });

  static const recipeVersion = 1;
  static const maximumTargetCount = 3;
  static const neutral = PortraitGeometryRecipe._(
    faceTargets: [FaceGeometryTarget.neutral],
    selectedFaceIndex: 0,
    bodyTargets: [BodyGeometryTarget.neutral],
    selectedBodyIndex: 0,
  );

  final List<FaceGeometryTarget> faceTargets;
  final int selectedFaceIndex;
  final List<BodyGeometryTarget> bodyTargets;
  final int selectedBodyIndex;
  bool get isNeutral =>
      faceTargets.every((target) => target.isNeutral) &&
      bodyTargets.every((target) => target.isNeutral);

  PortraitGeometryRecipe selectFace(int index) =>
      copyWith(selectedFaceIndex: index);
  PortraitGeometryRecipe selectBody(int index) =>
      copyWith(selectedBodyIndex: index);

  PortraitGeometryRecipe updateSelectedFace(
    FaceGeometryTarget Function(FaceGeometryTarget target) update,
  ) {
    final targets = faceTargets.toList();
    targets[selectedFaceIndex] = update(targets[selectedFaceIndex]);
    return copyWith(faceTargets: targets);
  }

  PortraitGeometryRecipe updateSelectedBody(
    BodyGeometryTarget Function(BodyGeometryTarget target) update,
  ) {
    final targets = bodyTargets.toList();
    targets[selectedBodyIndex] = update(targets[selectedBodyIndex]);
    return copyWith(bodyTargets: targets);
  }

  PortraitGeometryRecipe withFaceTargetCount(int count) => copyWith(
    faceTargets: _resize(faceTargets, count, FaceGeometryTarget.neutral),
    selectedFaceIndex: selectedFaceIndex.clamp(0, count - 1),
  );

  PortraitGeometryRecipe withBodyTargetCount(int count) => copyWith(
    bodyTargets: _resize(bodyTargets, count, BodyGeometryTarget.neutral),
    selectedBodyIndex: selectedBodyIndex.clamp(0, count - 1),
  );

  PortraitGeometryRecipe copyWith({
    List<FaceGeometryTarget>? faceTargets,
    int? selectedFaceIndex,
    List<BodyGeometryTarget>? bodyTargets,
    int? selectedBodyIndex,
  }) => PortraitGeometryRecipe(
    faceTargets: faceTargets ?? this.faceTargets,
    selectedFaceIndex: selectedFaceIndex ?? this.selectedFaceIndex,
    bodyTargets: bodyTargets ?? this.bodyTargets,
    selectedBodyIndex: selectedBodyIndex ?? this.selectedBodyIndex,
  );

  Map<String, Object> toJson() => {
    'recipeVersion': recipeVersion,
    'selectedFaceIndex': selectedFaceIndex,
    'faceTargets': faceTargets.map((target) => target.toJson()).toList(),
    'selectedBodyIndex': selectedBodyIndex,
    'bodyTargets': bodyTargets.map((target) => target.toJson()).toList(),
  };

  factory PortraitGeometryRecipe.fromJson(Map<String, Object?> json) {
    if (json['recipeVersion'] != recipeVersion ||
        json['faceTargets'] is! List ||
        json['bodyTargets'] is! List ||
        json['selectedFaceIndex'] is! int ||
        json['selectedBodyIndex'] is! int) {
      throw const FormatException('Invalid portrait geometry recipe');
    }
    try {
      return PortraitGeometryRecipe(
        faceTargets: (json['faceTargets']! as List)
            .map(
              (value) => FaceGeometryTarget.fromJson(
                Map<String, Object?>.from(value as Map),
              ),
            )
            .toList(),
        selectedFaceIndex: json['selectedFaceIndex']! as int,
        bodyTargets: (json['bodyTargets']! as List)
            .map(
              (value) => BodyGeometryTarget.fromJson(
                Map<String, Object?>.from(value as Map),
              ),
            )
            .toList(),
        selectedBodyIndex: json['selectedBodyIndex']! as int,
      );
    } on Object catch (error) {
      throw FormatException('Invalid portrait geometry recipe: $error');
    }
  }

  static PortraitGeometryRecipe migrateLegacy({
    required List<double> faceSlimStrengths,
    required int selectedFaceIndex,
    required double bodySlimStrength,
  }) => PortraitGeometryRecipe(
    faceTargets: faceSlimStrengths
        .map((value) => FaceGeometryTarget(faceSlim: value * 100))
        .toList(),
    selectedFaceIndex: selectedFaceIndex,
    bodyTargets: [BodyGeometryTarget(slimming: bodySlimStrength * 100)],
  );

  static List<T> _resize<T>(List<T> current, int count, T neutral) {
    if (count < 1 || count > maximumTargetCount) {
      throw RangeError.range(count, 1, maximumTargetCount, 'count');
    }
    return [
      ...current.take(count),
      ...List.filled(max(0, count - current.length), neutral),
    ];
  }

  static void _validateTargets(int count, int selected, String name) {
    if (count < 1 || count > maximumTargetCount) {
      throw RangeError.range(count, 1, maximumTargetCount, '$name.length');
    }
    if (selected < 0 || selected >= count) {
      throw RangeError.range(selected, 0, count - 1, 'selectedIndex');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PortraitGeometryRecipe &&
      other.selectedFaceIndex == selectedFaceIndex &&
      other.selectedBodyIndex == selectedBodyIndex &&
      listEquals(other.faceTargets, faceTargets) &&
      listEquals(other.bodyTargets, bodyTargets);

  @override
  int get hashCode => Object.hash(
    selectedFaceIndex,
    Object.hashAll(faceTargets),
    selectedBodyIndex,
    Object.hashAll(bodyTargets),
  );
}

void _bounded(double value, double minimum, double maximum, String name) {
  if (!value.isFinite || value < minimum || value > maximum) {
    throw RangeError.value(
      value,
      name,
      'Must be between $minimum and $maximum',
    );
  }
}
