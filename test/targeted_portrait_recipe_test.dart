import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';
import 'package:yingjian/features/editor/domain/targeted_portrait_recipe.dart';

void main() {
  const region = NormalizedEditRegion(
    left: 0.1,
    top: 0.2,
    right: 0.4,
    bottom: 0.7,
  );

  test('stores portrait values by stable target id and round trips', () {
    final recipe = TargetedPortraitRecipe.neutral
        .update(
          targetId: 'target-v1-1234abcd',
          region: region,
          parameter: TargetedPortraitParameter.textureSmoothing,
          value: 42,
        )
        .update(
          targetId: 'target-v1-1234abcd',
          region: region,
          parameter: TargetedPortraitParameter.skinToneLighting,
          value: 25,
        );

    expect(recipe.adjustments.keys, ['target-v1-1234abcd']);
    expect(recipe.adjustments.values.single.textureSmoothing, 42);
    expect(recipe.adjustments.values.single.skinToneLighting, 25);
    expect(TargetedPortraitRecipe.fromJson(recipe.toJson()), recipe);
    final editRecipe = EditRecipe(targetedPortraitRecipe: recipe);
    expect(EditRecipe.fromJson(editRecipe.toJson()), editRecipe);
  });

  test('zeroing the final value removes the target entry', () {
    final edited = TargetedPortraitRecipe.neutral.update(
      targetId: 'target-v1-1234abcd',
      region: region,
      parameter: TargetedPortraitParameter.blemishReduction,
      value: 20,
    );

    final reset = edited.update(
      targetId: 'target-v1-1234abcd',
      region: region,
      parameter: TargetedPortraitParameter.blemishReduction,
      value: 0,
    );

    expect(reset, TargetedPortraitRecipe.neutral);
  });

  test('retaining active ids suspends missing target effects', () {
    var recipe = TargetedPortraitRecipe.neutral;
    for (final id in ['target-v1-1234abcd', 'target-v1-deadbeef']) {
      recipe = recipe.update(
        targetId: id,
        region: region,
        parameter: TargetedPortraitParameter.textureSmoothing,
        value: 30,
      );
    }

    final active = recipe.retainTargets(const {'target-v1-deadbeef'});

    expect(active.adjustments.keys, ['target-v1-deadbeef']);
    expect(recipe.adjustments, hasLength(2));
  });

  test('rejects invalid ids, values, and regions on decode', () {
    expect(
      () => TargetedPortraitRecipe.neutral.update(
        targetId: 'face-0',
        region: region,
        parameter: TargetedPortraitParameter.textureSmoothing,
        value: 10,
      ),
      throwsArgumentError,
    );
    expect(
      () => TargetedPortraitRecipe.neutral.update(
        targetId: 'target-v1-1234abcd',
        region: region,
        parameter: TargetedPortraitParameter.textureSmoothing,
        value: 101,
      ),
      throwsRangeError,
    );
    expect(
      () => TargetedPortraitRecipe.fromJson({
        'schemaVersion': 1,
        'adjustments': [
          {
            'targetId': 'target-v1-1234abcd',
            'region': region.toJson(),
            'textureSmoothing': 10.5,
            'skinToneLighting': 0,
            'blemishReduction': 0,
          },
        ],
      }),
      throwsFormatException,
    );
  });
}
