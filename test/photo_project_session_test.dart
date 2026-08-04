import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
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

    test('does not start export until every photo is queued', () async {
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

      await expectLater(
        session.transitionTo(PhotoProjectFlowState.exporting),
        throwsStateError,
      );

      expect(session.project, saved);
    });

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

    test('a new recommendation replaces stale edit and export state', () async {
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

      expect(session.project?.photoOverrides, isEmpty);
      expect(session.project?.undoHistory, isEmpty);
      expect(session.project?.redoHistory, isEmpty);
      expect(session.project?.exportStates, {
        'photo-1': PhotoExportState.notQueued,
        'photo-2': PhotoExportState.notQueued,
      });
    });

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

        await session.commitEdit(EditRecipe(contrast: 0.3));

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
              recipe: EditRecipe(exposure: 0.125, contrast: 0.25, crop: crop),
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
          EditRecipe(crop: crop),
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
          session.commitEdit(EditRecipe(exposure: 0.3)),
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

        await session.commitEdit(recipe);

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
