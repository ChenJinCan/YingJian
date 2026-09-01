import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/creation/domain/creation_capability.dart';

void main() {
  test(
    'creation capabilities keep the agreed stable ids and task ownership',
    () {
      expect(
        CreationCapability.values
            .map(
              (capability) =>
                  '${capability.persistedId}:${capability.task.name}',
            )
            .toList(growable: false),
        const [
          'optimize.natural:optimize',
          'optimize.aiRepair:optimize',
          'optimize.upscale:optimize',
          'optimize.oldPhoto:optimize',
          'style.official:style',
          'style.text:style',
          'style.voice:style',
          'style.reference:style',
          'style.aiRedraw:style',
          'cleanup.white:cleanup',
          'cleanup.transparent:cleanup',
          'cleanup.replaceBackground:cleanup',
          'cleanup.removePasserby:cleanup',
          'cleanup.brushRemove:cleanup',
          'motion.subtle:motion',
          'motion.cameraPush:motion',
          'motion.lightFlow:motion',
          'motion.aiNatural:motion',
        ],
      );
    },
  );

  test('creation capability decoding accepts only an exact persisted id', () {
    expect(
      CreationCapability.fromPersistedId('cleanup.replaceBackground'),
      CreationCapability.cleanupReplaceBackground,
    );
    expect(
      () => CreationCapability.fromPersistedId('cleanup.replace-background'),
      throwsFormatException,
    );
    expect(
      () => CreationCapability.fromPersistedId('motion.generatePhoto'),
      throwsFormatException,
    );
  });
}
