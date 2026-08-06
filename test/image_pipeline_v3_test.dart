import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_for_platform.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v2.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v3.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v5.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('selects V5 only for the iOS versioned portrait adapter', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(
      imagePipelineForCurrentPlatform(EditRecipe.neutral),
      isA<ImagePipelineV5>(),
    );

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
      imagePipelineForCurrentPlatform(EditRecipe.neutral),
      isA<ImagePipelineV2>(),
    );
  });

  test(
    'serializes explicit zero-default face and torso reshape parameters',
    () {
      final pipeline = ImagePipelineV3.fromRecipe(
        EditRecipe(
          portraitStrength: 0.4,
          faceSlimStrength: 0.25,
          bodySlimStrength: 0.15,
        ),
      );

      final arguments = pipeline.toPlatformArguments();
      expect(arguments['schemaVersion'], 3);
      expect(arguments['portrait'], <String, Object>{
        'recipeVersion': 1,
        'strength': 0.4,
      });
      expect(arguments['reshape'], <String, Object>{
        'recipeVersion': 1,
        'faceSlimStrength': 0.25,
        'bodySlimStrength': 0.15,
      });
      expect(arguments.containsKey('imageBytes'), isFalse);

      final neutral = ImagePipelineV3.fromRecipe(
        EditRecipe.neutral,
      ).toPlatformArguments()['reshape'];
      expect(neutral, <String, Object>{
        'recipeVersion': 1,
        'faceSlimStrength': 0.0,
        'bodySlimStrength': 0.0,
      });
    },
  );

  test('reshape strengths reject values outside the versioned unit range', () {
    expect(() => EditRecipe(faceSlimStrength: -0.01), throwsRangeError);
    expect(() => EditRecipe(faceSlimStrength: 1.01), throwsRangeError);
    expect(() => EditRecipe(bodySlimStrength: -0.01), throwsRangeError);
    expect(() => EditRecipe(bodySlimStrength: 1.01), throwsRangeError);
  });
}
