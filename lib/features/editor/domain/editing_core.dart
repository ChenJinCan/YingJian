import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/meta_op_availability.dart';

enum EditScope { group, currentPhoto }

enum EditSource { manual, ai, migration, targetRebind }

@immutable
final class OpAddress {
  const OpAddress({
    required this.metaOpId,
    required this.metaOpVersion,
    required this.parameterId,
    required this.scope,
    this.photoId,
    this.targetId,
  });

  final String metaOpId;
  final int metaOpVersion;
  final String parameterId;
  final EditScope scope;
  final String? photoId;
  final String? targetId;

  Map<String, Object> toJson() => {
    'metaOpId': metaOpId,
    'metaOpVersion': metaOpVersion,
    'parameterId': parameterId,
    'scope': scope.name,
    'photoId': ?photoId,
    'targetId': ?targetId,
  };

  factory OpAddress.fromJson(Map<String, Object?> json) {
    final scopeName = json['scope'] as String?;
    final scope = EditScope.values
        .where((value) => value.name == scopeName)
        .firstOrNull;
    if (scope == null) {
      throw FormatException('Unknown edit scope $scopeName');
    }
    return OpAddress(
      metaOpId: json['metaOpId']! as String,
      metaOpVersion: (json['metaOpVersion']! as num).toInt(),
      parameterId: json['parameterId']! as String,
      scope: scope,
      photoId: json['photoId'] as String?,
      targetId: json['targetId'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OpAddress &&
      other.metaOpId == metaOpId &&
      other.metaOpVersion == metaOpVersion &&
      other.parameterId == parameterId &&
      other.scope == scope &&
      other.photoId == photoId &&
      other.targetId == targetId;

  @override
  int get hashCode => Object.hash(
    metaOpId,
    metaOpVersion,
    parameterId,
    scope,
    photoId,
    targetId,
  );
}

@immutable
final class MetaOpChange {
  const MetaOpChange({required this.address, required this.value});

  final OpAddress address;
  final Object value;
}

@immutable
final class EditTransaction {
  EditTransaction({
    required this.id,
    required this.baseVersion,
    required this.source,
    required Iterable<MetaOpChange> changes,
  }) : changes = List.unmodifiable(changes);

  final String id;
  final int baseVersion;
  final EditSource source;
  final List<MetaOpChange> changes;
}

@immutable
final class EditState {
  const EditState({this.version = 0, this.values = const {}});

  static const empty = EditState();

  final int version;
  final Map<OpAddress, Object> values;

  Object? valueAt(OpAddress address) => values[address];

  Map<String, Object> toJson() => {
    'version': version,
    'values': values.entries
        .map(
          (entry) => <String, Object>{
            'address': entry.key.toJson(),
            'value': entry.value,
          },
        )
        .toList(growable: false),
  };

  factory EditState.fromJson(Map<String, Object?> json) {
    final version = (json['version'] as num?)?.toInt() ?? 0;
    final rawValues = json['values'];
    if (version < 0 || rawValues is! List) {
      throw const FormatException('Invalid edit state');
    }
    final values = <OpAddress, Object>{};
    for (final rawEntry in rawValues) {
      if (rawEntry is! Map) throw const FormatException('Invalid edit value');
      final entry = Map<String, Object?>.from(rawEntry);
      final rawAddress = entry['address'];
      final value = entry['value'];
      if (rawAddress is! Map || value == null) {
        throw const FormatException('Invalid edit value');
      }
      final address = OpAddress.fromJson(Map<String, Object?>.from(rawAddress));
      if (values.containsKey(address)) {
        throw const FormatException('Duplicate edit address');
      }
      values[address] = value;
    }
    return EditState(version: version, values: Map.unmodifiable(values));
  }

  @override
  bool operator ==(Object other) =>
      other is EditState &&
      other.version == version &&
      mapEquals(other.values, values);

  @override
  int get hashCode => Object.hash(
    version,
    Object.hashAllUnordered(
      values.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );
}

@immutable
final class EditContext {
  const EditContext({
    required this.platform,
    this.photoIds = const {},
    this.targetIds = const {},
    this.capabilities = const {},
    this.applicability = const {'photo'},
    this.resourceIds = const {},
    this.resourceByteLengths = const {},
    this.metaOpCapabilities,
  });

  static const ios = EditContext(platform: EditPlatform.ios);

  final EditPlatform platform;
  final Set<String> photoIds;
  final Set<String> targetIds;
  final Set<String> capabilities;
  final Set<String> applicability;
  final Set<String> resourceIds;
  final Map<String, int> resourceByteLengths;
  final PlatformMetaOpCapabilities? metaOpCapabilities;
}

enum EditRejection {
  emptyTransaction,
  duplicateTransaction,
  staleVersion,
  duplicateAddress,
  unknownMetaOp,
  unsupportedVersion,
  unknownParameter,
  outOfRange,
  invalidScope,
  invalidTarget,
  notApplicable,
  conflict,
  capabilityMissing,
  invalidResource,
  targetLimitExceeded,
  resourceLimitExceeded,
}

sealed class EditResult {
  const EditResult();
}

@immutable
final class EditSummary {
  const EditSummary({required this.changedAddresses});

  final List<OpAddress> changedAddresses;
}

final class AcceptedEdit extends EditResult {
  const AcceptedEdit({required this.state, required this.summary});

  final EditState state;
  final EditSummary summary;
}

final class RejectedEdit extends EditResult {
  const RejectedEdit({required this.reason, this.address});

  final EditRejection reason;
  final OpAddress? address;
}

final class EditingCore {
  const EditingCore();

  EditResult apply({
    required EditState state,
    required EditTransaction transaction,
    required EditContext context,
    MetaOpCatalog? catalog,
  }) {
    final source = catalog ?? MetaOpCatalog.standard;
    if (transaction.baseVersion != state.version) {
      return const RejectedEdit(reason: EditRejection.staleVersion);
    }
    if (transaction.changes.isEmpty) {
      return const RejectedEdit(reason: EditRejection.emptyTransaction);
    }

    final addresses = <OpAddress>{};
    final definitions = <MetaOpDefinition>[];
    for (final change in transaction.changes) {
      if (!addresses.add(change.address)) {
        return RejectedEdit(
          reason: EditRejection.duplicateAddress,
          address: change.address,
        );
      }
      final definition = source.find(change.address.metaOpId);
      if (definition == null) {
        return RejectedEdit(
          reason: EditRejection.unknownMetaOp,
          address: change.address,
        );
      }
      definitions.add(definition);
      if (definition.version != change.address.metaOpVersion) {
        return RejectedEdit(
          reason: EditRejection.unsupportedVersion,
          address: change.address,
        );
      }
      final parameter = definition.parameter(change.address.parameterId);
      if (parameter == null) {
        return RejectedEdit(
          reason: EditRejection.unknownParameter,
          address: change.address,
        );
      }
      if (!parameter.accepts(change.value)) {
        return RejectedEdit(
          reason: EditRejection.outOfRange,
          address: change.address,
        );
      }
      if (parameter.type == MetaOpValueType.resource &&
          change.value != parameter.neutralValue &&
          !context.resourceIds.contains(change.value)) {
        return RejectedEdit(
          reason: EditRejection.invalidResource,
          address: change.address,
        );
      }
      final expectedScope = definition.sharing == MetaOpSharing.group
          ? EditScope.group
          : EditScope.currentPhoto;
      if (change.address.scope != expectedScope) {
        return RejectedEdit(
          reason: EditRejection.invalidScope,
          address: change.address,
        );
      }
      if (!_hasValidTarget(change.address, definition, context)) {
        return RejectedEdit(
          reason: EditRejection.invalidTarget,
          address: change.address,
        );
      }
      if (!context.applicability.containsAll(definition.applicability)) {
        return RejectedEdit(
          reason: EditRejection.notApplicable,
          address: change.address,
        );
      }
      if (context.capabilities.isNotEmpty &&
          !context.capabilities.contains(definition.requiredCapability)) {
        return RejectedEdit(
          reason: EditRejection.capabilityMissing,
          address: change.address,
        );
      }
      if (context.metaOpCapabilities case final capabilities?
          when !capabilities.fullySupports(definition)) {
        return RejectedEdit(
          reason: EditRejection.capabilityMissing,
          address: change.address,
        );
      }
    }

    final ids = definitions.map((definition) => definition.id).toSet();
    for (final definition in definitions) {
      if (definition.exclusions.any(ids.contains)) {
        return const RejectedEdit(reason: EditRejection.conflict);
      }
    }

    final nextValues = Map<OpAddress, Object>.of(state.values);
    for (final change in transaction.changes) {
      final definition = source.definition(change.address.metaOpId);
      final parameter = definition.parameter(change.address.parameterId)!;
      if (change.value == parameter.neutralValue) {
        nextValues.remove(change.address);
      } else {
        nextValues[change.address] = change.value;
      }
    }

    for (final definition in definitions.toSet()) {
      final support = context.metaOpCapabilities?.supportFor(
        definition.id,
        definition.version,
      );
      if (support == null) continue;
      final operationValues = nextValues.entries.where(
        (entry) => entry.key.metaOpId == definition.id,
      );
      final targetCount = operationValues
          .map((entry) => entry.key.targetId)
          .whereType<String>()
          .toSet()
          .length;
      if (targetCount > support.maxTargets) {
        return RejectedEdit(
          reason: EditRejection.targetLimitExceeded,
          address: transaction.changes
              .firstWhere((change) => change.address.metaOpId == definition.id)
              .address,
        );
      }
      final resourceParameterIds = definition.parameters
          .where((parameter) => parameter.type == MetaOpValueType.resource)
          .map((parameter) => parameter.id)
          .toSet();
      final resourceIds = operationValues
          .where(
            (entry) => resourceParameterIds.contains(entry.key.parameterId),
          )
          .map((entry) => entry.value)
          .whereType<String>()
          .toSet();
      var resourceBytes = 0;
      for (final resourceId in resourceIds) {
        final byteLength = context.resourceByteLengths[resourceId];
        if (byteLength == null) {
          return RejectedEdit(
            reason: EditRejection.invalidResource,
            address: transaction.changes
                .firstWhere(
                  (change) => change.address.metaOpId == definition.id,
                )
                .address,
          );
        }
        resourceBytes += byteLength;
      }
      if (resourceBytes > support.maxResourceBytes) {
        return RejectedEdit(
          reason: EditRejection.resourceLimitExceeded,
          address: transaction.changes
              .firstWhere((change) => change.address.metaOpId == definition.id)
              .address,
        );
      }
    }
    final invalidComposition = _invalidCompositionAddress(
      nextValues,
      transaction.changes,
      source,
    );
    if (invalidComposition != null) {
      return RejectedEdit(
        reason: EditRejection.conflict,
        address: invalidComposition,
      );
    }
    final invalidFilter = _invalidFilterAddress(
      nextValues,
      transaction.changes,
      source,
    );
    if (invalidFilter != null) {
      return RejectedEdit(
        reason: EditRejection.conflict,
        address: invalidFilter,
      );
    }
    return AcceptedEdit(
      state: EditState(
        version: state.version + 1,
        values: Map.unmodifiable(nextValues),
      ),
      summary: EditSummary(
        changedAddresses: List.unmodifiable(
          transaction.changes.map((e) => e.address),
        ),
      ),
    );
  }

  OpAddress? _invalidCompositionAddress(
    Map<OpAddress, Object> values,
    List<MetaOpChange> changes,
    MetaOpCatalog catalog,
  ) {
    final compositionChanges = changes.where(
      (change) => change.address.metaOpId == MetaOpIds.compositionGeometry,
    );
    final photoIds = compositionChanges
        .map((change) => change.address.photoId)
        .whereType<String>()
        .toSet();
    final definition = catalog.find(MetaOpIds.compositionGeometry);
    if (definition == null) return null;
    for (final photoId in photoIds) {
      Object value(String parameterId) {
        final address = OpAddress(
          metaOpId: MetaOpIds.compositionGeometry,
          metaOpVersion: definition.version,
          parameterId: parameterId,
          scope: EditScope.currentPhoto,
          photoId: photoId,
        );
        return values[address] ??
            definition.parameter(parameterId)!.neutralValue;
      }

      final left = (value('left') as num).toDouble();
      final top = (value('top') as num).toDouble();
      final right = (value('right') as num).toDouble();
      final bottom = (value('bottom') as num).toDouble();
      if (left >= right || top >= bottom) {
        return OpAddress(
          metaOpId: MetaOpIds.compositionGeometry,
          metaOpVersion: definition.version,
          parameterId: left >= right ? 'left' : 'top',
          scope: EditScope.currentPhoto,
          photoId: photoId,
        );
      }
    }
    return null;
  }

  OpAddress? _invalidFilterAddress(
    Map<OpAddress, Object> values,
    List<MetaOpChange> changes,
    MetaOpCatalog catalog,
  ) {
    if (!changes.any((change) => change.address.metaOpId == MetaOpIds.filter)) {
      return null;
    }
    final definition = catalog.find(MetaOpIds.filter);
    if (definition == null) return null;
    OpAddress address(String parameterId) => OpAddress(
      metaOpId: MetaOpIds.filter,
      metaOpVersion: definition.version,
      parameterId: parameterId,
      scope: EditScope.group,
    );
    final filterAddress = address('filter');
    final strengthAddress = address('strength');
    final filter =
        values[filterAddress] ?? definition.parameter('filter')!.neutralValue;
    final strength =
        values[strengthAddress] ??
        definition.parameter('strength')!.neutralValue;
    if (filter == 'none' && (strength as num).toDouble() != 0) {
      return strengthAddress;
    }
    return null;
  }

  bool _hasValidTarget(
    OpAddress address,
    MetaOpDefinition definition,
    EditContext context,
  ) {
    if (address.scope == EditScope.group) {
      return address.photoId == null && address.targetId == null;
    }
    if (address.photoId == null ||
        !context.photoIds.contains(address.photoId)) {
      return false;
    }
    if (definition.targetType == MetaOpTargetType.none) {
      return address.targetId == null;
    }
    return address.targetId != null &&
        context.targetIds.contains(address.targetId);
  }
}
