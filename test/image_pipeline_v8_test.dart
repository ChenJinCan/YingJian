import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v8.dart';
import 'package:yingjian/features/editor/domain/portrait_geometry_recipe.dart';

void main() {
  test('serializes independent portrait geometry without image data', () {
    final geometry = PortraitGeometryRecipe(
      faceTargets: [
        FaceGeometryTarget(
          faceSlim: 32,
          headSize: 18,
          jaw: -12,
          chin: 9,
          eyes: 14,
          nose: -8,
          mouth: 7,
        ),
        FaceGeometryTarget(faceSlim: 10),
      ],
      selectedFaceIndex: 1,
      bodyTargets: [
        BodyGeometryTarget(
          slimming: 25,
          height: 16,
          shoulders: 12,
          waist: -20,
          legs: 18,
        ),
      ],
    );
    final arguments = ImagePipelineV8.fromRecipe(
      EditRecipe(portraitGeometryRecipe: geometry),
    ).toPlatformArguments();

    expect(arguments['schemaVersion'], 8);
    expect(arguments['portraitGeometryRecipeV1'], geometry.toJson());
    expect(arguments.containsKey('imageBytes'), isFalse);
  });
}
