import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

void main() {
  const first = ProjectPhoto(
    id: 'photo-1',
    localPath: '/app/media/photo-1.jpg',
    originalName: 'first.jpg',
  );
  const second = ProjectPhoto(
    id: 'photo-2',
    localPath: '/app/media/photo-2.jpg',
    originalName: 'second.jpg',
  );

  test('effective recipe composes shared, adaptive, and override layers', () {
    final project = PhotoProject(
      id: 'project-1',
      createdAt: DateTime.utc(2026, 8, 4),
      updatedAt: DateTime.utc(2026, 8, 4),
      photos: const [first, second],
      sharedStyle: SharedStyle(recipe: EditRecipe(exposure: 0.2)),
      adaptiveCompensations: {
        first.id: AdaptiveCompensation(
          source: AdaptiveCompensationSource.localAnalysisV1,
          recipe: EditRecipe(exposure: 0.1, warmth: -0.1),
        ),
      },
      photoOverrides: {
        first.id: PhotoOverride(recipe: EditRecipe(contrast: 0.3)),
      },
    );

    final firstRecipe = project.effectiveRecipeFor(first.id);
    expect(firstRecipe.exposure, closeTo(0.3, 1e-12));
    expect(firstRecipe.contrast, closeTo(0.3, 1e-12));
    expect(firstRecipe.warmth, closeTo(-0.1, 1e-12));
    expect(project.effectiveRecipeFor(second.id), EditRecipe(exposure: 0.2));
  });

  test('effective recipe preserves every V2 adjustment and photo geometry', () {
    final photoCrop = CropGeometry(
      left: 0.1,
      top: 0.2,
      right: 0.9,
      bottom: 0.8,
      quarterTurns: 1,
    );
    final project = PhotoProject(
      id: 'project-v2',
      createdAt: DateTime.utc(2026, 8, 4),
      updatedAt: DateTime.utc(2026, 8, 4),
      photos: const [first],
      sharedStyle: SharedStyle(
        intensity: 0.5,
        recipe: EditRecipe(
          highlights: 0.4,
          shadows: 0.2,
          tint: -0.2,
          saturation: 0.6,
          clarity: 0.4,
        ),
      ),
      photoOverrides: {
        first.id: PhotoOverride(
          recipe: EditRecipe(
            highlights: 0.1,
            shadows: -0.2,
            tint: 0.1,
            saturation: -0.1,
            clarity: 0.2,
            portraitStrength: 0.35,
            crop: photoCrop,
          ),
        ),
      },
    );

    final effective = project.effectiveRecipeFor(first.id);
    expect(effective.highlights, closeTo(0.3, 1e-12));
    expect(effective.shadows, closeTo(-0.1, 1e-12));
    expect(effective.tint, 0);
    expect(effective.saturation, closeTo(0.2, 1e-12));
    expect(effective.clarity, closeTo(0.4, 1e-12));
    expect(effective.portraitStrength, closeTo(0.35, 1e-12));
    expect(effective.crop, photoCrop);
  });

  test(
    'portrait retouch stays with its photo when color edits sync to group',
    () {
      final project = PhotoProject(
        id: 'project-portrait-sync',
        createdAt: DateTime.utc(2026, 8, 4),
        updatedAt: DateTime.utc(2026, 8, 4),
        photos: const [first, second],
        photoOverrides: {
          first.id: PhotoOverride(
            recipe: EditRecipe(exposure: 0.2, portraitStrength: 0.4),
          ),
        },
      );

      final plan = project.planPhotoAdjustmentsToGroup(first.id)!;

      expect(plan.sharedStyle.recipe.exposure, closeTo(0.2, 1e-12));
      expect(plan.sharedStyle.recipe.portraitStrength, 0);
      expect(plan.remainingPhotoOverride.portraitStrength, closeTo(0.4, 1e-12));
    },
  );

  test('per-photo safety caps shared intensity with declared provenance', () {
    final project = PhotoProject(
      id: 'project-1',
      createdAt: DateTime.utc(2026, 8, 4),
      updatedAt: DateTime.utc(2026, 8, 4),
      photos: const [first, second],
      sharedStyle: SharedStyle(
        family: SharedStyleFamily.atmosphericColor,
        intensity: 0.8,
        recipe: EditRecipe(exposure: 0.5, warmth: 0.5),
      ),
      adaptiveCompensations: {
        first.id: AdaptiveCompensation(
          source: AdaptiveCompensationSource.localAnalysisV1,
          safeSharedIntensity: 0.4,
          skinProtection: 0.75,
          recipe: EditRecipe(exposure: -0.1),
        ),
      },
    );

    expect(
      project.effectiveRecipeFor(first.id),
      EditRecipe(exposure: 0.1, warmth: 0.2),
    );
    expect(
      project.effectiveRecipeFor(second.id),
      EditRecipe(exposure: 0.4, warmth: 0.4),
    );
    final restored = PhotoProject.fromJson(project.toJson());
    expect(restored.sharedStyle.family, SharedStyleFamily.atmosphericColor);
    expect(
      restored.adaptiveCompensations[first.id]?.source,
      AdaptiveCompensationSource.localAnalysisV1,
    );
    expect(
      restored.adaptiveCompensations[first.id]?.skinProtection,
      closeTo(0.75, 1e-12),
    );
  });

  test(
    'group sync is unavailable when preserving the photo would overflow',
    () {
      final project = PhotoProject(
        id: 'project-overflow',
        createdAt: DateTime.utc(2026, 8, 4),
        updatedAt: DateTime.utc(2026, 8, 4),
        photos: const [first, second],
        sharedStyle: SharedStyle(
          intensity: 0.25,
          recipe: EditRecipe(exposure: 0.9),
        ),
        photoOverrides: {
          first.id: PhotoOverride(recipe: EditRecipe(exposure: 0.1)),
        },
      );

      expect(project.planPhotoAdjustmentsToGroup(first.id), isNull);
    },
  );

  test('rejects scoped history that only changes sync-only fields', () {
    expect(
      () => PhotoProject(
        id: 'project-invalid-history',
        createdAt: DateTime.utc(2026, 8, 4),
        updatedAt: DateTime.utc(2026, 8, 4),
        photos: const [first, second],
        undoHistory: [
          ProjectEditOperation(
            scope: ProjectEditingScope.currentPhoto,
            photoId: first.id,
            beforeRecipe: EditRecipe.neutral,
            afterRecipe: EditRecipe.neutral,
            beforePhotoOverrideRecipe: EditRecipe.neutral,
            afterPhotoOverrideRecipe: EditRecipe(contrast: 0.2),
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('current project keeps per-photo state and explicit editing scope', () {
    final project = PhotoProject(
      id: 'project-1',
      createdAt: DateTime.utc(2026, 8, 4),
      updatedAt: DateTime.utc(2026, 8, 4, 1),
      photos: const [first],
      flowState: PhotoProjectFlowState.choosingRecommendation,
      focusPhotoId: first.id,
      selectedRecommendationId: 'clean-natural-01',
      sharedStyle: SharedStyle(recipe: EditRecipe(warmth: 0.2)),
      adaptiveCompensations: {
        first.id: AdaptiveCompensation(
          source: AdaptiveCompensationSource.safeFallbackV1,
          recipe: EditRecipe(exposure: 0.1),
        ),
      },
      photoOverrides: {
        first.id: PhotoOverride(recipe: EditRecipe(contrast: 0.2)),
      },
      analysisStates: {first.id: PhotoAnalysisState.ready},
      exportStates: {first.id: PhotoExportState.queued},
      editingScope: ProjectEditingScope.currentPhoto,
      undoHistory: [
        ProjectEditOperation(
          scope: ProjectEditingScope.currentPhoto,
          photoId: first.id,
          beforeRecipe: EditRecipe.neutral,
          afterRecipe: EditRecipe(contrast: 0.2),
        ),
      ],
    );

    final restored = PhotoProject.fromJson(project.toJson());

    expect(restored, project);
    expect(restored.analysisStates[first.id], PhotoAnalysisState.ready);
    expect(restored.exportStates[first.id], PhotoExportState.queued);
    expect(restored.editingScope, ProjectEditingScope.currentPhoto);
    expect(restored.undoHistory, project.undoHistory);
    expect(project.toJson()['schemaVersion'], 5);
  });

  test('version three project migrates to a safe scope with empty history', () {
    final restored = PhotoProject.fromJson({
      'schemaVersion': 3,
      'id': 'version-three',
      'createdAt': '2026-08-04T00:00:00.000Z',
      'updatedAt': '2026-08-04T01:00:00.000Z',
      'photos': [
        {
          'id': first.id,
          'localPath': first.localPath,
          'originalName': first.originalName,
        },
      ],
      'flowState': 'editing',
      'sharedStyle': {
        'recipe': {'exposure': 0.1, 'contrast': 0.0, 'warmth': 0.0},
      },
      'adaptiveCompensations': <String, Object>{},
      'photoOverrides': <String, Object>{},
      'analysisStates': {first.id: 'ready'},
      'exportStates': {first.id: 'notQueued'},
    });

    expect(restored.editingScope, ProjectEditingScope.currentPhoto);
    expect(restored.undoHistory, isEmpty);
    expect(restored.redoHistory, isEmpty);
  });

  test(
    'version two project migrates stable per-photo states without layers',
    () {
      final restored = PhotoProject.fromJson({
        'schemaVersion': 2,
        'id': 'version-two',
        'createdAt': '2026-08-04T00:00:00.000Z',
        'updatedAt': '2026-08-04T01:00:00.000Z',
        'photos': [
          {
            'id': first.id,
            'localPath': first.localPath,
            'originalName': first.originalName,
          },
        ],
        'flowState': 'analyzing',
        'sharedStyle': {
          'recipe': {'exposure': 0.0, 'contrast': 0.0, 'warmth': 0.0},
        },
        'adaptiveCompensations': <String, Object>{},
        'photoOverrides': <String, Object>{},
      });

      expect(restored.analysisStates, {first.id: PhotoAnalysisState.pending});
      expect(restored.exportStates, {first.id: PhotoExportState.notQueued});
      expect(restored.adaptiveCompensations, isEmpty);
      expect(restored.photoOverrides, isEmpty);
    },
  );

  test('legacy recipe migrates to the shared style without duplication', () {
    final restored = PhotoProject.fromJson({
      'id': 'legacy',
      'createdAt': '2026-08-04T00:00:00.000Z',
      'updatedAt': '2026-08-04T01:00:00.000Z',
      'photos': [
        {
          'id': first.id,
          'localPath': first.localPath,
          'originalName': first.originalName,
        },
      ],
      'recipe': {'exposure': 0.25, 'contrast': 0.1, 'warmth': -0.2},
    });

    expect(
      restored.sharedStyle.recipe,
      EditRecipe(exposure: 0.25, contrast: 0.1, warmth: -0.2),
    );
    expect(restored.adaptiveCompensations, isEmpty);
    expect(restored.photoOverrides, isEmpty);
    expect(restored.analysisStates, {first.id: PhotoAnalysisState.pending});
    expect(restored.exportStates, {first.id: PhotoExportState.notQueued});
    expect(restored.effectiveRecipeFor(first.id), restored.sharedStyle.recipe);
  });

  test('rejects layers that reference a photo outside the project', () {
    expect(
      () => PhotoProject(
        id: 'project-1',
        createdAt: DateTime.utc(2026, 8, 4),
        updatedAt: DateTime.utc(2026, 8, 4),
        photos: const [first],
        photoOverrides: {
          'missing': PhotoOverride(recipe: EditRecipe(exposure: 0.2)),
        },
      ),
      throwsArgumentError,
    );
  });

  test('rejects an invalid stored orientation outside debug mode', () {
    expect(
      () => ProjectPhoto.fromJson({
        'id': 'invalid',
        'localPath': '/app/media/invalid.jpg',
        'originalName': 'invalid.jpg',
        'orientation': 9,
      }),
      throwsFormatException,
    );
  });
}
