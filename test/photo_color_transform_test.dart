import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/photo_color_transform.dart';

void main() {
  test('neutral recipe preserves every color channel', () {
    final transform = PhotoColorTransform.fromRecipe(EditRecipe.neutral);

    expect(transform.flutterMatrix, const <double>[
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
