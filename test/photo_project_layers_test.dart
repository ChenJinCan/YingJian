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

  test('version three project keeps per-photo analysis and export state', () {
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
        first.id: AdaptiveCompensation(recipe: EditRecipe(exposure: 0.1)),
      },
      photoOverrides: {
        first.id: PhotoOverride(recipe: EditRecipe(contrast: 0.2)),
      },
      analysisStates: {first.id: PhotoAnalysisState.ready},
      exportStates: {first.id: PhotoExportState.queued},
    );

    final restored = PhotoProject.fromJson(project.toJson());

    expect(restored, project);
    expect(restored.analysisStates[first.id], PhotoAnalysisState.ready);
    expect(restored.exportStates[first.id], PhotoExportState.queued);
    expect(project.toJson()['schemaVersion'], 3);
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
