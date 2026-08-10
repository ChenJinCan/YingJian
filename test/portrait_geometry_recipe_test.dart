import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/portrait_geometry_recipe.dart';

void main() {
  test('round trips independent face and body targets through EditRecipe', () {
    final geometry = PortraitGeometryRecipe(
      faceTargets: [
        FaceGeometryTarget(faceSlim: 32, headSize: 18, eyes: 12, jaw: -8),
        FaceGeometryTarget(chin: 15, nose: -10, mouth: 8),
      ],
      selectedFaceIndex: 1,
      bodyTargets: [
        BodyGeometryTarget(
          slimming: 20,
          height: 16,
          shoulders: -8,
          waist: -14,
          legs: 12,
        ),
      ],
    );
    final recipe = EditRecipe(portraitGeometryRecipe: geometry);

    expect(EditRecipe.fromJson(recipe.toJson()), recipe);
    expect(recipe.portraitGeometryRecipe, geometry);
  });

  test('legacy slim values migrate without enabling new geometry', () {
    final recipe = EditRecipe.fromJson({
      'faceSlimStrength': 0.3,
      'bodySlimStrength': 0.2,
    });

    expect(recipe.portraitGeometryRecipe.faceTargets.single.faceSlim, 30);
    expect(recipe.portraitGeometryRecipe.bodyTargets.single.slimming, 20);
    expect(recipe.portraitGeometryRecipe.faceTargets.single.headSize, 0);
    expect(recipe.portraitGeometryRecipe.bodyTargets.single.height, 0);
  });

  test('target selection and updates preserve other people', () {
    final recipe = PortraitGeometryRecipe(
      faceTargets: [FaceGeometryTarget(), FaceGeometryTarget()],
      selectedFaceIndex: 0,
      bodyTargets: [BodyGeometryTarget(), BodyGeometryTarget()],
      selectedBodyIndex: 0,
    );

    final updated = recipe
        .selectFace(1)
        .updateSelectedFace((target) => target.copyWith(eyes: 25))
        .selectBody(1)
        .updateSelectedBody((target) => target.copyWith(waist: -20));

    expect(updated.faceTargets[0].eyes, 0);
    expect(updated.faceTargets[1].eyes, 25);
    expect(updated.bodyTargets[0].waist, 0);
    expect(updated.bodyTargets[1].waist, -20);
  });

  test('rejects unsafe ranges and more than three targets', () {
    expect(() => FaceGeometryTarget(eyes: 101), throwsRangeError);
    expect(() => FaceGeometryTarget(faceSlim: -1), throwsRangeError);
    expect(() => BodyGeometryTarget(height: -1), throwsRangeError);
    expect(
      () => PortraitGeometryRecipe(
        faceTargets: List.generate(4, (_) => FaceGeometryTarget()),
      ),
      throwsRangeError,
    );
  });
}
