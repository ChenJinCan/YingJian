import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v11.dart';
import 'package:yingjian/features/editor/domain/targeted_portrait_recipe.dart';

void main() {
  test('serializes stable-target portrait values without image bytes', () {
    const region = NormalizedEditRegion(
      left: 0.1,
      top: 0.2,
      right: 0.4,
      bottom: 0.7,
    );
    final targeted = TargetedPortraitRecipe.neutral
        .update(
          targetId: 'target-v1-1234abcd',
          region: region,
          parameter: TargetedPortraitParameter.textureSmoothing,
          value: 42,
        )
        .update(
          targetId: 'target-v1-1234abcd',
          region: region,
          parameter: TargetedPortraitParameter.blemishReduction,
          value: 18,
        );

    final arguments = ImagePipelineV11.fromRecipe(
      EditRecipe(targetedPortraitRecipe: targeted),
    ).toPlatformArguments();

    expect(arguments['schemaVersion'], 11);
    expect(arguments['targetedPortraitRecipeV1'], targeted.toJson());
    expect(arguments.containsKey('imageBytes'), isFalse);
  });
}
