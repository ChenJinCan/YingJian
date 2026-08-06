import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/application/editor_session.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/portrait_retouch_recipe.dart';

void main() {
  group('EditRecipe', () {
    test('rejects values outside the normalized adjustment range', () {
      expect(() => EditRecipe(exposure: 1.1), throwsRangeError);
      expect(() => EditRecipe(warmth: double.nan), throwsRangeError);
      expect(() => EditRecipe(portraitStrength: -0.01), throwsRangeError);
      expect(() => EditRecipe(portraitStrength: 1.01), throwsRangeError);
      expect(
        () => CropGeometry(left: 0.8, top: 0, right: 0.2, bottom: 1),
        throwsRangeError,
      );
    });

    test('round trips the complete single-photo recipe', () {
      final recipe = EditRecipe(
        exposure: 0.1,
        highlights: -0.2,
        shadows: 0.3,
        contrast: 0.4,
        warmth: -0.5,
        tint: 0.6,
        saturation: -0.7,
        clarity: 0.8,
        portraitRecipe: PortraitRetouchRecipe(
          textureSmoothing: 35,
          skinToneLighting: 35,
          blemishReduction: 15,
        ),
        crop: CropGeometry(
          left: 0.1,
          top: 0.2,
          right: 0.9,
          bottom: 0.8,
          quarterTurns: 1,
          straightenDegrees: 2.5,
        ),
      );

      expect(EditRecipe.fromJson(recipe.toJson()), recipe);
    });

    test(
      'migrates a legacy three-adjustment recipe with neutral additions',
      () {
        final recipe = EditRecipe.fromJson(<String, Object?>{
          'exposure': 0.2,
          'contrast': -0.3,
          'warmth': 0.4,
        });

        expect(recipe.exposure, 0.2);
        expect(recipe.contrast, -0.3);
        expect(recipe.warmth, 0.4);
        expect(recipe.highlights, 0);
        expect(recipe.shadows, 0);
        expect(recipe.portraitStrength, 0);
        expect(recipe.crop, CropGeometry.original);
      },
    );

    test('distinguishes geometry changes that resize a preview texture', () {
      const original = CropGeometry.original;

      expect(
        original.hasSameOutputDimensions(
          original.copyWith(straightenDegrees: 4),
        ),
        isTrue,
      );
      expect(
        original.hasSameOutputDimensions(original.copyWith(left: 0.1)),
        isFalse,
      );
      expect(
        original.hasSameOutputDimensions(original.copyWith(quarterTurns: 1)),
        isFalse,
      );
    });

    test('crop presets use the post-rotation image axes', () {
      final rotated = CropGeometry.original.copyWith(quarterTurns: 1);

      final crop = rotated.centeredForAspect(
        sourceWidth: 4000,
        sourceHeight: 3000,
        targetAspectRatio: 16 / 9,
      );

      final outputWidth = 3000 * (crop.bottom - crop.top);
      final outputHeight = 4000 * (crop.right - crop.left);
      expect(outputWidth / outputHeight, closeTo(16 / 9, 1e-12));
    });
  });

  group('EditorSession', () {
    test('applies and undoes a recipe without mutating the original', () {
      final session = EditorSession();
      final original = session.recipe;
      final edited = original.copyWith(exposure: 0.4);

      session.apply(edited);

      expect(session.recipe, edited);
      expect(session.canUndo, isTrue);
      expect(original, EditRecipe.neutral);

      session.undo();

      expect(session.recipe, original);
      expect(session.canUndo, isFalse);
    });

    test('records a slider gesture as one undo step', () {
      final session = EditorSession();

      session.beginAdjustment();
      session.preview(session.recipe.copyWith(contrast: 0.2));
      session.preview(session.recipe.copyWith(contrast: 0.6));
      session.commitAdjustment();

      expect(session.recipe.contrast, 0.6);
      session.undo();
      expect(session.recipe, EditRecipe.neutral);
      expect(session.canUndo, isFalse);
    });

    test('records natural portrait retouch as one undoable semantic edit', () {
      final session = EditorSession();

      session.beginAdjustment();
      session.preview(session.recipe.copyWith(portraitStrength: 0.2));
      session.preview(session.recipe.copyWith(portraitStrength: 0.35));
      session.commitAdjustment();

      expect(session.recipe.portraitStrength, 0.35);
      session.undo();
      expect(session.recipe.portraitStrength, 0);
    });

    test('requires an explicit adjustment gesture before preview', () {
      final session = EditorSession();

      expect(
        () => session.preview(session.recipe.copyWith(warmth: 0.2)),
        throwsStateError,
      );
    });

    test('user can redo an undone semantic edit', () {
      final session = EditorSession();
      final edited = EditRecipe(exposure: 0.4);
      session.apply(edited);

      session.undo();
      expect(session.recipe, EditRecipe.neutral);
      expect(session.canRedo, isTrue);

      session.redo();
      expect(session.recipe, edited);
      expect(session.canUndo, isTrue);
      expect(session.canRedo, isFalse);
    });

    test('a new edit discards the redo branch', () {
      final session = EditorSession();
      session.apply(EditRecipe(exposure: 0.4));
      session.undo();

      session.apply(EditRecipe(contrast: 0.3));

      expect(session.canRedo, isFalse);
    });
  });
}
