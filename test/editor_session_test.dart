import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/application/editor_session.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';

void main() {
  group('EditRecipe', () {
    test('rejects values outside the normalized adjustment range', () {
      expect(() => EditRecipe(exposure: 1.1), throwsRangeError);
      expect(() => EditRecipe(warmth: double.nan), throwsRangeError);
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

    test('requires an explicit adjustment gesture before preview', () {
      final session = EditorSession();

      expect(
        () => session.preview(session.recipe.copyWith(warmth: 0.2)),
        throwsStateError,
      );
    });
  });
}
