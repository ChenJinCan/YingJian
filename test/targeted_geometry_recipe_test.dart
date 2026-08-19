import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';
import 'package:yingjian/features/editor/domain/portrait_geometry_recipe.dart';
import 'package:yingjian/features/editor/domain/targeted_geometry_recipe.dart';

void main() {
  const leftFace = DetectedEditTarget(
    photoId: 'photo-1',
    kind: EditTargetKind.face,
    analysisVersion: 'vision-v1',
    region: NormalizedEditRegion(left: 0.1, top: 0.2, right: 0.3, bottom: 0.6),
  );
  const rightFace = DetectedEditTarget(
    photoId: 'photo-1',
    kind: EditTargetKind.face,
    analysisVersion: 'vision-v1',
    region: NormalizedEditRegion(left: 0.6, top: 0.2, right: 0.8, bottom: 0.6),
  );

  test('stores geometry by stable target id and round trips', () {
    final registry = EditTargetRegistry.seed(const [leftFace, rightFace]);
    final rightId = registry.targets.values
        .singleWhere((target) => target.region == rightFace.region)
        .id;
    final recipe = TargetedGeometryRecipe.neutral.updateFace(
      rightId,
      (target) => target.copyWith(faceSlim: 30, eyes: 12),
    );

    expect(TargetedGeometryRecipe.fromJson(recipe.toJson()), recipe);
    final projected = recipe.project(registry);
    expect(projected.faceTargets[0], FaceGeometryTarget.neutral);
    expect(projected.faceTargets[1].faceSlim, 30);
    expect(projected.faceTargets[1].eyes, 12);
  });

  test('suspended targets pause instead of transferring geometry', () {
    final registry = EditTargetRegistry.seed(const [leftFace, rightFace]);
    final leftId = registry.targets.values
        .singleWhere((target) => target.region == leftFace.region)
        .id;
    final recipe = TargetedGeometryRecipe.neutral.updateFace(
      leftId,
      (target) => target.copyWith(faceSlim: 40),
    );

    final suspended = registry.reconcile(const [rightFace]);
    final projected = recipe
        .retainTargets({
          for (final target in suspended.targets.values)
            if (target.status == EditTargetStatus.active) target.id,
        })
        .project(suspended);

    expect(projected.faceTargets, hasLength(1));
    expect(projected.faceTargets.single, FaceGeometryTarget.neutral);
    expect(recipe.faces[leftId]?.faceSlim, 40);
  });

  test('rebind keeps geometry attached to the same logical target', () {
    final registry = EditTargetRegistry.seed(const [leftFace]);
    final targetId = registry.targets.keys.single;
    final recipe = TargetedGeometryRecipe.neutral.updateFace(
      targetId,
      (target) => target.copyWith(jaw: -18),
    );

    final rebound = registry.rebind(targetId, rightFace);

    expect(recipe.project(rebound).faceTargets.single.jaw, -18);
    expect(rebound.targets.keys.single, targetId);
  });
}
