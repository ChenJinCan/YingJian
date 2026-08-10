import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v7.dart';

void main() {
  test('serializes basic editing without image data', () {
    final recipe = EditRecipe(
      basicEditingRecipe: BasicEditingRecipe(
        flipVertical: true,
        filter: PhotoFilter.clean,
        filterStrength: 45,
        hsl: {HslChannel.red: HslAdjustment(saturation: 20)},
      ),
    );

    final arguments = ImagePipelineV7.fromRecipe(recipe).toPlatformArguments();

    expect(arguments['schemaVersion'], 7);
    expect(
      arguments['basicEditingRecipeV1'],
      recipe.basicEditingRecipe.toJson(),
    );
    expect(arguments.containsKey('imageBytes'), isFalse);
  });
}
