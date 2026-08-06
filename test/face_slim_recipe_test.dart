import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/face_slim_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';

void main() {
  test('keeps an independent strength for each stable face target', () {
    final recipe = FaceSlimRecipe(targetStrengths: const [0.2, 0.4]);

    final second = recipe.selectTarget(1);
    final changed = second.setSelectedStrength(0.5);

    expect(changed.selectedTargetIndex, 1);
    expect(changed.selectedStrength, 0.5);
    expect(changed.targetStrengths, [0.2, 0.5]);
    expect(changed.selectTarget(0).selectedStrength, 0.2);
  });

  test('round trips target selection and expands without losing strengths', () {
    final restored = FaceSlimRecipe.fromJson(
      FaceSlimRecipe(
        targetStrengths: const [0.15, 0.35],
        selectedTargetIndex: 1,
      ).toJson(),
    ).withTargetCount(3);

    expect(restored.targetStrengths, [0.15, 0.35, 0]);
    expect(restored.selectedTargetIndex, 1);
  });

  test('rejects malformed, excessive, and non-finite target strengths', () {
    expect(
      () => FaceSlimRecipe(targetStrengths: const [0, 0, 0, 0]),
      throwsRangeError,
    );
    expect(
      () => FaceSlimRecipe(targetStrengths: const [double.nan]),
      throwsArgumentError,
    );
    expect(
      () => FaceSlimRecipe.fromJson({
        'recipeVersion': 1,
        'selectedTargetIndex': 0,
        'targetStrengths': [true],
      }),
      throwsFormatException,
    );
  });

  test('edit recipe migrates one legacy strength and persists all targets', () {
    final migrated = EditRecipe(faceSlimStrength: 0.3);
    expect(migrated.faceSlimRecipe.targetStrengths, [0.3]);

    final multi = migrated.copyWith(
      faceSlimRecipe: FaceSlimRecipe(
        targetStrengths: const [0.2, 0.45],
        selectedTargetIndex: 1,
      ),
    );
    final restored = EditRecipe.fromJson(multi.toJson());

    expect(restored.faceSlimStrength, 0.45);
    expect(restored.faceSlimRecipe.targetStrengths, [0.2, 0.45]);
    expect(restored.faceSlimRecipe.selectedTargetIndex, 1);
  });
}
