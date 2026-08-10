import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v9.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';

void main() {
  test('serializes bounded semantic editing without image bytes', () {
    final semantic = SemanticEditingRecipe(
      background: BackgroundTreatment.white,
      subjectExposure: 15,
      eraseStrokes: [
        EraseStroke(radius: 0.03, points: const [NormalizedPoint(0.4, 0.5)]),
      ],
    );
    final arguments = ImagePipelineV9.fromRecipe(
      EditRecipe(semanticEditingRecipe: semantic),
    ).toPlatformArguments();

    expect(arguments['schemaVersion'], 9);
    expect(arguments['semanticEditingRecipeV1'], semantic.toLegacyV1Json());
    expect(arguments.containsKey('imageBytes'), isFalse);
  });
}
