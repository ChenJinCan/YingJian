import 'package:flutter/foundation.dart';

@immutable
final class CropGeometry {
  factory CropGeometry({
    double left = 0,
    double top = 0,
    double right = 1,
    double bottom = 1,
    int quarterTurns = 0,
    double straightenDegrees = 0,
  }) {
    for (final entry in <String, double>{
      'left': left,
      'top': top,
      'right': right,
      'bottom': bottom,
    }.entries) {
      if (!entry.value.isFinite || entry.value < 0 || entry.value > 1) {
        throw RangeError.range(entry.value, 0, 1, entry.key);
      }
    }
    if (right <= left) {
      throw RangeError.value(right, 'right', 'Must be greater than left');
    }
    if (bottom <= top) {
      throw RangeError.value(bottom, 'bottom', 'Must be greater than top');
    }
    if (quarterTurns < 0 || quarterTurns > 3) {
      throw RangeError.range(quarterTurns, 0, 3, 'quarterTurns');
    }
    if (!straightenDegrees.isFinite ||
        straightenDegrees < -45 ||
        straightenDegrees > 45) {
      throw RangeError.range(straightenDegrees, -45, 45, 'straightenDegrees');
    }
    return CropGeometry._(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      quarterTurns: quarterTurns,
      straightenDegrees: straightenDegrees,
    );
  }

  const CropGeometry._({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.quarterTurns,
    required this.straightenDegrees,
  });

  static const original = CropGeometry._(
    left: 0,
    top: 0,
    right: 1,
    bottom: 1,
    quarterTurns: 0,
    straightenDegrees: 0,
  );

  final double left;
  final double top;
  final double right;
  final double bottom;
  final int quarterTurns;
  final double straightenDegrees;

  bool get isOriginal => this == original;

  bool hasSameOutputDimensions(CropGeometry other) {
    return right - left == other.right - other.left &&
        bottom - top == other.bottom - other.top &&
        quarterTurns.isOdd == other.quarterTurns.isOdd;
  }

  CropGeometry centeredForAspect({
    required int sourceWidth,
    required int sourceHeight,
    required double targetAspectRatio,
  }) {
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      throw RangeError('Source dimensions must be positive');
    }
    if (!targetAspectRatio.isFinite || targetAspectRatio <= 0) {
      throw RangeError.value(targetAspectRatio, 'targetAspectRatio');
    }
    final sourceAspectRatio = sourceWidth / sourceHeight;
    final preRotationTarget = quarterTurns.isOdd
        ? 1 / targetAspectRatio
        : targetAspectRatio;
    if (sourceAspectRatio > preRotationTarget) {
      final normalizedWidth = preRotationTarget / sourceAspectRatio;
      final inset = (1 - normalizedWidth) / 2;
      return copyWith(left: inset, top: 0, right: 1 - inset, bottom: 1);
    }
    final normalizedHeight = sourceAspectRatio / preRotationTarget;
    final inset = (1 - normalizedHeight) / 2;
    return copyWith(left: 0, top: inset, right: 1, bottom: 1 - inset);
  }

  Map<String, Object> toJson() => <String, Object>{
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
    'quarterTurns': quarterTurns,
    'straightenDegrees': straightenDegrees,
  };

  factory CropGeometry.fromJson(Map<String, Object?> json) => CropGeometry(
    left: (json['left'] as num?)?.toDouble() ?? 0,
    top: (json['top'] as num?)?.toDouble() ?? 0,
    right: (json['right'] as num?)?.toDouble() ?? 1,
    bottom: (json['bottom'] as num?)?.toDouble() ?? 1,
    quarterTurns: (json['quarterTurns'] as num?)?.toInt() ?? 0,
    straightenDegrees: (json['straightenDegrees'] as num?)?.toDouble() ?? 0,
  );

  CropGeometry copyWith({
    double? left,
    double? top,
    double? right,
    double? bottom,
    int? quarterTurns,
    double? straightenDegrees,
  }) => CropGeometry(
    left: left ?? this.left,
    top: top ?? this.top,
    right: right ?? this.right,
    bottom: bottom ?? this.bottom,
    quarterTurns: quarterTurns ?? this.quarterTurns,
    straightenDegrees: straightenDegrees ?? this.straightenDegrees,
  );

  @override
  bool operator ==(Object other) =>
      other is CropGeometry &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.quarterTurns == quarterTurns &&
      other.straightenDegrees == straightenDegrees;

  @override
  int get hashCode =>
      Object.hash(left, top, right, bottom, quarterTurns, straightenDegrees);
}

@immutable
class EditRecipe {
  factory EditRecipe({
    double exposure = 0,
    double highlights = 0,
    double shadows = 0,
    double contrast = 0,
    double warmth = 0,
    double tint = 0,
    double saturation = 0,
    double clarity = 0,
    double portraitStrength = 0,
    CropGeometry crop = CropGeometry.original,
  }) {
    for (final entry in <String, double>{
      'exposure': exposure,
      'highlights': highlights,
      'shadows': shadows,
      'contrast': contrast,
      'warmth': warmth,
      'tint': tint,
      'saturation': saturation,
      'clarity': clarity,
    }.entries) {
      _validate(entry.value, entry.key);
    }
    _validate(portraitStrength, 'portraitStrength', minimum: 0);
    return EditRecipe._(
      exposure: exposure,
      highlights: highlights,
      shadows: shadows,
      contrast: contrast,
      warmth: warmth,
      tint: tint,
      saturation: saturation,
      clarity: clarity,
      portraitStrength: portraitStrength,
      crop: crop,
    );
  }

  const EditRecipe._({
    required this.exposure,
    required this.highlights,
    required this.shadows,
    required this.contrast,
    required this.warmth,
    required this.tint,
    required this.saturation,
    required this.clarity,
    required this.portraitStrength,
    required this.crop,
  });

  static final neutral = EditRecipe();

  final double exposure;
  final double highlights;
  final double shadows;
  final double contrast;
  final double warmth;
  final double tint;
  final double saturation;
  final double clarity;
  final double portraitStrength;
  final CropGeometry crop;

  bool get isLegacyColorOnly =>
      highlights == 0 &&
      shadows == 0 &&
      tint == 0 &&
      saturation == 0 &&
      clarity == 0 &&
      portraitStrength == 0 &&
      crop.isOriginal;

  bool get hasColorAdjustments =>
      exposure != 0 ||
      highlights != 0 ||
      shadows != 0 ||
      contrast != 0 ||
      warmth != 0 ||
      tint != 0 ||
      saturation != 0 ||
      clarity != 0;

  Map<String, Object> toJson() => <String, Object>{
    'exposure': exposure,
    'highlights': highlights,
    'shadows': shadows,
    'contrast': contrast,
    'warmth': warmth,
    'tint': tint,
    'saturation': saturation,
    'clarity': clarity,
    'portraitStrength': portraitStrength,
    'crop': crop.toJson(),
  };

  factory EditRecipe.fromJson(Map<String, Object?> json) => EditRecipe(
    exposure: (json['exposure'] as num?)?.toDouble() ?? 0,
    highlights: (json['highlights'] as num?)?.toDouble() ?? 0,
    shadows: (json['shadows'] as num?)?.toDouble() ?? 0,
    contrast: (json['contrast'] as num?)?.toDouble() ?? 0,
    warmth: (json['warmth'] as num?)?.toDouble() ?? 0,
    tint: (json['tint'] as num?)?.toDouble() ?? 0,
    saturation: (json['saturation'] as num?)?.toDouble() ?? 0,
    clarity: (json['clarity'] as num?)?.toDouble() ?? 0,
    portraitStrength: (json['portraitStrength'] as num?)?.toDouble() ?? 0,
    crop: json['crop'] is Map<String, Object?>
        ? CropGeometry.fromJson(json['crop']! as Map<String, Object?>)
        : CropGeometry.original,
  );

  EditRecipe copyWith({
    double? exposure,
    double? highlights,
    double? shadows,
    double? contrast,
    double? warmth,
    double? tint,
    double? saturation,
    double? clarity,
    double? portraitStrength,
    CropGeometry? crop,
  }) => EditRecipe(
    exposure: exposure ?? this.exposure,
    highlights: highlights ?? this.highlights,
    shadows: shadows ?? this.shadows,
    contrast: contrast ?? this.contrast,
    warmth: warmth ?? this.warmth,
    tint: tint ?? this.tint,
    saturation: saturation ?? this.saturation,
    clarity: clarity ?? this.clarity,
    portraitStrength: portraitStrength ?? this.portraitStrength,
    crop: crop ?? this.crop,
  );

  static void _validate(double value, String name, {double minimum = -1}) {
    if (!value.isFinite || value < minimum || value > 1) {
      throw RangeError.value(value, name, 'Must be between $minimum and 1');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is EditRecipe &&
      other.exposure == exposure &&
      other.highlights == highlights &&
      other.shadows == shadows &&
      other.contrast == contrast &&
      other.warmth == warmth &&
      other.tint == tint &&
      other.saturation == saturation &&
      other.clarity == clarity &&
      other.portraitStrength == portraitStrength &&
      other.crop == crop;

  @override
  int get hashCode => Object.hash(
    exposure,
    highlights,
    shadows,
    contrast,
    warmth,
    tint,
    saturation,
    clarity,
    portraitStrength,
    crop,
  );
}
