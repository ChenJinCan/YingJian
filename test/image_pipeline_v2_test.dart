import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_for_platform.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v2.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('selects V2 for the implemented Android adapter', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
      imagePipelineForCurrentPlatform(EditRecipe.neutral),
      isA<ImagePipelineV2>(),
    );
  });

  test('serializes the complete single-photo contract without image data', () {
    final pipeline = ImagePipelineV2.fromRecipe(
      EditRecipe(
        exposure: 0.25,
        highlights: -0.5,
        shadows: 0.4,
        contrast: -0.2,
        warmth: 0.6,
        tint: -0.3,
        saturation: 0.7,
        clarity: 0.2,
        portraitStrength: 0.35,
        crop: CropGeometry(
          left: 0.1,
          top: 0.2,
          right: 0.9,
          bottom: 0.8,
          quarterTurns: 3,
          straightenDegrees: -1.5,
        ),
      ),
    );

    expect(pipeline.toPlatformArguments(), <String, Object>{
      'schemaVersion': 2,
      'workingColorSpace': 'srgb',
      'adjustments': <String, double>{
        'exposureEv': 0.5,
        'highlights': -0.5,
        'shadows': 0.4,
        'contrast': -0.2,
        'warmth': 0.6,
        'tint': -0.3,
        'saturation': 0.7,
        'clarity': 0.2,
      },
      'geometry': <String, Object>{
        'normalizedCrop': <double>[0.1, 0.2, 0.9, 0.8],
        'quarterTurns': 3,
        'straightenDegrees': -1.5,
      },
      'portrait': <String, Object>{'recipeVersion': 1, 'strength': 0.35},
    });
    expect(pipeline.toPlatformArguments().containsKey('imageBytes'), isFalse);
  });

  test('neutral geometry preserves the whole normalized source', () {
    final geometry = ImagePipelineV2.fromRecipe(
      EditRecipe.neutral,
    ).toPlatformArguments()['geometry'];

    expect(geometry, <String, Object>{
      'normalizedCrop': <double>[0.0, 0.0, 1.0, 1.0],
      'quarterTurns': 0,
      'straightenDegrees': 0.0,
    });
  });
}
