import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';

enum MetaOpLifecycle {
  defined,
  platformDevelopment,
  manualExperiment,
  manualProduction,
  aiProposal,
  aiProduction;

  bool canAdvanceTo(MetaOpLifecycle next) => next.index == index + 1;

  bool isAtLeast(MetaOpLifecycle minimum) => index >= minimum.index;
}

@immutable
final class MetaOpExecutionSupport {
  const MetaOpExecutionSupport({
    required this.metaOpId,
    required this.metaOpVersion,
    required this.preview,
    required this.export,
    required this.maxTargets,
    required this.maxResourceBytes,
  });

  final String metaOpId;
  final int metaOpVersion;
  final bool preview;
  final bool export;
  final int maxTargets;
  final int maxResourceBytes;

  bool supports(MetaOpDefinition definition) =>
      metaOpId == definition.id &&
      metaOpVersion == definition.version &&
      preview &&
      export &&
      maxTargets >= 0 &&
      maxResourceBytes >= 0;
}

final class PlatformMetaOpCapabilities {
  PlatformMetaOpCapabilities({
    required this.platform,
    required Iterable<MetaOpExecutionSupport> entries,
  }) : _entries = Map.unmodifiable({
         for (final entry in entries)
           _key(entry.metaOpId, entry.metaOpVersion): entry,
       });

  final EditPlatform platform;
  final Map<String, MetaOpExecutionSupport> _entries;

  MetaOpExecutionSupport? supportFor(String id, int version) =>
      _entries[_key(id, version)];

  bool fullySupports(MetaOpDefinition definition) =>
      supportFor(definition.id, definition.version)?.supports(definition) ??
      false;

  static String _key(String id, int version) => '$id@$version';
}

@immutable
final class MetaOpProductPolicy {
  MetaOpProductPolicy({
    required Map<String, MetaOpLifecycle> lifecycleById,
    Set<String> remotelyEnabledIds = const {},
  }) : lifecycleById = Map.unmodifiable(lifecycleById),
       remotelyEnabledIds = Set.unmodifiable(remotelyEnabledIds);

  final Map<String, MetaOpLifecycle> lifecycleById;
  final Set<String> remotelyEnabledIds;

  MetaOpLifecycle lifecycleFor(String id) =>
      lifecycleById[id] ?? MetaOpLifecycle.defined;

  bool remoteAllows(String id) =>
      remotelyEnabledIds.isEmpty || remotelyEnabledIds.contains(id);
}

final standardMetaOpProductPolicy = MetaOpProductPolicy(
  lifecycleById: const {
    MetaOpIds.compositionGeometry: MetaOpLifecycle.manualProduction,
    MetaOpIds.exposure: MetaOpLifecycle.aiProduction,
    MetaOpIds.highlights: MetaOpLifecycle.aiProduction,
    MetaOpIds.shadows: MetaOpLifecycle.aiProduction,
    MetaOpIds.contrast: MetaOpLifecycle.aiProduction,
    MetaOpIds.warmth: MetaOpLifecycle.aiProduction,
    MetaOpIds.tint: MetaOpLifecycle.aiProduction,
    MetaOpIds.saturation: MetaOpLifecycle.aiProduction,
    MetaOpIds.clarity: MetaOpLifecycle.aiProduction,
    MetaOpIds.filter: MetaOpLifecycle.aiProduction,
    MetaOpIds.hslRed: MetaOpLifecycle.manualProduction,
    MetaOpIds.hslOrange: MetaOpLifecycle.manualProduction,
    MetaOpIds.hslYellow: MetaOpLifecycle.manualProduction,
    MetaOpIds.hslGreen: MetaOpLifecycle.manualProduction,
    MetaOpIds.hslCyan: MetaOpLifecycle.manualProduction,
    MetaOpIds.hslBlue: MetaOpLifecycle.manualProduction,
    MetaOpIds.hslPurple: MetaOpLifecycle.manualProduction,
    MetaOpIds.hslMagenta: MetaOpLifecycle.manualProduction,
    MetaOpIds.noiseReduction: MetaOpLifecycle.aiProduction,
    MetaOpIds.lowLightRecovery: MetaOpLifecycle.manualProduction,
    MetaOpIds.hazeRemoval: MetaOpLifecycle.manualProduction,
    MetaOpIds.detailSharpening: MetaOpLifecycle.manualProduction,
    MetaOpIds.skinSmooth: MetaOpLifecycle.aiProduction,
    MetaOpIds.skinToneLighting: MetaOpLifecycle.aiProduction,
    MetaOpIds.blemishReduction: MetaOpLifecycle.aiProduction,
    MetaOpIds.faceGeometry: MetaOpLifecycle.aiProposal,
    MetaOpIds.bodyGeometry: MetaOpLifecycle.aiProposal,
    MetaOpIds.directionalLighting: MetaOpLifecycle.manualProduction,
    MetaOpIds.semanticAdjustments: MetaOpLifecycle.aiProduction,
  },
);

@immutable
final class MetaOpAvailability {
  const MetaOpAvailability._({
    required this.manualIds,
    required this.searchIds,
    required this.aiProposalIds,
    required this.aiProductionIds,
    required this.ignoredRemoteIds,
  });

  factory MetaOpAvailability.resolve({
    required MetaOpCatalog catalog,
    required PlatformMetaOpCapabilities capabilities,
    required MetaOpProductPolicy policy,
    required Set<String> applicability,
  }) {
    final definitions = catalog.definitions.toList()
      ..sort((left, right) => left.defaultOrder.compareTo(right.defaultOrder));
    final shippedIds = definitions.map((definition) => definition.id).toSet();
    final eligible = definitions.where(
      (definition) =>
          policy.remoteAllows(definition.id) &&
          capabilities.fullySupports(definition) &&
          applicability.containsAll(definition.applicability),
    );
    final manual = eligible
        .where(
          (definition) => policy
              .lifecycleFor(definition.id)
              .isAtLeast(MetaOpLifecycle.manualProduction),
        )
        .map((definition) => definition.id)
        .toList(growable: false);
    final aiProposal = eligible
        .where(
          (definition) =>
              definition.aiAvailability != AiAvailability.disabled &&
              policy
                  .lifecycleFor(definition.id)
                  .isAtLeast(MetaOpLifecycle.aiProposal),
        )
        .map((definition) => definition.id)
        .toList(growable: false);
    final aiProduction = eligible
        .where(
          (definition) =>
              definition.aiAvailability == AiAvailability.enabled &&
              policy
                  .lifecycleFor(definition.id)
                  .isAtLeast(MetaOpLifecycle.aiProduction),
        )
        .map((definition) => definition.id)
        .toList(growable: false);
    return MetaOpAvailability._(
      manualIds: List.unmodifiable(manual),
      searchIds: List.unmodifiable(manual),
      aiProposalIds: List.unmodifiable(aiProposal),
      aiProductionIds: List.unmodifiable(aiProduction),
      ignoredRemoteIds: Set.unmodifiable(
        policy.remotelyEnabledIds.difference(shippedIds),
      ),
    );
  }

  final List<String> manualIds;
  final List<String> searchIds;
  final List<String> aiProposalIds;
  final List<String> aiProductionIds;
  final Set<String> ignoredRemoteIds;

  List<String> search(MetaOpCatalog catalog, String query) {
    final admitted = searchIds.toSet();
    return List.unmodifiable(catalog.search(query).where(admitted.contains));
  }

  List<AiMetaOpCapability> aiCapabilities(MetaOpCatalog catalog) =>
      List.unmodifiable(
        aiProposalIds.map(
          (id) => AiMetaOpCapability.fromDefinition(catalog.definition(id)),
        ),
      );
}

@immutable
final class AiMetaOpCapability {
  const AiMetaOpCapability._({required this.definition});

  factory AiMetaOpCapability.fromDefinition(MetaOpDefinition definition) =>
      AiMetaOpCapability._(definition: definition);

  final MetaOpDefinition definition;

  Map<String, Object?> toJson() => {
    'id': definition.id,
    'version': definition.version,
    'semantic': definition.semantic,
    'exclusions': definition.exclusions.toList()..sort(),
    'scope': definition.sharing.name,
    'target': definition.targetType.name,
    'parameters': definition.parameters
        .map((parameter) => parameter.toJson())
        .toList(growable: false),
  };
}
