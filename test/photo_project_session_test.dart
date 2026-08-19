import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/application/ai_edit_planner.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/editing_resource.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/portrait_retouch_recipe.dart';
import 'package:yingjian/features/editor/domain/quality_enhancement_recipe.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

void main() {
  group('PhotoProjectSession', () {
    test('publishes empty, importing, then saved analyzing flow', () async {
      final store = _DeferredSavePhotoProjectStore();
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const [
          ProjectPhoto(
            id: 'photo-1',
            localPath: '/app/media/photo-1.jpg',
            originalName: 'first.jpg',
          ),
        ]),
        store: store,
      );

      expect(session.flowState, PhotoProjectFlowState.empty);
      final importing = session.importPhotos();
      while (store.pendingProject == null) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(session.flowState, PhotoProjectFlowState.importing);
      expect(session.project, isNull);

      store.allowSave.complete();
      await importing;

      expect(session.flowState, PhotoProjectFlowState.analyzing);
      expect(session.project, store.savedProject);
    });

    test('imports up to six app-owned photos and saves the project', () async {
      final importer = _FakePhotoImporter([
        const ProjectPhoto(
          id: 'photo-1',
          localPath: '/app/media/photo-1.jpg',
          originalName: 'first.jpg',
        ),
        const ProjectPhoto(
          id: 'photo-2',
          localPath: '/app/media/photo-2.heic',
          originalName: 'second.heic',
        ),
      ]);
      final store = _MemoryPhotoProjectStore();
      final session = PhotoProjectSession(
        importer: importer,
        store: store,
        now: () => DateTime.utc(2026, 8, 4, 5),
        createId: () => 'project-1',
      );

      final result = await session.importPhotos();

      expect(result, PhotoImportResult.imported);
      expect(importer.requestedLimits, [6]);
      expect(session.project?.id, 'project-1');
      expect(session.photos, hasLength(2));
      expect(session.photos.first.localPath, '/app/media/photo-1.jpg');
      expect(store.savedProject, session.project);
      expect(session.project?.flowState, PhotoProjectFlowState.analyzing);
    });

    test(
      'rejects a project flow transition that skips required stages',
      () async {
        final saved = PhotoProject(
          id: 'project-1',
          createdAt: DateTime.utc(2026, 8, 4),
          updatedAt: DateTime.utc(2026, 8, 4),
          photos: const [
            ProjectPhoto(
              id: 'photo-1',
              localPath: '/app/media/photo-1.jpg',
              originalName: 'first.jpg',
            ),
          ],
          flowState: PhotoProjectFlowState.analyzing,
          analysisStates: const {'photo-1': PhotoAnalysisState.ready},
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();

        expect(
          () => session.transitionTo(PhotoProjectFlowState.exporting),
          throwsStateError,
        );
        expect(session.project, saved);
        expect(store.savedProject, saved);
      },
    );

    test('does not finish analysis while any photo is still pending', () async {
      final saved = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.analyzing,
        analysisStates: const {
          'photo-1': PhotoAnalysisState.ready,
          'photo-2': PhotoAnalysisState.pending,
        },
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();

      await expectLater(
        session.transitionTo(PhotoProjectFlowState.choosingRecommendation),
        throwsStateError,
      );

      expect(session.project, saved);
    });

    test(
      'starts a scoped export while untouched photos stay unqueued',
      () async {
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'clean-natural-01',
          exportStates: const {
            'photo-1': PhotoExportState.queued,
            'photo-2': PhotoExportState.notQueued,
          },
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();

        await session.transitionTo(PhotoProjectFlowState.exporting);

        expect(session.project?.flowState, PhotoProjectFlowState.exporting);
        expect(
          session.project?.exportStates['photo-2'],
          PhotoExportState.notQueued,
        );
      },
    );

    test('retries queued failures without re-queuing saved photos', () async {
      final saved = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.editing,
        selectedRecommendationId: 'clean-natural-01',
        exportStates: const {
          'photo-1': PhotoExportState.saved,
          'photo-2': PhotoExportState.queued,
        },
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();

      await session.transitionTo(PhotoProjectFlowState.exporting);

      expect(session.project?.flowState, PhotoProjectFlowState.exporting);
      expect(session.project?.exportStates['photo-1'], PhotoExportState.saved);
      expect(store.savedProject, session.project);
    });

    test('does not finish export while a photo is still running', () async {
      final saved = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.exporting,
        selectedRecommendationId: 'clean-natural-01',
        exportStates: const {
          'photo-1': PhotoExportState.saved,
          'photo-2': PhotoExportState.running,
        },
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();

      await expectLater(
        session.transitionTo(PhotoProjectFlowState.exported),
        throwsStateError,
      );

      expect(session.project, saved);
    });

    test(
      'keeps the last safe state when a flow transition cannot be saved',
      () async {
        final saved = PhotoProject(
          id: 'project-1',
          createdAt: DateTime.utc(2026, 8, 4),
          updatedAt: DateTime.utc(2026, 8, 4),
          photos: const [
            ProjectPhoto(
              id: 'photo-1',
              localPath: '/app/media/photo-1.jpg',
              originalName: 'first.jpg',
            ),
          ],
          flowState: PhotoProjectFlowState.analyzing,
          analysisStates: const {'photo-1': PhotoAnalysisState.ready},
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();
        store.failOnSave = true;

        await expectLater(
          session.transitionTo(PhotoProjectFlowState.choosingRecommendation),
          throwsA(isA<FileSystemException>()),
        );

        expect(session.project, saved);
        expect(store.savedProject, saved);
      },
    );

    test(
      'selects a recommendation and enters editing in one saved snapshot',
      () async {
        final saved = PhotoProject(
          id: 'project-1',
          createdAt: DateTime.utc(2026, 8, 4),
          updatedAt: DateTime.utc(2026, 8, 4),
          photos: const [
            ProjectPhoto(
              id: 'photo-1',
              localPath: '/app/media/photo-1.jpg',
              originalName: 'first.jpg',
            ),
            ProjectPhoto(
              id: 'photo-2',
              localPath: '/app/media/photo-2.jpg',
              originalName: 'second.jpg',
            ),
          ],
          flowState: PhotoProjectFlowState.choosingRecommendation,
          analysisStates: const {
            'photo-1': PhotoAnalysisState.ready,
            'photo-2': PhotoAnalysisState.fallback,
          },
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
          now: () => DateTime.utc(2026, 8, 4, 1),
        );
        await session.restore();

        await session.selectRecommendation(
          recommendationId: 'clean-natural-01',
          sharedStyle: SharedStyle(
            recipe: EditRecipe(exposure: 0.2, warmth: 0.1),
          ),
          adaptiveCompensations: {
            'photo-2': AdaptiveCompensation(
              source: AdaptiveCompensationSource.safeFallbackV1,
              recipe: EditRecipe(exposure: -0.1),
              portraitStrength: 0.35,
            ),
          },
        );

        expect(session.project?.selectedRecommendationId, 'clean-natural-01');
        expect(session.project?.flowState, PhotoProjectFlowState.editing);
        expect(
          session.project?.sharedStyle.recipe,
          EditRecipe(exposure: 0.2, warmth: 0.1),
        );
        expect(
          session.project?.adaptiveCompensations['photo-2']?.recipe,
          EditRecipe(exposure: -0.1),
        );
        expect(session.project?.undoHistory, hasLength(1));
        expect(session.project?.editState.version, 1);
        await session.undoEdit();
        expect(session.project?.sharedStyle.recipe, EditRecipe.neutral);
        expect(session.project?.editState, EditState.empty);
        await session.redoEdit();
        expect(
          session.project?.sharedStyle.recipe,
          EditRecipe(exposure: 0.2, warmth: 0.1),
        );
        await session.setEditingScope(
          ProjectEditingScope.currentPhoto,
          photoId: 'photo-2',
        );
        expect(session.editableRecipe.portraitRecipe.textureSmoothing, 35);
        expect(
          session
              .previewRecipeFor('photo-2', session.editableRecipe)
              .portraitRecipe
              .textureSmoothing,
          35,
        );

        await session.commitLegacyRecipeForTesting(EditRecipe.neutral);
        expect(
          session.effectiveRecipeFor('photo-2').portraitRecipe.isNeutral,
          isTrue,
        );
        expect(session.project?.photoOverrides, contains('photo-2'));

        await session.undoEdit();
        expect(
          session.effectiveRecipeFor('photo-2').portraitRecipe.textureSmoothing,
          35,
        );
        expect(store.savedProject, session.project);
      },
    );

    test('does not enter editing without a selected recommendation', () async {
      final saved = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.choosingRecommendation,
        selectedRecommendationId: null,
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();

      await expectLater(
        session.transitionTo(PhotoProjectFlowState.editing),
        throwsStateError,
      );

      expect(session.project, saved);
    });

    test(
      'a new recommendation preserves prior edits and resets export state',
      () async {
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.choosingRecommendation,
          photoOverrides: {
            'photo-2': PhotoOverride(recipe: EditRecipe(contrast: 0.3)),
          },
          exportStates: const {
            'photo-1': PhotoExportState.saved,
            'photo-2': PhotoExportState.saved,
          },
          undoHistory: [
            ProjectEditOperation(
              scope: ProjectEditingScope.currentPhoto,
              photoId: 'photo-2',
              beforeRecipe: EditRecipe.neutral,
              afterRecipe: EditRecipe(contrast: 0.3),
            ),
          ],
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();

        await session.selectRecommendation(
          recommendationId: 'texture-01',
          sharedStyle: SharedStyle(recipe: EditRecipe(warmth: -0.2)),
        );

        expect(session.project?.photoOverrides['photo-2'], isNotNull);
        expect(session.project?.undoHistory, hasLength(1));
        expect(session.project?.redoHistory, isEmpty);
        expect(session.project?.exportStates, {
          'photo-1': PhotoExportState.notQueued,
          'photo-2': PhotoExportState.notQueued,
        });
      },
    );

    test('persists an explicit current-photo editing scope', () async {
      final saved = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.editing,
        selectedRecommendationId: 'clean-natural-01',
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();

      await session.setEditingScope(
        ProjectEditingScope.currentPhoto,
        photoId: 'photo-2',
      );

      expect(session.project?.editingScope, ProjectEditingScope.currentPhoto);
      expect(session.project?.focusPhotoId, 'photo-2');
      final restored = PhotoProject.fromJson(store.savedProject!.toJson());
      expect(restored.editingScope, ProjectEditingScope.currentPhoto);
      expect(restored.focusPhotoId, 'photo-2');
    });

    test(
      'legacy current-photo filter override is not a canonical reset',
      () async {
        final sharedBasic = BasicEditingRecipe(
          filter: PhotoFilter.cinematic,
          filterStrength: 60,
          hsl: {HslChannel.blue: HslAdjustment(saturation: -12)},
        );
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'group-filter',
          sharedStyle: SharedStyle(
            recipe: EditRecipe(basicEditingRecipe: sharedBasic),
          ),
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();

        await session.setEditingScope(
          ProjectEditingScope.currentPhoto,
          photoId: 'photo-2',
        );
        expect(
          session.editableRecipe.basicEditingRecipe.filter,
          PhotoFilter.cinematic,
        );

        await session.commitLegacyRecipeForTesting(EditRecipe.neutral);
        expect(
          session.effectiveRecipeFor('photo-1').basicEditingRecipe.filter,
          PhotoFilter.cinematic,
        );
        expect(
          session.effectiveRecipeFor('photo-2').basicEditingRecipe.filter,
          PhotoFilter.none,
        );
        expect(session.project?.photoOverrides, contains('photo-2'));

        expect(session.canResetScopedEdit, isFalse);
        await session.resetScopedEdit();
        expect(session.project?.photoOverrides, contains('photo-2'));
        expect(
          session.effectiveRecipeFor('photo-2').basicEditingRecipe.filter,
          PhotoFilter.none,
        );
      },
    );

    test(
      'syncs a current filter to the group without promoting photo geometry',
      () async {
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'group-look',
          sharedStyle: SharedStyle(
            intensity: 0.5,
            recipe: EditRecipe(
              basicEditingRecipe: BasicEditingRecipe(
                filter: PhotoFilter.clean,
                filterStrength: 40,
              ),
            ),
          ),
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();
        await session.setEditingScope(
          ProjectEditingScope.currentPhoto,
          photoId: 'photo-2',
        );
        final crop = CropGeometry(left: 0.1, right: 0.9);
        await session.commitLegacyRecipeForTesting(
          EditRecipe(
            basicEditingRecipe: BasicEditingRecipe(
              flipHorizontal: true,
              perspectiveHorizontal: 7,
              filter: PhotoFilter.film,
              filterStrength: 35,
              hsl: {HslChannel.orange: HslAdjustment(saturation: 10)},
            ),
            crop: crop,
          ),
        );

        expect(session.canSyncCurrentPhotoAdjustmentsToGroup, isTrue);
        await session.syncCurrentPhotoAdjustmentsToGroup();

        expect(
          session.project!.sharedStyle.recipe.basicEditingRecipe.filter,
          PhotoFilter.film,
        );
        expect(
          session.project!.sharedStyle.recipe.basicEditingRecipe.filterStrength,
          70,
        );
        expect(
          session.effectiveRecipeFor('photo-1').basicEditingRecipe.filter,
          PhotoFilter.film,
        );
        expect(
          session
              .effectiveRecipeFor('photo-1')
              .basicEditingRecipe
              .filterStrength,
          35,
        );
        final current = session.effectiveRecipeFor('photo-2');
        expect(current.basicEditingRecipe.filter, PhotoFilter.film);
        expect(current.basicEditingRecipe.filterStrength, 35);
        expect(current.basicEditingRecipe.flipHorizontal, isTrue);
        expect(current.basicEditingRecipe.perspectiveHorizontal, 7);
        expect(current.crop, crop);
        expect(
          session.project!.photoOverrides['photo-2']!.overridesBasicLook,
          isFalse,
        );

        await session.undoEdit();
        expect(
          session.project!.sharedStyle.recipe.basicEditingRecipe.filter,
          PhotoFilter.clean,
        );
        expect(
          session.project!.photoOverrides['photo-2']!.overridesBasicLook,
          isTrue,
        );
        expect(
          session.effectiveRecipeFor('photo-2').basicEditingRecipe.filter,
          PhotoFilter.film,
        );
        await session.redoEdit();
        expect(
          session.project!.sharedStyle.recipe.basicEditingRecipe.filter,
          PhotoFilter.film,
        );
        expect(
          session.project!.photoOverrides['photo-2']!.overridesBasicLook,
          isFalse,
        );

        await session.setEditingScope(ProjectEditingScope.group);
        await session.commitLegacyRecipeForTesting(
          session.editableRecipe.copyWith(
            basicEditingRecipe: BasicEditingRecipe(
              filter: PhotoFilter.cinematic,
              filterStrength: 30,
            ),
          ),
        );
        final afterGroupChange = session.effectiveRecipeFor('photo-2');
        expect(
          afterGroupChange.basicEditingRecipe.filter,
          PhotoFilter.cinematic,
        );
        expect(afterGroupChange.basicEditingRecipe.filterStrength, 15);
        expect(afterGroupChange.basicEditingRecipe.flipHorizontal, isTrue);
        expect(afterGroupChange.crop, crop);
      },
    );

    test(
      'restores semantic current-photo history and can undo and redo it',
      () async {
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'clean-natural-01',
          editingScope: ProjectEditingScope.currentPhoto,
          focusPhotoId: 'photo-2',
          sharedStyle: SharedStyle(recipe: EditRecipe(exposure: 0.2)),
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();

        await session.commitLegacyRecipeForTesting(EditRecipe(contrast: 0.3));

        expect(
          session.project?.effectiveRecipeFor('photo-1'),
          EditRecipe(exposure: 0.2),
        );
        expect(
          session.project?.effectiveRecipeFor('photo-2'),
          EditRecipe(exposure: 0.2, contrast: 0.3),
        );
        expect(session.canUndo, isTrue);
        expect(session.canRedo, isFalse);

        final restoredSession = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await restoredSession.restore();
        expect(restoredSession.canUndo, isTrue);

        await restoredSession.undoEdit();
        expect(restoredSession.project?.photoOverrides, isEmpty);
        expect(restoredSession.canRedo, isTrue);

        await restoredSession.redoEdit();
        expect(
          restoredSession.project?.photoOverrides['photo-2']?.recipe,
          EditRecipe(contrast: 0.3),
        );
        expect(restoredSession.canRedo, isFalse);
      },
    );

    test(
      'routes a shareable exposure meta op to the group without a scope choice',
      () async {
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'clean-natural-01',
          editingScope: ProjectEditingScope.currentPhoto,
          focusPhotoId: 'photo-2',
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();

        final result = await session.commitMetaOp(
          address: const OpAddress(
            metaOpId: MetaOpIds.exposure,
            metaOpVersion: 1,
            parameterId: 'value',
            scope: EditScope.group,
          ),
          value: 0.4,
          context: EditContext.ios,
        );

        expect(result, isA<AcceptedEdit>());
        expect(session.project!.sharedStyle.recipe.exposure, 0.4);
        expect(session.project!.editingScope, ProjectEditingScope.currentPhoto);
        expect(session.effectiveRecipeFor('photo-1').exposure, 0.4);
        expect(session.effectiveRecipeFor('photo-2').exposure, 0.4);
        expect(session.project!.undoHistory, hasLength(1));
        expect(
          session.project!.undoHistory.single.scope,
          ProjectEditingScope.group,
        );

        await session.undoEdit();
        expect(session.project!.sharedStyle.recipe.exposure, 0);
        expect(session.effectiveRecipeFor('photo-1').exposure, 0);
        expect(session.effectiveRecipeFor('photo-2').exposure, 0);
        expect(session.project!.editingScope, ProjectEditingScope.currentPhoto);
      },
    );

    test(
      'commits a multi-parameter recommendation as one atomic transaction',
      () async {
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'clean-natural-01',
          editingScope: ProjectEditingScope.currentPhoto,
          focusPhotoId: 'photo-2',
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();
        const exposure = OpAddress(
          metaOpId: MetaOpIds.exposure,
          metaOpVersion: 1,
          parameterId: 'value',
          scope: EditScope.group,
        );
        const contrast = OpAddress(
          metaOpId: MetaOpIds.contrast,
          metaOpVersion: 1,
          parameterId: 'value',
          scope: EditScope.group,
        );

        final rejected = await session.commitMetaOps(
          changes: const [
            MetaOpChange(address: exposure, value: 0.2),
            MetaOpChange(address: contrast, value: 2.0),
          ],
          source: EditSource.recommendation,
          context: EditContext.ios,
        );

        expect(rejected, isA<RejectedEdit>());
        expect(session.project!.sharedStyle.recipe, EditRecipe.neutral);
        expect(session.project!.undoHistory, isEmpty);

        final accepted = await session.commitMetaOps(
          changes: const [
            MetaOpChange(address: exposure, value: 0.2),
            MetaOpChange(address: contrast, value: 0.3),
          ],
          source: EditSource.recommendation,
          context: EditContext.ios,
        );

        expect(accepted, isA<AcceptedEdit>());
        expect(session.project!.editState.version, 1);
        expect(session.project!.editState.valueAt(exposure), 0.2);
        expect(session.project!.editState.valueAt(contrast), 0.3);
        expect(session.project!.sharedStyle.recipe.exposure, 0.2);
        expect(session.project!.sharedStyle.recipe.contrast, 0.3);
        expect(session.project!.undoHistory, hasLength(1));
        await session.undoEdit();
        expect(session.project!.editState.version, 0);
        expect(session.project!.editState.values, isEmpty);
        expect(session.project!.sharedStyle.recipe, EditRecipe.neutral);
        await session.redoEdit();
        expect(session.project!.editState.version, 1);
        expect(session.project!.editState.valueAt(exposure), 0.2);
      },
    );

    test(
      'commits composition geometry to one photo as one transaction',
      () async {
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'clean-natural-01',
          editingScope: ProjectEditingScope.currentPhoto,
          focusPhotoId: 'photo-2',
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();
        OpAddress address(String parameterId) => OpAddress(
          metaOpId: MetaOpIds.compositionGeometry,
          metaOpVersion: 1,
          parameterId: parameterId,
          scope: EditScope.currentPhoto,
          photoId: 'photo-2',
        );

        final result = await session.commitMetaOps(
          changes: [
            MetaOpChange(address: address('left'), value: 0.1),
            MetaOpChange(address: address('right'), value: 0.9),
            MetaOpChange(address: address('quarterTurns'), value: 1),
            MetaOpChange(address: address('flipHorizontal'), value: true),
          ],
          source: EditSource.manual,
          context: const EditContext(
            platform: EditPlatform.ios,
            photoIds: {'photo-2'},
          ),
        );

        expect(result, isA<AcceptedEdit>());
        expect(
          session.effectiveRecipeFor('photo-1').crop,
          CropGeometry.original,
        );
        expect(session.effectiveRecipeFor('photo-2').crop.left, 0.1);
        expect(session.effectiveRecipeFor('photo-2').crop.right, 0.9);
        expect(session.effectiveRecipeFor('photo-2').crop.quarterTurns, 1);
        expect(
          session
              .effectiveRecipeFor('photo-2')
              .basicEditingRecipe
              .flipHorizontal,
          isTrue,
        );
        expect(session.project!.undoHistory, hasLength(1));

        await session.undoEdit();
        expect(session.effectiveRecipeFor('photo-2'), EditRecipe.neutral);
      },
    );

    test('manual composition reset preserves the photo look', () async {
      final look = BasicEditingRecipe(
        filter: PhotoFilter.cinematic,
        filterStrength: 55,
        hsl: {HslChannel.orange: HslAdjustment(saturation: 18)},
        flipHorizontal: true,
        perspectiveVertical: 12,
      );
      final saved = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.editing,
        selectedRecommendationId: 'clean-natural-01',
        editingScope: ProjectEditingScope.currentPhoto,
        focusPhotoId: 'photo-2',
        photoOverrides: {
          'photo-2': PhotoOverride(
            recipe: EditRecipe(basicEditingRecipe: look),
          ),
        },
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();

      final before = session.editableRecipe;
      final result = await session.commitManualRecipe(
        desiredRecipe: before.copyWith(
          crop: CropGeometry.original,
          basicEditingRecipe: before.basicEditingRecipe.copyWith(
            flipHorizontal: false,
            flipVertical: false,
            perspectiveHorizontal: 0,
            perspectiveVertical: 0,
          ),
        ),
        context: const EditContext(
          platform: EditPlatform.ios,
          photoIds: {'photo-1', 'photo-2'},
        ),
      );

      expect(result.result, isA<AcceptedEdit>());
      final current = session.effectiveRecipeFor('photo-2');
      expect(current.basicEditingRecipe.flipHorizontal, isFalse);
      expect(current.basicEditingRecipe.perspectiveVertical, 0);
      expect(current.basicEditingRecipe.filter, PhotoFilter.cinematic);
      expect(current.basicEditingRecipe.filterStrength, 55);
      expect(current.basicEditingRecipe.hsl[HslChannel.orange]?.saturation, 18);
    });

    test(
      'commits filter and HSL to the group as one undoable transaction',
      () async {
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'clean-natural-01',
          editingScope: ProjectEditingScope.currentPhoto,
          focusPhotoId: 'photo-2',
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();
        OpAddress address(String id, String parameterId) => OpAddress(
          metaOpId: id,
          metaOpVersion: 1,
          parameterId: parameterId,
          scope: EditScope.group,
        );

        final rejected = await session.commitMetaOps(
          changes: [
            MetaOpChange(
              address: address(MetaOpIds.filter, 'filter'),
              value: 'none',
            ),
            MetaOpChange(
              address: address(MetaOpIds.filter, 'strength'),
              value: 55.0,
            ),
          ],
          source: EditSource.manual,
          context: EditContext.ios,
        );
        expect(rejected, isA<RejectedEdit>());
        expect(session.project!.sharedStyle.recipe, EditRecipe.neutral);
        expect(session.project!.undoHistory, isEmpty);

        final accepted = await session.commitMetaOps(
          changes: [
            MetaOpChange(
              address: address(MetaOpIds.filter, 'filter'),
              value: 'film',
            ),
            MetaOpChange(
              address: address(MetaOpIds.filter, 'strength'),
              value: 55.0,
            ),
            MetaOpChange(
              address: address(MetaOpIds.hslBlue, 'saturation'),
              value: -18.0,
            ),
          ],
          source: EditSource.manual,
          context: EditContext.ios,
        );

        expect(accepted, isA<AcceptedEdit>());
        for (final photoId in ['photo-1', 'photo-2']) {
          final basic = session.effectiveRecipeFor(photoId).basicEditingRecipe;
          expect(basic.filter, PhotoFilter.film);
          expect(basic.filterStrength, 55);
          expect(basic.hsl[HslChannel.blue]?.saturation, -18);
        }
        expect(session.project!.undoHistory, hasLength(1));
        await session.undoEdit();
        expect(session.project!.sharedStyle.recipe, EditRecipe.neutral);
      },
    );

    test(
      'commits quality output to one photo as one undoable transaction',
      () async {
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'clean-natural-01',
          editingScope: ProjectEditingScope.currentPhoto,
          focusPhotoId: 'photo-2',
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();
        OpAddress address(String id) => OpAddress(
          metaOpId: id,
          metaOpVersion: 1,
          parameterId: 'value',
          scope: EditScope.currentPhoto,
          photoId: 'photo-2',
        );

        final result = await session.commitMetaOps(
          changes: [
            MetaOpChange(address: address(MetaOpIds.noiseReduction), value: 28),
            MetaOpChange(
              address: address(MetaOpIds.detailSharpening),
              value: 16,
            ),
          ],
          source: EditSource.manual,
          context: const EditContext(
            platform: EditPlatform.ios,
            photoIds: {'photo-2'},
          ),
        );

        expect(result, isA<AcceptedEdit>());
        expect(
          session.effectiveRecipeFor('photo-1').qualityEnhancementRecipe,
          QualityEnhancementRecipe.neutral,
        );
        final quality = session
            .effectiveRecipeFor('photo-2')
            .qualityEnhancementRecipe;
        expect(quality.noiseReduction, 28);
        expect(quality.detailSharpening, 16);
        expect(session.project!.undoHistory, hasLength(1));
        await session.undoEdit();
        expect(
          session.effectiveRecipeFor('photo-2').qualityEnhancementRecipe,
          QualityEnhancementRecipe.neutral,
        );
      },
    );

    test('persists, suspends, and explicitly rebinds stable targets', () async {
      const originalDetection = DetectedEditTarget(
        photoId: 'photo-2',
        kind: EditTargetKind.face,
        analysisVersion: 'vision-v1',
        region: NormalizedEditRegion(
          left: 0.1,
          top: 0.2,
          right: 0.35,
          bottom: 0.65,
        ),
      );
      const replacementDetection = DetectedEditTarget(
        photoId: 'photo-2',
        kind: EditTargetKind.face,
        analysisVersion: 'vision-v2',
        region: NormalizedEditRegion(
          left: 0.55,
          top: 0.18,
          right: 0.82,
          bottom: 0.66,
        ),
      );
      final originalRegistry = EditTargetRegistry.seed(const [
        originalDetection,
      ]);
      final targetId = originalRegistry.targets.keys.single;
      final saved = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.editing,
        selectedRecommendationId: 'clean-natural-01',
        editingScope: ProjectEditingScope.currentPhoto,
        focusPhotoId: 'photo-2',
        targetRegistries: {'photo-2': originalRegistry},
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();

      await session.reconcileEditTargets('photo-2', const []);
      expect(
        session.project!.targetRegistries['photo-2']!.target(targetId).status,
        EditTargetStatus.suspended,
      );
      expect(session.project!.undoHistory, isEmpty);

      await session.rebindEditTarget(
        photoId: 'photo-2',
        targetId: targetId,
        detection: replacementDetection,
      );
      var target = session.project!.targetRegistries['photo-2']!.target(
        targetId,
      );
      expect(target.id, targetId);
      expect(target.region, replacementDetection.region);
      expect(target.status, EditTargetStatus.active);
      expect(
        session.project!.undoHistory.single.kind,
        ProjectEditOperationKind.targetRebind,
      );
      final restored = PhotoProject.fromJson(store.savedProject!.toJson());
      expect(restored.undoHistory, session.project!.undoHistory);
      expect(restored.targetRegistries, session.project!.targetRegistries);
      expect(restored, session.project);

      await session.undoEdit();
      target = session.project!.targetRegistries['photo-2']!.target(targetId);
      expect(target.region, originalDetection.region);
      expect(target.status, EditTargetStatus.suspended);
      await session.redoEdit();
      target = session.project!.targetRegistries['photo-2']!.target(targetId);
      expect(target.region, replacementDetection.region);
      expect(target.status, EditTargetStatus.active);
    });

    test(
      'commits targeted portrait meta ops as one undoable transaction',
      () async {
        const detection = DetectedEditTarget(
          photoId: 'photo-2',
          kind: EditTargetKind.face,
          analysisVersion: 'vision-v1',
          region: NormalizedEditRegion(
            left: 0.1,
            top: 0.2,
            right: 0.35,
            bottom: 0.65,
          ),
        );
        final registry = EditTargetRegistry.seed(const [detection]);
        final target = registry.targets.values.single;
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'clean-natural-01',
          editingScope: ProjectEditingScope.currentPhoto,
          focusPhotoId: 'photo-2',
          targetRegistries: {'photo-2': registry},
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();
        OpAddress address(String id) => OpAddress(
          metaOpId: id,
          metaOpVersion: 1,
          parameterId: 'value',
          scope: EditScope.currentPhoto,
          photoId: 'photo-2',
          targetId: target.id,
        );

        final result = await session.commitMetaOps(
          changes: [
            MetaOpChange(address: address(MetaOpIds.skinSmooth), value: 0.42),
            MetaOpChange(
              address: address(MetaOpIds.skinToneLighting),
              value: 0.25,
            ),
            MetaOpChange(
              address: address(MetaOpIds.blemishReduction),
              value: 0.18,
            ),
          ],
          source: EditSource.manual,
          context: EditContext(
            platform: EditPlatform.ios,
            photoIds: const {'photo-2'},
            targetIds: {target.id},
            applicability: const {'photo', 'face'},
          ),
        );

        expect(result, isA<AcceptedEdit>());
        final adjustment = session
            .effectiveRecipeFor('photo-2')
            .targetedPortraitRecipe
            .adjustments[target.id]!;
        expect(adjustment.textureSmoothing, 42);
        expect(adjustment.skinToneLighting, 25);
        expect(adjustment.blemishReduction, 18);
        expect(session.project!.undoHistory, hasLength(1));
        await session.undoEdit();
        expect(
          session
              .effectiveRecipeFor('photo-2')
              .targetedPortraitRecipe
              .isNeutral,
          isTrue,
        );
      },
    );

    test(
      'commits background and local values as one undoable transaction',
      () async {
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'clean-natural-01',
          editingScope: ProjectEditingScope.currentPhoto,
          focusPhotoId: 'photo-2',
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();
        OpAddress address(String parameterId) => OpAddress(
          metaOpId: MetaOpIds.semanticAdjustments,
          metaOpVersion: 1,
          parameterId: parameterId,
          scope: EditScope.currentPhoto,
          photoId: 'photo-2',
        );

        final result = await session.commitMetaOps(
          changes: [
            MetaOpChange(
              address: address('background'),
              value: BackgroundTreatment.white.name,
            ),
            MetaOpChange(address: address('localExposure'), value: 35),
          ],
          source: EditSource.manual,
          context: const EditContext(
            platform: EditPlatform.ios,
            photoIds: {'photo-2'},
          ),
        );

        expect(result, isA<AcceptedEdit>());
        final semantic = session
            .effectiveRecipeFor('photo-2')
            .semanticEditingRecipe;
        expect(semantic.background, BackgroundTreatment.white);
        expect(semantic.localExposure, 35);
        expect(session.project!.undoHistory, hasLength(1));
        await session.undoEdit();
        expect(
          session.effectiveRecipeFor('photo-2').semanticEditingRecipe,
          SemanticEditingRecipe.neutral,
        );
      },
    );

    test(
      'keeps an image resource through current undo and redo ownership',
      () async {
        const sha =
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
        const resourceId = 'resource-v1-$sha';
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'clean-natural-01',
          editingScope: ProjectEditingScope.currentPhoto,
          focusPhotoId: 'photo-2',
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();
        OpAddress address(String parameterId) => OpAddress(
          metaOpId: MetaOpIds.semanticAdjustments,
          metaOpVersion: 1,
          parameterId: parameterId,
          scope: EditScope.currentPhoto,
          photoId: 'photo-2',
        );

        final result = await session.commitMetaOps(
          changes: [
            MetaOpChange(address: address('background'), value: 'image'),
            MetaOpChange(
              address: address('backgroundImageResource'),
              value: resourceId,
            ),
          ],
          source: EditSource.manual,
          context: const EditContext(
            platform: EditPlatform.ios,
            photoIds: {'photo-2'},
          ),
          editingResources: const [
            ImportedEditingResource(
              descriptor: EditingResourceDescriptor(
                id: resourceId,
                kind: EditingResourceKind.backgroundImage,
                relativePath: 'resources/aa/$sha.jpg',
                contentSha256: sha,
                byteLength: 2048,
              ),
              localPath: '/app/resources/aa/$sha.jpg',
            ),
          ],
        );

        expect(result, isA<AcceptedEdit>());
        expect(
          session
              .effectiveRecipeFor('photo-2')
              .semanticEditingRecipe
              .backgroundImagePath,
          '/app/resources/aa/$sha.jpg',
        );
        expect(
          session.project!.editingResources.referenceCount(
            resourceId,
            EditingResourceOwner.currentState,
          ),
          1,
        );
        expect(
          session.project!.editingResources.referenceCount(
            resourceId,
            EditingResourceOwner.undoHistory,
          ),
          1,
        );

        await session.undoEdit();
        expect(
          session.project!.editingResources.referenceCount(
            resourceId,
            EditingResourceOwner.currentState,
          ),
          0,
        );
        expect(
          session.project!.editingResources.referenceCount(
            resourceId,
            EditingResourceOwner.redoHistory,
          ),
          1,
        );

        await session.redoEdit();
        expect(
          session.project!.editingResources.referenceCount(
            resourceId,
            EditingResourceOwner.currentState,
          ),
          1,
        );

        const exposureAddress = OpAddress(
          metaOpId: MetaOpIds.exposure,
          metaOpVersion: 1,
          parameterId: 'value',
          scope: EditScope.group,
        );
        for (var index = 0; index < 19; index++) {
          await session.commitMetaOp(
            address: exposureAddress,
            value: index.isEven ? 0.1 : 0.2,
            context: EditContext.ios,
          );
        }
        expect(session.project!.editCheckpoints.single.editCount, 20);
        expect(
          session.project!.editingResources.referenceCount(
            resourceId,
            EditingResourceOwner.checkpoint,
          ),
          1,
        );
      },
    );

    test('commits a mask resource as one undoable transaction', () async {
      const sha =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      const resourceId = 'resource-v1-$sha';
      final saved = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.editing,
        selectedRecommendationId: 'clean-natural-01',
        editingScope: ProjectEditingScope.currentPhoto,
        focusPhotoId: 'photo-2',
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();
      const address = OpAddress(
        metaOpId: MetaOpIds.semanticAdjustments,
        metaOpVersion: 1,
        parameterId: 'subjectMaskResource',
        scope: EditScope.currentPhoto,
        photoId: 'photo-2',
      );
      const payload = <Object>[
        {
          'operation': 'paint',
          'radius': 0.04,
          'points': [
            [0.5, 0.5],
          ],
        },
      ];

      final result = await session.commitMetaOps(
        changes: const [MetaOpChange(address: address, value: resourceId)],
        source: EditSource.manual,
        context: const EditContext(
          platform: EditPlatform.ios,
          photoIds: {'photo-2'},
        ),
        editingResources: const [
          ImportedEditingResource(
            descriptor: EditingResourceDescriptor(
              id: resourceId,
              kind: EditingResourceKind.subjectMask,
              relativePath: 'resources/bb/$sha.json',
              contentSha256: sha,
              byteLength: 96,
            ),
            localPath: '/app/resources/bb/$sha.json',
            payload: payload,
          ),
        ],
      );

      expect(result, isA<AcceptedEdit>());
      final semantic = session
          .effectiveRecipeFor('photo-2')
          .semanticEditingRecipe;
      expect(semantic.subjectMaskResourceId, resourceId);
      expect(semantic.subjectMaskStrokes, hasLength(1));
      expect(
        session.project!.editingResources.references(
          EditingResourceOwner.currentState,
        ),
        contains(resourceId),
      );
      await session.undoEdit();
      expect(
        session
            .effectiveRecipeFor('photo-2')
            .semanticEditingRecipe
            .subjectMaskStrokes,
        isEmpty,
      );
      expect(
        session.project!.editingResources.references(
          EditingResourceOwner.redoHistory,
        ),
        contains(resourceId),
      );
      await session.redoEdit();
      expect(
        session
            .effectiveRecipeFor('photo-2')
            .semanticEditingRecipe
            .subjectMaskResourceId,
        resourceId,
      );
    });

    test(
      'reclaims a redo-only resource when a new edit ends the branch',
      () async {
        const sha =
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
        const resourceId = 'resource-v1-$sha';
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'clean-natural-01',
          focusPhotoId: 'photo-2',
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();
        OpAddress backgroundAddress(String parameterId) => OpAddress(
          metaOpId: MetaOpIds.semanticAdjustments,
          metaOpVersion: 1,
          parameterId: parameterId,
          scope: EditScope.currentPhoto,
          photoId: 'photo-2',
        );
        await session.commitMetaOps(
          changes: [
            MetaOpChange(
              address: backgroundAddress('background'),
              value: 'image',
            ),
            MetaOpChange(
              address: backgroundAddress('backgroundImageResource'),
              value: resourceId,
            ),
          ],
          source: EditSource.manual,
          context: const EditContext(
            platform: EditPlatform.ios,
            photoIds: {'photo-2'},
          ),
          editingResources: const [
            ImportedEditingResource(
              descriptor: EditingResourceDescriptor(
                id: resourceId,
                kind: EditingResourceKind.backgroundImage,
                relativePath: 'resources/bb/$sha.jpg',
                contentSha256: sha,
                byteLength: 1024,
              ),
              localPath: '/app/resources/bb/$sha.jpg',
            ),
          ],
        );
        await session.undoEdit();

        await session.commitMetaOp(
          address: const OpAddress(
            metaOpId: MetaOpIds.exposure,
            metaOpVersion: 1,
            parameterId: 'value',
            scope: EditScope.group,
          ),
          value: 0.1,
          context: EditContext.ios,
        );

        expect(session.project!.redoHistory, isEmpty);
        expect(
          session.project!.editingResources.resources.containsKey(resourceId),
          isFalse,
        );
      },
    );

    test(
      'persists shared intensity in semantic undo and redo history',
      () async {
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'clean-natural-01',
          sharedStyle: SharedStyle(
            family: SharedStyleFamily.naturalClean,
            intensity: 0.8,
            recipe: EditRecipe(exposure: 0.2),
          ),
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();

        await session.commitSharedIntensity(0.4);

        expect(session.project?.sharedStyle.intensity, closeTo(0.4, 1e-12));
        expect(
          session.effectiveRecipeFor('photo-1').exposure,
          closeTo(0.08, 1e-12),
        );
        await session.undoEdit();
        expect(session.project?.sharedStyle.intensity, closeTo(0.8, 1e-12));
        await session.redoEdit();
        expect(session.project?.sharedStyle.intensity, closeTo(0.4, 1e-12));
        final restored = PhotoProject.fromJson(session.project!.toJson());
        expect(restored.sharedStyle, session.project!.sharedStyle);
        expect(restored.undoHistory, session.project!.undoHistory);
        expect(restored.redoHistory, session.project!.redoHistory);
      },
    );

    test('keeps only the latest one hundred undoable transactions', () async {
      final saved = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.editing,
        selectedRecommendationId: 'clean-natural-01',
        focusPhotoId: 'photo-1',
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();
      const address = OpAddress(
        metaOpId: MetaOpIds.exposure,
        metaOpVersion: 1,
        parameterId: 'value',
        scope: EditScope.group,
      );

      for (var index = 0; index < 105; index++) {
        final result = await session.commitMetaOp(
          address: address,
          value: index.isEven ? 0.1 : 0.2,
          context: EditContext.ios,
        );
        expect(result, isA<AcceptedEdit>());
      }

      expect(
        session.project!.undoHistory,
        hasLength(PhotoProject.maxEditHistoryCount),
      );
      expect(session.project!.foldedEditCount, 5);
      expect(session.project!.historyBaseSnapshot, isNotNull);
      expect(session.project!.editCheckpoints.map((value) => value.editCount), [
        20,
        40,
        60,
        80,
        100,
      ]);
      expect(session.project!.hasValidHistoryReplay, isTrue);
      expect(
        PhotoProject.fromJson(session.project!.toJson()).hasValidHistoryReplay,
        isTrue,
      );
      expect(session.project!.sharedStyle.recipe.exposure, 0.1);
      for (var index = 0; index < PhotoProject.maxEditHistoryCount; index++) {
        await session.undoEdit();
      }
      expect(session.canUndo, isFalse);
      expect(session.project!.sharedStyle.recipe.exposure, 0.1);
      expect(session.project!.redoHistory, hasLength(100));
      expect(session.project!.hasValidHistoryReplay, isTrue);
    });

    test('rejects a persisted project whose history cannot replay', () async {
      final saved = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.editing,
        selectedRecommendationId: 'clean-natural-01',
        focusPhotoId: 'photo-1',
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();
      await session.commitMetaOp(
        address: const OpAddress(
          metaOpId: MetaOpIds.exposure,
          metaOpVersion: 1,
          parameterId: 'value',
          scope: EditScope.group,
        ),
        value: 0.2,
        context: EditContext.ios,
      );

      final valid = session.project!;
      final corrupted = valid.copyWith(
        sharedStyle: SharedStyle(
          recipe: EditRecipe.neutral,
          family: valid.sharedStyle.family,
          intensity: valid.sharedStyle.intensity,
        ),
      );

      expect(
        () => PhotoProject.fromJson(corrupted.toJson()),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'persists an explainable AI history summary without prompts',
      () async {
        const detection = DetectedEditTarget(
          photoId: 'photo-1',
          kind: EditTargetKind.face,
          analysisVersion: 'vision-v1',
          region: NormalizedEditRegion(
            left: 0.1,
            top: 0.2,
            right: 0.4,
            bottom: 0.7,
          ),
        );
        final registry = EditTargetRegistry.seed(const [detection]);
        final targetId = registry.targets.keys.single;
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'clean-natural-01',
          focusPhotoId: 'photo-1',
          targetRegistries: {'photo-1': registry},
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();
        final address = OpAddress(
          metaOpId: MetaOpIds.skinSmooth,
          metaOpVersion: 1,
          parameterId: 'value',
          scope: EditScope.currentPhoto,
          photoId: 'photo-1',
          targetId: targetId,
        );

        final result = await session.commitMetaOps(
          changes: [MetaOpChange(address: address, value: 0.18)],
          source: EditSource.ai,
          context: EditContext(
            platform: EditPlatform.ios,
            photoIds: const {'photo-1'},
            targetIds: {targetId},
            applicability: const {'photo', 'face'},
          ),
        );

        expect(result, isA<AcceptedEdit>());
        final operation = session.project!.undoHistory.single;
        expect(operation.source, EditSource.ai);
        expect(operation.changedAddresses, [address]);
        final json = operation.toJson();
        expect(json['source'], 'ai');
        expect(json['changedAddresses'], hasLength(1));
        expect(json.toString(), isNot(contains('prompt')));
        expect(ProjectEditOperation.fromJson(json), operation);
      },
    );

    test('edit state version is stable until editable state changes', () {
      const detection = DetectedEditTarget(
        photoId: 'photo-1',
        kind: EditTargetKind.face,
        analysisVersion: 'vision-v1',
        region: NormalizedEditRegion(
          left: 0.1,
          top: 0.2,
          right: 0.4,
          bottom: 0.7,
        ),
      );
      final project = _twoPhotoProject().copyWith(
        targetRegistries: {
          'photo-1': EditTargetRegistry.seed(const [detection]),
        },
      );
      final first = project.editStateVersion;

      expect(project.editStateVersion, first);
      expect(PhotoProject.fromJson(project.toJson()).editStateVersion, first);
      expect(project.copyWith(groupScrollOffset: 18).editStateVersion, first);
    });

    test('keeps an unknown-meta-op project read-only in the session', () async {
      final protected = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.editing,
        selectedRecommendationId: 'clean-natural-01',
        unknownMetaOps: const [
          {
            'id': 'future.generative_relight',
            'version': 7,
            'payload': {'mode': 'cinematic'},
          },
        ],
      );
      final store = _MemoryPhotoProjectStore()..savedProject = protected;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();

      await expectLater(
        session.commitMetaOp(
          address: const OpAddress(
            metaOpId: MetaOpIds.exposure,
            metaOpVersion: 1,
            parameterId: 'value',
            scope: EditScope.group,
          ),
          value: 0.2,
          context: EditContext.ios,
        ),
        throwsA(isA<StateError>()),
      );

      expect(session.project, protected);
      expect(store.savedProject, protected);
    });

    test(
      'applies one current AI proposal and rejects its stale reuse',
      () async {
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'clean-natural-01',
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();
        const address = OpAddress(
          metaOpId: MetaOpIds.exposure,
          metaOpVersion: 1,
          parameterId: 'value',
          scope: EditScope.group,
        );
        final proposal = AiEditProposal(
          baseStateVersion: session.project!.editStateVersion,
          changes: const [MetaOpChange(address: address, value: 0.2)],
          summary: const [MetaOpIds.exposure],
        );

        final accepted = await session.commitAiProposal(
          proposal,
          context: EditContext.ios,
        );
        final stale = await session.commitAiProposal(
          proposal,
          context: EditContext.ios,
        );

        expect(accepted, isA<AcceptedEdit>());
        expect(stale, isA<RejectedEdit>());
        expect(
          (stale as RejectedEdit).reason,
          EditRejection.duplicateTransaction,
        );
        expect(proposal.proposalId, startsWith('proposal-v1-'));
        expect(proposal.idempotencyKey, startsWith('ai-edit-v1-'));
        expect(session.project!.sharedStyle.recipe.exposure, 0.2);
        expect(session.project!.undoHistory, hasLength(1));
        expect(session.project!.undoHistory.single.source, EditSource.ai);
      },
    );

    test(
      'resets the group recipe and intensity as one undoable edit',
      () async {
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'group-reset',
          sharedStyle: SharedStyle(
            intensity: 0.4,
            recipe: EditRecipe(
              exposure: 0.2,
              basicEditingRecipe: BasicEditingRecipe(
                filter: PhotoFilter.film,
                filterStrength: 60,
              ),
            ),
          ),
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();
        final beforeResetVersion = session.project!.editState.version;

        await session.resetScopedEdit();

        expect(session.project!.sharedStyle.recipe, EditRecipe.neutral);
        expect(session.project!.sharedStyle.intensity, 1);
        expect(session.project!.editState.version, beforeResetVersion + 1);
        expect(session.project!.undoHistory, hasLength(1));
        await session.undoEdit();
        expect(session.project!.sharedStyle, saved.sharedStyle);
        await session.redoEdit();
        expect(session.project!.sharedStyle.recipe, EditRecipe.neutral);
        expect(session.project!.sharedStyle.intensity, 1);
      },
    );

    test(
      'stale legacy intensity is not exposed as a canonical reset',
      () async {
        final store = _MemoryPhotoProjectStore()
          ..savedProject = _twoPhotoProject().copyWith(
            flowState: PhotoProjectFlowState.editing,
            selectedRecommendationId: 'neutral-strength',
            sharedStyle: SharedStyle(
              intensity: 0.4,
              recipe: EditRecipe.neutral,
            ),
          );
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();

        expect(session.canResetScopedEdit, isFalse);
        await session.resetScopedEdit();

        expect(session.project!.sharedStyle.intensity, 0.4);
        expect(session.canResetScopedEdit, isFalse);
      },
    );

    test(
      'syncs current color adjustments to the group as one undoable operation',
      () async {
        final crop = CropGeometry(left: 0.1, right: 0.9);
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'clean-natural-01',
          editingScope: ProjectEditingScope.currentPhoto,
          focusPhotoId: 'photo-2',
          sharedStyle: SharedStyle(
            family: SharedStyleFamily.naturalClean,
            intensity: 0.5,
            recipe: EditRecipe(exposure: 0.25, warmth: 0.25),
          ),
          adaptiveCompensations: {
            'photo-2': AdaptiveCompensation(
              recipe: EditRecipe(exposure: 0.05),
              source: AdaptiveCompensationSource.localAnalysisV1,
              safeSharedIntensity: 0.25,
            ),
          },
          photoOverrides: {
            'photo-2': PhotoOverride(
              recipe: EditRecipe(
                exposure: 0.125,
                contrast: 0.25,
                faceSlimStrength: 0.25,
                bodySlimStrength: 0.15,
                crop: crop,
              ),
            ),
          },
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();
        final beforeCurrent = session.project!.effectiveRecipeFor('photo-2');

        await session.syncCurrentPhotoAdjustmentsToGroup();

        expect(session.project?.undoHistory, hasLength(1));
        expect(session.project?.editingScope, ProjectEditingScope.currentPhoto);
        expect(session.project?.sharedStyle.intensity, 0.5);
        expect(
          session.project?.sharedStyle.recipe,
          EditRecipe(exposure: 0.75, warmth: 0.25, contrast: 1),
        );
        expect(
          session.project?.photoOverrides['photo-2']?.recipe,
          EditRecipe(
            faceSlimStrength: 0.25,
            bodySlimStrength: 0.15,
            crop: crop,
          ),
        );
        expect(session.project?.effectiveRecipeFor('photo-2'), beforeCurrent);
        expect(
          session.project?.effectiveRecipeFor('photo-1'),
          EditRecipe(exposure: 0.375, warmth: 0.125, contrast: 0.5),
        );

        await session.undoEdit();
        expect(session.project?.sharedStyle, saved.sharedStyle);
        expect(session.project?.photoOverrides, saved.photoOverrides);
        await session.redoEdit();
        expect(session.project?.sharedStyle.intensity, 0.5);
        final restored = PhotoProject.fromJson(store.savedProject!.toJson());
        expect(restored.sharedStyle, session.project?.sharedStyle);
        expect(restored.photoOverrides, session.project?.photoOverrides);
        expect(restored.undoHistory, session.project?.undoHistory);
        expect(restored.redoHistory, session.project?.redoHistory);
      },
    );

    test(
      'legacy portrait override is not exposed as a canonical reset',
      () async {
        final adaptivePortrait = PortraitRetouchRecipe(textureSmoothing: 35);
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'clean-natural-01',
          editingScope: ProjectEditingScope.currentPhoto,
          focusPhotoId: 'photo-2',
          adaptiveCompensations: {
            'photo-2': AdaptiveCompensation(
              recipe: EditRecipe.neutral,
              source: AdaptiveCompensationSource.localAnalysisV1,
              portraitRecipe: adaptivePortrait,
            ),
          },
          photoOverrides: {
            'photo-2': PhotoOverride(
              recipe: EditRecipe(portraitRecipe: adaptivePortrait),
            ),
          },
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();

        await session.resetScopedEdit();

        expect(session.canResetScopedEdit, isFalse);
        expect(session.project?.photoOverrides, contains('photo-2'));
        expect(
          session.effectiveRecipeFor('photo-2').portraitRecipe.textureSmoothing,
          35,
        );
        expect(session.project?.undoHistory, isEmpty);

        await session.undoEdit();
        expect(
          session.project?.photoOverrides['photo-2']?.recipe,
          saved.photoOverrides['photo-2']?.recipe,
        );
        await session.redoEdit();
        expect(session.project?.photoOverrides, contains('photo-2'));
        expect(
          session.effectiveRecipeFor('photo-2').portraitRecipe.textureSmoothing,
          35,
        );
      },
    );

    test(
      'restores history after a photo override is fully synced to the group',
      () async {
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'clean-natural-01',
          editingScope: ProjectEditingScope.currentPhoto,
          focusPhotoId: 'photo-2',
          sharedStyle: SharedStyle(recipe: EditRecipe(exposure: 0.1)),
          photoOverrides: {
            'photo-2': PhotoOverride(recipe: EditRecipe(contrast: 0.2)),
          },
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();

        await session.syncCurrentPhotoAdjustmentsToGroup();
        final restored = PhotoProject.fromJson(session.project!.toJson());

        expect(restored.photoOverrides, isEmpty);
        expect(
          restored.undoHistory.single.kind,
          ProjectEditOperationKind.syncCurrentPhotoToGroup,
        );
      },
    );

    test(
      'persists the group photo-strip position across restoration',
      () async {
        final store = _MemoryPhotoProjectStore()
          ..savedProject = _twoPhotoProject().copyWith(
            flowState: PhotoProjectFlowState.editing,
          );
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();

        await session.setGroupScrollOffset(144);

        expect(session.project?.groupScrollOffset, 144);
        final restored = PhotoProject.fromJson(store.savedProject!.toJson());
        expect(restored.groupScrollOffset, 144);
      },
    );

    test('does not mutate edit history while export is active', () async {
      final operation = ProjectEditOperation(
        scope: ProjectEditingScope.group,
        beforeRecipe: EditRecipe.neutral,
        afterRecipe: EditRecipe(exposure: 0.2),
      );
      final saved = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.exporting,
        sharedStyle: SharedStyle(recipe: operation.afterRecipe),
        undoHistory: [operation],
        exportStates: const {
          'photo-1': PhotoExportState.running,
          'photo-2': PhotoExportState.queued,
        },
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();

      await expectLater(session.undoEdit(), throwsStateError);

      expect(session.project, saved);
      expect(store.savedProject, saved);
    });

    test(
      'keeps the last edit snapshot when a semantic edit cannot be saved',
      () async {
        final saved = _twoPhotoProject().copyWith(
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'clean-natural-01',
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
        );
        await session.restore();
        store.failOnSave = true;

        await expectLater(
          session.commitLegacyRecipeForTesting(EditRecipe(exposure: 0.3)),
          throwsA(isA<FileSystemException>()),
        );

        expect(session.project, saved);
        expect(store.savedProject, saved);
        expect(session.canUndo, isFalse);
      },
    );

    test('keeps recommendation choice unpublished when saving fails', () async {
      final saved = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.choosingRecommendation,
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();
      store.failOnSave = true;

      await expectLater(
        session.selectRecommendation(
          recommendationId: 'clean-natural-01',
          sharedStyle: SharedStyle(recipe: EditRecipe(exposure: 0.2)),
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(session.project, saved);
      expect(store.savedProject, saved);
    });

    test(
      'removes newly copied photos when the project cannot be saved',
      () async {
        const copied = ProjectPhoto(
          id: 'photo-new',
          localPath: '/app/media/photo-new.jpg',
          originalName: 'new.jpg',
        );
        final store = _MemoryPhotoProjectStore()..failOnSave = true;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const [copied]),
          store: store,
        );

        await expectLater(
          session.importPhotos(),
          throwsA(isA<FileSystemException>()),
        );

        expect(session.project, isNull);
        expect(store.deletedPhotoIds, ['photo-new']);
      },
    );

    test('restores the latest saved project before editing', () async {
      final saved = PhotoProject(
        id: 'project-restored',
        createdAt: DateTime.utc(2026, 8, 3),
        updatedAt: DateTime.utc(2026, 8, 4),
        photos: const [
          ProjectPhoto(
            id: 'photo-restored',
            localPath: '/app/media/restored.jpg',
            originalName: 'restored.jpg',
          ),
        ],
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );

      await session.restore();

      expect(session.project, saved);
      expect(session.photos.single.originalName, 'restored.jpg');
    });

    test(
      'persists a single-photo edit as reversible project history',
      () async {
        final store = _MemoryPhotoProjectStore()
          ..savedProject = PhotoProject(
            id: 'project-1',
            createdAt: DateTime.utc(2026, 8, 4, 5),
            updatedAt: DateTime.utc(2026, 8, 4, 5),
            photos: const [
              ProjectPhoto(
                id: 'photo-1',
                localPath: '/app/media/photo-1.jpg',
                originalName: 'first.jpg',
              ),
            ],
            flowState: PhotoProjectFlowState.editing,
            selectedRecommendationId: 'clean-natural-01',
          );
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
          now: () => DateTime.utc(2026, 8, 4, 6),
        );
        await session.restore();
        final recipe = EditRecipe(exposure: 0.3, contrast: 0.2, warmth: -0.1);

        await session.commitLegacyRecipeForTesting(recipe);

        expect(session.project?.photoOverrides['photo-1']?.recipe, recipe);
        expect(store.savedProject?.undoHistory, hasLength(1));
        expect(store.savedProject?.updatedAt, DateTime.utc(2026, 8, 4, 6));
      },
    );

    test(
      'keeps startup available when the saved project is unreadable',
      () async {
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: _FailingPhotoProjectStore(),
        );

        await session.restore();

        expect(session.photos, isEmpty);
        expect(session.restoreError, isA<FormatException>());
      },
    );

    test('treats closing the system picker as a cancellation', () async {
      final store = _MemoryPhotoProjectStore();
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );

      final result = await session.importPhotos();

      expect(result, PhotoImportResult.canceled);
      expect(session.project, isNull);
      expect(store.savedProject, isNull);
    });

    test(
      'does not open the picker after a project reaches six photos',
      () async {
        final saved = PhotoProject(
          id: 'full-project',
          createdAt: DateTime.utc(2026, 8, 4),
          updatedAt: DateTime.utc(2026, 8, 4),
          photos: List.generate(
            6,
            (index) => ProjectPhoto(
              id: 'photo-$index',
              localPath: '/app/media/photo-$index.jpg',
              originalName: 'photo-$index.jpg',
            ),
          ),
        );
        final importer = _FakePhotoImporter(const []);
        final session = PhotoProjectSession(
          importer: importer,
          store: _MemoryPhotoProjectStore()..savedProject = saved,
        );
        await session.restore();

        final result = await session.importPhotos();

        expect(result, PhotoImportResult.limitReached);
        expect(importer.requestedLimits, isEmpty);
      },
    );

    test(
      'publishes valid photos and item-level import failures together',
      () async {
        final importer = _FakePhotoImporter(
          const [
            ProjectPhoto(
              id: 'photo-1',
              localPath: '/app/media/photo-1.jpg',
              originalName: 'valid.jpg',
            ),
          ],
          failures: const [
            PhotoImportFailure(
              photoName: 'animated.png',
              reason: PhotoImportFailureReason.animatedImage,
            ),
          ],
        );
        final session = PhotoProjectSession(
          importer: importer,
          store: _MemoryPhotoProjectStore(),
        );

        final result = await session.importPhotos();

        expect(result, PhotoImportResult.imported);
        expect(session.photos.single.originalName, 'valid.jpg');
        expect(session.importFailures, importer.failures);
      },
    );

    test('changing project inputs invalidates derived editing state', () async {
      final operation = ProjectEditOperation(
        scope: ProjectEditingScope.group,
        beforeRecipe: EditRecipe.neutral,
        afterRecipe: EditRecipe(exposure: 0.2),
      );
      final existing = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.editing,
        selectedRecommendationId: 'clean-natural-01',
        sharedStyle: SharedStyle(recipe: operation.afterRecipe),
        adaptiveCompensations: {
          'photo-1': AdaptiveCompensation(
            source: AdaptiveCompensationSource.localAnalysisV1,
            recipe: EditRecipe(exposure: -0.1),
          ),
        },
        photoOverrides: {
          'photo-2': PhotoOverride(recipe: EditRecipe(contrast: 0.3)),
        },
        analysisStates: const {
          'photo-1': PhotoAnalysisState.ready,
          'photo-2': PhotoAnalysisState.ready,
        },
        exportStates: const {
          'photo-1': PhotoExportState.saved,
          'photo-2': PhotoExportState.saved,
        },
        undoHistory: [operation],
      );
      const added = ProjectPhoto(
        id: 'photo-3',
        localPath: '/app/media/photo-3.jpg',
        originalName: 'third.jpg',
      );
      final store = _MemoryPhotoProjectStore()..savedProject = existing;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const [added]),
        store: store,
      );
      await session.restore();

      await session.importPhotos();

      expect(session.project?.flowState, PhotoProjectFlowState.analyzing);
      expect(session.project?.selectedRecommendationId, isNull);
      expect(session.project?.sharedStyle.recipe, EditRecipe.neutral);
      expect(session.project?.adaptiveCompensations, isEmpty);
      expect(session.project?.photoOverrides, isEmpty);
      expect(
        session.project?.analysisStates.values,
        everyElement(PhotoAnalysisState.pending),
      );
      expect(
        session.project?.exportStates.values,
        everyElement(PhotoExportState.notQueued),
      );
      expect(session.project?.undoHistory, isEmpty);
      expect(session.project?.redoHistory, isEmpty);
    });

    test('does not change project inputs while export is active', () async {
      final saved = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.exporting,
        exportStates: const {
          'photo-1': PhotoExportState.running,
          'photo-2': PhotoExportState.queued,
        },
      );
      final importer = _FakePhotoImporter(const [
        ProjectPhoto(
          id: 'photo-3',
          localPath: '/app/media/photo-3.jpg',
          originalName: 'third.jpg',
        ),
      ]);
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(importer: importer, store: store);
      await session.restore();

      await expectLater(session.importPhotos(), throwsStateError);

      expect(importer.requestedLimits, isEmpty);
      expect(session.project, saved);
    });

    test('does not reorder or remove inputs while export is active', () async {
      final saved = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.exporting,
        exportStates: const {
          'photo-1': PhotoExportState.running,
          'photo-2': PhotoExportState.queued,
        },
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();

      await expectLater(
        session.movePhoto(photoId: 'photo-2', toIndex: 0),
        throwsStateError,
      );
      await expectLater(session.removePhoto('photo-2'), throwsStateError);

      expect(session.project, saved);
      expect(store.deletedPhotoIds, isEmpty);
    });

    test(
      'moves a photo and saves the new project order before publishing',
      () async {
        final saved = PhotoProject(
          id: 'project-1',
          createdAt: DateTime.utc(2026, 8, 4),
          updatedAt: DateTime.utc(2026, 8, 4),
          photos: const [
            ProjectPhoto(
              id: 'photo-1',
              localPath: '/app/media/photo-1.jpg',
              originalName: 'first.jpg',
            ),
            ProjectPhoto(
              id: 'photo-2',
              localPath: '/app/media/photo-2.jpg',
              originalName: 'second.jpg',
            ),
          ],
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
          now: () => DateTime.utc(2026, 8, 4, 1),
        );
        await session.restore();

        await session.movePhoto(photoId: 'photo-2', toIndex: 0);

        expect(session.photos.map((photo) => photo.id), ['photo-2', 'photo-1']);
        expect(store.savedProject, session.project);
        expect(session.project?.updatedAt, DateTime.utc(2026, 8, 4, 1));
      },
    );

    test('selects and persists the focus photo', () async {
      final saved = PhotoProject(
        id: 'project-1',
        createdAt: DateTime.utc(2026, 8, 4),
        updatedAt: DateTime.utc(2026, 8, 4),
        photos: const [
          ProjectPhoto(
            id: 'photo-1',
            localPath: '/app/media/photo-1.jpg',
            originalName: 'first.jpg',
          ),
          ProjectPhoto(
            id: 'photo-2',
            localPath: '/app/media/photo-2.jpg',
            originalName: 'second.jpg',
          ),
        ],
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
        now: () => DateTime.utc(2026, 8, 4, 2),
      );
      await session.restore();

      await session.setFocusPhoto('photo-2');

      expect(session.project?.focusPhotoId, 'photo-2');
      expect(store.savedProject, session.project);
    });

    test('persists a stable analysis state for one project photo', () async {
      final saved = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.analyzing,
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();

      await session.setPhotoAnalysisState(
        'photo-2',
        PhotoAnalysisState.running,
      );
      await session.setPhotoAnalysisState('photo-2', PhotoAnalysisState.ready);

      expect(session.project?.analysisStates, {
        'photo-1': PhotoAnalysisState.pending,
        'photo-2': PhotoAnalysisState.ready,
      });
      expect(store.savedProject, session.project);
    });

    test('rejects an analysis state that skips execution', () async {
      final saved = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.analyzing,
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();

      await expectLater(
        session.setPhotoAnalysisState('photo-1', PhotoAnalysisState.ready),
        throwsStateError,
      );

      expect(session.project, saved);
      expect(store.savedProject, saved);
    });

    test('rejects per-photo task updates outside their owning phase', () async {
      final editing = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.editing,
        selectedRecommendationId: 'clean-natural-01',
      );
      final editingStore = _MemoryPhotoProjectStore()..savedProject = editing;
      final editingSession = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: editingStore,
      );
      await editingSession.restore();

      await expectLater(
        editingSession.setPhotoAnalysisState(
          'photo-1',
          PhotoAnalysisState.running,
        ),
        throwsStateError,
      );

      final analyzing = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.analyzing,
      );
      final analyzingStore = _MemoryPhotoProjectStore()
        ..savedProject = analyzing;
      final analyzingSession = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: analyzingStore,
      );
      await analyzingSession.restore();

      await expectLater(
        analyzingSession.setPhotoExportState(
          'photo-1',
          PhotoExportState.queued,
        ),
        throwsStateError,
      );

      expect(editingSession.project, editing);
      expect(analyzingSession.project, analyzing);
    });

    test('persists a stable export state for one project photo', () async {
      final saved = _twoPhotoProject();
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();

      await session.setPhotoExportState('photo-1', PhotoExportState.queued);

      expect(session.project?.exportStates, {
        'photo-1': PhotoExportState.queued,
        'photo-2': PhotoExportState.notQueued,
      });
      expect(store.savedProject, session.project);
    });

    test(
      'removes a photo and its layers, then chooses a valid focus',
      () async {
        final saved = PhotoProject(
          id: 'project-1',
          createdAt: DateTime.utc(2026, 8, 4),
          updatedAt: DateTime.utc(2026, 8, 4),
          photos: const [
            ProjectPhoto(
              id: 'photo-1',
              localPath: '/app/media/photo-1.jpg',
              originalName: 'first.jpg',
            ),
            ProjectPhoto(
              id: 'photo-2',
              localPath: '/app/media/photo-2.jpg',
              originalName: 'second.jpg',
            ),
          ],
          flowState: PhotoProjectFlowState.editing,
          selectedRecommendationId: 'clean-natural-01',
          sharedStyle: SharedStyle(recipe: EditRecipe(exposure: 0.2)),
          focusPhotoId: 'photo-2',
          adaptiveCompensations: {
            'photo-1': AdaptiveCompensation(
              recipe: EditRecipe(exposure: -0.1),
              source: AdaptiveCompensationSource.safeFallbackV1,
            ),
            'photo-2': AdaptiveCompensation(
              source: AdaptiveCompensationSource.safeFallbackV1,
              recipe: EditRecipe(exposure: 0.1),
            ),
          },
          photoOverrides: {
            'photo-2': PhotoOverride(recipe: EditRecipe(warmth: 0.2)),
          },
          undoHistory: [
            ProjectEditOperation(
              scope: ProjectEditingScope.currentPhoto,
              photoId: 'photo-2',
              beforeRecipe: EditRecipe.neutral,
              afterRecipe: EditRecipe(warmth: 0.2),
            ),
          ],
          analysisStates: const {
            'photo-1': PhotoAnalysisState.ready,
            'photo-2': PhotoAnalysisState.ready,
          },
          exportStates: const {
            'photo-1': PhotoExportState.saved,
            'photo-2': PhotoExportState.saved,
          },
        );
        final store = _MemoryPhotoProjectStore()..savedProject = saved;
        final session = PhotoProjectSession(
          importer: _FakePhotoImporter(const []),
          store: store,
          now: () => DateTime.utc(2026, 8, 4, 3),
        );
        await session.restore();

        await session.removePhoto('photo-2');

        expect(session.photos.map((photo) => photo.id), ['photo-1']);
        expect(session.project?.focusPhotoId, 'photo-1');
        expect(session.project?.flowState, PhotoProjectFlowState.analyzing);
        expect(session.project?.selectedRecommendationId, isNull);
        expect(session.project?.sharedStyle.recipe, EditRecipe.neutral);
        expect(session.project?.adaptiveCompensations, isEmpty);
        expect(session.project?.photoOverrides, isEmpty);
        expect(session.project?.analysisStates, {
          'photo-1': PhotoAnalysisState.pending,
        });
        expect(session.project?.exportStates, {
          'photo-1': PhotoExportState.notQueued,
        });
        expect(session.project?.undoHistory, isEmpty);
        expect(session.project?.redoHistory, isEmpty);
        expect(store.deletedPhotoIds, ['photo-2']);
      },
    );

    test('removing the final photo deletes the project', () async {
      final saved = PhotoProject(
        id: 'project-1',
        createdAt: DateTime.utc(2026, 8, 4),
        updatedAt: DateTime.utc(2026, 8, 4),
        photos: const [
          ProjectPhoto(
            id: 'photo-1',
            localPath: '/app/media/photo-1.jpg',
            originalName: 'only.jpg',
          ),
        ],
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();

      await session.removePhoto('photo-1');

      expect(session.project, isNull);
      expect(store.savedProject, isNull);
      expect(store.deletedProjectIds, ['project-1']);
    });

    test('deletes the complete project on request', () async {
      final saved = PhotoProject(
        id: 'project-1',
        createdAt: DateTime.utc(2026, 8, 4),
        updatedAt: DateTime.utc(2026, 8, 4),
        photos: const [
          ProjectPhoto(
            id: 'photo-1',
            localPath: '/app/media/photo-1.jpg',
            originalName: 'first.jpg',
          ),
          ProjectPhoto(
            id: 'photo-2',
            localPath: '/app/media/photo-2.jpg',
            originalName: 'second.jpg',
          ),
        ],
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();

      await session.deleteProject();

      expect(session.project, isNull);
      expect(store.savedProject, isNull);
      expect(store.deletedProjectIds, ['project-1']);
    });

    test('does not delete the project while export is active', () async {
      final saved = _twoPhotoProject().copyWith(
        flowState: PhotoProjectFlowState.exporting,
        exportStates: const {
          'photo-1': PhotoExportState.running,
          'photo-2': PhotoExportState.queued,
        },
      );
      final store = _MemoryPhotoProjectStore()..savedProject = saved;
      final session = PhotoProjectSession(
        importer: _FakePhotoImporter(const []),
        store: store,
      );
      await session.restore();

      await expectLater(session.deleteProject(), throwsStateError);

      expect(session.project, saved);
      expect(store.deletedProjectIds, isEmpty);
    });
  });
}

PhotoProject _twoPhotoProject() {
  return PhotoProject(
    id: 'project-1',
    createdAt: DateTime.utc(2026, 8, 4),
    updatedAt: DateTime.utc(2026, 8, 4),
    photos: const [
      ProjectPhoto(
        id: 'photo-1',
        localPath: '/app/media/photo-1.jpg',
        originalName: 'first.jpg',
      ),
      ProjectPhoto(
        id: 'photo-2',
        localPath: '/app/media/photo-2.jpg',
        originalName: 'second.jpg',
      ),
    ],
  );
}

final class _FakePhotoImporter implements PhotoImporter {
  _FakePhotoImporter(this.photos, {this.failures = const []});

  final List<ProjectPhoto> photos;
  final List<PhotoImportFailure> failures;
  final List<int> requestedLimits = [];

  @override
  Future<PhotoImportBatch> importPhotos({required int limit}) async {
    requestedLimits.add(limit);
    return PhotoImportBatch(photos: photos, failures: failures);
  }
}

final class _MemoryPhotoProjectStore implements PhotoProjectLifecycleStore {
  PhotoProject? savedProject;
  bool failOnSave = false;
  final List<String> deletedPhotoIds = [];
  final List<String> deletedProjectIds = [];

  @override
  Future<PhotoProject?> loadLatest() async => savedProject;

  @override
  Future<void> save(PhotoProject project) async {
    if (failOnSave) {
      throw FileSystemException('save failed');
    }
    savedProject = project;
  }

  @override
  Future<void> deletePhotoCopy(ProjectPhoto photo) async {
    deletedPhotoIds.add(photo.id);
  }

  @override
  Future<void> deleteProject(PhotoProject project) async {
    deletedProjectIds.add(project.id);
    savedProject = null;
  }
}

final class _FailingPhotoProjectStore implements PhotoProjectStore {
  @override
  Future<PhotoProject?> loadLatest() async {
    throw const FormatException('corrupt project');
  }

  @override
  Future<void> save(PhotoProject project) async {}
}

final class _DeferredSavePhotoProjectStore implements PhotoProjectStore {
  final Completer<void> allowSave = Completer<void>();
  PhotoProject? pendingProject;
  PhotoProject? savedProject;

  @override
  Future<PhotoProject?> loadLatest() async => savedProject;

  @override
  Future<void> save(PhotoProject project) async {
    pendingProject = project;
    await allowSave.future;
    savedProject = project;
  }
}
