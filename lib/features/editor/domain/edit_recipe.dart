import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/face_slim_recipe.dart';
import 'package:yingjian/features/editor/domain/portrait_retouch_recipe.dart';
import 'package:yingjian/features/editor/domain/portrait_geometry_recipe.dart';
import 'package:yingjian/features/editor/domain/quality_enhancement_recipe.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';

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
    double faceSlimStrength = 0,
    FaceSlimRecipe? faceSlimRecipe,
    double bodySlimStrength = 0,
    PortraitRetouchRecipe? portraitRecipe,
    QualityEnhancementRecipe qualityEnhancementRecipe =
        QualityEnhancementRecipe.neutral,
    BasicEditingRecipe basicEditingRecipe = BasicEditingRecipe.neutral,
    PortraitGeometryRecipe? portraitGeometryRecipe,
    SemanticEditingRecipe semanticEditingRecipe = SemanticEditingRecipe.neutral,
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
    _validate(faceSlimStrength, 'faceSlimStrength', minimum: 0);
    _validate(bodySlimStrength, 'bodySlimStrength', minimum: 0);
    final legacyFaceSlimRecipe =
        faceSlimRecipe ??
        FaceSlimRecipe(targetStrengths: <double>[faceSlimStrength]);
    final resolvedPortraitGeometryRecipe =
        portraitGeometryRecipe ??
        PortraitGeometryRecipe.migrateLegacy(
          faceSlimStrengths: legacyFaceSlimRecipe.targetStrengths,
          selectedFaceIndex: legacyFaceSlimRecipe.selectedTargetIndex,
          bodySlimStrength: bodySlimStrength,
        );
    final resolvedFaceSlimRecipe =
        faceSlimRecipe != null || portraitGeometryRecipe == null
        ? legacyFaceSlimRecipe
        : FaceSlimRecipe(
            targetStrengths: resolvedPortraitGeometryRecipe.faceTargets
                .map((target) => target.faceSlim / 100)
                .toList(),
            selectedTargetIndex:
                resolvedPortraitGeometryRecipe.selectedFaceIndex,
          );
    final resolvedBodySlimStrength = portraitGeometryRecipe == null
        ? bodySlimStrength
        : resolvedPortraitGeometryRecipe
                  .bodyTargets[resolvedPortraitGeometryRecipe.selectedBodyIndex]
                  .slimming /
              100;
    final resolvedPortraitRecipe =
        portraitRecipe ??
        PortraitRetouchRecipe.migrateLegacy(
          portraitStrength: portraitStrength,
          faceSlimStrength: resolvedFaceSlimRecipe.selectedStrength,
          bodySlimStrength: resolvedBodySlimStrength,
        );
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
      faceSlimRecipe: resolvedFaceSlimRecipe,
      bodySlimStrength: resolvedBodySlimStrength,
      portraitRecipe: resolvedPortraitRecipe,
      qualityEnhancementRecipe: qualityEnhancementRecipe,
      basicEditingRecipe: basicEditingRecipe,
      portraitGeometryRecipe: resolvedPortraitGeometryRecipe,
      semanticEditingRecipe: semanticEditingRecipe,
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
    required this.faceSlimRecipe,
    required this.bodySlimStrength,
    required this.portraitRecipe,
    required this.qualityEnhancementRecipe,
    required this.basicEditingRecipe,
    required this.portraitGeometryRecipe,
    required this.semanticEditingRecipe,
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
  final FaceSlimRecipe faceSlimRecipe;
  double get faceSlimStrength => faceSlimRecipe.selectedStrength;
  final double bodySlimStrength;
  final PortraitRetouchRecipe portraitRecipe;
  final QualityEnhancementRecipe qualityEnhancementRecipe;
  final BasicEditingRecipe basicEditingRecipe;
  final PortraitGeometryRecipe portraitGeometryRecipe;
  final SemanticEditingRecipe semanticEditingRecipe;
  final CropGeometry crop;

  bool get isLegacyColorOnly =>
      highlights == 0 &&
      shadows == 0 &&
      tint == 0 &&
      saturation == 0 &&
      clarity == 0 &&
      portraitStrength == 0 &&
      faceSlimRecipe.isNeutral &&
      bodySlimStrength == 0 &&
      portraitRecipe.isNeutral &&
      qualityEnhancementRecipe.isNeutral &&
      basicEditingRecipe.isNeutral &&
      portraitGeometryRecipe.isNeutral &&
      semanticEditingRecipe.isNeutral &&
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
    'faceSlimStrength': faceSlimStrength,
    'faceSlimRecipe': faceSlimRecipe.toJson(),
    'bodySlimStrength': bodySlimStrength,
    'portraitRecipe': portraitRecipe.toJson(),
    'qualityEnhancementRecipe': qualityEnhancementRecipe.toJson(),
    'basicEditingRecipe': basicEditingRecipe.toJson(),
    'portraitGeometryRecipe': portraitGeometryRecipe.toJson(),
    'semanticEditingRecipe': semanticEditingRecipe.toJson(),
    'crop': crop.toJson(),
  };

  factory EditRecipe.fromJson(Map<String, Object?> json) {
    final portraitStrength =
        (json['portraitStrength'] as num?)?.toDouble() ?? 0;
    final faceSlimStrength =
        (json['faceSlimStrength'] as num?)?.toDouble() ?? 0;
    final rawFaceSlimRecipe = json['faceSlimRecipe'];
    final faceSlimRecipe = rawFaceSlimRecipe == null
        ? null
        : rawFaceSlimRecipe is Map
        ? FaceSlimRecipe.fromJson(Map<String, Object?>.from(rawFaceSlimRecipe))
        : throw const FormatException('Invalid face slim recipe payload');
    final bodySlimStrength =
        (json['bodySlimStrength'] as num?)?.toDouble() ?? 0;
    final rawPortraitRecipe = json['portraitRecipe'];
    final portraitRecipe = rawPortraitRecipe == null
        ? null
        : rawPortraitRecipe is Map
        ? PortraitRetouchRecipe.fromJson(
            Map<String, Object?>.from(rawPortraitRecipe),
          )
        : throw const FormatException('Invalid portrait recipe payload');
    final migratedPortraitRecipe =
        portraitRecipe ??
        PortraitRetouchRecipe.migrateLegacy(
          portraitStrength: portraitStrength,
          faceSlimStrength: faceSlimStrength,
          bodySlimStrength: bodySlimStrength,
        );
    final rawQualityEnhancementRecipe = json['qualityEnhancementRecipe'];
    final qualityEnhancementRecipe = rawQualityEnhancementRecipe == null
        ? QualityEnhancementRecipe.neutral
        : rawQualityEnhancementRecipe is Map
        ? QualityEnhancementRecipe.fromJson(
            Map<String, Object?>.from(rawQualityEnhancementRecipe),
          )
        : throw const FormatException(
            'Invalid quality enhancement recipe payload',
          );
    final rawBasicEditingRecipe = json['basicEditingRecipe'];
    final basicEditingRecipe = rawBasicEditingRecipe == null
        ? BasicEditingRecipe.neutral
        : rawBasicEditingRecipe is Map
        ? BasicEditingRecipe.fromJson(
            Map<String, Object?>.from(rawBasicEditingRecipe),
          )
        : throw const FormatException('Invalid basic editing recipe payload');
    final rawPortraitGeometryRecipe = json['portraitGeometryRecipe'];
    final portraitGeometryRecipe = rawPortraitGeometryRecipe == null
        ? null
        : rawPortraitGeometryRecipe is Map
        ? PortraitGeometryRecipe.fromJson(
            Map<String, Object?>.from(rawPortraitGeometryRecipe),
          )
        : throw const FormatException(
            'Invalid portrait geometry recipe payload',
          );
    final rawSemanticEditingRecipe = json['semanticEditingRecipe'];
    final semanticEditingRecipe = rawSemanticEditingRecipe == null
        ? SemanticEditingRecipe.neutral
        : rawSemanticEditingRecipe is Map
        ? SemanticEditingRecipe.fromJson(
            Map<String, Object?>.from(rawSemanticEditingRecipe),
          )
        : throw const FormatException(
            'Invalid semantic editing recipe payload',
          );
    return EditRecipe(
      exposure: (json['exposure'] as num?)?.toDouble() ?? 0,
      highlights: (json['highlights'] as num?)?.toDouble() ?? 0,
      shadows: (json['shadows'] as num?)?.toDouble() ?? 0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 0,
      warmth: (json['warmth'] as num?)?.toDouble() ?? 0,
      tint: (json['tint'] as num?)?.toDouble() ?? 0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 0,
      clarity: (json['clarity'] as num?)?.toDouble() ?? 0,
      portraitStrength: 0,
      faceSlimStrength: faceSlimStrength,
      faceSlimRecipe: faceSlimRecipe,
      bodySlimStrength: bodySlimStrength,
      portraitRecipe: migratedPortraitRecipe,
      qualityEnhancementRecipe: qualityEnhancementRecipe,
      basicEditingRecipe: basicEditingRecipe,
      portraitGeometryRecipe: portraitGeometryRecipe,
      semanticEditingRecipe: semanticEditingRecipe,
      crop: json['crop'] is Map<String, Object?>
          ? CropGeometry.fromJson(json['crop']! as Map<String, Object?>)
          : CropGeometry.original,
    );
  }

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
    double? faceSlimStrength,
    FaceSlimRecipe? faceSlimRecipe,
    double? bodySlimStrength,
    PortraitRetouchRecipe? portraitRecipe,
    QualityEnhancementRecipe? qualityEnhancementRecipe,
    BasicEditingRecipe? basicEditingRecipe,
    PortraitGeometryRecipe? portraitGeometryRecipe,
    SemanticEditingRecipe? semanticEditingRecipe,
    CropGeometry? crop,
  }) {
    var resolvedGeometry =
        portraitGeometryRecipe ?? this.portraitGeometryRecipe;
    final resolvedFaceSlimRecipe =
        portraitGeometryRecipe != null &&
            faceSlimRecipe == null &&
            faceSlimStrength == null
        ? FaceSlimRecipe(
            targetStrengths: resolvedGeometry.faceTargets
                .map((target) => target.faceSlim / 100)
                .toList(),
            selectedTargetIndex: resolvedGeometry.selectedFaceIndex,
          )
        : faceSlimRecipe ??
              (faceSlimStrength == null
                  ? this.faceSlimRecipe
                  : this.faceSlimRecipe.setSelectedStrength(faceSlimStrength));
    if (faceSlimRecipe != null || faceSlimStrength != null) {
      resolvedGeometry = resolvedGeometry.withFaceTargetCount(
        resolvedFaceSlimRecipe.targetStrengths.length,
      );
      final targets = resolvedGeometry.faceTargets.toList();
      for (var index = 0; index < targets.length; index++) {
        targets[index] = targets[index].copyWith(
          faceSlim: resolvedFaceSlimRecipe.targetStrengths[index] * 100,
        );
      }
      resolvedGeometry = resolvedGeometry.copyWith(
        faceTargets: targets,
        selectedFaceIndex: resolvedFaceSlimRecipe.selectedTargetIndex,
      );
    }
    final resolvedBodySlimStrength =
        bodySlimStrength ??
        (portraitGeometryRecipe == null
            ? this.bodySlimStrength
            : resolvedGeometry
                      .bodyTargets[resolvedGeometry.selectedBodyIndex]
                      .slimming /
                  100);
    if (bodySlimStrength != null) {
      resolvedGeometry = resolvedGeometry.updateSelectedBody(
        (target) => target.copyWith(slimming: bodySlimStrength * 100),
      );
    }
    final resolvedPortraitRecipe =
        portraitRecipe ??
        this.portraitRecipe.copyWith(
          textureSmoothing: portraitStrength == null
              ? null
              : (portraitStrength * 100).round(),
          skinToneLighting: portraitStrength == null
              ? null
              : (portraitStrength * 100).round(),
          faceSlimming: faceSlimStrength == null && faceSlimRecipe == null
              ? null
              : (resolvedFaceSlimRecipe.selectedStrength * 100).round(),
          torsoSlimming: bodySlimStrength == null
              ? null
              : (bodySlimStrength * 100).round(),
        );
    return EditRecipe(
      exposure: exposure ?? this.exposure,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      contrast: contrast ?? this.contrast,
      warmth: warmth ?? this.warmth,
      tint: tint ?? this.tint,
      saturation: saturation ?? this.saturation,
      clarity: clarity ?? this.clarity,
      portraitStrength: portraitStrength ?? this.portraitStrength,
      faceSlimRecipe: resolvedFaceSlimRecipe,
      bodySlimStrength: resolvedBodySlimStrength,
      portraitRecipe: resolvedPortraitRecipe,
      qualityEnhancementRecipe:
          qualityEnhancementRecipe ?? this.qualityEnhancementRecipe,
      basicEditingRecipe: basicEditingRecipe ?? this.basicEditingRecipe,
      portraitGeometryRecipe: resolvedGeometry,
      semanticEditingRecipe:
          semanticEditingRecipe ?? this.semanticEditingRecipe,
      crop: crop ?? this.crop,
    );
  }

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
      other.faceSlimRecipe == faceSlimRecipe &&
      other.bodySlimStrength == bodySlimStrength &&
      other.portraitRecipe == portraitRecipe &&
      other.qualityEnhancementRecipe == qualityEnhancementRecipe &&
      other.basicEditingRecipe == basicEditingRecipe &&
      other.portraitGeometryRecipe == portraitGeometryRecipe &&
      other.semanticEditingRecipe == semanticEditingRecipe &&
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
    faceSlimRecipe,
    bodySlimStrength,
    portraitRecipe,
    qualityEnhancementRecipe,
    basicEditingRecipe,
    portraitGeometryRecipe,
    semanticEditingRecipe,
    crop,
  );
}
