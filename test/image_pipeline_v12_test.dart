import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/directional_lighting_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v12.dart';

void main() {
  test('serializes bounded target lighting without image bytes', () {
    const region = NormalizedEditRegion(
      left: .1,
      top: .2,
      right: .5,
      bottom: .8,
    );
    final lighting = DirectionalLightingRecipe.neutral.update(
      targetId: 'target-v1-1234abcd',
      region: region,
      azimuth: 60,
      intensity: 40,
    );
    final payload = ImagePipelineV12.fromRecipe(
      EditRecipe(directionalLightingRecipe: lighting),
    ).toPlatformArguments();
    expect(payload['schemaVersion'], 12);
    expect(payload['directionalLightingRecipeV1'], lighting.toJson());
    expect(payload, isNot(contains('imageBytes')));
  });
}
