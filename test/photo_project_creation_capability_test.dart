import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/creation/domain/creation_capability.dart';
import 'package:yingjian/features/creation/domain/creation_task.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

void main() {
  test('photo project persists an explicitly selected creation capability', () {
    final project = _project(
      task: CreationTask.style,
      capability: CreationCapability.styleText,
    );

    final json = project.toJson();
    final restored = PhotoProject.fromJson(json);

    expect(json['schemaVersion'], 20);
    expect(json['creationCapability'], 'style.text');
    expect(restored.creationCapability, CreationCapability.styleText);
    expect(restored, project);
  });

  test('photo project rejects a capability owned by another task', () {
    expect(
      () => _project(
        task: CreationTask.optimize,
        capability: CreationCapability.styleText,
      ),
      throwsArgumentError,
    );
  });

  test('copyWith preserves or explicitly clears the selected capability', () {
    final project = _project(
      task: CreationTask.cleanup,
      capability: CreationCapability.cleanupWhite,
    );

    expect(
      project.copyWith(updatedAt: DateTime.utc(2026, 9, 2)).creationCapability,
      CreationCapability.cleanupWhite,
    );
    expect(
      project.copyWith(creationCapability: null).creationCapability,
      isNull,
    );
    expect(project.creationCapability, CreationCapability.cleanupWhite);
  });

  test(
    'legacy or missing capability data stays unselected without inference',
    () {
      final selected = _project(
        task: CreationTask.cleanup,
        capability: CreationCapability.cleanupWhite,
      ).toJson();
      final legacy = Map<String, Object?>.from(selected)
        ..['schemaVersion'] = 19
        ..['creationCapability'] = 'style.text';
      final currentWithoutCapability = Map<String, Object?>.from(selected)
        ..remove('creationCapability')
        ..['creationStyleId'] = 'local-cleanup-white-background-v1';
      final unselected = _project(task: CreationTask.cleanup).toJson();

      expect(PhotoProject.fromJson(legacy).creationCapability, isNull);
      expect(
        PhotoProject.fromJson(currentWithoutCapability).creationCapability,
        isNull,
      );
      expect(unselected.containsKey('creationCapability'), isFalse);
      expect(PhotoProject.fromJson(unselected).creationCapability, isNull);
    },
  );

  test('a source photo change requires a fresh explicit capability choice', () {
    final project =
        _project(
          task: CreationTask.style,
          capability: CreationCapability.styleOfficial,
        ).copyWith(
          creationStyleId: 'natural',
          creationStyleRecipe: EditRecipe.neutral,
        );

    final replaced = project.replacePhotosAndInvalidateDerivedState(
      photos: const [
        ProjectPhoto(
          id: 'replacement-photo',
          localPath: '/app/media/replacement-photo.jpg',
          originalName: 'replacement-photo.jpg',
        ),
      ],
      updatedAt: DateTime.utc(2026, 9, 2),
      focusPhotoId: 'replacement-photo',
    );

    expect(replaced.creationCapability, isNull);
    expect(replaced.creationStyleId, isNull);
    expect(replaced.creationStyleRecipe, isNull);
  });

  test('a static result is recoverable only for its selected capability', () {
    final project =
        _project(
          task: CreationTask.style,
          capability: CreationCapability.styleOfficial,
        ).copyWith(
          creationStyleId: 'natural',
          creationStyleRecipe: EditRecipe.neutral,
          creationResult: StaticStyleResultIdentity(
            sourcePhotoId: 'source-photo',
            editStateVersion: 0,
            styleId: 'natural',
            capability: CreationCapability.styleOfficial,
            recipe: EditRecipe.neutral,
          ),
          creationResultActive: true,
        );

    expect(
      project.recoverableStaticStyleResult?.capability,
      CreationCapability.styleOfficial,
    );
    expect(
      project
          .copyWith(creationCapability: CreationCapability.styleText)
          .recoverableStaticStyleResult,
      isNull,
    );
    expect(
      PhotoProject.fromJson(project.toJson()).creationResult?.capability,
      CreationCapability.styleOfficial,
    );
  });
}

PhotoProject _project({
  required CreationTask task,
  CreationCapability? capability,
}) => PhotoProject(
  id: 'capability-project',
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
  photos: const [
    ProjectPhoto(
      id: 'source-photo',
      localPath: '/app/media/source-photo.jpg',
      originalName: 'source-photo.jpg',
    ),
  ],
  creationIntent: task.creationIntent,
  creationTask: task,
  creationCapability: capability,
);
