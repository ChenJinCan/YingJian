import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/meta_op_availability.dart';

@immutable
final class AiPhotoAnalysis {
  const AiPhotoAnalysis({required this.scene, this.targetIds = const []});

  final String scene;
  final List<String> targetIds;

  Map<String, Object> toJson() => {'scene': scene, 'targetIds': targetIds};
}

@immutable
final class AiEditPlanningRequest {
  AiEditPlanningRequest({
    required this.intent,
    required this.baseStateVersion,
    required this.currentState,
    required Iterable<AiMetaOpCapability> capabilities,
    required this.photoAnalysis,
    this.photoId,
  }) : capabilities = List.unmodifiable(capabilities);

  final String intent;
  final int baseStateVersion;
  final EditState currentState;
  final List<AiMetaOpCapability> capabilities;
  final AiPhotoAnalysis photoAnalysis;
  final String? photoId;
}

sealed class AiPlanningOutcome {
  const AiPlanningOutcome();
}

@immutable
final class AiEditProposal extends AiPlanningOutcome {
  AiEditProposal({
    String? proposalId,
    String? idempotencyKey,
    required this.baseStateVersion,
    required Iterable<MetaOpChange> changes,
    required Iterable<String> summary,
    Iterable<String> warnings = const [],
    this.confidence = 1,
  }) : changes = List.unmodifiable(changes),
       summary = List.unmodifiable(summary),
       warnings = List.unmodifiable(warnings),
       proposalId =
           proposalId ??
           _proposalIdentity(baseStateVersion, changes, prefix: 'proposal'),
       idempotencyKey =
           idempotencyKey ??
           _proposalIdentity(baseStateVersion, changes, prefix: 'ai-edit');

  final String proposalId;
  final String idempotencyKey;
  final int baseStateVersion;
  final List<MetaOpChange> changes;
  final List<String> summary;
  final List<String> warnings;
  final double confidence;

  static String _proposalIdentity(
    int baseStateVersion,
    Iterable<MetaOpChange> changes, {
    required String prefix,
  }) {
    final payload = jsonEncode({
      'baseStateVersion': baseStateVersion,
      'changes': changes
          .map(
            (change) => {
              'address': change.address.toJson(),
              'value': change.value,
            },
          )
          .toList(growable: false),
    });
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(payload)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return '$prefix-v1-${hash.toRadixString(16).padLeft(8, '0')}';
  }
}

@immutable
final class AiNoAction extends AiPlanningOutcome {
  const AiNoAction();
}

@immutable
final class AiPlannerUnavailable extends AiPlanningOutcome {
  const AiPlannerUnavailable();
}

@immutable
final class AiTargetClarification extends AiPlanningOutcome {
  AiTargetClarification({
    required this.targetType,
    required this.baseStateVersion,
    required Iterable<MetaOpChange> pendingChanges,
    required Iterable<String> summary,
  }) : pendingChanges = List.unmodifiable(pendingChanges),
       summary = List.unmodifiable(summary);

  final MetaOpTargetType targetType;
  final int baseStateVersion;
  final List<MetaOpChange> pendingChanges;
  final List<String> summary;

  AiEditProposal resolve(String targetId) => AiEditProposal(
    baseStateVersion: baseStateVersion,
    changes: pendingChanges.map(
      (change) => MetaOpChange(
        address: OpAddress(
          metaOpId: change.address.metaOpId,
          metaOpVersion: change.address.metaOpVersion,
          parameterId: change.address.parameterId,
          scope: change.address.scope,
          photoId: change.address.photoId,
          targetId: targetId,
        ),
        value: change.value,
      ),
    ),
    summary: summary,
  );
}

abstract interface class AiEditPlanner {
  Future<AiPlanningOutcome> plan(AiEditPlanningRequest request);
}

/// Deterministic offline planner used as the always-available baseline.
///
/// A cloud planner may replace this adapter, but it must return the same
/// structured proposal contract and never pixels, scripts, or render plans.
final class LocalAiEditPlanner implements AiEditPlanner {
  const LocalAiEditPlanner();

  @override
  Future<AiPlanningOutcome> plan(AiEditPlanningRequest request) async {
    final intent = request.intent.trim().toLowerCase();
    if (intent.isEmpty) return const AiNoAction();
    final admitted = {
      for (final capability in request.capabilities)
        capability.definition.id: capability.definition,
    };
    final changes = <MetaOpChange>[];

    AiPlanningOutcome? portraitProposal() {
      if (!_containsAny(intent, const [
        '皮肤自然',
        '自然美化',
        '皮肤干净',
        'natural skin',
      ])) {
        return null;
      }
      const values = {
        MetaOpIds.skinSmooth: 0.5,
        MetaOpIds.skinToneLighting: 0.3,
        MetaOpIds.blemishReduction: 0.2,
      };
      if (!values.keys.every(admitted.containsKey)) return const AiNoAction();
      final pending = [
        for (final entry in values.entries)
          MetaOpChange(
            address: OpAddress(
              metaOpId: entry.key,
              metaOpVersion: admitted[entry.key]!.version,
              parameterId: 'value',
              scope: EditScope.currentPhoto,
              photoId: request.photoId,
            ),
            value: entry.value,
          ),
      ];
      if (request.photoAnalysis.targetIds.length != 1) {
        return AiTargetClarification(
          targetType: MetaOpTargetType.face,
          baseStateVersion: request.baseStateVersion,
          pendingChanges: pending,
          summary: values.keys,
        );
      }
      return AiTargetClarification(
        targetType: MetaOpTargetType.face,
        baseStateVersion: request.baseStateVersion,
        pendingChanges: pending,
        summary: values.keys,
      ).resolve(request.photoAnalysis.targetIds.single);
    }

    final portrait = portraitProposal();
    if (portrait != null) return portrait;

    void setParameter(String id, String parameterId, Object value) {
      final definition = admitted[id];
      final parameter = definition?.parameter(parameterId);
      if (definition == null ||
          parameter == null ||
          !parameter.accepts(value)) {
        return;
      }
      changes.add(
        MetaOpChange(
          address: OpAddress(
            metaOpId: id,
            metaOpVersion: definition.version,
            parameterId: parameterId,
            scope: definition.sharing == MetaOpSharing.group
                ? EditScope.group
                : EditScope.currentPhoto,
            photoId: definition.sharing == MetaOpSharing.currentPhoto
                ? request.photoId
                : null,
          ),
          value: value,
        ),
      );
    }

    final portraitBrightness = _containsAny(intent, const [
      '脸上亮',
      '脸更亮',
      '人物更亮',
      '人像提亮',
      '只调整人物',
      'brighten face',
      'brighter person',
      'person only',
    ]);
    if (portraitBrightness) {
      final definition = admitted[MetaOpIds.skinToneLighting];
      final parameter = definition?.parameter('value');
      if (definition != null && parameter != null) {
        final pending = MetaOpChange(
          address: OpAddress(
            metaOpId: definition.id,
            metaOpVersion: definition.version,
            parameterId: parameter.id,
            scope: EditScope.currentPhoto,
            photoId: request.photoId,
          ),
          value: 0.12,
        );
        if (request.photoAnalysis.targetIds.length != 1) {
          return AiTargetClarification(
            targetType: MetaOpTargetType.face,
            baseStateVersion: request.baseStateVersion,
            pendingChanges: [pending],
            summary: const [MetaOpIds.skinToneLighting],
          );
        }
        changes.add(
          MetaOpChange(
            address: OpAddress(
              metaOpId: pending.address.metaOpId,
              metaOpVersion: pending.address.metaOpVersion,
              parameterId: pending.address.parameterId,
              scope: pending.address.scope,
              photoId: pending.address.photoId,
              targetId: request.photoAnalysis.targetIds.single,
            ),
            value: pending.value,
          ),
        );
      }
    }

    if (_containsAny(intent, const [
      '背景柔和',
      '虚化背景',
      '背景虚化',
      'soft background',
      'blur background',
    ])) {
      setParameter(MetaOpIds.semanticAdjustments, 'background', 'blur');
      setParameter(MetaOpIds.semanticAdjustments, 'backgroundBlur', 35);
    }
    if (_containsAny(intent, const [
      '背景不要太艳',
      '背景不太艳',
      '背景饱和低一点',
      'less saturated background',
    ])) {
      setParameter(MetaOpIds.semanticAdjustments, 'backgroundSaturation', -8);
    }
    if (_containsAny(intent, const ['电影感', 'cinematic'])) {
      setParameter(MetaOpIds.filter, 'filter', 'cinematic');
      setParameter(MetaOpIds.filter, 'strength', 45);
    }
    if (_containsAny(intent, const ['降噪', '减少噪点', 'denoise'])) {
      setParameter(MetaOpIds.noiseReduction, 'value', 35);
    }

    void changeBy(String id, double delta) {
      final definition = admitted[id];
      final parameter = definition?.parameter('value');
      if (definition == null || parameter == null) return;
      final address = OpAddress(
        metaOpId: id,
        metaOpVersion: definition.version,
        parameterId: parameter.id,
        scope: definition.sharing == MetaOpSharing.group
            ? EditScope.group
            : EditScope.currentPhoto,
        photoId: definition.sharing == MetaOpSharing.currentPhoto
            ? request.photoId
            : null,
      );
      final before =
          (request.currentState.valueAt(address) as num?)?.toDouble() ??
          (parameter.neutralValue as num).toDouble();
      final after = (before + delta)
          .clamp(parameter.minimum!.toDouble(), parameter.maximum!.toDouble())
          .toDouble();
      if (after != before) {
        changes.add(MetaOpChange(address: address, value: after));
      }
    }

    if (!portraitBrightness &&
        _containsAny(intent, const [
          '亮一点',
          '更亮',
          '提亮',
          '白一点',
          '更白',
          '变白',
          'brighter',
          'whiter',
        ])) {
      changeBy(MetaOpIds.exposure, 0.12);
    } else if (_containsAny(intent, const ['暗一点', '更暗', '压暗', 'darker'])) {
      changeBy(MetaOpIds.exposure, -0.12);
    }
    if (_containsAny(intent, const ['暖一点', '更暖', 'warmer'])) {
      changeBy(MetaOpIds.warmth, 0.12);
    } else if (_containsAny(intent, const ['冷一点', '更冷', 'cooler'])) {
      changeBy(MetaOpIds.warmth, -0.12);
    }
    if (_containsAny(intent, const [
      '鲜艳一点',
      '更鲜艳',
      '更有氛围',
      'more vivid',
      'more atmosphere',
    ])) {
      changeBy(MetaOpIds.saturation, 0.1);
    }
    if (changes.isEmpty) return const AiNoAction();
    return AiEditProposal(
      baseStateVersion: request.baseStateVersion,
      changes: changes,
      summary: changes.map((change) => change.address.metaOpId),
    );
  }

  static bool _containsAny(String input, List<String> phrases) =>
      phrases.any(input.contains);
}
