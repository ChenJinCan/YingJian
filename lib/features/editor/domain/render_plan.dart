import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';

sealed class RenderPlanCompilation {
  const RenderPlanCompilation();
}

@immutable
final class AcceptedRenderPlan extends RenderPlanCompilation {
  const AcceptedRenderPlan({required this.plan});

  final RenderPlan plan;
}

@immutable
final class RejectedRenderPlan extends RenderPlanCompilation {
  const RejectedRenderPlan({required this.reason, this.address});

  final EditRejection reason;
  final OpAddress? address;
}

@immutable
final class RenderPlanOperation {
  const RenderPlanOperation({required this.address, required this.value});

  final OpAddress address;
  final Object value;

  Map<String, Object> toJson() => {'address': address.toJson(), 'value': value};
}

@immutable
final class RenderPlanStage {
  const RenderPlanStage({required this.stage, required this.operations});

  final RenderStage stage;
  final List<RenderPlanOperation> operations;

  Map<String, Object> toJson() => {
    'stage': stage.name,
    'operations': operations
        .map((operation) => operation.toJson())
        .toList(growable: false),
  };
}

enum RenderOutputPurpose { preview, export }

@immutable
final class RenderOutputRequirements {
  const RenderOutputRequirements({
    required this.purpose,
    this.colorSpace = 'srgb',
    this.format = 'display',
    this.quality = 'interactive',
    this.maxEdge,
  });

  const RenderOutputRequirements.preview({int? maxEdge})
    : this(purpose: RenderOutputPurpose.preview, maxEdge: maxEdge);

  const RenderOutputRequirements.export({
    String format = 'jpeg',
    String quality = 'high',
    int? maxEdge,
  }) : this(
         purpose: RenderOutputPurpose.export,
         format: format,
         quality: quality,
         maxEdge: maxEdge,
       );

  final RenderOutputPurpose purpose;
  final String colorSpace;
  final String format;
  final String quality;
  final int? maxEdge;

  Map<String, Object> toJson() => {
    'purpose': purpose.name,
    'colorSpace': colorSpace,
    'format': format,
    'quality': quality,
    'maxEdge': ?maxEdge,
  };
}

@immutable
final class RenderPlan {
  const RenderPlan({
    required this.protocolVersion,
    required this.planId,
    required this.sourceId,
    required this.stateRevision,
    required this.stages,
    required this.requiredCapabilities,
    required this.outputRequirements,
  });

  final int protocolVersion;
  final String planId;
  final String sourceId;
  final int stateRevision;
  final List<RenderPlanStage> stages;
  final List<String> requiredCapabilities;
  final RenderOutputRequirements outputRequirements;

  Map<String, Object> toJson() => {
    'protocolVersion': protocolVersion,
    'planId': planId,
    'sourceId': sourceId,
    'stateRevision': stateRevision,
    'stages': stages.map((stage) => stage.toJson()).toList(growable: false),
    'requiredCapabilities': requiredCapabilities,
    'outputRequirements': outputRequirements.toJson(),
  };
}

final class RenderPlanCompiler {
  const RenderPlanCompiler({
    this.catalog,
    this.editingCore = const EditingCore(),
  });

  final MetaOpCatalog? catalog;
  final EditingCore editingCore;

  RenderPlanCompilation compile({
    required String sourceId,
    required EditState state,
    required EditContext context,
    RenderOutputRequirements outputRequirements =
        const RenderOutputRequirements.preview(),
  }) {
    final activeCatalog = catalog ?? MetaOpCatalog.standard;
    if (sourceId.trim().isEmpty) {
      return const RejectedRenderPlan(reason: EditRejection.invalidTarget);
    }
    final entries = state.values.entries.toList(growable: false);
    if (entries.isNotEmpty) {
      final validation = editingCore.apply(
        state: EditState.empty,
        transaction: EditTransaction(
          id: 'render-plan-validation',
          baseVersion: 0,
          source: EditSource.migration,
          changes: entries
              .map(
                (entry) => MetaOpChange(address: entry.key, value: entry.value),
              )
              .toList(growable: false),
        ),
        context: context,
        catalog: activeCatalog,
      );
      if (validation case RejectedEdit(:final reason, :final address)) {
        return RejectedRenderPlan(reason: reason, address: address);
      }
    }

    final ordered = entries.toList()
      ..sort((left, right) {
        final leftDefinition = activeCatalog.definition(left.key.metaOpId);
        final rightDefinition = activeCatalog.definition(right.key.metaOpId);
        var order = leftDefinition.stage.index.compareTo(
          rightDefinition.stage.index,
        );
        if (order != 0) return order;
        order = leftDefinition.defaultOrder.compareTo(
          rightDefinition.defaultOrder,
        );
        if (order != 0) return order;
        order = left.key.metaOpId.compareTo(right.key.metaOpId);
        if (order != 0) return order;
        order = (left.key.photoId ?? '').compareTo(right.key.photoId ?? '');
        if (order != 0) return order;
        order = (left.key.targetId ?? '').compareTo(right.key.targetId ?? '');
        if (order != 0) return order;
        return left.key.parameterId.compareTo(right.key.parameterId);
      });
    final stages = <RenderPlanStage>[];
    for (final stage in RenderStage.values) {
      final operations = ordered
          .where(
            (entry) =>
                activeCatalog.definition(entry.key.metaOpId).stage == stage,
          )
          .map(
            (entry) =>
                RenderPlanOperation(address: entry.key, value: entry.value),
          )
          .toList(growable: false);
      if (operations.isNotEmpty) {
        stages.add(
          RenderPlanStage(
            stage: stage,
            operations: List.unmodifiable(operations),
          ),
        );
      }
    }
    final requiredCapabilities =
        ordered
            .map(
              (entry) => activeCatalog
                  .definition(entry.key.metaOpId)
                  .requiredCapability,
            )
            .toSet()
            .toList()
          ..sort();
    final unsignedPayload = <String, Object>{
      'protocolVersion': 1,
      'sourceId': sourceId,
      'stateRevision': state.version,
      'stages': stages.map((stage) => stage.toJson()).toList(growable: false),
      'requiredCapabilities': requiredCapabilities,
      'outputRequirements': outputRequirements.toJson(),
    };
    final planId = 'rp1-${_fnv1a32(jsonEncode(unsignedPayload))}';
    return AcceptedRenderPlan(
      plan: RenderPlan(
        protocolVersion: 1,
        planId: planId,
        sourceId: sourceId,
        stateRevision: state.version,
        stages: List.unmodifiable(stages),
        requiredCapabilities: List.unmodifiable(requiredCapabilities),
        outputRequirements: outputRequirements,
      ),
    );
  }

  static String _fnv1a32(String value) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
