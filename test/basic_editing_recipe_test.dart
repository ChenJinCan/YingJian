import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';

void main() {
  test('round trips filter, HSL and geometry details through EditRecipe', () {
    final basic = BasicEditingRecipe(
      flipHorizontal: true,
      perspectiveHorizontal: 18,
      perspectiveVertical: -12,
      filter: PhotoFilter.cinematic,
      filterStrength: 64,
      hsl: {
        HslChannel.orange: HslAdjustment(hue: -8, saturation: 15, lightness: 6),
        HslChannel.blue: HslAdjustment(hue: 12, saturation: -20, lightness: -4),
      },
    );
    final recipe = EditRecipe(basicEditingRecipe: basic);

    expect(EditRecipe.fromJson(recipe.toJson()), recipe);
    expect(recipe.basicEditingRecipe, basic);
  });

  test('legacy recipes migrate to a strictly neutral basic editing recipe', () {
    final restored = EditRecipe.fromJson({'exposure': 0.2});

    expect(restored.basicEditingRecipe, BasicEditingRecipe.neutral);
    expect(restored.basicEditingRecipe.isNeutral, isTrue);
  });

  test('rejects values outside the declared public ranges', () {
    expect(
      () => BasicEditingRecipe(perspectiveHorizontal: 31),
      throwsRangeError,
    );
    expect(() => BasicEditingRecipe(filterStrength: 101), throwsRangeError);
    expect(() => HslAdjustment(hue: -101), throwsRangeError);
    expect(() => HslAdjustment(saturation: 101), throwsRangeError);
  });

  test('catalog freezes twelve distinct non-neutral filters', () {
    expect(
      PhotoFilter.values.where((value) => value != PhotoFilter.none),
      hasLength(12),
    );
    expect(
      PhotoFilter.values.map((value) => value.name).toSet(),
      hasLength(13),
    );
  });
}
