import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/editing_resource.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/portrait_geometry_recipe.dart';
import 'package:yingjian/features/editor/domain/semantic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/targeted_portrait_recipe.dart';

/// Expand-contract bridge while admitted production slices migrate from
/// [EditRecipe] to versioned meta-op state and transactions.
final class LegacyEditRecipeAdapter {
  const LegacyEditRecipeAdapter();

  EditState read(
    EditRecipe recipe, {
    String? photoId,
    EditTargetRegistry? targetRegistry,
  }) {
    final values = <OpAddress, Object>{};
    void add(String id, double value) {
      if (value == 0) return;
      values[OpAddress(
            metaOpId: id,
            metaOpVersion: 1,
            parameterId: 'value',
            scope: EditScope.group,
          )] =
          value;
    }

    add(MetaOpIds.exposure, recipe.exposure);
    add(MetaOpIds.highlights, recipe.highlights);
    add(MetaOpIds.shadows, recipe.shadows);
    add(MetaOpIds.contrast, recipe.contrast);
    add(MetaOpIds.warmth, recipe.warmth);
    add(MetaOpIds.tint, recipe.tint);
    add(MetaOpIds.saturation, recipe.saturation);
    add(MetaOpIds.clarity, recipe.clarity);
    final basic = recipe.basicEditingRecipe;
    void addGroupValue(
      String id,
      String parameterId,
      Object value,
      Object neutral,
    ) {
      if (value == neutral) return;
      values[OpAddress(
            metaOpId: id,
            metaOpVersion: 1,
            parameterId: parameterId,
            scope: EditScope.group,
          )] =
          value;
    }

    addGroupValue(MetaOpIds.filter, 'filter', basic.filter.name, 'none');
    addGroupValue(MetaOpIds.filter, 'strength', basic.filterStrength, 0.0);
    for (final entry in basic.hsl.entries) {
      final id = _metaOpIdForHslChannel(entry.key);
      addGroupValue(id, 'hue', entry.value.hue, 0.0);
      addGroupValue(id, 'saturation', entry.value.saturation, 0.0);
      addGroupValue(id, 'lightness', entry.value.lightness, 0.0);
    }
    if (photoId != null) {
      void addCurrentPhoto(String id, Object value, Object neutral) {
        if (value == neutral) return;
        values[OpAddress(
              metaOpId: id,
              metaOpVersion: 1,
              parameterId: 'value',
              scope: EditScope.currentPhoto,
              photoId: photoId,
            )] =
            value;
      }

      final quality = recipe.qualityEnhancementRecipe;
      addCurrentPhoto(MetaOpIds.noiseReduction, quality.noiseReduction, 0);
      addCurrentPhoto(MetaOpIds.lowLightRecovery, quality.lowLightRecovery, 0);
      addCurrentPhoto(MetaOpIds.hazeRemoval, quality.hazeRemoval, 0);
      addCurrentPhoto(MetaOpIds.detailSharpening, quality.detailSharpening, 0);
      for (final adjustment
          in recipe.targetedPortraitRecipe.adjustments.values) {
        void addTargeted(String id, int rawValue) {
          if (rawValue == 0) return;
          values[OpAddress(
                metaOpId: id,
                metaOpVersion: 1,
                parameterId: 'value',
                scope: EditScope.currentPhoto,
                photoId: photoId,
                targetId: adjustment.targetId,
              )] =
              rawValue / 100;
        }

        addTargeted(MetaOpIds.skinSmooth, adjustment.textureSmoothing);
        addTargeted(MetaOpIds.skinToneLighting, adjustment.skinToneLighting);
        addTargeted(MetaOpIds.blemishReduction, adjustment.blemishReduction);
      }
      for (final adjustment
          in recipe.directionalLightingRecipe.adjustments.values) {
        void addLighting(String parameterId, Object value, Object neutral) {
          if (value == neutral) return;
          values[OpAddress(
                metaOpId: MetaOpIds.directionalLighting,
                metaOpVersion: 1,
                parameterId: parameterId,
                scope: EditScope.currentPhoto,
                photoId: photoId,
                targetId: adjustment.targetId,
              )] =
              value;
        }

        addLighting('azimuth', adjustment.azimuth, 0.0);
        addLighting('intensity', adjustment.intensity, 0);
      }
      void addGeometry(
        String id,
        String parameterId,
        String targetId,
        double rawValue,
      ) {
        if (rawValue == 0 ||
            targetRegistry?.targets[targetId]?.status ==
                EditTargetStatus.suspended) {
          return;
        }
        values[OpAddress(
              metaOpId: id,
              metaOpVersion: 1,
              parameterId: parameterId,
              scope: EditScope.currentPhoto,
              photoId: photoId,
              targetId: targetId,
            )] =
            rawValue / 100;
      }

      for (final entry in recipe.targetedGeometryRecipe.faces.entries) {
        final target = entry.value;
        addGeometry(
          MetaOpIds.faceGeometry,
          'faceSlim',
          entry.key,
          target.faceSlim,
        );
        addGeometry(
          MetaOpIds.faceGeometry,
          'headSize',
          entry.key,
          target.headSize,
        );
        addGeometry(MetaOpIds.faceGeometry, 'jaw', entry.key, target.jaw);
        addGeometry(MetaOpIds.faceGeometry, 'chin', entry.key, target.chin);
        addGeometry(MetaOpIds.faceGeometry, 'eyes', entry.key, target.eyes);
        addGeometry(MetaOpIds.faceGeometry, 'nose', entry.key, target.nose);
        addGeometry(MetaOpIds.faceGeometry, 'mouth', entry.key, target.mouth);
      }
      for (final entry in recipe.targetedGeometryRecipe.bodies.entries) {
        final target = entry.value;
        addGeometry(
          MetaOpIds.bodyGeometry,
          'slimming',
          entry.key,
          target.slimming,
        );
        addGeometry(MetaOpIds.bodyGeometry, 'height', entry.key, target.height);
        addGeometry(
          MetaOpIds.bodyGeometry,
          'shoulders',
          entry.key,
          target.shoulders,
        );
        addGeometry(MetaOpIds.bodyGeometry, 'waist', entry.key, target.waist);
        addGeometry(MetaOpIds.bodyGeometry, 'legs', entry.key, target.legs);
      }
      final semantic = recipe.semanticEditingRecipe;
      void addSemantic(String parameterId, Object value, Object neutral) {
        if (value == neutral) return;
        values[OpAddress(
              metaOpId: MetaOpIds.semanticAdjustments,
              metaOpVersion: 1,
              parameterId: parameterId,
              scope: EditScope.currentPhoto,
              photoId: photoId,
            )] =
            value;
      }

      addSemantic(
        'background',
        semantic.background.name,
        BackgroundTreatment.original.name,
      );
      addSemantic(
        'backgroundImageResource',
        semantic.backgroundImageResourceId ?? '',
        '',
      );
      addSemantic(
        'subjectMaskResource',
        semantic.subjectMaskResourceId ?? '',
        '',
      );
      addSemantic('localMaskResource', semantic.localMaskResourceId ?? '', '');
      addSemantic('eraseMaskResource', semantic.eraseMaskResourceId ?? '', '');
      addSemantic('backgroundBlur', semantic.backgroundBlur, 0);
      addSemantic('subjectExposure', semantic.subjectExposure, 0);
      addSemantic('subjectSaturation', semantic.subjectSaturation, 0);
      addSemantic('backgroundExposure', semantic.backgroundExposure, 0);
      addSemantic('backgroundSaturation', semantic.backgroundSaturation, 0);
      addSemantic('localExposure', semantic.localExposure, 0);
      addSemantic('localSaturation', semantic.localSaturation, 0);
      final crop = recipe.crop;
      void addComposition(String parameterId, Object value, Object neutral) {
        if (value == neutral) return;
        values[OpAddress(
              metaOpId: MetaOpIds.compositionGeometry,
              metaOpVersion: 1,
              parameterId: parameterId,
              scope: EditScope.currentPhoto,
              photoId: photoId,
            )] =
            value;
      }

      addComposition('left', crop.left, 0.0);
      addComposition('top', crop.top, 0.0);
      addComposition('right', crop.right, 1.0);
      addComposition('bottom', crop.bottom, 1.0);
      addComposition('quarterTurns', crop.quarterTurns, 0);
      addComposition('straightenDegrees', crop.straightenDegrees, 0.0);
      addComposition('flipHorizontal', basic.flipHorizontal, false);
      addComposition('flipVertical', basic.flipVertical, false);
      addComposition('perspectiveHorizontal', basic.perspectiveHorizontal, 0.0);
      addComposition('perspectiveVertical', basic.perspectiveVertical, 0.0);
    }
    return EditState(values: Map.unmodifiable(values));
  }

  EditRecipe writeKnownValue({
    required EditRecipe recipe,
    required OpAddress address,
    required EditState state,
    EditTargetRegistry? targetRegistry,
    Map<String, String> resourcePaths = const {},
    Map<String, Object> resourcePayloads = const {},
  }) {
    final definition = MetaOpCatalog.standard.definition(address.metaOpId);
    final value =
        state.valueAt(address) ??
        definition.parameter(address.parameterId)!.neutralValue;
    return switch (address.metaOpId) {
      MetaOpIds.exposure => recipe.copyWith(
        exposure: (value as num).toDouble(),
      ),
      MetaOpIds.highlights => recipe.copyWith(
        highlights: (value as num).toDouble(),
      ),
      MetaOpIds.shadows => recipe.copyWith(shadows: (value as num).toDouble()),
      MetaOpIds.contrast => recipe.copyWith(
        contrast: (value as num).toDouble(),
      ),
      MetaOpIds.warmth => recipe.copyWith(warmth: (value as num).toDouble()),
      MetaOpIds.tint => recipe.copyWith(tint: (value as num).toDouble()),
      MetaOpIds.saturation => recipe.copyWith(
        saturation: (value as num).toDouble(),
      ),
      MetaOpIds.clarity => recipe.copyWith(clarity: (value as num).toDouble()),
      MetaOpIds.noiseReduction ||
      MetaOpIds.lowLightRecovery ||
      MetaOpIds.hazeRemoval ||
      MetaOpIds.detailSharpening => _writeQuality(
        recipe,
        address.metaOpId,
        value as int,
      ),
      MetaOpIds.skinSmooth ||
      MetaOpIds.skinToneLighting ||
      MetaOpIds.blemishReduction => _writeTargetedPortrait(
        recipe,
        address,
        (value as num).toDouble(),
        targetRegistry,
      ),
      MetaOpIds.faceGeometry ||
      MetaOpIds.bodyGeometry => _writeTargetedGeometry(
        recipe,
        address,
        (value as num).toDouble(),
        targetRegistry,
      ),
      MetaOpIds.directionalLighting => _writeDirectionalLighting(
        recipe,
        address,
        value,
        state,
        targetRegistry,
      ),
      MetaOpIds.semanticAdjustments => _writeSemantic(
        recipe,
        address,
        state,
        resourcePaths,
        resourcePayloads,
      ),
      MetaOpIds.filter => _writeFilter(recipe, address.parameterId, value),
      MetaOpIds.compositionGeometry => _writeComposition(
        recipe,
        address.parameterId,
        value,
      ),
      _ when MetaOpIds.hslChannels.contains(address.metaOpId) => _writeHsl(
        recipe,
        address.metaOpId,
        address.parameterId,
        value,
      ),
      _ => throw ArgumentError.value(
        address.metaOpId,
        'address',
        'Meta op has no legacy write bridge',
      ),
    };
  }

  LegacyMetaOpTransition? tryEncodeTransition({
    required EditRecipe before,
    required EditRecipe after,
    required String photoId,
    EditTargetRegistry? targetRegistry,
  }) {
    final changes = <MetaOpChange>[];
    void addGlobal(String id, double previous, double next) {
      if (previous == next) return;
      changes.add(
        MetaOpChange(
          address: OpAddress(
            metaOpId: id,
            metaOpVersion: 1,
            parameterId: 'value',
            scope: EditScope.group,
          ),
          value: next,
        ),
      );
    }

    addGlobal(MetaOpIds.exposure, before.exposure, after.exposure);
    addGlobal(MetaOpIds.highlights, before.highlights, after.highlights);
    addGlobal(MetaOpIds.shadows, before.shadows, after.shadows);
    addGlobal(MetaOpIds.contrast, before.contrast, after.contrast);
    addGlobal(MetaOpIds.warmth, before.warmth, after.warmth);
    addGlobal(MetaOpIds.tint, before.tint, after.tint);
    addGlobal(MetaOpIds.saturation, before.saturation, after.saturation);
    addGlobal(MetaOpIds.clarity, before.clarity, after.clarity);

    void addGroup(String id, String parameterId, Object previous, Object next) {
      if (previous == next) return;
      changes.add(
        MetaOpChange(
          address: OpAddress(
            metaOpId: id,
            metaOpVersion: 1,
            parameterId: parameterId,
            scope: EditScope.group,
          ),
          value: next,
        ),
      );
    }

    final beforeBasic = before.basicEditingRecipe;
    final afterBasic = after.basicEditingRecipe;
    addGroup(
      MetaOpIds.filter,
      'filter',
      beforeBasic.filter.name,
      afterBasic.filter.name,
    );
    addGroup(
      MetaOpIds.filter,
      'strength',
      beforeBasic.filterStrength,
      afterBasic.filterStrength,
    );
    for (final channel in HslChannel.values) {
      final id = _metaOpIdForHslChannel(channel);
      final previous = beforeBasic.hsl[channel] ?? HslAdjustment.neutral;
      final next = afterBasic.hsl[channel] ?? HslAdjustment.neutral;
      addGroup(id, 'hue', previous.hue, next.hue);
      addGroup(id, 'saturation', previous.saturation, next.saturation);
      addGroup(id, 'lightness', previous.lightness, next.lightness);
    }

    void addComposition(String parameterId, Object previous, Object next) {
      if (previous == next) return;
      changes.add(
        MetaOpChange(
          address: OpAddress(
            metaOpId: MetaOpIds.compositionGeometry,
            metaOpVersion: 1,
            parameterId: parameterId,
            scope: EditScope.currentPhoto,
            photoId: photoId,
          ),
          value: next,
        ),
      );
    }

    addComposition('left', before.crop.left, after.crop.left);
    addComposition('top', before.crop.top, after.crop.top);
    addComposition('right', before.crop.right, after.crop.right);
    addComposition('bottom', before.crop.bottom, after.crop.bottom);
    addComposition(
      'quarterTurns',
      before.crop.quarterTurns,
      after.crop.quarterTurns,
    );
    addComposition(
      'straightenDegrees',
      before.crop.straightenDegrees,
      after.crop.straightenDegrees,
    );
    addComposition(
      'flipHorizontal',
      beforeBasic.flipHorizontal,
      afterBasic.flipHorizontal,
    );
    addComposition(
      'flipVertical',
      beforeBasic.flipVertical,
      afterBasic.flipVertical,
    );
    addComposition(
      'perspectiveHorizontal',
      beforeBasic.perspectiveHorizontal,
      afterBasic.perspectiveHorizontal,
    );
    addComposition(
      'perspectiveVertical',
      beforeBasic.perspectiveVertical,
      afterBasic.perspectiveVertical,
    );

    void addQuality(String id, int previous, int next) {
      if (previous == next) return;
      changes.add(
        MetaOpChange(
          address: OpAddress(
            metaOpId: id,
            metaOpVersion: 1,
            parameterId: 'value',
            scope: EditScope.currentPhoto,
            photoId: photoId,
          ),
          value: next,
        ),
      );
    }

    final beforeQuality = before.qualityEnhancementRecipe;
    final afterQuality = after.qualityEnhancementRecipe;
    addQuality(
      MetaOpIds.noiseReduction,
      beforeQuality.noiseReduction,
      afterQuality.noiseReduction,
    );
    addQuality(
      MetaOpIds.lowLightRecovery,
      beforeQuality.lowLightRecovery,
      afterQuality.lowLightRecovery,
    );
    addQuality(
      MetaOpIds.hazeRemoval,
      beforeQuality.hazeRemoval,
      afterQuality.hazeRemoval,
    );
    addQuality(
      MetaOpIds.detailSharpening,
      beforeQuality.detailSharpening,
      afterQuality.detailSharpening,
    );

    void addTargeted(String id, String targetId, int previous, int next) {
      if (previous == next) return;
      changes.add(
        MetaOpChange(
          address: OpAddress(
            metaOpId: id,
            metaOpVersion: 1,
            parameterId: 'value',
            scope: EditScope.currentPhoto,
            photoId: photoId,
            targetId: targetId,
          ),
          value: next / 100,
        ),
      );
    }

    final targetIds = {
      ...before.targetedPortraitRecipe.adjustments.keys,
      ...after.targetedPortraitRecipe.adjustments.keys,
    };
    for (final targetId in targetIds) {
      final previous = before.targetedPortraitRecipe.adjustments[targetId];
      final next = after.targetedPortraitRecipe.adjustments[targetId];
      addTargeted(
        MetaOpIds.skinSmooth,
        targetId,
        previous?.textureSmoothing ?? 0,
        next?.textureSmoothing ?? 0,
      );
      addTargeted(
        MetaOpIds.skinToneLighting,
        targetId,
        previous?.skinToneLighting ?? 0,
        next?.skinToneLighting ?? 0,
      );
      addTargeted(
        MetaOpIds.blemishReduction,
        targetId,
        previous?.blemishReduction ?? 0,
        next?.blemishReduction ?? 0,
      );
    }

    final lightingTargetIds = {
      ...before.directionalLightingRecipe.adjustments.keys,
      ...after.directionalLightingRecipe.adjustments.keys,
    };
    for (final targetId in lightingTargetIds) {
      final previous = before.directionalLightingRecipe.adjustments[targetId];
      final next = after.directionalLightingRecipe.adjustments[targetId];
      void addLighting(String parameterId, Object oldValue, Object newValue) {
        if (oldValue == newValue) return;
        changes.add(
          MetaOpChange(
            address: OpAddress(
              metaOpId: MetaOpIds.directionalLighting,
              metaOpVersion: 1,
              parameterId: parameterId,
              scope: EditScope.currentPhoto,
              photoId: photoId,
              targetId: targetId,
            ),
            value: newValue,
          ),
        );
      }

      addLighting('azimuth', previous?.azimuth ?? 0.0, next?.azimuth ?? 0.0);
      addLighting('intensity', previous?.intensity ?? 0, next?.intensity ?? 0);
    }

    void addGeometry(
      String id,
      String parameterId,
      String targetId,
      double previous,
      double next,
    ) {
      if (previous == next) return;
      changes.add(
        MetaOpChange(
          address: OpAddress(
            metaOpId: id,
            metaOpVersion: 1,
            parameterId: parameterId,
            scope: EditScope.currentPhoto,
            photoId: photoId,
            targetId: targetId,
          ),
          value: next / 100,
        ),
      );
    }

    if (targetRegistry != null) {
      final faces = _activeTargets(targetRegistry, EditTargetKind.face);
      final bodies = _activeTargets(targetRegistry, EditTargetKind.body);
      for (var index = 0; index < faces.length; index++) {
        final previous =
            index < before.portraitGeometryRecipe.faceTargets.length
            ? before.portraitGeometryRecipe.faceTargets[index]
            : FaceGeometryTarget.neutral;
        final next = index < after.portraitGeometryRecipe.faceTargets.length
            ? after.portraitGeometryRecipe.faceTargets[index]
            : FaceGeometryTarget.neutral;
        for (final entry in <String, (double, double)>{
          'faceSlim': (previous.faceSlim, next.faceSlim),
          'headSize': (previous.headSize, next.headSize),
          'jaw': (previous.jaw, next.jaw),
          'chin': (previous.chin, next.chin),
          'eyes': (previous.eyes, next.eyes),
          'nose': (previous.nose, next.nose),
          'mouth': (previous.mouth, next.mouth),
        }.entries) {
          addGeometry(
            MetaOpIds.faceGeometry,
            entry.key,
            faces[index].id,
            entry.value.$1,
            entry.value.$2,
          );
        }
      }
      for (var index = 0; index < bodies.length; index++) {
        final previous =
            index < before.portraitGeometryRecipe.bodyTargets.length
            ? before.portraitGeometryRecipe.bodyTargets[index]
            : BodyGeometryTarget.neutral;
        final next = index < after.portraitGeometryRecipe.bodyTargets.length
            ? after.portraitGeometryRecipe.bodyTargets[index]
            : BodyGeometryTarget.neutral;
        for (final entry in <String, (double, double)>{
          'slimming': (previous.slimming, next.slimming),
          'height': (previous.height, next.height),
          'shoulders': (previous.shoulders, next.shoulders),
          'waist': (previous.waist, next.waist),
          'legs': (previous.legs, next.legs),
        }.entries) {
          addGeometry(
            MetaOpIds.bodyGeometry,
            entry.key,
            bodies[index].id,
            entry.value.$1,
            entry.value.$2,
          );
        }
      }
    }

    final beforeSemantic = before.semanticEditingRecipe;
    final afterSemantic = after.semanticEditingRecipe;
    void addSemantic(String parameterId, Object previous, Object next) {
      if (previous == next) return;
      changes.add(
        MetaOpChange(
          address: OpAddress(
            metaOpId: MetaOpIds.semanticAdjustments,
            metaOpVersion: 1,
            parameterId: parameterId,
            scope: EditScope.currentPhoto,
            photoId: photoId,
          ),
          value: next,
        ),
      );
    }

    addSemantic(
      'background',
      beforeSemantic.background.name,
      afterSemantic.background.name,
    );
    addSemantic(
      'backgroundImageResource',
      beforeSemantic.backgroundImageResourceId ?? '',
      afterSemantic.backgroundImageResourceId ?? '',
    );
    addSemantic(
      'backgroundBlur',
      beforeSemantic.backgroundBlur,
      afterSemantic.backgroundBlur,
    );
    addSemantic(
      'subjectExposure',
      beforeSemantic.subjectExposure,
      afterSemantic.subjectExposure,
    );
    addSemantic(
      'subjectSaturation',
      beforeSemantic.subjectSaturation,
      afterSemantic.subjectSaturation,
    );
    addSemantic(
      'backgroundExposure',
      beforeSemantic.backgroundExposure,
      afterSemantic.backgroundExposure,
    );
    addSemantic(
      'backgroundSaturation',
      beforeSemantic.backgroundSaturation,
      afterSemantic.backgroundSaturation,
    );
    addSemantic(
      'localExposure',
      beforeSemantic.localExposure,
      afterSemantic.localExposure,
    );
    addSemantic(
      'localSaturation',
      beforeSemantic.localSaturation,
      afterSemantic.localSaturation,
    );
    addSemantic(
      'subjectMaskResource',
      beforeSemantic.subjectMaskResourceId ?? '',
      afterSemantic.subjectMaskResourceId ?? '',
    );
    addSemantic(
      'localMaskResource',
      beforeSemantic.localMaskResourceId ?? '',
      afterSemantic.localMaskResourceId ?? '',
    );
    addSemantic(
      'eraseMaskResource',
      beforeSemantic.eraseMaskResourceId ?? '',
      afterSemantic.eraseMaskResourceId ?? '',
    );

    final projected = before.copyWith(
      exposure: after.exposure,
      highlights: after.highlights,
      shadows: after.shadows,
      contrast: after.contrast,
      warmth: after.warmth,
      tint: after.tint,
      saturation: after.saturation,
      clarity: after.clarity,
      crop: after.crop,
      basicEditingRecipe: beforeBasic.copyWith(
        flipHorizontal: afterBasic.flipHorizontal,
        flipVertical: afterBasic.flipVertical,
        perspectiveHorizontal: afterBasic.perspectiveHorizontal,
        perspectiveVertical: afterBasic.perspectiveVertical,
        filter: afterBasic.filter,
        filterStrength: afterBasic.filterStrength,
        hsl: afterBasic.hsl,
      ),
      qualityEnhancementRecipe: afterQuality,
      portraitGeometryRecipe: targetRegistry == null
          ? before.portraitGeometryRecipe
          : after.portraitGeometryRecipe,
      targetedPortraitRecipe: after.targetedPortraitRecipe,
      targetedGeometryRecipe: after.targetedGeometryRecipe,
      directionalLightingRecipe: after.directionalLightingRecipe,
      semanticEditingRecipe: beforeSemantic.copyWith(
        background: afterSemantic.background,
        backgroundImagePath: afterSemantic.backgroundImagePath,
        backgroundImageResourceId: afterSemantic.backgroundImageResourceId,
        backgroundBlur: afterSemantic.backgroundBlur,
        subjectExposure: afterSemantic.subjectExposure,
        subjectSaturation: afterSemantic.subjectSaturation,
        backgroundExposure: afterSemantic.backgroundExposure,
        backgroundSaturation: afterSemantic.backgroundSaturation,
        localExposure: afterSemantic.localExposure,
        localSaturation: afterSemantic.localSaturation,
        subjectMaskStrokes: afterSemantic.subjectMaskStrokes,
        subjectMaskResourceId: afterSemantic.subjectMaskResourceId,
        localAdjustmentStrokes: afterSemantic.localAdjustmentStrokes,
        localMaskResourceId: afterSemantic.localMaskResourceId,
        eraseStrokes: afterSemantic.eraseStrokes,
        eraseMaskResourceId: afterSemantic.eraseMaskResourceId,
      ),
    );
    if (projected != after) return null;
    final scopes = changes.map((change) => change.address.scope).toSet();
    if (scopes.length > 1) return null;
    return LegacyMetaOpTransition(changes: changes);
  }

  EditRecipe _writeSemantic(
    EditRecipe recipe,
    OpAddress address,
    EditState state,
    Map<String, String> resourcePaths,
    Map<String, Object> resourcePayloads,
  ) {
    final semantic = recipe.semanticEditingRecipe;
    Object? value(String parameterId) => state.valueAt(
      OpAddress(
        metaOpId: address.metaOpId,
        metaOpVersion: address.metaOpVersion,
        parameterId: parameterId,
        scope: address.scope,
        photoId: address.photoId,
        targetId: address.targetId,
      ),
    );
    final background = BackgroundTreatment.values.byName(
      (value('background') as String?) ?? semantic.background.name,
    );
    final resourceId = value('backgroundImageResource') as String?;
    final next = switch (address.parameterId) {
      'background' || 'backgroundImageResource' => semantic.copyWith(
        background: background,
        backgroundImagePath: background == BackgroundTreatment.image
            ? resourcePaths[resourceId]
            : null,
        backgroundImageResourceId: background == BackgroundTreatment.image
            ? resourceId
            : null,
      ),
      'backgroundBlur' => semantic.copyWith(
        backgroundBlur: value('backgroundBlur') as int,
      ),
      'subjectExposure' => semantic.copyWith(
        subjectExposure: value('subjectExposure') as int,
      ),
      'subjectSaturation' => semantic.copyWith(
        subjectSaturation: value('subjectSaturation') as int,
      ),
      'backgroundExposure' => semantic.copyWith(
        backgroundExposure: value('backgroundExposure') as int,
      ),
      'backgroundSaturation' => semantic.copyWith(
        backgroundSaturation: value('backgroundSaturation') as int,
      ),
      'localExposure' => semantic.copyWith(
        localExposure: value('localExposure') as int,
      ),
      'localSaturation' => semantic.copyWith(
        localSaturation: value('localSaturation') as int,
      ),
      'subjectMaskResource' => _writeMaskResource(
        semantic,
        resourceId: value('subjectMaskResource') as String?,
        payloads: resourcePayloads,
        kind: EditingResourceKind.subjectMask,
      ),
      'localMaskResource' => _writeMaskResource(
        semantic,
        resourceId: value('localMaskResource') as String?,
        payloads: resourcePayloads,
        kind: EditingResourceKind.localMask,
      ),
      'eraseMaskResource' => _writeMaskResource(
        semantic,
        resourceId: value('eraseMaskResource') as String?,
        payloads: resourcePayloads,
        kind: EditingResourceKind.eraseMask,
      ),
      _ => throw ArgumentError.value(address.parameterId, 'parameterId'),
    };
    return recipe.copyWith(semanticEditingRecipe: next);
  }

  EditRecipe _writeComposition(
    EditRecipe recipe,
    String parameterId,
    Object value,
  ) {
    final crop = recipe.crop;
    final basic = recipe.basicEditingRecipe;
    return switch (parameterId) {
      'left' => recipe.copyWith(
        crop: crop.copyWith(left: (value as num).toDouble()),
      ),
      'top' => recipe.copyWith(
        crop: crop.copyWith(top: (value as num).toDouble()),
      ),
      'right' => recipe.copyWith(
        crop: crop.copyWith(right: (value as num).toDouble()),
      ),
      'bottom' => recipe.copyWith(
        crop: crop.copyWith(bottom: (value as num).toDouble()),
      ),
      'quarterTurns' => recipe.copyWith(
        crop: crop.copyWith(quarterTurns: value as int),
      ),
      'straightenDegrees' => recipe.copyWith(
        crop: crop.copyWith(straightenDegrees: (value as num).toDouble()),
      ),
      'flipHorizontal' => recipe.copyWith(
        basicEditingRecipe: basic.copyWith(flipHorizontal: value as bool),
      ),
      'flipVertical' => recipe.copyWith(
        basicEditingRecipe: basic.copyWith(flipVertical: value as bool),
      ),
      'perspectiveHorizontal' => recipe.copyWith(
        basicEditingRecipe: basic.copyWith(
          perspectiveHorizontal: (value as num).toDouble(),
        ),
      ),
      'perspectiveVertical' => recipe.copyWith(
        basicEditingRecipe: basic.copyWith(
          perspectiveVertical: (value as num).toDouble(),
        ),
      ),
      _ => throw ArgumentError.value(
        parameterId,
        'parameterId',
        'Unknown composition parameter',
      ),
    };
  }

  SemanticEditingRecipe _writeMaskResource(
    SemanticEditingRecipe semantic, {
    required String? resourceId,
    required Map<String, Object> payloads,
    required EditingResourceKind kind,
  }) {
    if (resourceId == null || resourceId.isEmpty) {
      return switch (kind) {
        EditingResourceKind.subjectMask => semantic.copyWith(
          subjectMaskStrokes: const [],
          subjectMaskResourceId: null,
        ),
        EditingResourceKind.localMask => semantic.copyWith(
          localAdjustmentStrokes: const [],
          localMaskResourceId: null,
        ),
        EditingResourceKind.eraseMask => semantic.copyWith(
          eraseStrokes: const [],
          eraseMaskResourceId: null,
        ),
        EditingResourceKind.backgroundImage => throw ArgumentError.value(kind),
      };
    }
    final payload = payloads[resourceId];
    if (payload is! List) {
      throw ArgumentError.value(resourceId, 'resourceId', 'Payload is missing');
    }
    return switch (kind) {
      EditingResourceKind.subjectMask => semantic.copyWith(
        subjectMaskStrokes: payload
            .map(
              (value) =>
                  MaskStroke.fromJson(Map<String, Object?>.from(value as Map)),
            )
            .toList(growable: false),
        subjectMaskResourceId: resourceId,
      ),
      EditingResourceKind.localMask => semantic.copyWith(
        localAdjustmentStrokes: payload
            .map(
              (value) =>
                  MaskStroke.fromJson(Map<String, Object?>.from(value as Map)),
            )
            .toList(growable: false),
        localMaskResourceId: resourceId,
      ),
      EditingResourceKind.eraseMask => semantic.copyWith(
        eraseStrokes: payload
            .map(
              (value) =>
                  EraseStroke.fromJson(Map<String, Object?>.from(value as Map)),
            )
            .toList(growable: false),
        eraseMaskResourceId: resourceId,
      ),
      EditingResourceKind.backgroundImage => throw ArgumentError.value(kind),
    };
  }

  EditRecipe _writeFilter(EditRecipe recipe, String parameterId, Object value) {
    final basic = recipe.basicEditingRecipe;
    return switch (parameterId) {
      'filter' => recipe.copyWith(
        basicEditingRecipe: basic.copyWith(
          filter: PhotoFilter.values.byName(value as String),
        ),
      ),
      'strength' => recipe.copyWith(
        basicEditingRecipe: basic.copyWith(
          filterStrength: (value as num).toDouble(),
        ),
      ),
      _ => throw ArgumentError.value(
        parameterId,
        'parameterId',
        'Unknown filter parameter',
      ),
    };
  }

  EditRecipe _writeQuality(EditRecipe recipe, String metaOpId, int value) {
    final quality = recipe.qualityEnhancementRecipe;
    final next = switch (metaOpId) {
      MetaOpIds.noiseReduction => quality.copyWith(noiseReduction: value),
      MetaOpIds.lowLightRecovery => quality.copyWith(lowLightRecovery: value),
      MetaOpIds.hazeRemoval => quality.copyWith(hazeRemoval: value),
      MetaOpIds.detailSharpening => quality.copyWith(detailSharpening: value),
      _ => throw ArgumentError.value(
        metaOpId,
        'metaOpId',
        'Unknown quality meta op',
      ),
    };
    return recipe.copyWith(qualityEnhancementRecipe: next);
  }

  EditRecipe _writeTargetedPortrait(
    EditRecipe recipe,
    OpAddress address,
    double value,
    EditTargetRegistry? targetRegistry,
  ) {
    final targetId = address.targetId;
    if (targetId == null) {
      throw ArgumentError.value(address, 'address', 'Face target is required');
    }
    final existing = recipe.targetedPortraitRecipe.adjustments[targetId];
    final target = existing == null ? targetRegistry?.targets[targetId] : null;
    if (existing == null && target == null) {
      throw ArgumentError.value(
        targetId,
        'address.targetId',
        'Unknown stable face target',
      );
    }
    final parameter = switch (address.metaOpId) {
      MetaOpIds.skinSmooth => TargetedPortraitParameter.textureSmoothing,
      MetaOpIds.skinToneLighting => TargetedPortraitParameter.skinToneLighting,
      MetaOpIds.blemishReduction => TargetedPortraitParameter.blemishReduction,
      _ => throw ArgumentError.value(address.metaOpId, 'address.metaOpId'),
    };
    return recipe.copyWith(
      targetedPortraitRecipe: recipe.targetedPortraitRecipe.update(
        targetId: targetId,
        region: existing?.region ?? target!.region,
        parameter: parameter,
        value: (value * 100).round(),
      ),
    );
  }

  EditRecipe _writeTargetedGeometry(
    EditRecipe recipe,
    OpAddress address,
    double value,
    EditTargetRegistry? targetRegistry,
  ) {
    final targetId = address.targetId;
    if (targetId == null || targetRegistry == null) {
      throw ArgumentError.value(
        address,
        'address',
        'Stable target is required',
      );
    }
    final kind = address.metaOpId == MetaOpIds.faceGeometry
        ? EditTargetKind.face
        : EditTargetKind.body;
    final targets = _activeTargets(targetRegistry, kind);
    final index = targets.indexWhere((target) => target.id == targetId);
    if (index < 0) {
      throw ArgumentError.value(targetId, 'address.targetId', 'Unknown target');
    }
    var geometry = recipe.portraitGeometryRecipe;
    var targeted = recipe.targetedGeometryRecipe;
    if (kind == EditTargetKind.face) {
      geometry = geometry.withFaceTargetCount(targets.length).selectFace(index);
      geometry = geometry.updateSelectedFace(
        (target) => switch (address.parameterId) {
          'faceSlim' => target.copyWith(faceSlim: value * 100),
          'headSize' => target.copyWith(headSize: value * 100),
          'jaw' => target.copyWith(jaw: value * 100),
          'chin' => target.copyWith(chin: value * 100),
          'eyes' => target.copyWith(eyes: value * 100),
          'nose' => target.copyWith(nose: value * 100),
          'mouth' => target.copyWith(mouth: value * 100),
          _ => throw ArgumentError.value(address.parameterId, 'parameterId'),
        },
      );
      targeted = targeted.updateFace(
        targetId,
        (target) => switch (address.parameterId) {
          'faceSlim' => target.copyWith(faceSlim: value * 100),
          'headSize' => target.copyWith(headSize: value * 100),
          'jaw' => target.copyWith(jaw: value * 100),
          'chin' => target.copyWith(chin: value * 100),
          'eyes' => target.copyWith(eyes: value * 100),
          'nose' => target.copyWith(nose: value * 100),
          'mouth' => target.copyWith(mouth: value * 100),
          _ => throw ArgumentError.value(address.parameterId, 'parameterId'),
        },
      );
    } else {
      geometry = geometry.withBodyTargetCount(targets.length).selectBody(index);
      geometry = geometry.updateSelectedBody(
        (target) => switch (address.parameterId) {
          'slimming' => target.copyWith(slimming: value * 100),
          'height' => target.copyWith(height: value * 100),
          'shoulders' => target.copyWith(shoulders: value * 100),
          'waist' => target.copyWith(waist: value * 100),
          'legs' => target.copyWith(legs: value * 100),
          _ => throw ArgumentError.value(address.parameterId, 'parameterId'),
        },
      );
      targeted = targeted.updateBody(
        targetId,
        (target) => switch (address.parameterId) {
          'slimming' => target.copyWith(slimming: value * 100),
          'height' => target.copyWith(height: value * 100),
          'shoulders' => target.copyWith(shoulders: value * 100),
          'waist' => target.copyWith(waist: value * 100),
          'legs' => target.copyWith(legs: value * 100),
          _ => throw ArgumentError.value(address.parameterId, 'parameterId'),
        },
      );
    }
    return recipe.copyWith(
      portraitGeometryRecipe: geometry,
      targetedGeometryRecipe: targeted,
    );
  }

  EditRecipe _writeDirectionalLighting(
    EditRecipe recipe,
    OpAddress address,
    Object value,
    EditState state,
    EditTargetRegistry? targetRegistry,
  ) {
    final targetId = address.targetId;
    if (targetId == null) {
      throw ArgumentError.value(address, 'address', 'Face target is required');
    }
    final existing = recipe.directionalLightingRecipe.adjustments[targetId];
    final target = existing == null ? targetRegistry?.targets[targetId] : null;
    if (existing == null && target == null) {
      throw ArgumentError.value(targetId, 'targetId', 'Unknown face target');
    }
    Object read(String parameterId, Object fallback) =>
        state.valueAt(
          OpAddress(
            metaOpId: MetaOpIds.directionalLighting,
            metaOpVersion: 1,
            parameterId: parameterId,
            scope: address.scope,
            photoId: address.photoId,
            targetId: targetId,
          ),
        ) ??
        fallback;
    final azimuth = address.parameterId == 'azimuth'
        ? (value as num).toDouble()
        : (read('azimuth', existing?.azimuth ?? 0.0) as num).toDouble();
    final intensity = address.parameterId == 'intensity'
        ? value as int
        : read('intensity', existing?.intensity ?? 0) as int;
    return recipe.copyWith(
      directionalLightingRecipe: recipe.directionalLightingRecipe.update(
        targetId: targetId,
        region: existing?.region ?? target!.region,
        azimuth: azimuth,
        intensity: intensity,
      ),
    );
  }

  EditRecipe _writeHsl(
    EditRecipe recipe,
    String metaOpId,
    String parameterId,
    Object value,
  ) {
    final channel = _hslChannelForMetaOp(metaOpId);
    final basic = recipe.basicEditingRecipe;
    final current = basic.hsl[channel] ?? HslAdjustment.neutral;
    final numeric = (value as num).toDouble();
    final next = switch (parameterId) {
      'hue' => HslAdjustment(
        hue: numeric,
        saturation: current.saturation,
        lightness: current.lightness,
      ),
      'saturation' => HslAdjustment(
        hue: current.hue,
        saturation: numeric,
        lightness: current.lightness,
      ),
      'lightness' => HslAdjustment(
        hue: current.hue,
        saturation: current.saturation,
        lightness: numeric,
      ),
      _ => throw ArgumentError.value(
        parameterId,
        'parameterId',
        'Unknown HSL parameter',
      ),
    };
    final hsl = Map<HslChannel, HslAdjustment>.of(basic.hsl);
    if (next.isNeutral) {
      hsl.remove(channel);
    } else {
      hsl[channel] = next;
    }
    return recipe.copyWith(basicEditingRecipe: basic.copyWith(hsl: hsl));
  }
}

List<StableEditTarget> _activeTargets(
  EditTargetRegistry registry,
  EditTargetKind kind,
) =>
    registry.targets.values
        .where(
          (target) =>
              target.kind == kind && target.status == EditTargetStatus.active,
        )
        .toList()
      ..sort((left, right) {
        final horizontal = left.region.left.compareTo(right.region.left);
        return horizontal != 0
            ? horizontal
            : left.region.top.compareTo(right.region.top);
      });

String _metaOpIdForHslChannel(HslChannel channel) =>
    MetaOpIds.hslChannels[channel.index];

HslChannel _hslChannelForMetaOp(String id) {
  final index = MetaOpIds.hslChannels.indexOf(id);
  if (index < 0) throw ArgumentError.value(id, 'id', 'Unknown HSL meta op');
  return HslChannel.values[index];
}

@immutable
final class LegacyMetaOpTransition {
  LegacyMetaOpTransition({required Iterable<MetaOpChange> changes})
    : changes = List.unmodifiable(changes);

  final List<MetaOpChange> changes;
}
