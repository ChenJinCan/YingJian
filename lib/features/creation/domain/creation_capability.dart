import 'package:yingjian/features/creation/domain/creation_task.dart';

/// One named result capability explicitly selected within a creation task.
///
/// [persistedId] is a storage contract and must not be changed when a Dart enum
/// value or user-facing label is renamed.
enum CreationCapability {
  optimizeNatural('optimize.natural', CreationTask.optimize),
  optimizeAiRepair('optimize.aiRepair', CreationTask.optimize),
  optimizeUpscale('optimize.upscale', CreationTask.optimize),
  optimizeOldPhoto('optimize.oldPhoto', CreationTask.optimize),
  styleOfficial('style.official', CreationTask.style),
  styleText('style.text', CreationTask.style),
  styleVoice('style.voice', CreationTask.style),
  styleReference('style.reference', CreationTask.style),
  styleAiRedraw('style.aiRedraw', CreationTask.style),
  cleanupWhite('cleanup.white', CreationTask.cleanup),
  cleanupTransparent('cleanup.transparent', CreationTask.cleanup),
  cleanupReplaceBackground('cleanup.replaceBackground', CreationTask.cleanup),
  cleanupRemovePasserby('cleanup.removePasserby', CreationTask.cleanup),
  cleanupBrushRemove('cleanup.brushRemove', CreationTask.cleanup),
  motionSubtle('motion.subtle', CreationTask.motion),
  motionCameraPush('motion.cameraPush', CreationTask.motion),
  motionLightFlow('motion.lightFlow', CreationTask.motion),
  motionAiNatural('motion.aiNatural', CreationTask.motion);

  const CreationCapability(this.persistedId, this.task);

  final String persistedId;
  final CreationTask task;

  static CreationCapability fromPersistedId(Object? value) {
    for (final capability in values) {
      if (capability.persistedId == value) return capability;
    }
    throw FormatException('Unsupported creation capability $value');
  }
}
