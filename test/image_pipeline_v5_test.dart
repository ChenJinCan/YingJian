import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/face_slim_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v5.dart';

void main() {
  test(
    'serializes independent face targets without geometry or image data',
    () {
      final recipe = EditRecipe(
        faceSlimRecipe: FaceSlimRecipe(
          targetStrengths: const [0.2, 0.45],
          selectedTargetIndex: 1,
        ),
      );

      final arguments = ImagePipelineV5.fromRecipe(
        recipe,
      ).toPlatformArguments();

      expect(arguments['schemaVersion'], 5);
      expect(arguments['faceSlimRecipeV1'], {
        'recipeVersion': 1,
        'selectedTargetIndex': 1,
        'targetStrengths': [0.2, 0.45],
      });
      expect(arguments.containsKey('imageBytes'), isFalse);
      expect(arguments.containsKey('faceBounds'), isFalse);
      expect(arguments.containsKey('landmarks'), isFalse);
    },
  );
}
