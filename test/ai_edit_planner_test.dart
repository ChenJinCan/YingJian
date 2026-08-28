import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/application/ai_edit_planner.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/meta_op_availability.dart';
import 'package:yingjian/features/editor/domain/platform_meta_op_capabilities.dart';

void main() {
  test(
    'AI capability manifest comes only from admitted executable meta ops',
    () {
      final availability = MetaOpAvailability.resolve(
        catalog: MetaOpCatalog.standard,
        capabilities: iosMetaOpCapabilities,
        policy: standardMetaOpProductPolicy,
        applicability: const {'photo'},
      );

      final capabilities = availability.aiCapabilities(MetaOpCatalog.standard);
      final exposure = capabilities.singleWhere(
        (value) => value.definition.id == MetaOpIds.exposure,
      );
      final json = exposure.toJson();

      expect(availability.aiProductionIds, contains(MetaOpIds.exposure));
      expect(json['id'], MetaOpIds.exposure);
      expect(json['version'], 1);
      expect(json['semantic'], contains('global scene exposure'));
      expect(json['scope'], 'group');
      expect(json['target'], 'none');
      expect(json['parameters'], [
        {
          'id': 'value',
          'type': 'number',
          'neutralValue': 0.0,
          'minimum': -1.0,
          'maximum': 1.0,
        },
      ]);
      expect(json.keys, isNot(contains('controlLabel')));
    },
  );

  test(
    'planner returns absolute versioned meta ops instead of UI or pixels',
    () async {
      final availability = MetaOpAvailability.resolve(
        catalog: MetaOpCatalog.standard,
        capabilities: iosMetaOpCapabilities,
        policy: standardMetaOpProductPolicy,
        applicability: const {'photo'},
      );
      const exposureAddress = OpAddress(
        metaOpId: MetaOpIds.exposure,
        metaOpVersion: 1,
        parameterId: 'value',
        scope: EditScope.group,
      );

      final outcome = await const LocalAiEditPlanner().plan(
        AiEditPlanningRequest(
          intent: '亮一点，也暖一点',
          baseStateVersion: 41,
          currentState: EditState(version: 0, values: {exposureAddress: 0.2}),
          capabilities: availability.aiCapabilities(MetaOpCatalog.standard),
          photoAnalysis: const AiPhotoAnalysis(scene: 'portrait'),
        ),
      );

      expect(outcome, isA<AiEditProposal>());
      final proposal = outcome as AiEditProposal;
      expect(proposal.baseStateVersion, 41);
      expect(proposal.changes, hasLength(2));
      expect(
        proposal.changes
            .singleWhere(
              (change) => change.address.metaOpId == MetaOpIds.exposure,
            )
            .value,
        closeTo(0.32, 1e-12),
      );
      expect(
        proposal.changes
            .singleWhere(
              (change) => change.address.metaOpId == MetaOpIds.warmth,
            )
            .value,
        closeTo(0.12, 1e-12),
      );
      expect(proposal.summary, [MetaOpIds.exposure, MetaOpIds.warmth]);
    },
  );

  test(
    'multi-face portrait intent asks once then resolves one atomic proposal',
    () async {
      final availability = MetaOpAvailability.resolve(
        catalog: MetaOpCatalog.standard,
        capabilities: iosMetaOpCapabilities,
        policy: standardMetaOpProductPolicy,
        applicability: const {'photo', 'face'},
      );

      final outcome = await const LocalAiEditPlanner().plan(
        AiEditPlanningRequest(
          intent: '皮肤自然一点',
          baseStateVersion: 12,
          currentState: EditState.empty,
          capabilities: availability.aiCapabilities(MetaOpCatalog.standard),
          photoAnalysis: const AiPhotoAnalysis(
            scene: 'people',
            targetIds: ['face-a', 'face-b'],
          ),
          photoId: 'photo-1',
        ),
      );

      expect(outcome, isA<AiTargetClarification>());
      final proposal = (outcome as AiTargetClarification).resolve('face-b');
      expect(proposal.baseStateVersion, 12);
      expect(proposal.changes, hasLength(3));
      expect(proposal.changes.map((change) => change.address.metaOpId), [
        MetaOpIds.skinSmooth,
        MetaOpIds.skinToneLighting,
        MetaOpIds.blemishReduction,
      ]);
      expect(
        proposal.changes.map((change) => change.address.targetId).toSet(),
        {'face-b'},
      );
      expect(proposal.changes.map((change) => change.address.photoId).toSet(), {
        'photo-1',
      });
    },
  );

  test('complex intents produce one atomic multi-parameter proposal', () async {
    final availability = MetaOpAvailability.resolve(
      catalog: MetaOpCatalog.standard,
      capabilities: iosMetaOpCapabilities,
      policy: standardMetaOpProductPolicy,
      applicability: const {'photo'},
    );

    final backgroundOutcome = await const LocalAiEditPlanner().plan(
      AiEditPlanningRequest(
        intent: '背景柔和一点，主体更突出',
        baseStateVersion: 20,
        currentState: EditState.empty,
        capabilities: availability.aiCapabilities(MetaOpCatalog.standard),
        photoAnalysis: const AiPhotoAnalysis(scene: 'people'),
        photoId: 'photo-1',
      ),
    );
    final backgroundProposal = backgroundOutcome as AiEditProposal;
    expect(backgroundProposal.baseStateVersion, 20);
    expect(backgroundProposal.changes, hasLength(2));
    expect(
      backgroundProposal.changes.map((change) => change.address.parameterId),
      ['background', 'backgroundBlur'],
    );
    expect(backgroundProposal.changes.map((change) => change.value), [
      'blur',
      35,
    ]);
    expect(
      backgroundProposal.changes
          .map((change) => change.address.photoId)
          .toSet(),
      {'photo-1'},
    );

    final filterOutcome = await const LocalAiEditPlanner().plan(
      AiEditPlanningRequest(
        intent: '电影感一点',
        baseStateVersion: 21,
        currentState: EditState.empty,
        capabilities: availability.aiCapabilities(MetaOpCatalog.standard),
        photoAnalysis: const AiPhotoAnalysis(scene: 'street'),
      ),
    );
    final filterProposal = filterOutcome as AiEditProposal;
    expect(filterProposal.changes, hasLength(2));
    expect(filterProposal.changes.map((change) => change.address.parameterId), [
      'filter',
      'strength',
    ]);
    expect(filterProposal.changes.map((change) => change.value), [
      'cinematic',
      45,
    ]);
  });

  test('portrait brightness and restrained background stay explicit', () async {
    final availability = MetaOpAvailability.resolve(
      catalog: MetaOpCatalog.standard,
      capabilities: iosMetaOpCapabilities,
      policy: standardMetaOpProductPolicy,
      applicability: const {'photo', 'face'},
    );

    final outcome = await const LocalAiEditPlanner().plan(
      AiEditPlanningRequest(
        intent: '脸上亮一点，背景不要太艳',
        baseStateVersion: 22,
        currentState: EditState.empty,
        capabilities: availability.aiCapabilities(MetaOpCatalog.standard),
        photoAnalysis: const AiPhotoAnalysis(
          scene: 'people',
          targetIds: ['face-a'],
        ),
        photoId: 'photo-1',
      ),
    );

    final proposal = outcome as AiEditProposal;
    expect(proposal.changes, hasLength(2));
    expect(proposal.changes.map((change) => change.address.metaOpId), [
      MetaOpIds.skinToneLighting,
      MetaOpIds.semanticAdjustments,
    ]);
    expect(proposal.changes.first.address.targetId, 'face-a');
    expect(proposal.changes.last.address.parameterId, 'backgroundSaturation');
    expect(proposal.changes.last.value, -8);
  });

  test('cancelled target clarification does not invent a target', () async {
    final availability = MetaOpAvailability.resolve(
      catalog: MetaOpCatalog.standard,
      capabilities: iosMetaOpCapabilities,
      policy: standardMetaOpProductPolicy,
      applicability: const {'photo', 'face'},
    );

    final outcome = await const LocalAiEditPlanner().plan(
      AiEditPlanningRequest(
        intent: '皮肤自然一点',
        baseStateVersion: 30,
        currentState: EditState.empty,
        capabilities: availability.aiCapabilities(MetaOpCatalog.standard),
        photoAnalysis: const AiPhotoAnalysis(
          scene: 'people',
          targetIds: ['face-a', 'face-b'],
        ),
        photoId: 'photo-1',
      ),
    );

    expect(outcome, isA<AiTargetClarification>());
    expect((outcome as AiTargetClarification).pendingChanges, hasLength(3));
    expect(
      outcome.pendingChanges.every((change) => change.address.targetId == null),
      isTrue,
    );
  });
}
