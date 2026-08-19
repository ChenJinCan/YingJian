import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/editing_resource.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

void main() {
  const sha =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const id = 'resource-v1-$sha';
  const resource = EditingResourceDescriptor(
    id: id,
    kind: EditingResourceKind.backgroundImage,
    relativePath: 'resources/aa/$sha.jpg',
    contentSha256: sha,
    byteLength: 2048,
  );

  test(
    'resource survives until current history and draft owners all release it',
    () {
      var registry = EditingResourceRegistry.empty.register(resource);
      registry = registry
          .retain(id, EditingResourceOwner.currentState)
          .retain(id, EditingResourceOwner.undoHistory)
          .retain(id, EditingResourceOwner.activeDraft);

      expect(registry.reclaimableIds, isEmpty);
      registry = registry.release(id, EditingResourceOwner.currentState);
      expect(registry.reclaimableIds, isEmpty);
      registry = registry.release(id, EditingResourceOwner.undoHistory);
      expect(registry.reclaimableIds, isEmpty);
      registry = registry.release(id, EditingResourceOwner.activeDraft);

      expect(registry.reclaimableIds, {id});
      expect(registry.removeReclaimable().resources, isEmpty);
    },
  );

  test(
    'persisted registry restores durable owners but never an active draft',
    () {
      final registry = EditingResourceRegistry.empty
          .register(resource)
          .retain(id, EditingResourceOwner.currentState)
          .retain(id, EditingResourceOwner.redoHistory)
          .retain(id, EditingResourceOwner.activeDraft);

      final restored = EditingResourceRegistry.fromJson(registry.toJson());

      expect(restored.references(EditingResourceOwner.currentState), {id});
      expect(restored.references(EditingResourceOwner.redoHistory), {id});
      expect(restored.references(EditingResourceOwner.activeDraft), isEmpty);
      expect(restored.resources[id], resource);
    },
  );

  test('resource identity and app-owned relative path are validated', () {
    expect(
      () => const EditingResourceDescriptor(
        id: id,
        kind: EditingResourceKind.backgroundImage,
        relativePath: '../outside.jpg',
        contentSha256: sha,
        byteLength: 1,
      ).validate(),
      throwsArgumentError,
    );
    expect(
      () => const EditingResourceDescriptor(
        id: 'resource-v1-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        kind: EditingResourceKind.backgroundImage,
        relativePath: 'resources/aa/image.jpg',
        contentSha256: sha,
        byteLength: 1,
      ).validate(),
      throwsArgumentError,
    );
  });

  test('project snapshot persists the durable resource ledger', () {
    final registry = EditingResourceRegistry.empty
        .register(resource)
        .retain(id, EditingResourceOwner.currentState)
        .retain(id, EditingResourceOwner.undoHistory);
    final project = PhotoProject(
      id: 'project-1',
      createdAt: DateTime.utc(2026, 8, 20),
      updatedAt: DateTime.utc(2026, 8, 20),
      photos: const [
        ProjectPhoto(
          id: 'photo-1',
          localPath: '/app/media/photo.jpg',
          originalName: 'photo.jpg',
        ),
      ],
      editingResources: registry,
    );

    final restored = PhotoProject.fromJson(project.toJson());

    expect(restored.editingResources.resources[id], resource);
    expect(
      restored.editingResources.referenceCount(
        id,
        EditingResourceOwner.undoHistory,
      ),
      1,
    );
  });
}
