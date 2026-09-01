import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';

abstract final class MetaOpIds {
  static const compositionGeometry = 'composition.geometry';
  static const filter = 'style.filter';
  static const hslRed = 'color.hsl.red';
  static const hslOrange = 'color.hsl.orange';
  static const hslYellow = 'color.hsl.yellow';
  static const hslGreen = 'color.hsl.green';
  static const hslCyan = 'color.hsl.cyan';
  static const hslBlue = 'color.hsl.blue';
  static const hslPurple = 'color.hsl.purple';
  static const hslMagenta = 'color.hsl.magenta';
  static const hslChannels = [
    hslRed,
    hslOrange,
    hslYellow,
    hslGreen,
    hslCyan,
    hslBlue,
    hslPurple,
    hslMagenta,
  ];
  static const exposure = 'tone.exposure';
  static const highlights = 'tone.highlights';
  static const shadows = 'tone.shadows';
  static const contrast = 'tone.contrast';
  static const warmth = 'color.warmth';
  static const tint = 'color.tint';
  static const saturation = 'color.saturation';
  static const clarity = 'tone.clarity';
  static const noiseReduction = 'quality.noise_reduction';
  static const lowLightRecovery = 'quality.low_light_recovery';
  static const hazeRemoval = 'quality.haze_removal';
  static const detailSharpening = 'quality.detail_sharpening';
  static const skinSmooth = 'portrait.skin_smooth';
  static const skinToneLighting = 'portrait.skin_tone_lighting';
  static const blemishReduction = 'portrait.blemish_reduction';
  static const faceGeometry = 'portrait.face_geometry';
  static const bodyGeometry = 'portrait.body_geometry';
  static const directionalLighting = 'portrait.directional_lighting';
  static const semanticAdjustments = 'semantic.background_local';
}

enum EditPlatform { ios, android }

enum MetaOpValueType { number, integer, boolean, choice, resource }

enum MetaOpTargetType { none, face, body, region, background }

enum RenderStage {
  inputOrientation,
  compositionGeometry,
  globalToneColor,
  subjectAnalysis,
  portraitBody,
  backgroundLocalMask,
  qualityOutput,
}

enum MetaOpSharing { group, currentPhoto }

enum AiAvailability { disabled, proposalOnly, enabled }

enum MetaOpControl { slider, toggle, choices, dedicatedEditor }

@immutable
final class MetaOpParameterDefinition {
  const MetaOpParameterDefinition.number({
    required this.id,
    required double this.neutralValue,
    required double this.minimum,
    required double this.maximum,
  }) : type = MetaOpValueType.number,
       choices = const [];

  const MetaOpParameterDefinition.integer({
    required this.id,
    required int this.neutralValue,
    required int this.minimum,
    required int this.maximum,
  }) : type = MetaOpValueType.integer,
       choices = const [];

  const MetaOpParameterDefinition.boolean({
    required this.id,
    required bool this.neutralValue,
  }) : type = MetaOpValueType.boolean,
       minimum = null,
       maximum = null,
       choices = const [];

  const MetaOpParameterDefinition.choice({
    required this.id,
    required String this.neutralValue,
    required this.choices,
  }) : type = MetaOpValueType.choice,
       minimum = null,
       maximum = null;

  const MetaOpParameterDefinition.resource({required this.id})
    : type = MetaOpValueType.resource,
      neutralValue = '',
      minimum = null,
      maximum = null,
      choices = const [];

  final String id;
  final MetaOpValueType type;
  final Object neutralValue;
  final num? minimum;
  final num? maximum;
  final List<String> choices;

  bool accepts(Object value) => switch (type) {
    MetaOpValueType.number =>
      value is num && value.isFinite && value >= minimum! && value <= maximum!,
    MetaOpValueType.integer =>
      value is int && value >= minimum! && value <= maximum!,
    MetaOpValueType.boolean => value is bool,
    MetaOpValueType.choice => value is String && choices.contains(value),
    MetaOpValueType.resource =>
      value is String &&
          (value.isEmpty ||
              RegExp(r'^resource-v1-[a-f0-9]{64}$').hasMatch(value)),
  };

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'neutralValue': neutralValue,
    if (minimum != null) 'minimum': minimum,
    if (maximum != null) 'maximum': maximum,
    if (choices.isNotEmpty) 'choices': choices,
  };
}

@immutable
final class MetaOpDefinition {
  const MetaOpDefinition({
    required this.id,
    required this.version,
    required this.semantic,
    required this.exclusions,
    required this.parameters,
    required this.targetType,
    required this.stage,
    required this.sharing,
    required this.applicability,
    required this.searchTerms,
    required this.defaultOrder,
    required this.control,
    required this.aiAvailability,
    required this.requiredCapability,
  });

  final String id;
  final int version;
  final String semantic;
  final Set<String> exclusions;
  final List<MetaOpParameterDefinition> parameters;
  final MetaOpTargetType targetType;
  final RenderStage stage;
  final MetaOpSharing sharing;
  final Set<String> applicability;
  final Set<String> searchTerms;
  final int defaultOrder;
  final MetaOpControl control;
  final AiAvailability aiAvailability;
  final String requiredCapability;

  MetaOpParameterDefinition? parameter(String id) {
    for (final parameter in parameters) {
      if (parameter.id == id) return parameter;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'semantic': semantic,
    'exclusions': exclusions.toList()..sort(),
    'parameters': parameters.map((value) => value.toJson()).toList(),
    'targetType': targetType.name,
    'stage': stage.name,
    'sharing': sharing.name,
    'applicability': applicability.toList()..sort(),
    'searchTerms': searchTerms.toList()..sort(),
    'defaultOrder': defaultOrder,
    'control': control.name,
    'aiAvailability': aiAvailability.name,
    'requiredCapability': requiredCapability,
  };
}

final class MetaOpCatalog {
  MetaOpCatalog(Iterable<MetaOpDefinition> definitions)
    : _definitions = Map.unmodifiable({
        for (final definition in definitions) definition.id: definition,
      });

  static final standard = MetaOpCatalog([
    const MetaOpDefinition(
      id: MetaOpIds.compositionGeometry,
      version: 1,
      semantic:
          'Adjust crop, rotation, straightening, flips, and perspective for one photo.',
      exclusions: {},
      parameters: [
        MetaOpParameterDefinition.number(
          id: 'left',
          neutralValue: 0,
          minimum: 0,
          maximum: 1,
        ),
        MetaOpParameterDefinition.number(
          id: 'top',
          neutralValue: 0,
          minimum: 0,
          maximum: 1,
        ),
        MetaOpParameterDefinition.number(
          id: 'right',
          neutralValue: 1,
          minimum: 0,
          maximum: 1,
        ),
        MetaOpParameterDefinition.number(
          id: 'bottom',
          neutralValue: 1,
          minimum: 0,
          maximum: 1,
        ),
        MetaOpParameterDefinition.integer(
          id: 'quarterTurns',
          neutralValue: 0,
          minimum: 0,
          maximum: 3,
        ),
        MetaOpParameterDefinition.number(
          id: 'straightenDegrees',
          neutralValue: 0,
          minimum: -45,
          maximum: 45,
        ),
        MetaOpParameterDefinition.boolean(
          id: 'flipHorizontal',
          neutralValue: false,
        ),
        MetaOpParameterDefinition.boolean(
          id: 'flipVertical',
          neutralValue: false,
        ),
        MetaOpParameterDefinition.number(
          id: 'perspectiveHorizontal',
          neutralValue: 0,
          minimum: -30,
          maximum: 30,
        ),
        MetaOpParameterDefinition.number(
          id: 'perspectiveVertical',
          neutralValue: 0,
          minimum: -30,
          maximum: 30,
        ),
      ],
      targetType: MetaOpTargetType.none,
      stage: RenderStage.compositionGeometry,
      sharing: MetaOpSharing.currentPhoto,
      applicability: {'photo'},
      searchTerms: {
        '构图',
        '裁剪',
        '旋转',
        '拉直',
        '翻转',
        '透视',
        'crop',
        'rotate',
        'perspective',
      },
      defaultOrder: 8,
      control: MetaOpControl.dedicatedEditor,
      aiAvailability: AiAvailability.proposalOnly,
      requiredCapability: 'composition.geometry.v1',
    ),
    const MetaOpDefinition(
      id: MetaOpIds.filter,
      version: 1,
      semantic:
          'Select one global photographic filter and adjust its visible strength.',
      exclusions: {},
      parameters: [
        MetaOpParameterDefinition.choice(
          id: 'filter',
          neutralValue: 'none',
          choices: [
            'none',
            'clean',
            'portrait',
            'cinematic',
            'film',
            'warmSun',
            'coolAir',
            'vivid',
            'faded',
            'noir',
            'food',
            'landscape',
            'night',
          ],
        ),
        MetaOpParameterDefinition.number(
          id: 'strength',
          neutralValue: 0,
          minimum: 0,
          maximum: 100,
        ),
      ],
      targetType: MetaOpTargetType.none,
      stage: RenderStage.globalToneColor,
      sharing: MetaOpSharing.group,
      applicability: {'photo'},
      searchTerms: {'滤镜', '风格', '质感', 'filter', 'style'},
      defaultOrder: 9,
      control: MetaOpControl.dedicatedEditor,
      aiAvailability: AiAvailability.enabled,
      requiredCapability: 'style.filter.v1',
    ),
    _hslDefinition(
      id: MetaOpIds.hslRed,
      channel: HslChannel.red,
      searchTerms: {'红色', 'red'},
      defaultOrder: 10,
    ),
    _hslDefinition(
      id: MetaOpIds.hslOrange,
      channel: HslChannel.orange,
      searchTerms: {'橙色', 'orange'},
      defaultOrder: 11,
    ),
    _hslDefinition(
      id: MetaOpIds.hslYellow,
      channel: HslChannel.yellow,
      searchTerms: {'黄色', 'yellow'},
      defaultOrder: 12,
    ),
    _hslDefinition(
      id: MetaOpIds.hslGreen,
      channel: HslChannel.green,
      searchTerms: {'绿色', 'green'},
      defaultOrder: 13,
    ),
    _hslDefinition(
      id: MetaOpIds.hslCyan,
      channel: HslChannel.cyan,
      searchTerms: {'青色', 'cyan'},
      defaultOrder: 14,
    ),
    _hslDefinition(
      id: MetaOpIds.hslBlue,
      channel: HslChannel.blue,
      searchTerms: {'蓝色', 'blue'},
      defaultOrder: 15,
    ),
    _hslDefinition(
      id: MetaOpIds.hslPurple,
      channel: HslChannel.purple,
      searchTerms: {'紫色', 'purple'},
      defaultOrder: 16,
    ),
    _hslDefinition(
      id: MetaOpIds.hslMagenta,
      channel: HslChannel.magenta,
      searchTerms: {'洋红', '品红', 'magenta'},
      defaultOrder: 17,
    ),
    _globalToneDefinition(
      id: MetaOpIds.exposure,
      semantic: 'Adjust global scene exposure without changing white balance.',
      searchTerms: const {'曝光', '亮度', 'exposure', 'brightness'},
      defaultOrder: 0,
    ),
    _globalToneDefinition(
      id: MetaOpIds.highlights,
      semantic: 'Adjust detail and brightness in global highlight regions.',
      searchTerms: const {'高光', '亮部', 'highlights'},
      defaultOrder: 1,
    ),
    _globalToneDefinition(
      id: MetaOpIds.shadows,
      semantic: 'Adjust detail and brightness in global shadow regions.',
      searchTerms: const {'阴影', '暗部', 'shadows'},
      defaultOrder: 2,
    ),
    _globalToneDefinition(
      id: MetaOpIds.contrast,
      semantic: 'Adjust global tonal separation.',
      searchTerms: const {'对比度', 'contrast'},
      defaultOrder: 3,
    ),
    _globalToneDefinition(
      id: MetaOpIds.warmth,
      semantic: 'Adjust global color temperature on a warm-to-cool axis.',
      searchTerms: const {'色温', '冷暖', '温暖', 'warmth', 'temperature'},
      defaultOrder: 4,
    ),
    _globalToneDefinition(
      id: MetaOpIds.tint,
      semantic: 'Adjust global green-to-magenta tint.',
      searchTerms: const {'色调', '偏绿', '偏洋红', 'tint'},
      defaultOrder: 5,
    ),
    _globalToneDefinition(
      id: MetaOpIds.saturation,
      semantic: 'Adjust global color saturation.',
      searchTerms: const {'饱和度', '鲜艳', 'saturation', 'vivid'},
      defaultOrder: 6,
    ),
    _globalToneDefinition(
      id: MetaOpIds.clarity,
      semantic: 'Adjust global local contrast and perceived clarity.',
      searchTerms: const {'清晰度', '通透', 'clarity'},
      defaultOrder: 7,
    ),
    _qualityDefinition(
      id: MetaOpIds.noiseReduction,
      semantic: 'Reduce visible image noise without changing composition.',
      searchTerms: const {'降噪', '噪点', 'noise', 'denoise'},
      defaultOrder: 18,
    ),
    _qualityDefinition(
      id: MetaOpIds.lowLightRecovery,
      semantic: 'Recover usable tonal detail in low-light images.',
      searchTerms: const {'暗部恢复', '低光', '夜景', 'low light'},
      defaultOrder: 19,
    ),
    _qualityDefinition(
      id: MetaOpIds.hazeRemoval,
      semantic: 'Reduce atmospheric haze while preserving image geometry.',
      searchTerms: const {'去雾', '雾霾', '通透', 'dehaze', 'haze'},
      defaultOrder: 20,
    ),
    _qualityDefinition(
      id: MetaOpIds.detailSharpening,
      semantic: 'Sharpen visible image detail at the output stage.',
      searchTerms: const {'锐化', '细节', '清晰', 'sharpen', 'detail'},
      defaultOrder: 21,
    ),
    _portraitDefinition(
      id: MetaOpIds.skinSmooth,
      semantic:
          'Reduce uneven skin texture for one stable face target while preserving identity features.',
      searchTerms: const {'磨皮', '质感磨皮', '皮肤', 'smooth skin'},
      defaultOrder: 22,
    ),
    _portraitDefinition(
      id: MetaOpIds.skinToneLighting,
      semantic:
          'Improve skin tone and facial lighting for one stable face target without changing identity.',
      searchTerms: const {'肤色', '面部光线', '提亮', 'skin tone', 'face lighting'},
      defaultOrder: 23,
    ),
    _portraitDefinition(
      id: MetaOpIds.blemishReduction,
      semantic:
          'Reduce discrete skin blemishes for one stable face target while preserving identity marks.',
      searchTerms: const {'瑕疵', '痘印', '色斑', 'blemish'},
      defaultOrder: 24,
    ),
    _targetGeometryDefinition(
      id: MetaOpIds.faceGeometry,
      semantic:
          'Adjust facial geometry for one stable face target without transferring the effect to another person.',
      targetType: MetaOpTargetType.face,
      applicability: const {'photo', 'face'},
      parameters: const [
        MetaOpParameterDefinition.number(
          id: 'faceSlim',
          neutralValue: 0,
          minimum: 0,
          maximum: 1,
        ),
        MetaOpParameterDefinition.number(
          id: 'headSize',
          neutralValue: 0,
          minimum: 0,
          maximum: 1,
        ),
        MetaOpParameterDefinition.number(
          id: 'jaw',
          neutralValue: 0,
          minimum: -1,
          maximum: 1,
        ),
        MetaOpParameterDefinition.number(
          id: 'chin',
          neutralValue: 0,
          minimum: -1,
          maximum: 1,
        ),
        MetaOpParameterDefinition.number(
          id: 'eyes',
          neutralValue: 0,
          minimum: -1,
          maximum: 1,
        ),
        MetaOpParameterDefinition.number(
          id: 'nose',
          neutralValue: 0,
          minimum: -1,
          maximum: 1,
        ),
        MetaOpParameterDefinition.number(
          id: 'mouth',
          neutralValue: 0,
          minimum: -1,
          maximum: 1,
        ),
      ],
      searchTerms: const {'瘦脸', '五官', '脸型', 'face shape', 'reshape'},
      defaultOrder: 25,
    ),
    _targetGeometryDefinition(
      id: MetaOpIds.bodyGeometry,
      semantic:
          'Adjust body geometry for one stable body target without transferring the effect to another person.',
      targetType: MetaOpTargetType.body,
      applicability: const {'photo', 'body'},
      parameters: const [
        MetaOpParameterDefinition.number(
          id: 'slimming',
          neutralValue: 0,
          minimum: 0,
          maximum: 1,
        ),
        MetaOpParameterDefinition.number(
          id: 'height',
          neutralValue: 0,
          minimum: 0,
          maximum: 1,
        ),
        MetaOpParameterDefinition.number(
          id: 'shoulders',
          neutralValue: 0,
          minimum: -1,
          maximum: 1,
        ),
        MetaOpParameterDefinition.number(
          id: 'waist',
          neutralValue: 0,
          minimum: -1,
          maximum: 1,
        ),
        MetaOpParameterDefinition.number(
          id: 'legs',
          neutralValue: 0,
          minimum: 0,
          maximum: 1,
        ),
      ],
      searchTerms: const {'瘦身', '身材', '体态', 'body shape', 'reshape'},
      defaultOrder: 26,
    ),
    const MetaOpDefinition(
      id: MetaOpIds.directionalLighting,
      version: 1,
      semantic:
          'Relight one stable face target with a bounded horizontal key-light direction and intensity.',
      exclusions: {},
      parameters: [
        MetaOpParameterDefinition.number(
          id: 'azimuth',
          neutralValue: 0,
          minimum: -90,
          maximum: 90,
        ),
        MetaOpParameterDefinition.integer(
          id: 'intensity',
          neutralValue: 0,
          minimum: 0,
          maximum: 100,
        ),
      ],
      targetType: MetaOpTargetType.face,
      stage: RenderStage.portraitBody,
      sharing: MetaOpSharing.currentPhoto,
      applicability: {'photo', 'face'},
      searchTerms: {'光照', '左侧光', '右侧光', 'relight', 'directional light'},
      defaultOrder: 27,
      control: MetaOpControl.dedicatedEditor,
      aiAvailability: AiAvailability.proposalOnly,
      requiredCapability: 'portrait.directional_lighting.v1',
    ),
    const MetaOpDefinition(
      id: MetaOpIds.semanticAdjustments,
      version: 1,
      semantic:
          'Adjust background, subject, and masked local tone for one photo.',
      exclusions: {},
      parameters: [
        MetaOpParameterDefinition.choice(
          id: 'background',
          neutralValue: 'original',
          choices: [
            'original',
            'blur',
            'white',
            'black',
            'warm',
            'cool',
            'image',
            'transparent',
          ],
        ),
        MetaOpParameterDefinition.resource(id: 'backgroundImageResource'),
        MetaOpParameterDefinition.resource(id: 'subjectMaskResource'),
        MetaOpParameterDefinition.resource(id: 'localMaskResource'),
        MetaOpParameterDefinition.resource(id: 'eraseMaskResource'),
        MetaOpParameterDefinition.integer(
          id: 'backgroundBlur',
          neutralValue: 0,
          minimum: 0,
          maximum: 100,
        ),
        MetaOpParameterDefinition.integer(
          id: 'subjectExposure',
          neutralValue: 0,
          minimum: -100,
          maximum: 100,
        ),
        MetaOpParameterDefinition.integer(
          id: 'subjectSaturation',
          neutralValue: 0,
          minimum: -100,
          maximum: 100,
        ),
        MetaOpParameterDefinition.integer(
          id: 'backgroundExposure',
          neutralValue: 0,
          minimum: -100,
          maximum: 100,
        ),
        MetaOpParameterDefinition.integer(
          id: 'backgroundSaturation',
          neutralValue: 0,
          minimum: -100,
          maximum: 100,
        ),
        MetaOpParameterDefinition.integer(
          id: 'localExposure',
          neutralValue: 0,
          minimum: -100,
          maximum: 100,
        ),
        MetaOpParameterDefinition.integer(
          id: 'localSaturation',
          neutralValue: 0,
          minimum: -100,
          maximum: 100,
        ),
      ],
      targetType: MetaOpTargetType.none,
      stage: RenderStage.backgroundLocalMask,
      sharing: MetaOpSharing.currentPhoto,
      applicability: {'photo'},
      searchTerms: {
        '背景',
        '主体',
        '局部',
        '蒙版',
        'background',
        'subject',
        'local',
        'mask',
      },
      defaultOrder: 28,
      control: MetaOpControl.dedicatedEditor,
      aiAvailability: AiAvailability.enabled,
      requiredCapability: 'semantic.background_local.v1',
    ),
  ]);

  final Map<String, MetaOpDefinition> _definitions;

  Iterable<MetaOpDefinition> get definitions => _definitions.values;

  MetaOpDefinition definition(String id) {
    final result = _definitions[id];
    if (result == null) throw ArgumentError.value(id, 'id', 'Unknown meta op');
    return result;
  }

  MetaOpDefinition? find(String id) => _definitions[id];

  List<String> search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    final matches =
        definitions
            .where(
              (definition) =>
                  definition.id.toLowerCase().contains(normalized) ||
                  definition.searchTerms.any(
                    (term) => term.toLowerCase().contains(normalized),
                  ),
            )
            .toList()
          ..sort((a, b) => a.defaultOrder.compareTo(b.defaultOrder));
    return List.unmodifiable(matches.map((definition) => definition.id));
  }

  List<String> validateContract() {
    final issues = <String>[];
    final orders = <int>{};
    for (final definition in definitions) {
      if (definition.id.trim().isEmpty || definition.version < 1) {
        issues.add('${definition.id}: invalid identity');
      }
      if (definition.semantic.trim().isEmpty ||
          definition.applicability.isEmpty ||
          definition.searchTerms.isEmpty ||
          definition.requiredCapability.trim().isEmpty) {
        issues.add('${definition.id}: incomplete discovery contract');
      }
      if (!orders.add(definition.defaultOrder)) {
        issues.add('${definition.id}: duplicate default order');
      }
      final parameterIds = <String>{};
      for (final parameter in definition.parameters) {
        if (!parameterIds.add(parameter.id) ||
            !parameter.accepts(parameter.neutralValue)) {
          issues.add('${definition.id}.${parameter.id}: invalid parameter');
        }
      }
      if (definition.parameters.isEmpty) {
        issues.add('${definition.id}: no parameters');
      }
      final encoded = definition.toJson();
      if (encoded['id'] != definition.id ||
          encoded['version'] != definition.version) {
        issues.add('${definition.id}: serialization mismatch');
      }
    }
    return List.unmodifiable(issues);
  }
}

MetaOpDefinition _globalToneDefinition({
  required String id,
  required String semantic,
  required Set<String> searchTerms,
  required int defaultOrder,
}) => MetaOpDefinition(
  id: id,
  version: 1,
  semantic: semantic,
  exclusions: const {},
  parameters: const [
    MetaOpParameterDefinition.number(
      id: 'value',
      neutralValue: 0,
      minimum: -1,
      maximum: 1,
    ),
  ],
  targetType: MetaOpTargetType.none,
  stage: RenderStage.globalToneColor,
  sharing: MetaOpSharing.group,
  applicability: const {'photo'},
  searchTerms: Set.unmodifiable(searchTerms),
  defaultOrder: defaultOrder,
  control: MetaOpControl.slider,
  aiAvailability: AiAvailability.enabled,
  requiredCapability: '$id.v1',
);

MetaOpDefinition _hslDefinition({
  required String id,
  required HslChannel channel,
  required Set<String> searchTerms,
  required int defaultOrder,
}) => MetaOpDefinition(
  id: id,
  version: 1,
  semantic:
      'Adjust hue, saturation, and lightness for the ${channel.name} color channel.',
  exclusions: const {},
  parameters: const [
    MetaOpParameterDefinition.number(
      id: 'hue',
      neutralValue: 0,
      minimum: -100,
      maximum: 100,
    ),
    MetaOpParameterDefinition.number(
      id: 'saturation',
      neutralValue: 0,
      minimum: -100,
      maximum: 100,
    ),
    MetaOpParameterDefinition.number(
      id: 'lightness',
      neutralValue: 0,
      minimum: -100,
      maximum: 100,
    ),
  ],
  targetType: MetaOpTargetType.none,
  stage: RenderStage.globalToneColor,
  sharing: MetaOpSharing.group,
  applicability: const {'photo'},
  searchTerms: Set.unmodifiable({'HSL', channel.name, ...searchTerms}),
  defaultOrder: defaultOrder,
  control: MetaOpControl.dedicatedEditor,
  aiAvailability: AiAvailability.enabled,
  requiredCapability: '$id.v1',
);

MetaOpDefinition _qualityDefinition({
  required String id,
  required String semantic,
  required Set<String> searchTerms,
  required int defaultOrder,
}) => MetaOpDefinition(
  id: id,
  version: 1,
  semantic: semantic,
  exclusions: const {},
  parameters: const [
    MetaOpParameterDefinition.integer(
      id: 'value',
      neutralValue: 0,
      minimum: 0,
      maximum: 100,
    ),
  ],
  targetType: MetaOpTargetType.none,
  stage: RenderStage.qualityOutput,
  sharing: MetaOpSharing.currentPhoto,
  applicability: const {'photo'},
  searchTerms: Set.unmodifiable(searchTerms),
  defaultOrder: defaultOrder,
  control: MetaOpControl.slider,
  aiAvailability: AiAvailability.enabled,
  requiredCapability: '$id.v1',
);

MetaOpDefinition _portraitDefinition({
  required String id,
  required String semantic,
  required Set<String> searchTerms,
  required int defaultOrder,
}) => MetaOpDefinition(
  id: id,
  version: 1,
  semantic: semantic,
  exclusions: const {},
  parameters: const [
    MetaOpParameterDefinition.number(
      id: 'value',
      neutralValue: 0,
      minimum: 0,
      maximum: 1,
    ),
  ],
  targetType: MetaOpTargetType.face,
  stage: RenderStage.portraitBody,
  sharing: MetaOpSharing.currentPhoto,
  applicability: const {'photo', 'face'},
  searchTerms: Set.unmodifiable(searchTerms),
  defaultOrder: defaultOrder,
  control: MetaOpControl.slider,
  aiAvailability: AiAvailability.enabled,
  requiredCapability: '$id.v1',
);

MetaOpDefinition _targetGeometryDefinition({
  required String id,
  required String semantic,
  required MetaOpTargetType targetType,
  required Set<String> applicability,
  required List<MetaOpParameterDefinition> parameters,
  required Set<String> searchTerms,
  required int defaultOrder,
}) => MetaOpDefinition(
  id: id,
  version: 1,
  semantic: semantic,
  exclusions: const {},
  parameters: List.unmodifiable(parameters),
  targetType: targetType,
  stage: RenderStage.portraitBody,
  sharing: MetaOpSharing.currentPhoto,
  applicability: Set.unmodifiable(applicability),
  searchTerms: Set.unmodifiable(searchTerms),
  defaultOrder: defaultOrder,
  control: MetaOpControl.dedicatedEditor,
  aiAvailability: AiAvailability.proposalOnly,
  requiredCapability: '$id.v1',
);
