import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/directional_lighting_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/legacy_edit_recipe_adapter.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/visual_track_resolver.dart';

void main() {
  const target = StableEditTarget(
    id: 'target-v1-1234abcd',
    photoId: 'photo-1',
    kind: EditTargetKind.face,
    analysisVersion: 'vision-v1',
    bindingFingerprint: 'binding',
    region: NormalizedEditRegion(left: .1, top: .2, right: .4, bottom: .7),
    status: EditTargetStatus.active,
  );

  test('era track is neutral at zero and monotonic toward both endpoints', () {
    final baseline = EditRecipe(exposure: .1, warmth: .05);
    expect(VisualTrackResolver.era(baseline, 0), baseline);
    final vintage = VisualTrackResolver.era(baseline, -1);
    final future = VisualTrackResolver.era(baseline, 1);
    expect(vintage.warmth, greaterThan(baseline.warmth));
    expect(vintage.saturation, lessThan(baseline.saturation));
    expect(future.warmth, lessThan(baseline.warmth));
    expect(future.clarity, greaterThan(baseline.clarity));
  });

  test('directional lighting serializes, restores, and resets by target', () {
    final recipe = VisualTrackResolver.lighting(
      EditRecipe.neutral,
      target: target,
      azimuth: -45,
      intensity: 35,
    );
    final restored = EditRecipe.fromJson(recipe.toJson());
    expect(restored, recipe);
    expect(
      restored.directionalLightingRecipe.adjustments[target.id],
      DirectionalLightingAdjustment(
        targetId: target.id,
        region: target.region,
        azimuth: -45,
        intensity: 35,
      ),
    );
    expect(
      VisualTrackResolver.lighting(
        restored,
        target: target,
        azimuth: 0,
        intensity: 0,
      ).directionalLightingRecipe,
      DirectionalLightingRecipe.neutral,
    );
  });

  test('directional lighting becomes one admitted targeted transaction', () {
    final after = VisualTrackResolver.lighting(
      EditRecipe.neutral,
      target: target,
      azimuth: -40,
      intensity: 25,
    );
    final registry = EditTargetRegistry(targets: {target.id: target});
    const adapter = LegacyEditRecipeAdapter();
    final transition = adapter.tryEncodeTransition(
      before: EditRecipe.neutral,
      after: after,
      photoId: target.photoId,
      targetRegistry: registry,
    );
    expect(transition, isNotNull);
    expect(transition!.changes, hasLength(2));
    final result = const EditingCore().apply(
      state: EditState.empty,
      transaction: EditTransaction(
        id: 'lighting-test',
        baseVersion: 0,
        source: EditSource.manual,
        changes: transition.changes,
      ),
      context: EditContext(
        platform: EditPlatform.ios,
        photoIds: {target.photoId},
        targetIds: {target.id},
        applicability: const {'photo', 'face'},
      ),
    );
    expect(result, isA<AcceptedEdit>());
  });
}
