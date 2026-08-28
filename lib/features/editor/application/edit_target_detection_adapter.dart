import 'package:yingjian/features/editor/domain/edit_target.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/features/photo_analysis/domain/photo_analysis.dart';

List<DetectedEditTarget> detectedEditTargetsFor({
  required ProjectPhoto photo,
  required LocalPhotoAnalysis analysis,
}) => List.unmodifiable([
  for (final region in analysis.faceTargetRegions)
    DetectedEditTarget(
      photoId: photo.id,
      kind: EditTargetKind.face,
      analysisVersion: analysis.analysisVersion,
      region: NormalizedEditRegion(
        left: region.left,
        top: region.top,
        right: region.right,
        bottom: region.bottom,
      ),
    ),
  for (final region in analysis.bodyTargetRegions)
    DetectedEditTarget(
      photoId: photo.id,
      kind: EditTargetKind.body,
      analysisVersion: analysis.analysisVersion,
      region: NormalizedEditRegion(
        left: region.left,
        top: region.top,
        right: region.right,
        bottom: region.bottom,
      ),
    ),
]);
