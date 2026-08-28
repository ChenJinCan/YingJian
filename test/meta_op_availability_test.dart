import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/meta_op_availability.dart';
import 'package:yingjian/features/editor/domain/platform_meta_op_capabilities.dart';

void main() {
  test(
    'exposes only shipped, promoted, preview-and-export capable meta ops',
    () {
      final capabilities = PlatformMetaOpCapabilities(
        platform: EditPlatform.ios,
        entries: const [
          MetaOpExecutionSupport(
            metaOpId: MetaOpIds.exposure,
            metaOpVersion: 1,
            preview: true,
            export: true,
            maxTargets: 0,
            maxResourceBytes: 0,
          ),
          MetaOpExecutionSupport(
            metaOpId: MetaOpIds.skinSmooth,
            metaOpVersion: 1,
            preview: true,
            export: false,
            maxTargets: 1,
            maxResourceBytes: 0,
          ),
        ],
      );
      final policy = MetaOpProductPolicy(
        lifecycleById: const {
          MetaOpIds.exposure: MetaOpLifecycle.manualProduction,
          MetaOpIds.skinSmooth: MetaOpLifecycle.aiProduction,
        },
        remotelyEnabledIds: const {
          MetaOpIds.exposure,
          MetaOpIds.skinSmooth,
          'remote.unknown',
        },
      );

      final availability = MetaOpAvailability.resolve(
        catalog: MetaOpCatalog.standard,
        capabilities: capabilities,
        policy: policy,
        applicability: const {'photo', 'face'},
      );

      expect(availability.manualIds, [MetaOpIds.exposure]);
      expect(availability.searchIds, [MetaOpIds.exposure]);
      expect(availability.search(MetaOpCatalog.standard, '皮肤'), isEmpty);
      expect(availability.search(MetaOpCatalog.standard, '亮度'), [
        MetaOpIds.exposure,
      ]);
      expect(availability.aiProposalIds, isEmpty);
      expect(availability.aiCapabilities(MetaOpCatalog.standard), isEmpty);
      expect(availability.ignoredRemoteIds, {'remote.unknown'});
    },
  );

  test('AI capabilities are generated from admitted catalog definitions', () {
    final availability = MetaOpAvailability.resolve(
      catalog: MetaOpCatalog.standard,
      capabilities: iosMetaOpCapabilities,
      policy: MetaOpProductPolicy(
        lifecycleById: const {
          MetaOpIds.exposure: MetaOpLifecycle.aiProduction,
          MetaOpIds.skinSmooth: MetaOpLifecycle.aiProposal,
        },
      ),
      applicability: const {'photo', 'face'},
    );

    expect(availability.aiProposalIds, [
      MetaOpIds.exposure,
      MetaOpIds.skinSmooth,
    ]);
    expect(availability.aiProductionIds, [MetaOpIds.exposure]);
    expect(
      availability
          .aiCapabilities(MetaOpCatalog.standard)
          .map((capability) => capability.toJson()),
      [
        {
          'id': MetaOpIds.exposure,
          'version': 1,
          'semantic':
              'Adjust global scene exposure without changing white balance.',
          'exclusions': <String>[],
          'scope': 'group',
          'target': 'none',
          'parameters': [
            {
              'id': 'value',
              'type': 'number',
              'neutralValue': 0.0,
              'minimum': -1.0,
              'maximum': 1.0,
            },
          ],
        },
        {
          'id': MetaOpIds.skinSmooth,
          'version': 1,
          'semantic':
              'Reduce uneven skin texture for one stable face target while preserving identity features.',
          'exclusions': <String>[],
          'scope': 'currentPhoto',
          'target': 'face',
          'parameters': [
            {
              'id': 'value',
              'type': 'number',
              'neutralValue': 0.0,
              'minimum': 0.0,
              'maximum': 1.0,
            },
          ],
        },
      ],
    );
  });

  test('lifecycle can only advance one declared stage at a time', () {
    expect(
      MetaOpLifecycle.defined.canAdvanceTo(MetaOpLifecycle.platformDevelopment),
      isTrue,
    );
    expect(
      MetaOpLifecycle.manualProduction.canAdvanceTo(MetaOpLifecycle.aiProposal),
      isTrue,
    );
    expect(
      MetaOpLifecycle.defined.canAdvanceTo(MetaOpLifecycle.aiProduction),
      isFalse,
    );
    expect(
      MetaOpLifecycle.aiProduction.canAdvanceTo(
        MetaOpLifecycle.manualProduction,
      ),
      isFalse,
    );
  });

  test('declares truthful per-op support for iOS and Android', () {
    final skinSmooth = MetaOpCatalog.standard.definition(MetaOpIds.skinSmooth);

    for (final id in const [
      MetaOpIds.exposure,
      MetaOpIds.highlights,
      MetaOpIds.shadows,
      MetaOpIds.contrast,
      MetaOpIds.warmth,
      MetaOpIds.tint,
      MetaOpIds.saturation,
      MetaOpIds.clarity,
    ]) {
      final definition = MetaOpCatalog.standard.definition(id);
      expect(iosMetaOpCapabilities.fullySupports(definition), isTrue);
      expect(androidMetaOpCapabilities.fullySupports(definition), isTrue);
    }
    for (final id in [MetaOpIds.filter, ...MetaOpIds.hslChannels]) {
      final definition = MetaOpCatalog.standard.definition(id);
      expect(iosMetaOpCapabilities.fullySupports(definition), isTrue);
      expect(androidMetaOpCapabilities.fullySupports(definition), isFalse);
    }
    for (final id in const [
      MetaOpIds.noiseReduction,
      MetaOpIds.lowLightRecovery,
      MetaOpIds.hazeRemoval,
      MetaOpIds.detailSharpening,
    ]) {
      final definition = MetaOpCatalog.standard.definition(id);
      expect(iosMetaOpCapabilities.fullySupports(definition), isTrue);
      expect(androidMetaOpCapabilities.fullySupports(definition), isFalse);
    }
    expect(iosMetaOpCapabilities.fullySupports(skinSmooth), isTrue);
    expect(androidMetaOpCapabilities.fullySupports(skinSmooth), isFalse);
    expect(
      iosMetaOpCapabilities.supportFor(MetaOpIds.skinSmooth, 1)!.maxTargets,
      6,
    );
  });

  test('admits filter and HSL manually on iOS but hides them on Android', () {
    MetaOpAvailability resolve(PlatformMetaOpCapabilities capabilities) =>
        MetaOpAvailability.resolve(
          catalog: MetaOpCatalog.standard,
          capabilities: capabilities,
          policy: standardMetaOpProductPolicy,
          applicability: const {'photo'},
        );

    final ios = resolve(iosMetaOpCapabilities);
    final android = resolve(androidMetaOpCapabilities);

    expect(ios.manualIds, contains(MetaOpIds.filter));
    expect(ios.manualIds, containsAll(MetaOpIds.hslChannels));
    expect(android.manualIds, isNot(contains(MetaOpIds.filter)));
    expect(android.manualIds, isNot(contains(anyOf(MetaOpIds.hslChannels))));
  });

  test('admits quality output ops manually only where export is supported', () {
    MetaOpAvailability resolve(PlatformMetaOpCapabilities capabilities) =>
        MetaOpAvailability.resolve(
          catalog: MetaOpCatalog.standard,
          capabilities: capabilities,
          policy: standardMetaOpProductPolicy,
          applicability: const {'photo'},
        );
    const qualityIds = {
      MetaOpIds.noiseReduction,
      MetaOpIds.lowLightRecovery,
      MetaOpIds.hazeRemoval,
      MetaOpIds.detailSharpening,
    };

    expect(resolve(iosMetaOpCapabilities).manualIds, containsAll(qualityIds));
    expect(
      resolve(
        androidMetaOpCapabilities,
      ).manualIds.toSet().intersection(qualityIds),
      isEmpty,
    );
  });
}
