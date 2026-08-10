import 'package:flutter/foundation.dart';

enum BackgroundTreatment { original, blur, white, black, warm, cool, image }

enum MaskBrushOperation { paint, erase }

@immutable
final class NormalizedPoint {
  const NormalizedPoint(this.x, this.y)
    : assert(x >= 0 && x <= 1),
      assert(y >= 0 && y <= 1);

  factory NormalizedPoint.checked(double x, double y) {
    if (!x.isFinite || !y.isFinite || x < 0 || x > 1 || y < 0 || y > 1) {
      throw RangeError('Normalized point must stay inside the image');
    }
    return NormalizedPoint(x, y);
  }

  final double x;
  final double y;

  List<double> toJson() => [x, y];

  factory NormalizedPoint.fromJson(Object? json) {
    if (json is! List ||
        json.length != 2 ||
        json[0] is! num ||
        json[1] is! num) {
      throw const FormatException('Invalid normalized point');
    }
    return NormalizedPoint.checked(
      (json[0] as num).toDouble(),
      (json[1] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NormalizedPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

@immutable
final class EraseStroke {
  factory EraseStroke({
    required double radius,
    required List<NormalizedPoint> points,
  }) {
    if (!radius.isFinite || radius < 0.005 || radius > 0.12) {
      throw RangeError.value(
        radius,
        'radius',
        'Must be between 0.005 and 0.12',
      );
    }
    if (points.isEmpty || points.length > 200) {
      throw RangeError.range(points.length, 1, 200, 'points.length');
    }
    return EraseStroke._(radius: radius, points: List.unmodifiable(points));
  }

  const EraseStroke._({required this.radius, required this.points});

  final double radius;
  final List<NormalizedPoint> points;

  Map<String, Object> toJson() => {
    'radius': radius,
    'points': points.map((point) => point.toJson()).toList(),
  };

  factory EraseStroke.fromJson(Map<String, Object?> json) {
    final radius = json['radius'];
    final points = json['points'];
    if (radius is! num || points is! List) {
      throw const FormatException('Invalid erase stroke');
    }
    return EraseStroke(
      radius: radius.toDouble(),
      points: points.map(NormalizedPoint.fromJson).toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EraseStroke &&
      other.radius == radius &&
      listEquals(other.points, points);

  @override
  int get hashCode => Object.hash(radius, Object.hashAll(points));
}

@immutable
final class MaskStroke {
  factory MaskStroke({
    required MaskBrushOperation operation,
    required double radius,
    required List<NormalizedPoint> points,
  }) {
    if (!radius.isFinite || radius < 0.005 || radius > 0.12) {
      throw RangeError.value(
        radius,
        'radius',
        'Must be between 0.005 and 0.12',
      );
    }
    if (points.isEmpty || points.length > 200) {
      throw RangeError.range(points.length, 1, 200, 'points.length');
    }
    return MaskStroke._(
      operation: operation,
      radius: radius,
      points: List.unmodifiable(points),
    );
  }

  const MaskStroke._({
    required this.operation,
    required this.radius,
    required this.points,
  });

  final MaskBrushOperation operation;
  final double radius;
  final List<NormalizedPoint> points;

  Map<String, Object> toJson() => {
    'operation': operation.name,
    'radius': radius,
    'points': points.map((point) => point.toJson()).toList(),
  };

  factory MaskStroke.fromJson(Map<String, Object?> json) {
    final operation = json['operation'];
    final radius = json['radius'];
    final points = json['points'];
    if (operation is! String || radius is! num || points is! List) {
      throw const FormatException('Invalid mask stroke');
    }
    return MaskStroke(
      operation: MaskBrushOperation.values.byName(operation),
      radius: radius.toDouble(),
      points: points.map(NormalizedPoint.fromJson).toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MaskStroke &&
      other.operation == operation &&
      other.radius == radius &&
      listEquals(other.points, points);

  @override
  int get hashCode => Object.hash(operation, radius, Object.hashAll(points));
}

@immutable
final class SemanticEditingRecipe {
  factory SemanticEditingRecipe({
    BackgroundTreatment background = BackgroundTreatment.original,
    String? backgroundImagePath,
    int backgroundBlur = 0,
    int subjectExposure = 0,
    int subjectSaturation = 0,
    int backgroundExposure = 0,
    int backgroundSaturation = 0,
    int localExposure = 0,
    int localSaturation = 0,
    List<MaskStroke> subjectMaskStrokes = const [],
    List<MaskStroke> localAdjustmentStrokes = const [],
    List<EraseStroke> eraseStrokes = const [],
  }) {
    if (background == BackgroundTreatment.image &&
        (backgroundImagePath == null || backgroundImagePath.trim().isEmpty)) {
      throw ArgumentError.value(
        backgroundImagePath,
        'backgroundImagePath',
        'Image backgrounds require an app-owned path',
      );
    }
    if (background != BackgroundTreatment.image &&
        backgroundImagePath != null) {
      throw ArgumentError.value(
        backgroundImagePath,
        'backgroundImagePath',
        'Only image backgrounds may retain an image path',
      );
    }
    _bounded(backgroundBlur, 0, 100, 'backgroundBlur');
    _bounded(subjectExposure, -100, 100, 'subjectExposure');
    _bounded(subjectSaturation, -100, 100, 'subjectSaturation');
    _bounded(backgroundExposure, -100, 100, 'backgroundExposure');
    _bounded(backgroundSaturation, -100, 100, 'backgroundSaturation');
    _bounded(localExposure, -100, 100, 'localExposure');
    _bounded(localSaturation, -100, 100, 'localSaturation');
    _boundedStrokes(subjectMaskStrokes, 'subjectMaskStrokes');
    _boundedStrokes(localAdjustmentStrokes, 'localAdjustmentStrokes');
    if (eraseStrokes.length > 20) {
      throw RangeError.range(eraseStrokes.length, 0, 20, 'eraseStrokes.length');
    }
    return SemanticEditingRecipe._(
      background: background,
      backgroundImagePath: backgroundImagePath,
      backgroundBlur: backgroundBlur,
      subjectExposure: subjectExposure,
      subjectSaturation: subjectSaturation,
      backgroundExposure: backgroundExposure,
      backgroundSaturation: backgroundSaturation,
      localExposure: localExposure,
      localSaturation: localSaturation,
      subjectMaskStrokes: List.unmodifiable(subjectMaskStrokes),
      localAdjustmentStrokes: List.unmodifiable(localAdjustmentStrokes),
      eraseStrokes: List.unmodifiable(eraseStrokes),
    );
  }

  const SemanticEditingRecipe._({
    required this.background,
    required this.backgroundImagePath,
    required this.backgroundBlur,
    required this.subjectExposure,
    required this.subjectSaturation,
    required this.backgroundExposure,
    required this.backgroundSaturation,
    required this.localExposure,
    required this.localSaturation,
    required this.subjectMaskStrokes,
    required this.localAdjustmentStrokes,
    required this.eraseStrokes,
  });

  static const recipeVersion = 2;
  static const neutral = SemanticEditingRecipe._(
    background: BackgroundTreatment.original,
    backgroundImagePath: null,
    backgroundBlur: 0,
    subjectExposure: 0,
    subjectSaturation: 0,
    backgroundExposure: 0,
    backgroundSaturation: 0,
    localExposure: 0,
    localSaturation: 0,
    subjectMaskStrokes: [],
    localAdjustmentStrokes: [],
    eraseStrokes: [],
  );

  final BackgroundTreatment background;
  final String? backgroundImagePath;
  final int backgroundBlur;
  final int subjectExposure;
  final int subjectSaturation;
  final int backgroundExposure;
  final int backgroundSaturation;
  final int localExposure;
  final int localSaturation;
  final List<MaskStroke> subjectMaskStrokes;
  final List<MaskStroke> localAdjustmentStrokes;
  final List<EraseStroke> eraseStrokes;

  bool get isNeutral => this == neutral;

  SemanticEditingRecipe copyWith({
    BackgroundTreatment? background,
    Object? backgroundImagePath = _unchanged,
    int? backgroundBlur,
    int? subjectExposure,
    int? subjectSaturation,
    int? backgroundExposure,
    int? backgroundSaturation,
    int? localExposure,
    int? localSaturation,
    List<MaskStroke>? subjectMaskStrokes,
    List<MaskStroke>? localAdjustmentStrokes,
    List<EraseStroke>? eraseStrokes,
  }) {
    final nextBackground = background ?? this.background;
    final nextPath = identical(backgroundImagePath, _unchanged)
        ? (nextBackground == BackgroundTreatment.image
              ? this.backgroundImagePath
              : null)
        : backgroundImagePath as String?;
    return SemanticEditingRecipe(
      background: nextBackground,
      backgroundImagePath: nextPath,
      backgroundBlur: backgroundBlur ?? this.backgroundBlur,
      subjectExposure: subjectExposure ?? this.subjectExposure,
      subjectSaturation: subjectSaturation ?? this.subjectSaturation,
      backgroundExposure: backgroundExposure ?? this.backgroundExposure,
      backgroundSaturation: backgroundSaturation ?? this.backgroundSaturation,
      localExposure: localExposure ?? this.localExposure,
      localSaturation: localSaturation ?? this.localSaturation,
      subjectMaskStrokes: subjectMaskStrokes ?? this.subjectMaskStrokes,
      localAdjustmentStrokes:
          localAdjustmentStrokes ?? this.localAdjustmentStrokes,
      eraseStrokes: eraseStrokes ?? this.eraseStrokes,
    );
  }

  Map<String, Object> toJson() => {
    'recipeVersion': recipeVersion,
    'background': background.name,
    'backgroundImagePath': backgroundImagePath ?? '',
    'backgroundBlur': backgroundBlur,
    'subjectExposure': subjectExposure,
    'subjectSaturation': subjectSaturation,
    'backgroundExposure': backgroundExposure,
    'backgroundSaturation': backgroundSaturation,
    'localExposure': localExposure,
    'localSaturation': localSaturation,
    'subjectMaskStrokes': subjectMaskStrokes
        .map((stroke) => stroke.toJson())
        .toList(),
    'localAdjustmentStrokes': localAdjustmentStrokes
        .map((stroke) => stroke.toJson())
        .toList(),
    'eraseStrokes': eraseStrokes.map((stroke) => stroke.toJson()).toList(),
  };

  Map<String, Object> toLegacyV1Json() => {
    'recipeVersion': 1,
    'background': background.name,
    'backgroundBlur': backgroundBlur,
    'subjectExposure': subjectExposure,
    'subjectSaturation': subjectSaturation,
    'backgroundExposure': backgroundExposure,
    'backgroundSaturation': backgroundSaturation,
    'eraseStrokes': eraseStrokes.map((stroke) => stroke.toJson()).toList(),
  };

  factory SemanticEditingRecipe.fromJson(Map<String, Object?> json) {
    final version = json['recipeVersion'];
    if ((version != 1 && version != recipeVersion) ||
        json['eraseStrokes'] is! List ||
        (version == recipeVersion &&
            (json['subjectMaskStrokes'] is! List ||
                json['localAdjustmentStrokes'] is! List))) {
      throw const FormatException('Invalid semantic editing recipe');
    }
    try {
      return SemanticEditingRecipe(
        background: BackgroundTreatment.values.byName(
          json['background']! as String,
        ),
        backgroundImagePath:
            version == 1 || (json['backgroundImagePath'] as String).isEmpty
            ? null
            : json['backgroundImagePath']! as String,
        backgroundBlur: json['backgroundBlur']! as int,
        subjectExposure: json['subjectExposure']! as int,
        subjectSaturation: json['subjectSaturation']! as int,
        backgroundExposure: json['backgroundExposure']! as int,
        backgroundSaturation: json['backgroundSaturation']! as int,
        localExposure: version == 1 ? 0 : json['localExposure']! as int,
        localSaturation: version == 1 ? 0 : json['localSaturation']! as int,
        subjectMaskStrokes: version == 1
            ? const []
            : (json['subjectMaskStrokes']! as List)
                  .map(
                    (value) => MaskStroke.fromJson(
                      Map<String, Object?>.from(value as Map),
                    ),
                  )
                  .toList(),
        localAdjustmentStrokes: version == 1
            ? const []
            : (json['localAdjustmentStrokes']! as List)
                  .map(
                    (value) => MaskStroke.fromJson(
                      Map<String, Object?>.from(value as Map),
                    ),
                  )
                  .toList(),
        eraseStrokes: (json['eraseStrokes']! as List)
            .map(
              (value) =>
                  EraseStroke.fromJson(Map<String, Object?>.from(value as Map)),
            )
            .toList(),
      );
    } on Object catch (error) {
      throw FormatException('Invalid semantic editing recipe: $error');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SemanticEditingRecipe &&
      other.background == background &&
      other.backgroundImagePath == backgroundImagePath &&
      other.backgroundBlur == backgroundBlur &&
      other.subjectExposure == subjectExposure &&
      other.subjectSaturation == subjectSaturation &&
      other.backgroundExposure == backgroundExposure &&
      other.backgroundSaturation == backgroundSaturation &&
      other.localExposure == localExposure &&
      other.localSaturation == localSaturation &&
      listEquals(other.subjectMaskStrokes, subjectMaskStrokes) &&
      listEquals(other.localAdjustmentStrokes, localAdjustmentStrokes) &&
      listEquals(other.eraseStrokes, eraseStrokes);

  @override
  int get hashCode => Object.hash(
    background,
    backgroundImagePath,
    backgroundBlur,
    subjectExposure,
    subjectSaturation,
    backgroundExposure,
    backgroundSaturation,
    localExposure,
    localSaturation,
    Object.hashAll(subjectMaskStrokes),
    Object.hashAll(localAdjustmentStrokes),
    Object.hashAll(eraseStrokes),
  );
}

const Object _unchanged = Object();

void _boundedStrokes(List<MaskStroke> strokes, String name) {
  if (strokes.length > 40) {
    throw RangeError.range(strokes.length, 0, 40, name);
  }
}

void _bounded(int value, int minimum, int maximum, String name) {
  if (value < minimum || value > maximum) {
    throw RangeError.range(value, minimum, maximum, name);
  }
}
