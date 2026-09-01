import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/creation/application/local_reference_style_analyzer.dart';
import 'package:yingjian/features/creation/application/local_style_definition_factory.dart';
import 'package:yingjian/features/creation/domain/style_definition.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';

void main() {
  test('confirmed text compiles only recognized style language', () {
    final cinematic = LocalStyleDefinitionFactory.recipeFromPrompt(
      '雨后的电影感，人物保持自然',
    );
    final film = LocalStyleDefinitionFactory.recipeFromPrompt('温暖的胶片感');
    final unknown = LocalStyleDefinitionFactory.recipeFromPrompt('帮我随便弄一下');
    final conflicting = LocalStyleDefinitionFactory.recipeFromPrompt(
      '再暖一点，同时也更冷一点',
    );

    expect(cinematic?.basicEditingRecipe.filter, PhotoFilter.cinematic);
    expect(cinematic?.contrast, greaterThan(0));
    expect(film?.basicEditingRecipe.filter, PhotoFilter.film);
    expect(film?.warmth, greaterThan(0));
    expect(unknown, isNull);
    expect(conflicting, isNull);
  });

  test('reference signals compile to a bounded warm local recipe', () {
    final recipe = LocalStyleDefinitionFactory.recipeFromReference(
      const ReferenceStyleSignals(
        red: 0.9,
        green: 0.55,
        blue: 0.2,
        luminance: 0.6,
        saturation: 0.75,
        contrast: 0.55,
        edgeStrength: 0.3,
      ),
    );

    expect(recipe.warmth, greaterThan(0));
    expect(recipe.exposure, inInclusiveRange(-0.08, 0.08));
    expect(recipe.saturation, inInclusiveRange(-0.08, 0.1));
    expect(recipe.basicEditingRecipe.filter, PhotoFilter.warmSun);
  });

  test('reference contrast and edge texture map to bounded local controls', () {
    const shared = (
      red: 0.5,
      green: 0.5,
      blue: 0.5,
      luminance: 0.5,
      saturation: 0.4,
    );
    final soft = LocalStyleDefinitionFactory.recipeFromReference(
      ReferenceStyleSignals(
        red: shared.red,
        green: shared.green,
        blue: shared.blue,
        luminance: shared.luminance,
        saturation: shared.saturation,
        contrast: 0,
        edgeStrength: 0,
      ),
    );
    final crisp = LocalStyleDefinitionFactory.recipeFromReference(
      ReferenceStyleSignals(
        red: shared.red,
        green: shared.green,
        blue: shared.blue,
        luminance: shared.luminance,
        saturation: shared.saturation,
        contrast: 1,
        edgeStrength: 1,
      ),
    );

    expect(soft.contrast, lessThan(crisp.contrast));
    expect(soft.clarity, lessThan(crisp.clarity));
    expect(soft.contrast, inInclusiveRange(-0.06, 0.06));
    expect(crisp.contrast, inInclusiveRange(-0.06, 0.06));
    expect(soft.clarity, inInclusiveRange(-0.02, 0.06));
    expect(crisp.clarity, inInclusiveRange(-0.02, 0.06));
  });

  test('invalid reference aggregates fail closed instead of being clamped', () {
    const invalidSignals = [
      ReferenceStyleSignals(
        red: 0.5,
        green: 1.1,
        blue: 0.5,
        luminance: 0.5,
        saturation: 0.4,
        contrast: 0.5,
        edgeStrength: 0.2,
      ),
      ReferenceStyleSignals(
        red: 0.5,
        green: 0.5,
        blue: 0.5,
        luminance: 0.5,
        saturation: 0.4,
        contrast: double.nan,
        edgeStrength: 0.2,
      ),
      ReferenceStyleSignals(
        red: 0.5,
        green: 0.5,
        blue: 0.5,
        luminance: 0.5,
        saturation: 0.4,
        contrast: 0.5,
        edgeStrength: double.infinity,
      ),
    ];
    for (final signals in invalidSignals) {
      expect(
        () => LocalStyleDefinitionFactory.recipeFromReference(signals),
        throwsArgumentError,
      );
    }
  });

  test(
    'style identifiers are stable and safe for persisted project identity',
    () {
      final first = LocalStyleDefinitionFactory.identifierFor(
        origin: StyleDefinitionOrigin.reference,
        stableSeed: 'a' * 64,
      );
      final second = LocalStyleDefinitionFactory.identifierFor(
        origin: StyleDefinitionOrigin.reference,
        stableSeed: 'a' * 64,
      );

      expect(first, second);
      expect(StyleDefinition.isValidStyleId(first), isTrue);
    },
  );
}
