import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/portrait_retouch_recipe.dart';

void main() {
  test(
    'natural beautification profile writes three real non-geometric values',
    () {
      const profile = PortraitRetouchRecipe.naturalBeautificationRecommended;

      expect(
        PortraitRetouchRecipe.naturalBeautificationProfileVersion,
        isNotEmpty,
      );
      expect(profile.textureSmoothing, 45);
      expect(profile.skinToneLighting, 40);
      expect(profile.blemishReduction, 20);
      expect(profile.faceSlimming, 0);
      expect(profile.torsoSlimming, 0);
    },
  );

  test('stores exactly five bounded 0...100 portrait parameters', () {
    final recipe = PortraitRetouchRecipe(
      textureSmoothing: 40,
      skinToneLighting: 35,
      blemishReduction: 20,
      faceSlimming: 12,
      torsoSlimming: 8,
    );

    expect(PortraitRetouchRecipe.fromJson(recipe.toJson()), recipe);
    expect(recipe.toJson().containsKey('oneTapStrength'), isFalse);
    expect(() => PortraitRetouchRecipe(textureSmoothing: -1), throwsRangeError);
    expect(() => PortraitRetouchRecipe(torsoSlimming: 101), throwsRangeError);
  });

  test(
    'migrates legacy portrait values once without enabling blemish repair',
    () {
      final restored = EditRecipe.fromJson(<String, Object?>{
        'portraitStrength': 0.35,
        'faceSlimStrength': 0.2,
        'bodySlimStrength': 0.1,
      });

      expect(restored.portraitRecipe.textureSmoothing, 35);
      expect(restored.portraitRecipe.skinToneLighting, 35);
      expect(restored.portraitRecipe.blemishReduction, 0);
      expect(restored.portraitRecipe.faceSlimming, 20);
      expect(restored.portraitRecipe.torsoSlimming, 10);
      expect(restored.portraitStrength, 0);
      expect(restored.toJson().containsKey('portraitStrength'), isFalse);
      expect(EditRecipe.fromJson(restored.toJson()), restored);
    },
  );

  test(
    'new portrait payload fails closed for unknown or malformed identity',
    () {
      final valid = PortraitRetouchRecipe().toJson();

      expect(
        () => PortraitRetouchRecipe.fromJson(<String, Object?>{
          ...valid,
          'recipeVersion': 99,
        }),
        throwsFormatException,
      );
      expect(
        () => PortraitRetouchRecipe.fromJson(<String, Object?>{
          ...valid,
          'futureField': 1,
        }),
        throwsFormatException,
      );
      expect(
        () => PortraitRetouchRecipe.fromJson(<String, Object?>{
          ...valid,
          'blemishReduction': double.nan,
        }),
        throwsFormatException,
      );
      expect(
        () => PortraitRetouchRecipe.fromJson(<String, Object?>{
          ...valid,
          'faceSlimming': 20.5,
        }),
        throwsFormatException,
      );
    },
  );
}
