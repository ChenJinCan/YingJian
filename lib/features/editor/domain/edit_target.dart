import 'package:flutter/foundation.dart';

enum EditTargetKind { face, body, background, region }

enum EditTargetStatus { active, suspended }

@immutable
final class NormalizedEditRegion {
  const NormalizedEditRegion({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  }) : assert(left >= 0 && left <= 1),
       assert(top >= 0 && top <= 1),
       assert(right >= 0 && right <= 1),
       assert(bottom >= 0 && bottom <= 1),
       assert(right > left),
       assert(bottom > top);

  final double left;
  final double top;
  final double right;
  final double bottom;

  Map<String, Object> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };

  factory NormalizedEditRegion.fromJson(Map<String, Object?> json) {
    double coordinate(String key) {
      final value = json[key];
      if (value is! num || !value.isFinite || value < 0 || value > 1) {
        throw FormatException('Invalid target coordinate $key');
      }
      return value.toDouble();
    }

    final region = NormalizedEditRegion(
      left: coordinate('left'),
      top: coordinate('top'),
      right: coordinate('right'),
      bottom: coordinate('bottom'),
    );
    if (region.left >= region.right || region.top >= region.bottom) {
      throw const FormatException('Invalid target region');
    }
    return region;
  }

  String get fingerprintComponent => [
    left,
    top,
    right,
    bottom,
  ].map((value) => (value * 1000000).round()).join(':');

  @override
  bool operator ==(Object other) =>
      other is NormalizedEditRegion &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

@immutable
final class DetectedEditTarget {
  const DetectedEditTarget({
    required this.photoId,
    required this.kind,
    required this.analysisVersion,
    required this.region,
  });

  final String photoId;
  final EditTargetKind kind;
  final String analysisVersion;
  final NormalizedEditRegion region;

  String get bindingFingerprint => [
    'binding-v1',
    photoId,
    kind.name,
    analysisVersion,
    region.fingerprintComponent,
  ].join('|');

  String get initialStableId => 'target-v1-${_fnv1a32(bindingFingerprint)}';
}

@immutable
final class StableEditTarget {
  const StableEditTarget({
    required this.id,
    required this.photoId,
    required this.kind,
    required this.analysisVersion,
    required this.bindingFingerprint,
    required this.region,
    required this.status,
  });

  factory StableEditTarget.fromDetection(DetectedEditTarget detection) =>
      StableEditTarget(
        id: detection.initialStableId,
        photoId: detection.photoId,
        kind: detection.kind,
        analysisVersion: detection.analysisVersion,
        bindingFingerprint: detection.bindingFingerprint,
        region: detection.region,
        status: EditTargetStatus.active,
      );

  final String id;
  final String photoId;
  final EditTargetKind kind;
  final String analysisVersion;
  final String bindingFingerprint;
  final NormalizedEditRegion region;
  final EditTargetStatus status;

  StableEditTarget copyWith({
    String? analysisVersion,
    String? bindingFingerprint,
    NormalizedEditRegion? region,
    EditTargetStatus? status,
  }) => StableEditTarget(
    id: id,
    photoId: photoId,
    kind: kind,
    analysisVersion: analysisVersion ?? this.analysisVersion,
    bindingFingerprint: bindingFingerprint ?? this.bindingFingerprint,
    region: region ?? this.region,
    status: status ?? this.status,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'photoId': photoId,
    'kind': kind.name,
    'analysisVersion': analysisVersion,
    'bindingFingerprint': bindingFingerprint,
    'region': region.toJson(),
    'status': status.name,
  };

  factory StableEditTarget.fromJson(Map<String, Object?> json) {
    String string(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Invalid target field $key');
      }
      return value;
    }

    T enumValue<T extends Enum>(String key, List<T> values) {
      final raw = string(key);
      return values.firstWhere(
        (value) => value.name == raw,
        orElse: () => throw FormatException('Unknown target $key $raw'),
      );
    }

    final region = json['region'];
    if (region is! Map) throw const FormatException('Invalid target region');
    return StableEditTarget(
      id: string('id'),
      photoId: string('photoId'),
      kind: enumValue('kind', EditTargetKind.values),
      analysisVersion: string('analysisVersion'),
      bindingFingerprint: string('bindingFingerprint'),
      region: NormalizedEditRegion.fromJson(Map<String, Object?>.from(region)),
      status: enumValue('status', EditTargetStatus.values),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StableEditTarget &&
      other.id == id &&
      other.photoId == photoId &&
      other.kind == kind &&
      other.analysisVersion == analysisVersion &&
      other.bindingFingerprint == bindingFingerprint &&
      other.region == region &&
      other.status == status;

  @override
  int get hashCode => Object.hash(
    id,
    photoId,
    kind,
    analysisVersion,
    bindingFingerprint,
    region,
    status,
  );
}

@immutable
final class TargetRebindRecord {
  const TargetRebindRecord({required this.before, required this.after});

  final StableEditTarget before;
  final StableEditTarget after;

  String get targetId => before.id;
  String get beforeFingerprint => before.bindingFingerprint;
  String get afterFingerprint => after.bindingFingerprint;

  Map<String, Object> toJson() => {
    'before': before.toJson(),
    'after': after.toJson(),
  };

  factory TargetRebindRecord.fromJson(Map<String, Object?> json) {
    Map<String, Object?> target(String key) {
      final value = json[key];
      if (value is! Map) throw FormatException('Invalid rebind $key');
      return Map<String, Object?>.from(value);
    }

    return TargetRebindRecord(
      before: StableEditTarget.fromJson(target('before')),
      after: StableEditTarget.fromJson(target('after')),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TargetRebindRecord &&
      other.before == before &&
      other.after == after;

  @override
  int get hashCode => Object.hash(before, after);
}

@immutable
final class EditTargetRegistry {
  EditTargetRegistry({
    required Map<String, StableEditTarget> targets,
    this.rebindRecord,
  }) : targets = Map.unmodifiable(targets) {
    for (final entry in targets.entries) {
      if (entry.key != entry.value.id ||
          !RegExp(r'^target-v1-[0-9a-f]{8}$').hasMatch(entry.key)) {
        throw ArgumentError.value(entry, 'targets', 'Invalid stable target');
      }
    }
    if (rebindRecord != null &&
        (rebindRecord!.before.id != rebindRecord!.after.id ||
            targets[rebindRecord!.targetId] != rebindRecord!.after)) {
      throw ArgumentError.value(
        rebindRecord,
        'rebindRecord',
        'Rebind record must describe the current target',
      );
    }
  }

  factory EditTargetRegistry.seed(Iterable<DetectedEditTarget> detections) {
    final targets = <String, StableEditTarget>{};
    for (final detection in detections) {
      final target = StableEditTarget.fromDetection(detection);
      final existing = targets[target.id];
      if (existing != null &&
          existing.bindingFingerprint != target.bindingFingerprint) {
        throw StateError('Stable target hash collision: ${target.id}');
      }
      targets[target.id] = target;
    }
    return EditTargetRegistry(targets: targets);
  }

  final Map<String, StableEditTarget> targets;
  final TargetRebindRecord? rebindRecord;

  StableEditTarget target(String id) {
    final result = targets[id];
    if (result == null) throw ArgumentError.value(id, 'id', 'Unknown target');
    return result;
  }

  EditTargetRegistry reconcile(Iterable<DetectedEditTarget> detections) {
    final byFingerprint = {
      for (final detection in detections)
        detection.bindingFingerprint: detection,
    };
    final next = <String, StableEditTarget>{};
    for (final entry in targets.entries) {
      final detection = byFingerprint.remove(entry.value.bindingFingerprint);
      next[entry.key] = detection == null
          ? entry.value.copyWith(status: EditTargetStatus.suspended)
          : entry.value.copyWith(
              analysisVersion: detection.analysisVersion,
              region: detection.region,
              status: EditTargetStatus.active,
            );
    }
    for (final detection in byFingerprint.values) {
      final target = StableEditTarget.fromDetection(detection);
      if (next[target.id] case final existing?
          when existing.bindingFingerprint != target.bindingFingerprint) {
        throw StateError('Stable target hash collision: ${target.id}');
      }
      next[target.id] = target;
    }
    return EditTargetRegistry(targets: next);
  }

  EditTargetRegistry rebind(String targetId, DetectedEditTarget detection) {
    final before = target(targetId);
    if (before.photoId != detection.photoId || before.kind != detection.kind) {
      throw ArgumentError.value(
        detection,
        'detection',
        'Rebind must keep the original photo and target kind',
      );
    }
    if (targets.values.any(
      (target) =>
          target.id != targetId &&
          target.bindingFingerprint == detection.bindingFingerprint,
    )) {
      throw StateError('Detection is already bound to another stable target');
    }
    final after = before.copyWith(
      analysisVersion: detection.analysisVersion,
      bindingFingerprint: detection.bindingFingerprint,
      region: detection.region,
      status: EditTargetStatus.active,
    );
    return EditTargetRegistry(
      targets: {...targets, targetId: after},
      rebindRecord: TargetRebindRecord(before: before, after: after),
    );
  }

  EditTargetRegistry undoLastRebind() {
    final record = rebindRecord;
    if (record == null) return this;
    return EditTargetRegistry(
      targets: {...targets, record.targetId: record.before},
    );
  }

  EditTargetRegistry withoutRebindRecord() =>
      rebindRecord == null ? this : EditTargetRegistry(targets: targets);

  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'targets': targets.values.map((target) => target.toJson()).toList(),
    if (rebindRecord != null) 'rebindRecord': rebindRecord!.toJson(),
  };

  factory EditTargetRegistry.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 1 || json['targets'] is! List) {
      throw const FormatException('Invalid target registry');
    }
    final targets = <String, StableEditTarget>{};
    for (final value in json['targets']! as List) {
      if (value is! Map) throw const FormatException('Invalid target entry');
      final target = StableEditTarget.fromJson(
        Map<String, Object?>.from(value),
      );
      if (targets.containsKey(target.id)) {
        throw const FormatException('Duplicate stable target');
      }
      targets[target.id] = target;
    }
    final rawRecord = json['rebindRecord'];
    return EditTargetRegistry(
      targets: targets,
      rebindRecord: rawRecord == null
          ? null
          : TargetRebindRecord.fromJson(
              Map<String, Object?>.from(rawRecord as Map),
            ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EditTargetRegistry &&
      mapEquals(other.targets, targets) &&
      other.rebindRecord == rebindRecord;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(
      targets.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    rebindRecord,
  );
}

String _fnv1a32(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
