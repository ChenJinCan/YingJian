import 'package:flutter/foundation.dart';

enum EditingResourceKind { backgroundImage, subjectMask, localMask, eraseMask }

enum EditingResourceOwner {
  currentState,
  undoHistory,
  redoHistory,
  checkpoint,
  activeDraft,
}

@immutable
final class EditingResourceDescriptor {
  const EditingResourceDescriptor({
    required this.id,
    required this.kind,
    required this.relativePath,
    required this.contentSha256,
    required this.byteLength,
  });

  final String id;
  final EditingResourceKind kind;
  final String relativePath;
  final String contentSha256;
  final int byteLength;

  void validate() {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(contentSha256) ||
        id != 'resource-v1-$contentSha256') {
      throw ArgumentError.value(
        id,
        'id',
        'Resource identity must match SHA-256',
      );
    }
    final segments = relativePath.split('/');
    if (relativePath.startsWith('/') ||
        !relativePath.startsWith('resources/') ||
        segments.any((segment) => segment.isEmpty || segment == '..')) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'Resource must use an app-owned relative path',
      );
    }
    if (byteLength <= 0) {
      throw RangeError.range(byteLength, 1, null, 'byteLength');
    }
  }

  Map<String, Object> toJson() => {
    'id': id,
    'kind': kind.name,
    'relativePath': relativePath,
    'contentSha256': contentSha256,
    'byteLength': byteLength,
  };

  factory EditingResourceDescriptor.fromJson(Map<String, Object?> json) {
    final kindName = json['kind'] as String?;
    final kind = EditingResourceKind.values
        .where((value) => value.name == kindName)
        .firstOrNull;
    if (kind == null) {
      throw FormatException('Unknown editing resource kind $kindName');
    }
    final value = EditingResourceDescriptor(
      id: json['id']! as String,
      kind: kind,
      relativePath: json['relativePath']! as String,
      contentSha256: json['contentSha256']! as String,
      byteLength: (json['byteLength']! as num).toInt(),
    );
    value.validate();
    return value;
  }

  @override
  bool operator ==(Object other) =>
      other is EditingResourceDescriptor &&
      other.id == id &&
      other.kind == kind &&
      other.relativePath == relativePath &&
      other.contentSha256 == contentSha256 &&
      other.byteLength == byteLength;

  @override
  int get hashCode =>
      Object.hash(id, kind, relativePath, contentSha256, byteLength);
}

@immutable
final class EditingResourceRegistry {
  EditingResourceRegistry._({
    required Map<String, EditingResourceDescriptor> resources,
    required Map<EditingResourceOwner, Map<String, int>> referenceCounts,
  }) : resources = Map<String, EditingResourceDescriptor>.unmodifiable(
         resources,
       ),
       _referenceCounts =
           Map<EditingResourceOwner, Map<String, int>>.unmodifiable({
             for (final entry in referenceCounts.entries)
               entry.key: Map<String, int>.unmodifiable(entry.value),
           }) {
    for (final entry in _referenceCounts.entries) {
      for (final count in entry.value.entries) {
        if (!this.resources.containsKey(count.key) || count.value <= 0) {
          throw ArgumentError.value(
            count,
            'referenceCounts',
            'Every positive reference must name a registered resource',
          );
        }
      }
    }
  }

  static final empty = EditingResourceRegistry._(
    resources: const {},
    referenceCounts: const {},
  );

  final Map<String, EditingResourceDescriptor> resources;
  final Map<EditingResourceOwner, Map<String, int>> _referenceCounts;

  Set<String> references(EditingResourceOwner owner) =>
      Set.unmodifiable(_referenceCounts[owner]?.keys ?? const <String>[]);

  int referenceCount(String id, EditingResourceOwner owner) =>
      _referenceCounts[owner]?[id] ?? 0;

  Set<String> get reclaimableIds => Set.unmodifiable(
    resources.keys.where(
      (id) => EditingResourceOwner.values.every(
        (owner) => referenceCount(id, owner) == 0,
      ),
    ),
  );

  EditingResourceRegistry register(EditingResourceDescriptor resource) {
    resource.validate();
    final existing = resources[resource.id];
    if (existing != null && existing != resource) {
      throw ArgumentError.value(
        resource.id,
        'resource',
        'A resource identity cannot describe different content',
      );
    }
    return EditingResourceRegistry._(
      resources: {...resources, resource.id: resource},
      referenceCounts: _referenceCounts,
    );
  }

  EditingResourceRegistry retain(String id, EditingResourceOwner owner) {
    if (!resources.containsKey(id)) {
      throw ArgumentError.value(id, 'id', 'Resource is not registered');
    }
    final counts = _mutableCounts();
    final ownerCounts = counts.putIfAbsent(owner, () => <String, int>{});
    ownerCounts[id] = (ownerCounts[id] ?? 0) + 1;
    return EditingResourceRegistry._(
      resources: resources,
      referenceCounts: counts,
    );
  }

  EditingResourceRegistry release(String id, EditingResourceOwner owner) {
    final current = referenceCount(id, owner);
    if (current == 0) {
      throw StateError('Resource $id has no ${owner.name} reference');
    }
    final counts = _mutableCounts();
    final ownerCounts = counts[owner]!;
    if (current == 1) {
      ownerCounts.remove(id);
      if (ownerCounts.isEmpty) counts.remove(owner);
    } else {
      ownerCounts[id] = current - 1;
    }
    return EditingResourceRegistry._(
      resources: resources,
      referenceCounts: counts,
    );
  }

  EditingResourceRegistry replaceReferences(
    EditingResourceOwner owner,
    Iterable<String> ids,
  ) {
    final counts = <String, int>{};
    for (final id in ids) {
      if (!resources.containsKey(id)) {
        throw ArgumentError.value(id, 'ids', 'Resource is not registered');
      }
      counts[id] = (counts[id] ?? 0) + 1;
    }
    final next = _mutableCounts();
    if (counts.isEmpty) {
      next.remove(owner);
    } else {
      next[owner] = counts;
    }
    return EditingResourceRegistry._(
      resources: resources,
      referenceCounts: next,
    );
  }

  EditingResourceRegistry removeReclaimable() {
    final reclaimable = reclaimableIds;
    if (reclaimable.isEmpty) return this;
    return EditingResourceRegistry._(
      resources: {
        for (final entry in resources.entries)
          if (!reclaimable.contains(entry.key)) entry.key: entry.value,
      },
      referenceCounts: _referenceCounts,
    );
  }

  Map<String, Object> toJson() {
    const durableOwners = [
      EditingResourceOwner.currentState,
      EditingResourceOwner.undoHistory,
      EditingResourceOwner.redoHistory,
      EditingResourceOwner.checkpoint,
    ];
    return {
      'resources': resources.map(
        (id, resource) => MapEntry(id, resource.toJson()),
      ),
      'referenceCounts': {
        for (final owner in durableOwners)
          if ((_referenceCounts[owner] ?? const {}).isNotEmpty)
            owner.name: _referenceCounts[owner]!,
      },
    };
  }

  factory EditingResourceRegistry.fromJson(Map<String, Object?> json) {
    final rawResources = Map<String, Object?>.from(json['resources']! as Map);
    final resources = rawResources.map(
      (id, value) => MapEntry(
        id,
        EditingResourceDescriptor.fromJson(
          Map<String, Object?>.from(value! as Map),
        ),
      ),
    );
    final rawCounts = Map<String, Object?>.from(
      json['referenceCounts']! as Map,
    );
    final counts = <EditingResourceOwner, Map<String, int>>{};
    for (final entry in rawCounts.entries) {
      final owner = EditingResourceOwner.values
          .where(
            (value) =>
                value != EditingResourceOwner.activeDraft &&
                value.name == entry.key,
          )
          .firstOrNull;
      if (owner == null) {
        throw FormatException('Unknown durable resource owner ${entry.key}');
      }
      counts[owner] = Map<String, Object?>.from(
        entry.value! as Map,
      ).map((id, count) => MapEntry(id, (count! as num).toInt()));
    }
    return EditingResourceRegistry._(
      resources: resources,
      referenceCounts: counts,
    );
  }

  Map<EditingResourceOwner, Map<String, int>> _mutableCounts() => {
    for (final entry in _referenceCounts.entries)
      entry.key: Map<String, int>.of(entry.value),
  };

  @override
  bool operator ==(Object other) {
    if (other is! EditingResourceRegistry ||
        !mapEquals(other.resources, resources) ||
        other._referenceCounts.length != _referenceCounts.length) {
      return false;
    }
    return _referenceCounts.entries.every(
      (entry) => mapEquals(other._referenceCounts[entry.key], entry.value),
    );
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(resources.entries),
    Object.hashAllUnordered(
      _referenceCounts.entries.map(
        (entry) => Object.hash(
          entry.key,
          Object.hashAllUnordered(entry.value.entries),
        ),
      ),
    ),
  );
}
