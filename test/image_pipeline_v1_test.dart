import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v1.dart';

void main() {
  test('serializes stable versioned pixel semantics', () {
    final pipeline = ImagePipelineV1.fromRecipe(
      EditRecipe(exposure: 0.25, contrast: -0.4, warmth: 0.6),
    );

    expect(pipeline.toPlatformArguments(), <String, Object>{
      'schemaVersion': 1,
      'workingColorSpace': 'srgb',
      'adjustments': <String, double>{
        'exposureEv': 0.5,
        'contrast': -0.4,
        'warmth': 0.6,
      },
    });
  });

  test('compatibility transform preserves the existing neutral result', () {
    final pipeline = ImagePipelineV1.fromRecipe(EditRecipe.neutral);

    expect(pipeline.compatibilityTransform.flutterMatrix, const <double>[
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);
  });
}
