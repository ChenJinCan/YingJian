import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/application/editor_session.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/portrait_geometry_recipe.dart';
import 'package:yingjian/features/editor/domain/portrait_retouch_recipe.dart';
import 'package:yingjian/features/editor/domain/platform_meta_op_capabilities.dart';

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

    test('cancels an unfinished gesture without creating history', () {
      final session = EditorSession(initialRecipe: EditRecipe(exposure: 0.2));

      session.beginAdjustment();
      session.preview(session.recipe.copyWith(exposure: 0.7));
      session.cancelAdjustment();

      expect(session.recipe, EditRecipe(exposure: 0.2));
      expect(session.canUndo, isFalse);
    });

    test('previews exposure through the meta-op contract as one undo step', () {
      final session = EditorSession(initialRecipe: EditRecipe(warmth: 0.25));
      const address = OpAddress(
        metaOpId: MetaOpIds.exposure,
        metaOpVersion: 1,
        parameterId: 'value',
        scope: EditScope.group,
      );

      session.beginAdjustment();
      expect(session.previewMetaOp(address, 0.2), isA<AcceptedEdit>());
      expect(session.previewMetaOp(address, 0.6), isA<AcceptedEdit>());
      expect(session.recipe.exposure, 0.6);
      expect(session.recipe.warmth, 0.25);

      final rejected = session.previewMetaOp(address, 2) as RejectedEdit;
      expect(rejected.reason, EditRejection.outOfRange);
      expect(session.recipe.exposure, 0.6);

      session.commitAdjustment();
      session.undo();
      expect(session.recipe, EditRecipe(warmth: 0.25));

      expect(session.applyMetaOp(address, 0.4), isA<AcceptedEdit>());
      expect(session.applyMetaOp(address, 0), isA<AcceptedEdit>());
      expect(session.recipe.exposure, 0);
      session.undo();
      expect(session.recipe.exposure, 0.4);
    });

    test(
      'previews current-photo quality through the same meta-op contract',
      () {
        final session = EditorSession()
          ..setPlatformCapabilities(iosMetaOpCapabilities);
        const address = OpAddress(
          metaOpId: MetaOpIds.noiseReduction,
          metaOpVersion: 1,
          parameterId: 'value',
          scope: EditScope.currentPhoto,
          photoId: 'photo-1',
        );

        session.beginAdjustment();
        expect(session.previewMetaOp(address, 20), isA<AcceptedEdit>());
        expect(session.previewMetaOp(address, 45), isA<AcceptedEdit>());
        expect(session.recipe.qualityEnhancementRecipe.noiseReduction, 45);
        session.commitAdjustment();
        session.undo();
        expect(session.recipe.qualityEnhancementRecipe.noiseReduction, 0);
      },
    );

    test('search discovers only meta ops admitted for this session', () {
      final session = EditorSession();

      expect(session.searchAvailableMetaOps('饱和度'), [MetaOpIds.saturation]);
      expect(session.searchAvailableMetaOps('磨皮'), isEmpty);
      expect(session.searchAvailableMetaOps('不存在'), isEmpty);
    });

    test('portrait target focus is not an undoable effect by itself', () {
      final session = EditorSession(
        initialRecipe: EditRecipe(
          portraitGeometryRecipe: PortraitGeometryRecipe(
            faceTargets: [FaceGeometryTarget(), FaceGeometryTarget()],
          ),
        ),
      );

      session.selectPortraitTarget(
        session.recipe.copyWith(
          portraitGeometryRecipe: session.recipe.portraitGeometryRecipe
              .selectFace(1),
        ),
      );

      expect(session.recipe.portraitGeometryRecipe.selectedFaceIndex, 1);
      expect(session.canUndo, isFalse);

      session.beginAdjustment();
      session.preview(
        session.recipe.copyWith(
          portraitGeometryRecipe: session.recipe.portraitGeometryRecipe
              .updateSelectedFace((target) => target.copyWith(faceSlim: 30)),
        ),
      );
      session.commitAdjustment();

      expect(session.canUndo, isTrue);
      session.undo();
      expect(session.recipe.portraitGeometryRecipe.selectedFaceIndex, 1);
      expect(session.recipe.portraitGeometryRecipe.faceTargets[1].faceSlim, 0);
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

    test('recent AI meta ops lead the next manual tool opening', () {
      final session = EditorSession();

      session.load(
        EditRecipe(saturation: 0.2, warmth: 0.1),
        prioritizedMetaOpIds: const [MetaOpIds.saturation, MetaOpIds.warmth],
      );

      expect(session.orderedManualMetaOpIds().take(5), [
        MetaOpIds.saturation,
        MetaOpIds.warmth,
        MetaOpIds.exposure,
        MetaOpIds.highlights,
        MetaOpIds.shadows,
      ]);
    });
  });
}
