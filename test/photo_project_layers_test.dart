import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/targeted_portrait_recipe.dart';
import 'package:yingjian/features/editor/domain/targeted_geometry_recipe.dart';
import 'package:yingjian/features/editor/domain/portrait_retouch_recipe.dart';
import 'package:yingjian/features/editor/domain/portrait_geometry_recipe.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/quality_enhancement_recipe.dart';
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

  test('group filter and HSL propagate while geometry stays per photo', () {
    final groupBasic = BasicEditingRecipe(
      flipHorizontal: true,
      perspectiveHorizontal: 12,
      filter: PhotoFilter.cinematic,
      filterStrength: 62,
      hsl: {HslChannel.blue: HslAdjustment(saturation: -18, lightness: 8)},
    );
    final project = PhotoProject(
      id: 'project-group-look',
      createdAt: DateTime.utc(2026, 8, 9),
      updatedAt: DateTime.utc(2026, 8, 9),
      photos: const [first, second],
      sharedStyle: SharedStyle(
        recipe: EditRecipe(basicEditingRecipe: groupBasic),
      ),
      photoOverrides: {
        first.id: PhotoOverride(
          recipe: EditRecipe(
            basicEditingRecipe: BasicEditingRecipe(
              flipVertical: true,
              filter: PhotoFilter.none,
            ),
          ),
          overridesBasicLook: true,
        ),
      },
    );

    final firstEffective = project.effectiveRecipeFor(first.id);
    final secondEffective = project.effectiveRecipeFor(second.id);
    expect(firstEffective.basicEditingRecipe.filter, PhotoFilter.none);
    expect(firstEffective.basicEditingRecipe.flipVertical, isTrue);
    expect(secondEffective.basicEditingRecipe.filter, PhotoFilter.cinematic);
    expect(secondEffective.basicEditingRecipe.filterStrength, 62);
    expect(
      secondEffective.basicEditingRecipe.hsl[HslChannel.blue],
      HslAdjustment(saturation: -18, lightness: 8),
    );
    expect(secondEffective.basicEditingRecipe.flipHorizontal, isFalse);
    expect(secondEffective.basicEditingRecipe.perspectiveHorizontal, 0);

    final baseline = project.photoOverrideBaselineFor(second.id);
    expect(baseline.basicEditingRecipe.filter, PhotoFilter.cinematic);
    expect(baseline.basicEditingRecipe.flipHorizontal, isFalse);
  });

  test('group intensity still reaches photos with color-only overrides', () {
    final sharedBasic = BasicEditingRecipe(
      filter: PhotoFilter.cinematic,
      filterStrength: 60,
      hsl: {HslChannel.blue: HslAdjustment(saturation: -20)},
    );
    final project = PhotoProject(
      id: 'project-group-strength',
      createdAt: DateTime.utc(2026, 8, 9),
      updatedAt: DateTime.utc(2026, 8, 9),
      photos: const [first, second],
      sharedStyle: SharedStyle(
        intensity: 0.8,
        recipe: EditRecipe(basicEditingRecipe: sharedBasic),
      ),
      photoOverrides: {
        first.id: PhotoOverride(
          recipe: EditRecipe(exposure: 0.1),
          overridesBasicLook: false,
        ),
      },
    );

    expect(
      project.effectiveRecipeFor(first.id).basicEditingRecipe.filterStrength,
      48,
    );
    expect(
      project
          .copyWith(
            sharedStyle: SharedStyle(
              intensity: 0.4,
              recipe: EditRecipe(basicEditingRecipe: sharedBasic),
            ),
          )
          .effectiveRecipeFor(first.id)
          .basicEditingRecipe
          .filterStrength,
      24,
    );
  });

  test('per-photo flip and perspective keep following the group look', () {
    final sharedBasic = BasicEditingRecipe(
      filter: PhotoFilter.film,
      filterStrength: 50,
      hsl: {HslChannel.orange: HslAdjustment(lightness: 12)},
    );
    final project = PhotoProject(
      id: 'project-independent-basic-geometry',
      createdAt: DateTime.utc(2026, 8, 9),
      updatedAt: DateTime.utc(2026, 8, 9),
      photos: const [first, second],
      sharedStyle: SharedStyle(
        intensity: 0.8,
        recipe: EditRecipe(basicEditingRecipe: sharedBasic),
      ),
      photoOverrides: {
        first.id: PhotoOverride(
          recipe: EditRecipe(
            basicEditingRecipe: BasicEditingRecipe(
              flipHorizontal: true,
              perspectiveVertical: -8,
              filter: PhotoFilter.film,
              filterStrength: 40,
              hsl: {HslChannel.orange: HslAdjustment(lightness: 9.6)},
            ),
          ),
          overridesBasicLook: false,
        ),
      },
    );

    final effective = project.effectiveRecipeFor(first.id).basicEditingRecipe;
    expect(effective.flipHorizontal, isTrue);
    expect(effective.perspectiveVertical, -8);
    expect(effective.filter, PhotoFilter.film);
    expect(effective.filterStrength, 40);

    final changed = project.copyWith(
      sharedStyle: SharedStyle(
        intensity: 0.4,
        recipe: EditRecipe(
          basicEditingRecipe: sharedBasic.copyWith(filter: PhotoFilter.clean),
        ),
      ),
    );
    final changedEffective = changed
        .effectiveRecipeFor(first.id)
        .basicEditingRecipe;
    expect(changedEffective.flipHorizontal, isTrue);
    expect(changedEffective.perspectiveVertical, -8);
    expect(changedEffective.filter, PhotoFilter.clean);
    expect(changedEffective.filterStrength, 20);
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
    expect(effective.portraitStrength, 0);
    expect(effective.portraitRecipe.textureSmoothing, 35);
    expect(effective.portraitRecipe.skinToneLighting, 35);
    expect(effective.crop, photoCrop);
  });

  test(
    'project restoration preserves the five-parameter portrait identity',
    () {
      final portraitRecipe = PortraitRetouchRecipe(
        textureSmoothing: 42,
        skinToneLighting: 31,
        blemishReduction: 18,
        faceSlimming: 9,
        torsoSlimming: 7,
      );
      final project = PhotoProject(
        id: 'project-portrait-v2',
        createdAt: DateTime.utc(2026, 8, 6),
        updatedAt: DateTime.utc(2026, 8, 6),
        photos: const [first],
        sharedStyle: SharedStyle(recipe: EditRecipe.neutral),
        photoOverrides: {
          first.id: PhotoOverride(
            recipe: EditRecipe(portraitRecipe: portraitRecipe),
          ),
        },
      );

      final restored = PhotoProject.fromJson(project.toJson());

      expect(
        restored.effectiveRecipeFor(first.id).portraitRecipe,
        portraitRecipe,
      );
    },
  );

  test('quality enhancement stays with one photo and survives restoration', () {
    final qualityRecipe = QualityEnhancementRecipe(
      noiseReduction: 28,
      lowLightRecovery: 32,
      hazeRemoval: 18,
      detailSharpening: 16,
    );
    final project = PhotoProject(
      id: 'project-quality-v1',
      createdAt: DateTime.utc(2026, 8, 7),
      updatedAt: DateTime.utc(2026, 8, 7),
      photos: const [first, second],
      sharedStyle: SharedStyle(recipe: EditRecipe.neutral),
      photoOverrides: {
        first.id: PhotoOverride(
          recipe: EditRecipe(qualityEnhancementRecipe: qualityRecipe),
        ),
      },
    );

    final restored = PhotoProject.fromJson(project.toJson());

    expect(
      restored.effectiveRecipeFor(first.id).qualityEnhancementRecipe,
      qualityRecipe,
    );
    expect(
      restored.effectiveRecipeFor(second.id).qualityEnhancementRecipe,
      QualityEnhancementRecipe.neutral,
    );
  });

  test('multi-target face and body geometry stays with one photo', () {
    final geometry = PortraitGeometryRecipe(
      faceTargets: [FaceGeometryTarget(eyes: 18), FaceGeometryTarget(jaw: -12)],
      bodyTargets: [BodyGeometryTarget(height: 15, waist: -10)],
    );
    final project = PhotoProject(
      id: 'project-geometry-v1',
      createdAt: DateTime.utc(2026, 8, 9),
      updatedAt: DateTime.utc(2026, 8, 9),
      photos: const [first, second],
      photoOverrides: {
        first.id: PhotoOverride(
          recipe: EditRecipe(portraitGeometryRecipe: geometry),
        ),
      },
    );

    final restored = PhotoProject.fromJson(project.toJson());

    expect(
      restored.effectiveRecipeFor(first.id).portraitGeometryRecipe,
      geometry,
    );
    expect(
      restored.effectiveRecipeFor(second.id).portraitGeometryRecipe,
      PortraitGeometryRecipe.neutral,
    );
  });

  test('semantic editing stays with one photo and survives restoration', () {
    final semantic = SemanticEditingRecipe(
      background: BackgroundTreatment.blur,
      backgroundBlur: 35,
      subjectExposure: 12,
    );
    final project = PhotoProject(
      id: 'project-semantic-v1',
      createdAt: DateTime.utc(2026, 8, 9),
      updatedAt: DateTime.utc(2026, 8, 9),
      photos: const [first, second],
      photoOverrides: {
        first.id: PhotoOverride(
          recipe: EditRecipe(semanticEditingRecipe: semantic),
        ),
      },
    );

    expect(
      project.effectiveRecipeFor(first.id).semanticEditingRecipe,
      semantic,
    );
    expect(
      project.effectiveRecipeFor(second.id).semanticEditingRecipe,
      SemanticEditingRecipe.neutral,
    );
    expect(
      PhotoProject.fromJson(
        project.toJson(),
      ).effectiveRecipeFor(first.id).semanticEditingRecipe,
      semantic,
    );
  });

  test(
    'portrait retouch and reshape stay with their photo when color edits sync to group',
    () {
      final project = PhotoProject(
        id: 'project-portrait-sync',
        createdAt: DateTime.utc(2026, 8, 4),
        updatedAt: DateTime.utc(2026, 8, 4),
        photos: const [first, second],
        photoOverrides: {
          first.id: PhotoOverride(
            recipe: EditRecipe(
              exposure: 0.2,
              portraitStrength: 0.4,
              faceSlimStrength: 0.25,
              bodySlimStrength: 0.15,
            ),
          ),
        },
      );

      final plan = project.planPhotoAdjustmentsToGroup(first.id)!;

      expect(plan.sharedStyle.recipe.exposure, closeTo(0.2, 1e-12));
      expect(plan.sharedStyle.recipe.portraitStrength, 0);
      expect(plan.sharedStyle.recipe.faceSlimStrength, 0);
      expect(plan.sharedStyle.recipe.bodySlimStrength, 0);
      expect(plan.remainingPhotoOverride.portraitStrength, closeTo(0.4, 1e-12));
      expect(
        plan.remainingPhotoOverride.faceSlimStrength,
        closeTo(0.25, 1e-12),
      );
      expect(
        plan.remainingPhotoOverride.bodySlimStrength,
        closeTo(0.15, 1e-12),
      );
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
          portraitStrength: 0.35,
          recipe: EditRecipe(exposure: -0.1),
        ),
      },
    );

    expect(
      project.effectiveRecipeFor(first.id),
      EditRecipe(
        exposure: 0.1,
        warmth: 0.2,
        portraitRecipe: PortraitRetouchRecipe(
          textureSmoothing: 35,
          skinToneLighting: 35,
        ),
      ),
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
    expect(
      restored.adaptiveCompensations[first.id]?.portraitStrength,
      closeTo(0.35, 1e-12),
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

  test('group sync rejects a photo look that cannot preserve its strength', () {
    final project = PhotoProject(
      id: 'project-filter-overflow',
      createdAt: DateTime.utc(2026, 8, 9),
      updatedAt: DateTime.utc(2026, 8, 9),
      photos: const [first, second],
      sharedStyle: SharedStyle(
        intensity: 0.5,
        recipe: EditRecipe(
          basicEditingRecipe: BasicEditingRecipe(
            filter: PhotoFilter.clean,
            filterStrength: 40,
          ),
        ),
      ),
      photoOverrides: {
        first.id: PhotoOverride(
          recipe: EditRecipe(
            basicEditingRecipe: BasicEditingRecipe(
              filter: PhotoFilter.film,
              filterStrength: 70,
            ),
          ),
          overridesBasicLook: true,
        ),
      },
    );

    expect(project.planPhotoAdjustmentsToGroup(first.id), isNull);
  });

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
      flowState: PhotoProjectFlowState.editing,
      focusPhotoId: first.id,
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
      targetRegistries: {
        first.id: EditTargetRegistry.seed(const [
          DetectedEditTarget(
            photoId: 'photo-1',
            kind: EditTargetKind.face,
            analysisVersion: 'vision-v1',
            region: NormalizedEditRegion(
              left: 0.1,
              top: 0.2,
              right: 0.4,
              bottom: 0.7,
            ),
          ),
        ]),
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

    final currentSnapshot = ProjectEditSnapshot.fromProject(project);
    final baseSnapshot = ProjectEditSnapshot(
      sharedStyle: project.sharedStyle,
      photoOverrides: const {},
      targetRegistries: project.targetRegistries,
    );
    final validProject = project.copyWith(
      historyBaseSnapshot: baseSnapshot,
      undoHistory: [
        project.undoHistory.single.withSnapshots(
          before: baseSnapshot,
          after: currentSnapshot,
        ),
      ],
    );
    final restored = PhotoProject.fromJson(validProject.toJson());

    expect(restored, validProject);
    expect(restored.analysisStates[first.id], PhotoAnalysisState.ready);
    expect(restored.exportStates[first.id], PhotoExportState.queued);
    expect(restored.editingScope, ProjectEditingScope.currentPhoto);
    expect(restored.undoHistory, validProject.undoHistory);
    expect(restored.targetRegistries[first.id]!.targets, hasLength(1));
    expect(project.toJson()['schemaVersion'], PhotoProject.schemaVersion);
  });

  test('effective recipe pauses targeted effects for suspended targets', () {
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
    final activeRegistry = EditTargetRegistry.seed(const [detection]);
    final target = activeRegistry.targets.values.single;
    final targeted = TargetedPortraitRecipe.neutral.update(
      targetId: target.id,
      region: target.region,
      parameter: TargetedPortraitParameter.textureSmoothing,
      value: 45,
    );
    final targetedGeometry = TargetedGeometryRecipe.neutral.updateFace(
      target.id,
      (geometry) => geometry.copyWith(faceSlim: 35),
    );
    final active = PhotoProject(
      id: 'targeted-effects',
      createdAt: DateTime.utc(2026, 8, 20),
      updatedAt: DateTime.utc(2026, 8, 20),
      photos: const [first],
      targetRegistries: {first.id: activeRegistry},
      photoOverrides: {
        first.id: PhotoOverride(
          recipe: EditRecipe(
            targetedPortraitRecipe: targeted,
            targetedGeometryRecipe: targetedGeometry,
          ),
        ),
      },
    );

    expect(
      active.effectiveRecipeFor(first.id).targetedPortraitRecipe,
      targeted,
    );
    expect(
      active
          .effectiveRecipeFor(first.id)
          .portraitGeometryRecipe
          .faceTargets
          .single
          .faceSlim,
      35,
    );

    final suspendedRegistry = activeRegistry.reconcile(const []);
    final suspended = active.copyWith(
      targetRegistries: {first.id: suspendedRegistry},
    );

    expect(
      suspended.effectiveRecipeFor(first.id).targetedPortraitRecipe.isNeutral,
      isTrue,
    );
    expect(
      suspended.effectiveRecipeFor(first.id).portraitGeometryRecipe.isNeutral,
      isTrue,
    );
    expect(
      suspended.photoOverrides[first.id]!.recipe.targetedPortraitRecipe,
      targeted,
      reason: 'suspending a target must not destroy its stored adjustment',
    );
    expect(
      suspended.photoOverrides[first.id]!.recipe.targetedGeometryRecipe,
      targetedGeometry,
      reason: 'suspending a target must preserve its stored geometry',
    );
  });

  test(
    'version eight basic override flag migrates to the split look model',
    () {
      final project = PhotoProject(
        id: 'version-eight-basic-look',
        createdAt: DateTime.utc(2026, 8, 9),
        updatedAt: DateTime.utc(2026, 8, 9),
        photos: const [first],
        sharedStyle: SharedStyle(
          recipe: EditRecipe(
            basicEditingRecipe: BasicEditingRecipe(
              filter: PhotoFilter.cinematic,
              filterStrength: 60,
            ),
          ),
        ),
        photoOverrides: {
          first.id: PhotoOverride(
            recipe: EditRecipe(
              basicEditingRecipe: BasicEditingRecipe(
                flipHorizontal: true,
                filter: PhotoFilter.cinematic,
                filterStrength: 60,
              ),
            ),
            overridesBasicLook: false,
          ),
        },
      );
      final json = project.toJson()..['schemaVersion'] = 8;
      final rawOverrides = json['photoOverrides']! as Map<String, Object>;
      final rawOverride = Map<String, Object>.from(
        rawOverrides[first.id]! as Map<String, Object>,
      );
      rawOverride['overridesBasicEditing'] = rawOverride.remove(
        'overridesBasicLook',
      )!;
      rawOverrides[first.id] = rawOverride;

      final restored = PhotoProject.fromJson(json);

      expect(restored.photoOverrides[first.id]!.overridesBasicLook, isFalse);
      final effective = restored
          .effectiveRecipeFor(first.id)
          .basicEditingRecipe;
      expect(effective.flipHorizontal, isTrue);
      expect(effective.filter, PhotoFilter.cinematic);
      expect(restored.toJson()['schemaVersion'], PhotoProject.schemaVersion);
    },
  );

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

  test('version eleven migrates replayable group history idempotently', () {
    final project = PhotoProject(
      id: 'version-eleven-group-history',
      createdAt: DateTime.utc(2026, 8, 20),
      updatedAt: DateTime.utc(2026, 8, 20, 1),
      photos: const [first],
      sharedStyle: SharedStyle(recipe: EditRecipe(exposure: 0.2)),
      undoHistory: [
        ProjectEditOperation(
          scope: ProjectEditingScope.group,
          beforeRecipe: EditRecipe.neutral,
          afterRecipe: EditRecipe(exposure: 0.2),
        ),
      ],
    );
    final legacyJson = project.toJson()..['schemaVersion'] = 11;
    for (final operation in legacyJson['undoHistory']! as List) {
      (operation as Map).remove('source');
      operation.remove('changedAddresses');
      operation.remove('beforeSnapshot');
      operation.remove('afterSnapshot');
    }

    final migrated = PhotoProject.fromJson(legacyJson);
    final reopened = PhotoProject.fromJson(migrated.toJson());

    expect(migrated.sharedStyle, project.sharedStyle);
    expect(migrated.historyBaseSnapshot, isNotNull);
    expect(migrated.undoHistory, hasLength(1));
    expect(migrated.undoHistory.single.source, EditSource.migration);
    expect(migrated.undoHistory.single.beforeSnapshot, isNotNull);
    expect(migrated.undoHistory.single.afterSnapshot, isNotNull);
    expect(migrated.hasValidHistoryReplay, isTrue);
    expect(reopened, migrated);
  });

  test('version eleven freezes ambiguous photo history at current result', () {
    final project = PhotoProject(
      id: 'version-eleven-photo-history',
      createdAt: DateTime.utc(2026, 8, 20),
      updatedAt: DateTime.utc(2026, 8, 20, 1),
      photos: const [first],
      photoOverrides: {
        first.id: PhotoOverride(recipe: EditRecipe(contrast: 0.2)),
      },
      undoHistory: [
        ProjectEditOperation(
          scope: ProjectEditingScope.currentPhoto,
          photoId: first.id,
          beforeRecipe: EditRecipe.neutral,
          afterRecipe: EditRecipe(contrast: 0.2),
        ),
      ],
    );
    final legacyJson = project.toJson()..['schemaVersion'] = 11;
    for (final operation in legacyJson['undoHistory']! as List) {
      (operation as Map).remove('source');
      operation.remove('changedAddresses');
      operation.remove('beforeSnapshot');
      operation.remove('afterSnapshot');
    }

    final migrated = PhotoProject.fromJson(legacyJson);

    expect(migrated.photoOverrides, project.photoOverrides);
    expect(migrated.undoHistory, isEmpty);
    expect(migrated.redoHistory, isEmpty);
    expect(migrated.foldedEditCount, 1);
    expect(
      migrated.historyBaseSnapshot,
      ProjectEditSnapshot.fromProject(project),
    );
    expect(migrated.hasValidHistoryReplay, isTrue);
    expect(PhotoProject.fromJson(migrated.toJson()), migrated);
  });

  test(
    'unknown future meta ops stay opaque and require a read-only update',
    () {
      final source = PhotoProject(
        id: 'future-meta-op',
        createdAt: DateTime.utc(2026, 8, 20),
        updatedAt: DateTime.utc(2026, 8, 20),
        photos: const [first],
      ).toJson();
      final unknown = <String, Object?>{
        'id': 'future.generative_relight',
        'version': 7,
        'scope': 'currentPhoto',
        'photoId': first.id,
        'payload': {
          'mode': 'cinematic',
          'weights': [0.2, 0.8],
        },
      };
      source['unknownMetaOps'] = [unknown];

      final restored = PhotoProject.fromJson(source);
      final persisted = restored.toJson();

      expect(restored.requiresUpdate, isTrue);
      expect(restored.isReadOnly, isTrue);
      expect(restored.canMutateInputs, isFalse);
      expect(restored.canExport, isFalse);
      expect(persisted['unknownMetaOps'], [unknown]);
      expect(PhotoProject.fromJson(persisted), restored);
    },
  );

  test(
    'version five project migrates portrait geometry as safely disabled',
    () {
      final project = PhotoProject(
        id: 'version-five',
        createdAt: DateTime.utc(2026, 8, 5),
        updatedAt: DateTime.utc(2026, 8, 5),
        photos: const [first],
      );
      final legacy = Map<String, Object?>.from(project.toJson())
        ..['schemaVersion'] = 5;

      final restored = PhotoProject.fromJson(legacy);

      expect(restored.effectiveRecipeFor(first.id).faceSlimStrength, 0);
      expect(restored.effectiveRecipeFor(first.id).bodySlimStrength, 0);
      expect(restored.toJson()['schemaVersion'], PhotoProject.schemaVersion);
    },
  );

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
