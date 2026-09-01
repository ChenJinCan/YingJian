import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/legacy_edit_recipe_adapter.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/meta_op_availability.dart';
import 'package:yingjian/features/editor/domain/platform_meta_op_capabilities.dart';
import 'package:yingjian/features/editor/domain/quality_enhancement_recipe.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/targeted_portrait_recipe.dart';

void main() {
  const exposureAddress = OpAddress(
    metaOpId: 'tone.exposure',
    metaOpVersion: 1,
    parameterId: 'value',
    scope: EditScope.group,
  );

  group('EditingCore', () {
    test('round-trips canonical state with its monotonic version', () {
      final state = EditState(version: 7, values: {exposureAddress: 0.4});

      expect(EditState.fromJson(state.toJson()), state);
    });

    test('atomically applies a valid transaction and advances the version', () {
      const core = EditingCore();
      final result = core.apply(
        state: EditState.empty,
        transaction: EditTransaction(
          id: 'tx-1',
          baseVersion: 0,
          source: EditSource.manual,
          changes: const [MetaOpChange(address: exposureAddress, value: 0.4)],
        ),
        context: EditContext.ios,
      );

      expect(result, isA<AcceptedEdit>());
      final accepted = result as AcceptedEdit;
      expect(accepted.state.version, 1);
      expect(accepted.state.valueAt(exposureAddress), 0.4);
      expect(accepted.summary.changedAddresses, [exposureAddress]);
    });

    test('rejects the whole transaction when any change is invalid', () {
      const core = EditingCore();
      final result = core.apply(
        state: EditState.empty,
        transaction: EditTransaction(
          id: 'tx-2',
          baseVersion: 0,
          source: EditSource.ai,
          changes: const [
            MetaOpChange(address: exposureAddress, value: 0.2),
            MetaOpChange(
              address: OpAddress(
                metaOpId: 'tone.contrast',
                metaOpVersion: 1,
                parameterId: 'value',
                scope: EditScope.group,
              ),
              value: 2,
            ),
          ],
        ),
        context: const EditContext(
          platform: EditPlatform.ios,
          photoIds: {'photo-1'},
        ),
      );

      expect(result, isA<RejectedEdit>());
      expect((result as RejectedEdit).reason, EditRejection.outOfRange);
      expect(EditState.empty.values, isEmpty);
    });

    test('accepts only registered content resources', () {
      const resourceId =
          'resource-v1-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const address = OpAddress(
        metaOpId: MetaOpIds.semanticAdjustments,
        metaOpVersion: 1,
        parameterId: 'backgroundImageResource',
        scope: EditScope.currentPhoto,
        photoId: 'photo-1',
      );
      EditResult apply(Set<String> resourceIds) => const EditingCore().apply(
        state: EditState.empty,
        transaction: EditTransaction(
          id: 'background-resource',
          baseVersion: 0,
          source: EditSource.manual,
          changes: const [MetaOpChange(address: address, value: resourceId)],
        ),
        context: EditContext(
          platform: EditPlatform.ios,
          photoIds: const {'photo-1'},
          resourceIds: resourceIds,
        ),
      );

      expect(
        (apply(const {}) as RejectedEdit).reason,
        EditRejection.invalidResource,
      );
      expect(apply(const {resourceId}), isA<AcceptedEdit>());
    });

    test('enforces platform target and resource limits atomically', () {
      const resourceId =
          'resource-v1-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final capabilities = PlatformMetaOpCapabilities(
        platform: EditPlatform.ios,
        entries: const [
          MetaOpExecutionSupport(
            metaOpId: MetaOpIds.skinSmooth,
            metaOpVersion: 1,
            preview: true,
            export: true,
            maxTargets: 1,
            maxResourceBytes: 0,
          ),
          MetaOpExecutionSupport(
            metaOpId: MetaOpIds.semanticAdjustments,
            metaOpVersion: 1,
            preview: true,
            export: true,
            maxTargets: 0,
            maxResourceBytes: 8,
          ),
        ],
      );
      const faceOne = OpAddress(
        metaOpId: MetaOpIds.skinSmooth,
        metaOpVersion: 1,
        parameterId: 'value',
        scope: EditScope.currentPhoto,
        photoId: 'photo-1',
        targetId: 'face-1',
      );
      const faceTwo = OpAddress(
        metaOpId: MetaOpIds.skinSmooth,
        metaOpVersion: 1,
        parameterId: 'value',
        scope: EditScope.currentPhoto,
        photoId: 'photo-1',
        targetId: 'face-2',
      );
      final targetResult = const EditingCore().apply(
        state: EditState.empty,
        transaction: EditTransaction(
          id: 'too-many-targets',
          baseVersion: 0,
          source: EditSource.manual,
          changes: const [
            MetaOpChange(address: faceOne, value: 0.2),
            MetaOpChange(address: faceTwo, value: 0.2),
          ],
        ),
        context: EditContext(
          platform: EditPlatform.ios,
          photoIds: const {'photo-1'},
          targetIds: const {'face-1', 'face-2'},
          applicability: const {'photo', 'face'},
          metaOpCapabilities: capabilities,
        ),
      );
      expect(
        (targetResult as RejectedEdit).reason,
        EditRejection.targetLimitExceeded,
      );

      const resourceAddress = OpAddress(
        metaOpId: MetaOpIds.semanticAdjustments,
        metaOpVersion: 1,
        parameterId: 'backgroundImageResource',
        scope: EditScope.currentPhoto,
        photoId: 'photo-1',
      );
      final resourceResult = const EditingCore().apply(
        state: EditState.empty,
        transaction: EditTransaction(
          id: 'resource-too-large',
          baseVersion: 0,
          source: EditSource.manual,
          changes: const [
            MetaOpChange(address: resourceAddress, value: resourceId),
          ],
        ),
        context: EditContext(
          platform: EditPlatform.ios,
          photoIds: const {'photo-1'},
          resourceIds: const {resourceId},
          resourceByteLengths: const {resourceId: 9},
          metaOpCapabilities: capabilities,
        ),
      );
      expect(
        (resourceResult as RejectedEdit).reason,
        EditRejection.resourceLimitExceeded,
      );
      expect(EditState.empty.values, isEmpty);
    });

    test(
      'rejects duplicate addresses, stale versions, and invalid targets',
      () {
        const core = EditingCore();
        final duplicate = core.apply(
          state: EditState.empty,
          transaction: EditTransaction(
            id: 'duplicate',
            baseVersion: 0,
            source: EditSource.manual,
            changes: const [
              MetaOpChange(address: exposureAddress, value: 0.1),
              MetaOpChange(address: exposureAddress, value: 0.2),
            ],
          ),
          context: EditContext.ios,
        );
        expect(
          (duplicate as RejectedEdit).reason,
          EditRejection.duplicateAddress,
        );

        final stale = core.apply(
          state: const EditState(version: 2),
          transaction: EditTransaction(
            id: 'stale',
            baseVersion: 1,
            source: EditSource.manual,
            changes: const [MetaOpChange(address: exposureAddress, value: 0.1)],
          ),
          context: EditContext.ios,
        );
        expect((stale as RejectedEdit).reason, EditRejection.staleVersion);

        final target = core.apply(
          state: EditState.empty,
          transaction: EditTransaction(
            id: 'target',
            baseVersion: 0,
            source: EditSource.manual,
            changes: const [
              MetaOpChange(
                address: OpAddress(
                  metaOpId: 'portrait.skin_smooth',
                  metaOpVersion: 1,
                  parameterId: 'value',
                  scope: EditScope.currentPhoto,
                  photoId: 'photo-1',
                  targetId: 'missing-face',
                ),
                value: 0.1,
              ),
            ],
          ),
          context: const EditContext(
            platform: EditPlatform.ios,
            photoIds: {'photo-1'},
          ),
        );
        expect((target as RejectedEdit).reason, EditRejection.invalidTarget);
      },
    );

    test('rejects conflicts, inapplicable ops, and missing capabilities', () {
      const core = EditingCore();
      final conflict = core.apply(
        state: EditState.empty,
        transaction: EditTransaction(
          id: 'conflict',
          baseVersion: 0,
          source: EditSource.manual,
          changes: const [
            MetaOpChange(address: _testAddressA, value: 0.1),
            MetaOpChange(address: _testAddressB, value: 0.1),
          ],
        ),
        context: EditContext.ios,
        catalog: MetaOpCatalog(const [_testDefinitionA, _testDefinitionB]),
      );
      expect((conflict as RejectedEdit).reason, EditRejection.conflict);

      final inapplicable = core.apply(
        state: EditState.empty,
        transaction: EditTransaction(
          id: 'inapplicable',
          baseVersion: 0,
          source: EditSource.manual,
          changes: const [
            MetaOpChange(
              address: OpAddress(
                metaOpId: MetaOpIds.skinSmooth,
                metaOpVersion: 1,
                parameterId: 'value',
                scope: EditScope.currentPhoto,
                photoId: 'photo-1',
                targetId: 'face-1',
              ),
              value: 0.2,
            ),
          ],
        ),
        context: const EditContext(
          platform: EditPlatform.ios,
          photoIds: {'photo-1'},
          targetIds: {'face-1'},
        ),
      );
      expect(
        (inapplicable as RejectedEdit).reason,
        EditRejection.notApplicable,
      );

      final unsupported = core.apply(
        state: EditState.empty,
        transaction: EditTransaction(
          id: 'unsupported',
          baseVersion: 0,
          source: EditSource.manual,
          changes: const [MetaOpChange(address: exposureAddress, value: 0.2)],
        ),
        context: const EditContext(
          platform: EditPlatform.android,
          capabilities: {'tone.contrast.v1'},
        ),
      );
      expect(
        (unsupported as RejectedEdit).reason,
        EditRejection.capabilityMissing,
      );

      final previewOnly = core.apply(
        state: EditState.empty,
        transaction: EditTransaction(
          id: 'preview-only',
          baseVersion: 0,
          source: EditSource.manual,
          changes: const [MetaOpChange(address: exposureAddress, value: 0.2)],
        ),
        context: EditContext(
          platform: EditPlatform.ios,
          metaOpCapabilities: PlatformMetaOpCapabilities(
            platform: EditPlatform.ios,
            entries: const [
              MetaOpExecutionSupport(
                metaOpId: MetaOpIds.exposure,
                metaOpVersion: 1,
                preview: true,
                export: false,
                maxTargets: 0,
                maxResourceBytes: 0,
              ),
            ],
          ),
        ),
      );
      expect(
        (previewOnly as RejectedEdit).reason,
        EditRejection.capabilityMissing,
      );
    });

    test(
      'rejects an invalid crop rectangle as one atomic composition transaction',
      () {
        const left = OpAddress(
          metaOpId: MetaOpIds.compositionGeometry,
          metaOpVersion: 1,
          parameterId: 'left',
          scope: EditScope.currentPhoto,
          photoId: 'photo-1',
        );
        const right = OpAddress(
          metaOpId: MetaOpIds.compositionGeometry,
          metaOpVersion: 1,
          parameterId: 'right',
          scope: EditScope.currentPhoto,
          photoId: 'photo-1',
        );

        final result = const EditingCore().apply(
          state: EditState.empty,
          transaction: EditTransaction(
            id: 'invalid-crop',
            baseVersion: 0,
            source: EditSource.manual,
            changes: const [
              MetaOpChange(address: left, value: 0.8),
              MetaOpChange(address: right, value: 0.2),
            ],
          ),
          context: const EditContext(
            platform: EditPlatform.ios,
            photoIds: {'photo-1'},
          ),
        );

        expect(result, isA<RejectedEdit>());
        expect((result as RejectedEdit).reason, EditRejection.conflict);
        expect(result.address, left);
      },
    );

    test('rejects an inactive filter with non-zero strength atomically', () {
      const filter = OpAddress(
        metaOpId: MetaOpIds.filter,
        metaOpVersion: 1,
        parameterId: 'filter',
        scope: EditScope.group,
      );
      const strength = OpAddress(
        metaOpId: MetaOpIds.filter,
        metaOpVersion: 1,
        parameterId: 'strength',
        scope: EditScope.group,
      );

      final result = const EditingCore().apply(
        state: EditState.empty,
        transaction: EditTransaction(
          id: 'invalid-filter',
          baseVersion: 0,
          source: EditSource.manual,
          changes: const [
            MetaOpChange(address: filter, value: 'none'),
            MetaOpChange(address: strength, value: 60.0),
          ],
        ),
        context: EditContext.ios,
      );

      expect(result, isA<RejectedEdit>());
      expect((result as RejectedEdit).reason, EditRejection.conflict);
      expect(result.address, strength);
    });

    test('switching filter replaces the stable address in one transaction', () {
      const filter = OpAddress(
        metaOpId: MetaOpIds.filter,
        metaOpVersion: 1,
        parameterId: 'filter',
        scope: EditScope.group,
      );
      final initial =
          const EditingCore().apply(
                state: EditState.empty,
                transaction: EditTransaction(
                  id: 'choose-cinematic',
                  baseVersion: 0,
                  source: EditSource.manual,
                  changes: const [
                    MetaOpChange(address: filter, value: 'cinematic'),
                  ],
                ),
                context: EditContext.ios,
              )
              as AcceptedEdit;

      final switched =
          const EditingCore().apply(
                state: initial.state,
                transaction: EditTransaction(
                  id: 'choose-film',
                  baseVersion: 1,
                  source: EditSource.manual,
                  changes: const [MetaOpChange(address: filter, value: 'film')],
                ),
                context: EditContext.ios,
              )
              as AcceptedEdit;

      expect(switched.state.values, {filter: 'film'});
    });
  });

  test('legacy bridge represents an image background by content identity', () {
    const sha =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const resourceId = 'resource-v1-$sha';
    const path = '/app/resources/aa/$sha.jpg';
    const adapter = LegacyEditRecipeAdapter();
    final before = EditRecipe(
      semanticEditingRecipe: SemanticEditingRecipe(
        background: BackgroundTreatment.white,
      ),
    );
    final after = EditRecipe(
      semanticEditingRecipe: SemanticEditingRecipe(
        background: BackgroundTreatment.image,
        backgroundImagePath: path,
        backgroundImageResourceId: resourceId,
      ),
    );

    final transition = adapter.tryEncodeTransition(
      before: before,
      after: after,
      photoId: 'photo-1',
    );

    expect(transition, isNotNull);
    expect(transition!.changes, hasLength(2));
    final result = const EditingCore().apply(
      state: adapter.read(before, photoId: 'photo-1'),
      transaction: EditTransaction(
        id: 'image-background',
        baseVersion: 0,
        source: EditSource.manual,
        changes: transition.changes,
      ),
      context: const EditContext(
        platform: EditPlatform.ios,
        photoIds: {'photo-1'},
        resourceIds: {resourceId},
      ),
    );
    expect(result, isA<AcceptedEdit>());
    var restored = before;
    for (final change in transition.changes) {
      restored = adapter.writeKnownValue(
        recipe: restored,
        address: change.address,
        state: (result as AcceptedEdit).state,
        resourcePaths: const {resourceId: path},
      );
    }
    expect(restored, after);
  });

  group('MetaOpCatalog', () {
    test('every definition satisfies the shared catalog contract', () {
      final catalog = MetaOpCatalog.standard;

      expect(catalog.validateContract(), isEmpty);
      expect(catalog.search('曝光'), contains(MetaOpIds.exposure));
      expect(catalog.search('brightness'), contains(MetaOpIds.exposure));
      expect(
        catalog.definition(MetaOpIds.exposure).sharing,
        MetaOpSharing.group,
      );
      expect(
        catalog.definition(MetaOpIds.exposure).aiAvailability,
        AiAvailability.enabled,
      );
    });

    test('contains the complete shareable global tone and color language', () {
      final catalog = MetaOpCatalog.standard;
      const expected = {
        MetaOpIds.exposure,
        MetaOpIds.highlights,
        MetaOpIds.shadows,
        MetaOpIds.contrast,
        MetaOpIds.warmth,
        MetaOpIds.tint,
        MetaOpIds.saturation,
        MetaOpIds.clarity,
      };

      expect(
        catalog.definitions.map((definition) => definition.id),
        containsAll(expected),
      );
      for (final id in expected) {
        final definition = catalog.definition(id);
        expect(definition.sharing, MetaOpSharing.group);
        expect(definition.stage, RenderStage.globalToneColor);
        expect(definition.parameter('value')!.neutralValue, 0);
      }
    });

    test(
      'defines composition geometry as one current-photo dedicated meta op',
      () {
        final definition = MetaOpCatalog.standard.definition(
          MetaOpIds.compositionGeometry,
        );

        expect(definition.sharing, MetaOpSharing.currentPhoto);
        expect(definition.stage, RenderStage.compositionGeometry);
        expect(definition.control, MetaOpControl.dedicatedEditor);
        expect(MetaOpCatalog.standard.search('裁剪'), [
          MetaOpIds.compositionGeometry,
        ]);
        expect(
          definition.parameters.map((parameter) => parameter.id),
          containsAll({
            'left',
            'top',
            'right',
            'bottom',
            'quarterTurns',
            'straightenDegrees',
            'flipHorizontal',
            'flipVertical',
            'perspectiveHorizontal',
            'perspectiveVertical',
          }),
        );
        expect(
          definition.parameter('quarterTurns')!.type,
          MetaOpValueType.integer,
        );
      },
    );
  });

  test('defines stable filter and per-channel HSL meta-op addresses', () {
    final catalog = MetaOpCatalog.standard;
    final filter = catalog.definition(MetaOpIds.filter);

    expect(filter.sharing, MetaOpSharing.group);
    expect(filter.stage, RenderStage.globalToneColor);
    expect(filter.control, MetaOpControl.dedicatedEditor);
    expect(filter.parameter('filter')!.choices, [
      for (final value in PhotoFilter.values) value.name,
    ]);
    expect(filter.parameter('strength')!.minimum, 0);
    expect(filter.parameter('strength')!.maximum, 100);
    expect(catalog.search('滤镜'), [MetaOpIds.filter]);

    expect(MetaOpIds.hslChannels, hasLength(HslChannel.values.length));
    for (var index = 0; index < HslChannel.values.length; index++) {
      final id = MetaOpIds.hslChannels[index];
      final definition = catalog.definition(id);
      expect(id, 'color.hsl.${HslChannel.values[index].name}');
      expect(definition.sharing, MetaOpSharing.group);
      expect(definition.stage, RenderStage.globalToneColor);
      expect(definition.parameters.map((parameter) => parameter.id), [
        'hue',
        'saturation',
        'lightness',
      ]);
    }
  });

  test('defines current-photo quality output meta ops with stable ranges', () {
    final catalog = MetaOpCatalog.standard;
    for (final id in const [
      MetaOpIds.noiseReduction,
      MetaOpIds.lowLightRecovery,
      MetaOpIds.hazeRemoval,
      MetaOpIds.detailSharpening,
    ]) {
      final definition = catalog.definition(id);
      expect(definition.sharing, MetaOpSharing.currentPhoto);
      expect(definition.targetType, MetaOpTargetType.none);
      expect(definition.stage, RenderStage.qualityOutput);
      expect(definition.control, MetaOpControl.slider);
      expect(definition.parameter('value')!.type, MetaOpValueType.integer);
      expect(definition.parameter('value')!.neutralValue, 0);
      expect(definition.parameter('value')!.minimum, 0);
      expect(definition.parameter('value')!.maximum, 100);
    }
    expect(catalog.search('降噪'), [MetaOpIds.noiseReduction]);
    expect(catalog.search('锐化'), [MetaOpIds.detailSharpening]);
  });

  test('defines the three non-geometric portrait meta ops by face target', () {
    final catalog = MetaOpCatalog.standard;
    for (final id in const [
      MetaOpIds.skinSmooth,
      MetaOpIds.skinToneLighting,
      MetaOpIds.blemishReduction,
    ]) {
      final definition = catalog.definition(id);
      expect(definition.sharing, MetaOpSharing.currentPhoto);
      expect(definition.targetType, MetaOpTargetType.face);
      expect(definition.stage, RenderStage.portraitBody);
      expect(definition.control, MetaOpControl.slider);
      expect(definition.parameter('value')!.neutralValue, 0);
      expect(definition.parameter('value')!.minimum, 0);
      expect(definition.parameter('value')!.maximum, 1);
    }
    expect(catalog.search('面部光线'), [MetaOpIds.skinToneLighting]);
    expect(catalog.search('瑕疵'), [MetaOpIds.blemishReduction]);
  });

  test('defines current-photo background and local adjustments as one op', () {
    final definition = MetaOpCatalog.standard.definition(
      MetaOpIds.semanticAdjustments,
    );

    expect(definition.stage, RenderStage.backgroundLocalMask);
    expect(definition.sharing, MetaOpSharing.currentPhoto);
    expect(definition.targetType, MetaOpTargetType.none);
    expect(
      definition.parameters.map((parameter) => parameter.id),
      containsAll(const [
        'background',
        'backgroundBlur',
        'subjectExposure',
        'subjectSaturation',
        'backgroundExposure',
        'backgroundSaturation',
        'localExposure',
        'localSaturation',
      ]),
    );
    expect(
      definition
          .parameter('background')!
          .accepts(BackgroundTreatment.white.name),
      isTrue,
    );
    expect(
      definition
          .parameter('background')!
          .accepts(BackgroundTreatment.transparent.name),
      isTrue,
    );
  });

  test('legacy adapter round trips portrait values by stable target id', () {
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
    final target = registry.targets.values.single;
    final recipe = EditRecipe(
      targetedPortraitRecipe: TargetedPortraitRecipe.neutral
          .update(
            targetId: target.id,
            region: target.region,
            parameter: TargetedPortraitParameter.textureSmoothing,
            value: 42,
          )
          .update(
            targetId: target.id,
            region: target.region,
            parameter: TargetedPortraitParameter.skinToneLighting,
            value: 25,
          ),
    );
    const adapter = LegacyEditRecipeAdapter();
    final state = adapter.read(recipe, photoId: 'photo-1');
    final addresses = state.values.keys
        .where((address) => address.targetId == target.id)
        .toList();

    expect(addresses, hasLength(2));
    expect(
      state.valueAt(
        OpAddress(
          metaOpId: MetaOpIds.skinSmooth,
          metaOpVersion: 1,
          parameterId: 'value',
          scope: EditScope.currentPhoto,
          photoId: 'photo-1',
          targetId: target.id,
        ),
      ),
      0.42,
    );

    var restored = EditRecipe.neutral;
    for (final address in addresses) {
      restored = adapter.writeKnownValue(
        recipe: restored,
        address: address,
        state: state,
        targetRegistry: registry,
      );
    }
    expect(restored.targetedPortraitRecipe, recipe.targetedPortraitRecipe);
  });

  test('legacy adapter admits geometry by stable target id', () {
    const left = DetectedEditTarget(
      photoId: 'photo-1',
      kind: EditTargetKind.face,
      analysisVersion: 'vision-v1',
      region: NormalizedEditRegion(
        left: 0.1,
        top: 0.2,
        right: 0.3,
        bottom: 0.7,
      ),
    );
    const right = DetectedEditTarget(
      photoId: 'photo-1',
      kind: EditTargetKind.face,
      analysisVersion: 'vision-v1',
      region: NormalizedEditRegion(
        left: 0.6,
        top: 0.2,
        right: 0.8,
        bottom: 0.7,
      ),
    );
    final registry = EditTargetRegistry.seed(const [left, right]);
    final rightId = registry.targets.values
        .singleWhere((target) => target.region == right.region)
        .id;
    final before = EditRecipe.neutral;
    final after = before.copyWith(
      portraitGeometryRecipe: before.portraitGeometryRecipe
          .withFaceTargetCount(2)
          .selectFace(1)
          .updateSelectedFace((target) => target.copyWith(faceSlim: 35)),
    );
    const adapter = LegacyEditRecipeAdapter();

    final transition = adapter.tryEncodeTransition(
      before: before,
      after: after,
      photoId: 'photo-1',
      targetRegistry: registry,
    );

    expect(transition, isNotNull);
    expect(transition!.changes, hasLength(1));
    final change = transition.changes.single;
    expect(change.address.metaOpId, MetaOpIds.faceGeometry);
    expect(change.address.parameterId, 'faceSlim');
    expect(change.address.targetId, rightId);
    expect(change.value, 0.35);

    final accepted = const EditingCore().apply(
      state: adapter.read(before, photoId: 'photo-1', targetRegistry: registry),
      transaction: EditTransaction(
        id: 'geometry-1',
        baseVersion: 0,
        source: EditSource.manual,
        changes: transition.changes,
      ),
      context: EditContext(
        platform: EditPlatform.ios,
        photoIds: const {'photo-1'},
        targetIds: {rightId},
        applicability: const {'photo', 'face'},
        metaOpCapabilities: iosMetaOpCapabilities,
      ),
    );
    expect(accepted, isA<AcceptedEdit>());
    final restored = adapter.writeKnownValue(
      recipe: before,
      address: change.address,
      state: (accepted as AcceptedEdit).state,
      targetRegistry: registry,
    );
    expect(restored.targetedGeometryRecipe.faces[rightId]?.faceSlim, 35);
  });

  test('legacy recipe adapter reads exposure without changing the recipe', () {
    final legacy = EditRecipe(exposure: 0.35, contrast: 0.1);

    final state = const LegacyEditRecipeAdapter().read(legacy);

    expect(state.valueAt(exposureAddress), 0.35);
    expect(legacy, EditRecipe(exposure: 0.35, contrast: 0.1));
  });

  test('legacy recipe adapter preserves every admitted global tone value', () {
    final legacy = EditRecipe(
      exposure: 0.1,
      highlights: 0.2,
      shadows: 0.3,
      contrast: 0.4,
      warmth: 0.5,
      tint: 0.6,
      saturation: 0.7,
      clarity: 0.8,
    );
    const adapter = LegacyEditRecipeAdapter();
    final state = adapter.read(legacy);

    for (final entry in const {
      MetaOpIds.exposure: 0.1,
      MetaOpIds.highlights: 0.2,
      MetaOpIds.shadows: 0.3,
      MetaOpIds.contrast: 0.4,
      MetaOpIds.warmth: 0.5,
      MetaOpIds.tint: 0.6,
      MetaOpIds.saturation: 0.7,
      MetaOpIds.clarity: 0.8,
    }.entries) {
      final address = OpAddress(
        metaOpId: entry.key,
        metaOpVersion: 1,
        parameterId: 'value',
        scope: EditScope.group,
      );
      expect(state.valueAt(address), entry.value);
      expect(
        adapter.writeKnownValue(
          recipe: EditRecipe.neutral,
          address: address,
          state: EditState(values: {address: entry.value}),
        ),
        isNot(EditRecipe.neutral),
      );
    }
  });

  test('legacy recipe adapter round trips admitted composition geometry', () {
    final legacy = EditRecipe(
      crop: CropGeometry(
        left: 0.1,
        top: 0.2,
        right: 0.9,
        bottom: 0.8,
        quarterTurns: 1,
        straightenDegrees: 2.5,
      ),
      basicEditingRecipe: BasicEditingRecipe(
        flipHorizontal: true,
        perspectiveVertical: 4,
      ),
    );
    const adapter = LegacyEditRecipeAdapter();
    final state = adapter.read(legacy, photoId: 'photo-1');

    var restored = EditRecipe.neutral;
    for (final address in state.values.keys.where(
      (address) => address.metaOpId == MetaOpIds.compositionGeometry,
    )) {
      restored = adapter.writeKnownValue(
        recipe: restored,
        address: address,
        state: state,
      );
    }

    expect(restored.crop, legacy.crop);
    expect(restored.basicEditingRecipe, legacy.basicEditingRecipe);
  });

  test('legacy recipe adapter round trips filter and keyed HSL channels', () {
    final legacy = EditRecipe(
      basicEditingRecipe: BasicEditingRecipe(
        filter: PhotoFilter.cinematic,
        filterStrength: 65,
        hsl: {
          HslChannel.red: HslAdjustment(hue: 12, saturation: -8),
          HslChannel.blue: HslAdjustment(lightness: 24),
        },
      ),
    );
    const adapter = LegacyEditRecipeAdapter();
    final state = adapter.read(legacy);

    var restored = EditRecipe.neutral;
    for (final address in state.values.keys.where(
      (address) =>
          address.metaOpId == MetaOpIds.filter ||
          MetaOpIds.hslChannels.contains(address.metaOpId),
    )) {
      restored = adapter.writeKnownValue(
        recipe: restored,
        address: address,
        state: state,
      );
    }

    expect(restored.basicEditingRecipe, legacy.basicEditingRecipe);
    final transition = adapter.tryEncodeTransition(
      before: EditRecipe.neutral,
      after: legacy,
      photoId: 'photo-1',
    );
    expect(transition, isNotNull);
    expect(
      transition!.changes.every(
        (change) => change.address.scope == EditScope.group,
      ),
      isTrue,
    );
  });

  test('legacy recipe adapter round trips current-photo quality meta ops', () {
    final legacy = EditRecipe(
      qualityEnhancementRecipe: QualityEnhancementRecipe(
        noiseReduction: 22,
        lowLightRecovery: 31,
        hazeRemoval: 14,
        detailSharpening: 27,
      ),
    );
    const adapter = LegacyEditRecipeAdapter();
    final state = adapter.read(legacy, photoId: 'photo-1');

    var restored = EditRecipe.neutral;
    for (final address in state.values.keys.where(
      (address) => const {
        MetaOpIds.noiseReduction,
        MetaOpIds.lowLightRecovery,
        MetaOpIds.hazeRemoval,
        MetaOpIds.detailSharpening,
      }.contains(address.metaOpId),
    )) {
      restored = adapter.writeKnownValue(
        recipe: restored,
        address: address,
        state: state,
      );
    }

    expect(restored.qualityEnhancementRecipe, legacy.qualityEnhancementRecipe);
    final transition = adapter.tryEncodeTransition(
      before: EditRecipe.neutral,
      after: legacy,
      photoId: 'photo-1',
    );
    expect(transition, isNotNull);
    expect(
      transition!.changes.every(
        (change) =>
            change.address.scope == EditScope.currentPhoto &&
            change.address.photoId == 'photo-1',
      ),
      isTrue,
    );
  });

  test('legacy adapter encodes only fully representable UI transitions', () {
    const adapter = LegacyEditRecipeAdapter();

    final tone = adapter.tryEncodeTransition(
      before: EditRecipe.neutral,
      after: EditRecipe(exposure: 0.2, contrast: 0.3),
      photoId: 'photo-1',
    );
    expect(tone, isNotNull);
    expect(tone!.changes, hasLength(2));
    expect(
      tone.changes.every((change) => change.address.scope == EditScope.group),
      isTrue,
    );

    final composition = adapter.tryEncodeTransition(
      before: EditRecipe.neutral,
      after: EditRecipe(crop: CropGeometry.original.copyWith(quarterTurns: 1)),
      photoId: 'photo-1',
    );
    expect(composition, isNotNull);
    expect(
      composition!.changes.single.address.metaOpId,
      MetaOpIds.compositionGeometry,
    );
    expect(composition.changes.single.address.photoId, 'photo-1');

    expect(
      adapter.tryEncodeTransition(
        before: EditRecipe.neutral,
        after: EditRecipe(portraitStrength: 0.4),
        photoId: 'photo-1',
      ),
      isNull,
    );
    expect(
      adapter.tryEncodeTransition(
        before: EditRecipe.neutral,
        after: EditRecipe(
          exposure: 0.2,
          crop: CropGeometry.original.copyWith(quarterTurns: 1),
        ),
        photoId: 'photo-1',
      ),
      isNull,
    );
  });
}

const _testDefinitionA = MetaOpDefinition(
  id: 'test.a',
  version: 1,
  semantic: 'Test operation A.',
  exclusions: {'test.b'},
  parameters: [_testParameter],
  targetType: MetaOpTargetType.none,
  stage: RenderStage.globalToneColor,
  sharing: MetaOpSharing.group,
  applicability: {'photo'},
  searchTerms: {'test a'},
  defaultOrder: 0,
  control: MetaOpControl.slider,
  aiAvailability: AiAvailability.disabled,
  requiredCapability: 'test.a.v1',
);

const _testDefinitionB = MetaOpDefinition(
  id: 'test.b',
  version: 1,
  semantic: 'Test operation B.',
  exclusions: {},
  parameters: [_testParameter],
  targetType: MetaOpTargetType.none,
  stage: RenderStage.globalToneColor,
  sharing: MetaOpSharing.group,
  applicability: {'photo'},
  searchTerms: {'test b'},
  defaultOrder: 1,
  control: MetaOpControl.slider,
  aiAvailability: AiAvailability.disabled,
  requiredCapability: 'test.b.v1',
);

const _testParameter = MetaOpParameterDefinition.number(
  id: 'value',
  neutralValue: 0,
  minimum: -1,
  maximum: 1,
);

const _testAddressA = OpAddress(
  metaOpId: 'test.a',
  metaOpVersion: 1,
  parameterId: 'value',
  scope: EditScope.group,
);

const _testAddressB = OpAddress(
  metaOpId: 'test.b',
  metaOpVersion: 1,
  parameterId: 'value',
  scope: EditScope.group,
);
