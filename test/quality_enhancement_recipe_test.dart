import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/quality_enhancement_recipe.dart';

void main() {
  test('round trips four independent quality enhancement parameters', () {
    final recipe = QualityEnhancementRecipe(
      noiseReduction: 30,
      lowLightRecovery: 40,
      hazeRemoval: 25,
      detailSharpening: 20,
    );

    expect(QualityEnhancementRecipe.fromJson(recipe.toJson()), recipe);
    expect(recipe.isNeutral, isFalse);
  });

  test('rejects fractional and out-of-range quality parameters', () {
    expect(
      () => QualityEnhancementRecipe.fromJson({
        'recipeVersion': 1,
        'noiseReduction': 20.5,
        'lowLightRecovery': 0,
        'hazeRemoval': 0,
        'detailSharpening': 0,
      }),
      throwsFormatException,
    );
    expect(
      () => QualityEnhancementRecipe(noiseReduction: 101),
      throwsRangeError,
    );
  });

  test('safe automatic improvement expands into visible parameters', () {
    expect(QualityEnhancementRecipe.safeAutomatic.toJson(), {
      'recipeVersion': 1,
      'noiseReduction': 28,
      'lowLightRecovery': 32,
      'hazeRemoval': 18,
      'detailSharpening': 16,
    });
  });
}
