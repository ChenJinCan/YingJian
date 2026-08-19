import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v10.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';

void main() {
  test('serializes editable subject and local masks without image bytes', () {
    final semantic = SemanticEditingRecipe(
      background: BackgroundTreatment.image,
      backgroundImagePath: '/app/media/background.jpg',
      backgroundImageResourceId:
          'resource-v1-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      localExposure: 20,
      subjectMaskStrokes: [
        MaskStroke(
          operation: MaskBrushOperation.erase,
          radius: 0.03,
          points: const [NormalizedPoint(0.3, 0.4)],
        ),
      ],
      localAdjustmentStrokes: [
        MaskStroke(
          operation: MaskBrushOperation.paint,
          radius: 0.05,
          points: const [NormalizedPoint(0.7, 0.6)],
        ),
      ],
    );

    final arguments = ImagePipelineV10.fromRecipe(
      EditRecipe(semanticEditingRecipe: semantic),
    ).toPlatformArguments();

    expect(arguments['schemaVersion'], 10);
    expect(arguments['semanticEditingRecipeV2'], semantic.toJson());
    expect(arguments.containsKey('imageBytes'), isFalse);
  });
}
