import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';

void main() {
  test('round trips subject background local color and erase strokes', () {
    final semantic = SemanticEditingRecipe(
      background: BackgroundTreatment.blur,
      backgroundBlur: 45,
      subjectExposure: 18,
      subjectSaturation: 12,
      backgroundExposure: -10,
      backgroundSaturation: -20,
      localExposure: 24,
      localSaturation: -16,
      subjectMaskStrokes: [
        MaskStroke(
          operation: MaskBrushOperation.erase,
          radius: 0.025,
          points: const [NormalizedPoint(0.2, 0.3)],
        ),
      ],
      localAdjustmentStrokes: [
        MaskStroke(
          operation: MaskBrushOperation.paint,
          radius: 0.04,
          points: const [NormalizedPoint(0.6, 0.5)],
        ),
      ],
      eraseStrokes: [
        EraseStroke(
          radius: 0.035,
          points: const [
            NormalizedPoint(0.25, 0.35),
            NormalizedPoint(0.28, 0.38),
          ],
        ),
      ],
    );

    final recipe = EditRecipe(semanticEditingRecipe: semantic);
    expect(
      EditRecipe.fromJson(recipe.toJson()).semanticEditingRecipe,
      semantic,
    );
  });

  test('migrates semantic V1 projects with neutral editable masks', () {
    final restored = SemanticEditingRecipe.fromJson({
      'recipeVersion': 1,
      'background': 'white',
      'backgroundBlur': 0,
      'subjectExposure': 8,
      'subjectSaturation': 0,
      'backgroundExposure': 0,
      'backgroundSaturation': 0,
      'eraseStrokes': <Object>[],
    });

    expect(restored.background, BackgroundTreatment.white);
    expect(restored.subjectMaskStrokes, isEmpty);
    expect(restored.localAdjustmentStrokes, isEmpty);
    expect(restored.localExposure, 0);
    expect(restored.localSaturation, 0);
  });

  test('rejects unsafe semantic ranges and excessive brush payloads', () {
    expect(() => SemanticEditingRecipe(subjectExposure: 101), throwsRangeError);
    expect(() => SemanticEditingRecipe(localExposure: 101), throwsRangeError);
    expect(
      () => MaskStroke(
        operation: MaskBrushOperation.paint,
        radius: 0.2,
        points: const [NormalizedPoint(0.5, 0.5)],
      ),
      throwsRangeError,
    );
    expect(
      () => EraseStroke(radius: 0.2, points: const [NormalizedPoint(0.5, 0.5)]),
      throwsRangeError,
    );
    expect(
      () => SemanticEditingRecipe(
        eraseStrokes: List.generate(
          21,
          (_) => EraseStroke(
            radius: 0.03,
            points: const [NormalizedPoint(0.5, 0.5)],
          ),
        ),
      ),
      throwsRangeError,
    );
  });

  test('neutral semantic recipe is an exact no-op', () {
    expect(SemanticEditingRecipe.neutral.isNeutral, isTrue);
    expect(EditRecipe.neutral.semanticEditingRecipe.isNeutral, isTrue);
  });

  test('round trips content identities for vector editing resources', () {
    const subjectId =
        'resource-v1-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const localId =
        'resource-v1-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const eraseId =
        'resource-v1-cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
    final recipe = SemanticEditingRecipe(
      subjectMaskStrokes: [
        MaskStroke(
          operation: MaskBrushOperation.paint,
          radius: 0.03,
          points: const [NormalizedPoint(0.5, 0.5)],
        ),
      ],
      subjectMaskResourceId: subjectId,
      localAdjustmentStrokes: [
        MaskStroke(
          operation: MaskBrushOperation.erase,
          radius: 0.04,
          points: const [NormalizedPoint(0.4, 0.6)],
        ),
      ],
      localMaskResourceId: localId,
      eraseStrokes: [
        EraseStroke(radius: 0.05, points: const [NormalizedPoint(0.3, 0.7)]),
      ],
      eraseMaskResourceId: eraseId,
    );

    expect(SemanticEditingRecipe.fromJson(recipe.toJson()), recipe);
  });

  test('custom background requires an app-owned path and content identity', () {
    expect(
      () => SemanticEditingRecipe(background: BackgroundTreatment.image),
      throwsArgumentError,
    );
    final recipe = SemanticEditingRecipe(
      background: BackgroundTreatment.image,
      backgroundImagePath: '/app/media/background.jpg',
      backgroundImageResourceId:
          'resource-v1-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );
    expect(recipe.backgroundImagePath, '/app/media/background.jpg');
    expect(
      recipe.backgroundImageResourceId,
      'resource-v1-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );
    expect(SemanticEditingRecipe.fromJson(recipe.toJson()), recipe);
  });

  test('round trips transparent background without a replacement resource', () {
    final recipe = SemanticEditingRecipe(
      background: BackgroundTreatment.transparent,
    );

    expect(recipe.toJson()['background'], 'transparent');
    expect(SemanticEditingRecipe.fromJson(recipe.toJson()), recipe);
    expect(recipe.backgroundImagePath, isNull);
    expect(recipe.backgroundImageResourceId, isNull);
  });
}
