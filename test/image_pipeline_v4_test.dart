import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v4.dart';
import 'package:yingjian/features/editor/domain/portrait_retouch_recipe.dart';

void main() {
  test(
    'serializes the five-parameter portrait identity without image data',
    () {
      final recipe = EditRecipe(
        faceSlimStrength: 0.25,
        bodySlimStrength: 0.15,
        portraitRecipe: PortraitRetouchRecipe(
          textureSmoothing: 40,
          skinToneLighting: 30,
          blemishReduction: 20,
          faceSlimming: 25,
          torsoSlimming: 15,
        ),
      );

      final arguments = ImagePipelineV4.fromRecipe(
        recipe,
      ).toPlatformArguments();

      expect(arguments['schemaVersion'], 4);
      expect(arguments['portraitRecipeV2'], recipe.portraitRecipe.toJson());
      expect(arguments.containsKey('imageBytes'), isFalse);
      expect(arguments.containsKey('portrait'), isFalse);
      expect(arguments.containsKey('reshape'), isFalse);
    },
  );
}
