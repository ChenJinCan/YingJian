import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/creation/domain/creation_capability.dart';
import 'package:yingjian/features/generation/application/generation_coordinator.dart';
import 'package:yingjian/features/generation/domain/generation_input.dart';

void main() {
  test('old photo restoration requires an explicit color decision', () {
    expect(
      () => GenerationSourceSnapshot(
        projectId: 'project-1',
        sourcePhotoId: 'photo-1',
        sourcePath: '/private/source.jpg',
        sourceSha256: 'a' * 64,
        capability: CreationCapability.optimizeOldPhoto,
        createdAt: DateTime.utc(2026, 9, 1),
      ),
      throwsArgumentError,
    );

    for (final mode in OldPhotoColorMode.values) {
      expect(
        () => GenerationSourceSnapshot(
          projectId: 'project-1',
          sourcePhotoId: 'photo-1',
          sourcePath: '/private/source.jpg',
          sourceSha256: 'a' * 64,
          capability: CreationCapability.optimizeOldPhoto,
          input: OldPhotoGenerationInput(colorMode: mode),
          createdAt: DateTime.utc(2026, 9, 1),
        ),
        returnsNormally,
      );
    }
    expect(OldPhotoColorMode.values, [
      OldPhotoColorMode.preserve,
      OldPhotoColorMode.colorize,
    ]);
  });
}
