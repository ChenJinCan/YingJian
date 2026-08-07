import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v6.dart';
import 'package:yingjian/features/editor/domain/quality_enhancement_recipe.dart';

void main() {
  test('serializes quality enhancement without image data', () {
    final recipe = EditRecipe(
      qualityEnhancementRecipe: QualityEnhancementRecipe(
        noiseReduction: 30,
        lowLightRecovery: 40,
        hazeRemoval: 25,
        detailSharpening: 20,
      ),
    );

    final arguments = ImagePipelineV6.fromRecipe(recipe).toPlatformArguments();

    expect(arguments['schemaVersion'], 6);
    expect(arguments['qualityEnhancementRecipeV1'], {
      'recipeVersion': 1,
      'noiseReduction': 30,
      'lowLightRecovery': 40,
      'hazeRemoval': 25,
      'detailSharpening': 20,
    });
    expect(arguments.containsKey('imageBytes'), isFalse);
  });
}
