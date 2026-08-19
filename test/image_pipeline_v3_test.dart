import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/compiled_image_pipeline.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_for_platform.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v3.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('selects V9 only for the iOS versioned semantic editing adapter', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(
      imagePipelineForCurrentPlatform(EditRecipe.neutral),
      isA<CompiledImagePipeline>(),
    );

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
      imagePipelineForCurrentPlatform(EditRecipe.neutral),
      isA<CompiledImagePipeline>(),
    );
  });

  test('production pipeline always carries its accepted render plan', () {
    final arguments = imagePipelineForCurrentPlatform(
      EditRecipe.neutral.copyWith(exposure: 0.2),
      sourceId: 'photo-1',
    ).toPlatformArguments();

    expect(arguments['renderPlanV1'], isA<Map<String, Object>>());
    final plan = arguments['renderPlanV1']! as Map<String, Object>;
    expect(plan['sourceId'], 'photo-1');
    expect(plan['planId'], startsWith('rp1-'));
    expect(arguments.keys, {'renderPlanV1'});
    expect(plan['backendPayload'], isA<Map<String, Object>>());
    expect(plan['outputRequirements'], {
      'purpose': 'preview',
      'colorSpace': 'srgb',
      'format': 'display',
      'quality': 'interactive',
    });
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
