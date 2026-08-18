import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/application/natural_language_edit_interpreter.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/portrait_retouch_recipe.dart';

void main() {
  const interpreter = LocalNaturalLanguageEditInterpreter();

  test(
    'compound plain-language request produces visible editable parameters',
    () {
      final result = interpreter.interpret(
        '照片亮一点，皮肤自然一点',
        current: EditRecipe.neutral,
      );

      expect(result.isApplicable, isTrue);
      expect(result.recipe.exposure, 0.12);
      expect(
        result.recipe.portraitRecipe,
        PortraitRetouchRecipe.naturalBeautificationRecommended,
      );
      expect(
        result.changes.map((change) => change.parameter),
        containsAll(<EditableParameter>{
          EditableParameter.exposure,
          EditableParameter.textureSmoothing,
          EditableParameter.skinToneLighting,
          EditableParameter.blemishReduction,
        }),
      );
    },
  );

  test('explicit negative instruction resets only the named parameter', () {
    final current = EditRecipe(
      exposure: 0.24,
      portraitRecipe: PortraitRetouchRecipe(
        textureSmoothing: 55,
        skinToneLighting: 30,
        blemishReduction: 10,
      ),
    );

    final result = interpreter.interpret('不要磨皮', current: current);

    expect(result.recipe.exposure, 0.24);
    expect(result.recipe.portraitRecipe.textureSmoothing, 0);
    expect(result.recipe.portraitRecipe.skinToneLighting, 30);
    expect(result.recipe.portraitRecipe.blemishReduction, 10);
    expect(result.changes, hasLength(1));
    expect(result.changes.single.parameter, EditableParameter.textureSmoothing);
  });

  test('unsupported request fails closed without changing the recipe', () {
    final current = EditRecipe(exposure: 0.2);

    final result = interpreter.interpret('把人物换成动漫角色', current: current);

    expect(result.isApplicable, isFalse);
    expect(result.recipe, current);
    expect(result.changes, isEmpty);
  });
}
