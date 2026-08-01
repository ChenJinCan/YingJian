import 'package:flutter/foundation.dart';

@immutable
class EditRecipe {
  factory EditRecipe({
    double exposure = 0,
    double contrast = 0,
    double warmth = 0,
  }) {
    _validate(exposure, 'exposure');
    _validate(contrast, 'contrast');
    _validate(warmth, 'warmth');
    return EditRecipe._(exposure: exposure, contrast: contrast, warmth: warmth);
  }

  const EditRecipe._({
    required this.exposure,
    required this.contrast,
    required this.warmth,
  });

  static final neutral = EditRecipe();

  final double exposure;
  final double contrast;
  final double warmth;

  EditRecipe copyWith({double? exposure, double? contrast, double? warmth}) {
    return EditRecipe(
      exposure: exposure ?? this.exposure,
      contrast: contrast ?? this.contrast,
      warmth: warmth ?? this.warmth,
    );
  }

  static void _validate(double value, String name) {
    if (!value.isFinite || value < -1 || value > 1) {
      throw RangeError.range(value, -1, 1, name);
    }
  }

  @override
  bool operator ==(Object other) {
    return other is EditRecipe &&
        other.exposure == exposure &&
        other.contrast == contrast &&
        other.warmth == warmth;
  }

  @override
  int get hashCode => Object.hash(exposure, contrast, warmth);
}
