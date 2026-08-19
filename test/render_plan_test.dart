import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/meta_op_availability.dart';
import 'package:yingjian/features/editor/domain/platform_meta_op_capabilities.dart';
import 'package:yingjian/features/editor/domain/render_plan.dart';

void main() {
  const composition = OpAddress(
    metaOpId: MetaOpIds.compositionGeometry,
    metaOpVersion: 1,
    parameterId: 'quarterTurns',
    scope: EditScope.currentPhoto,
    photoId: 'photo-1',
  );
  const exposure = OpAddress(
    metaOpId: MetaOpIds.exposure,
    metaOpVersion: 1,
    parameterId: 'value',
    scope: EditScope.group,
  );
  const sharpening = OpAddress(
    metaOpId: MetaOpIds.detailSharpening,
    metaOpVersion: 1,
    parameterId: 'value',
    scope: EditScope.currentPhoto,
    photoId: 'photo-1',
  );

  test(
    'compiles one stable stage-ordered plan from an admitted edit state',
    () {
      const compiler = RenderPlanCompiler();
      final first = compiler.compile(
        sourceId: 'photo-1',
        state: EditState(
          version: 7,
          values: {sharpening: 20, exposure: 0.25, composition: 1},
        ),
        context: EditContext(
          platform: EditPlatform.ios,
          photoIds: const {'photo-1'},
          metaOpCapabilities: iosMetaOpCapabilities,
        ),
      );
      final second = compiler.compile(
        sourceId: 'photo-1',
        state: EditState(
          version: 7,
          values: {composition: 1, exposure: 0.25, sharpening: 20},
        ),
        context: EditContext(
          platform: EditPlatform.ios,
          photoIds: const {'photo-1'},
          metaOpCapabilities: iosMetaOpCapabilities,
        ),
      );

      expect(first, isA<AcceptedRenderPlan>());
      expect(second, isA<AcceptedRenderPlan>());
      final plan = (first as AcceptedRenderPlan).plan;
      final samePlan = (second as AcceptedRenderPlan).plan;
      expect(plan.protocolVersion, 1);
      expect(plan.sourceId, 'photo-1');
      expect(plan.stateRevision, 7);
      expect(plan.outputRequirements.toJson(), {
        'purpose': 'preview',
        'colorSpace': 'srgb',
        'format': 'display',
        'quality': 'interactive',
      });
      expect(plan.stages.map((stage) => stage.stage), [
        RenderStage.compositionGeometry,
        RenderStage.globalToneColor,
        RenderStage.qualityOutput,
      ]);
      expect(plan.stages.first.operations.single.address, composition);
      expect(plan.stages[1].operations.single.address, exposure);
      expect(plan.stages.last.operations.single.address, sharpening);
      expect(plan.requiredCapabilities, [
        'composition.geometry.v1',
        'quality.detail_sharpening.v1',
        'tone.exposure.v1',
      ]);
      expect(plan.planId, samePlan.planId);
      expect(plan.planId, matches(RegExp(r'^rp1-[0-9a-f]{8}$')));
      expect(plan.toJson(), samePlan.toJson());
    },
  );

  test('rejects a state containing a non-neutral unsupported meta op', () {
    const compiler = RenderPlanCompiler();
    final result = compiler.compile(
      sourceId: 'photo-1',
      state: EditState(version: 2, values: {exposure: 0.25}),
      context: EditContext(
        platform: EditPlatform.ios,
        metaOpCapabilities: PlatformMetaOpCapabilities(
          platform: EditPlatform.ios,
          entries: const [],
        ),
      ),
    );

    expect(result, isA<RejectedRenderPlan>());
    expect(
      (result as RejectedRenderPlan).reason,
      EditRejection.capabilityMissing,
    );
    expect(result.address, exposure);
  });
}
