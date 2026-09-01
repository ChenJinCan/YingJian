import 'package:yingjian/features/creation/domain/creation_capability.dart';
import 'package:yingjian/features/editor/application/edit_target_detection_adapter.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/meta_op_availability.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/photo_analysis/domain/photo_analysis.dart';

/// Prepares the local subject contract only after the user explicitly selects
/// one of the subject-segmentation cleanup capabilities.
final class CleanupCapabilityPreparer {
  const CleanupCapabilityPreparer({required this.analyzer});

  final PhotoAnalyzer analyzer;

  Future<bool> prepare({
    required PhotoProjectSession session,
    required PhotoProject project,
    required PlatformMetaOpCapabilities capabilities,
  }) async {
    final selectedCapability = project.creationCapability;
    if (!_requiresSubjectSegmentation(selectedCapability)) {
      throw StateError(
        'Cleanup preparation requires an explicit segmentation capability',
      );
    }
    if (capabilities.platform != EditPlatform.ios) return false;

    final photo = project.photos.single;
    try {
      final analysis = await analyzer.analyze(photo);
      final current = session.project;
      if (current?.id != project.id ||
          current?.creationCapability != selectedCapability) {
        return false;
      }
      final available =
          !analysis.usesSafeFallback &&
          (analysis.portrait == PortraitApplicability.applicable ||
              analysis.body == PortraitApplicability.applicable);
      try {
        await session.reconcileEditTargets(
          photo.id,
          detectedEditTargetsFor(photo: photo, analysis: analysis),
        );
        await session.setPhotoAnalysisState(
          photo.id,
          available ? PhotoAnalysisState.ready : PhotoAnalysisState.fallback,
        );
      } on Object {
        // Eligibility remains a read-only answer. A failed persistence write
        // never selects or exposes another capability as a fallback.
      }
      return available;
    } on Object {
      return false;
    }
  }

  static bool _requiresSubjectSegmentation(CreationCapability? capability) =>
      capability == CreationCapability.cleanupWhite ||
      capability == CreationCapability.cleanupTransparent ||
      capability == CreationCapability.cleanupReplaceBackground;
}
