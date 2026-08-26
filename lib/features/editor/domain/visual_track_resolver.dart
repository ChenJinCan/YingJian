import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';

abstract final class VisualTrackResolver {
  static EditRecipe era(EditRecipe baseline, double position) {
    final value = position.clamp(-1.0, 1.0);
    double bounded(double value) => value.clamp(-1.0, 1.0);
    if (value < 0) {
      final strength = -value;
      return baseline.copyWith(
        exposure: bounded(baseline.exposure - 0.06 * strength),
        highlights: bounded(baseline.highlights - 0.18 * strength),
        contrast: bounded(baseline.contrast - 0.10 * strength),
        warmth: bounded(baseline.warmth + 0.28 * strength),
        tint: bounded(baseline.tint + 0.06 * strength),
        saturation: bounded(baseline.saturation - 0.18 * strength),
        clarity: bounded(baseline.clarity - 0.10 * strength),
      );
    }
    return baseline.copyWith(
      exposure: bounded(baseline.exposure + 0.08 * value),
      highlights: bounded(baseline.highlights - 0.08 * value),
      contrast: bounded(baseline.contrast + 0.18 * value),
      warmth: bounded(baseline.warmth - 0.24 * value),
      tint: bounded(baseline.tint + 0.14 * value),
      saturation: bounded(baseline.saturation + 0.16 * value),
      clarity: bounded(baseline.clarity + 0.24 * value),
    );
  }

  static EditRecipe lighting(
    EditRecipe baseline, {
    required StableEditTarget target,
    required double azimuth,
    required int intensity,
  }) => baseline.copyWith(
    directionalLightingRecipe: baseline.directionalLightingRecipe.update(
      targetId: target.id,
      region: target.region,
      azimuth: azimuth,
      intensity: intensity,
    ),
  );
}
