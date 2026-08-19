import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/edit_target.dart';

void main() {
  const leftFace = DetectedEditTarget(
    photoId: 'photo-1',
    kind: EditTargetKind.face,
    analysisVersion: 'vision-v1',
    region: NormalizedEditRegion(left: 0.1, top: 0.2, right: 0.3, bottom: 0.5),
  );
  const rightFace = DetectedEditTarget(
    photoId: 'photo-1',
    kind: EditTargetKind.face,
    analysisVersion: 'vision-v1',
    region: NormalizedEditRegion(left: 0.6, top: 0.2, right: 0.8, bottom: 0.5),
  );

  test('stable target ids do not depend on detection list order', () {
    final first = EditTargetRegistry.seed(const [leftFace, rightFace]);
    final reordered = EditTargetRegistry.seed(const [rightFace, leftFace]);

    expect(first.targets.keys.toSet(), reordered.targets.keys.toSet());
    expect(
      first.targets.values.map((target) => target.bindingFingerprint).toSet(),
      reordered.targets.values
          .map((target) => target.bindingFingerprint)
          .toSet(),
    );
    expect(EditTargetRegistry.fromJson(first.toJson()), first);
  });

  test('missing detections suspend a target instead of moving its effects', () {
    final registry = EditTargetRegistry.seed(const [leftFace, rightFace]);
    final leftId = registry.targets.values
        .singleWhere((target) => target.region.left == 0.1)
        .id;

    final reconciled = registry.reconcile(const [rightFace]);

    expect(reconciled.target(leftId).status, EditTargetStatus.suspended);
    expect(reconciled.target(leftId).region, leftFace.region);
    expect(
      reconciled.targets.values
          .singleWhere((target) => target.id != leftId)
          .status,
      EditTargetStatus.active,
    );
  });

  test('explicit rebind preserves logical identity and is reversible data', () {
    final registry = EditTargetRegistry.seed(const [leftFace]);
    final before = registry.targets.values.single;

    final rebound = registry.rebind(before.id, rightFace);

    expect(rebound.target(before.id).id, before.id);
    expect(rebound.target(before.id).region, rightFace.region);
    expect(rebound.target(before.id).status, EditTargetStatus.active);
    expect(rebound.rebindRecord, isNotNull);
    expect(rebound.rebindRecord!.targetId, before.id);
    expect(rebound.rebindRecord!.beforeFingerprint, before.bindingFingerprint);
    expect(
      rebound.rebindRecord!.afterFingerprint,
      rightFace.bindingFingerprint,
    );
    expect(rebound.undoLastRebind(), registry);
  });

  test('rebind rejects another photo or target kind', () {
    final registry = EditTargetRegistry.seed(const [leftFace]);
    final id = registry.targets.keys.single;

    expect(
      () => registry.rebind(
        id,
        DetectedEditTarget(
          photoId: 'photo-2',
          kind: EditTargetKind.face,
          analysisVersion: 'vision-v1',
          region: leftFace.region,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => registry.rebind(
        id,
        DetectedEditTarget(
          photoId: 'photo-1',
          kind: EditTargetKind.body,
          analysisVersion: 'vision-v1',
          region: leftFace.region,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('rebind cannot attach two logical targets to one detection', () {
    final registry = EditTargetRegistry.seed(const [leftFace, rightFace]);
    final leftId = registry.targets.values
        .singleWhere((target) => target.region == leftFace.region)
        .id;

    expect(() => registry.rebind(leftId, rightFace), throwsStateError);
  });
}
