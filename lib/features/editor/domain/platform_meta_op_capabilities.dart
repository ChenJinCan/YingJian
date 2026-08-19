import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/meta_op_availability.dart';

final iosMetaOpCapabilities = PlatformMetaOpCapabilities(
  platform: EditPlatform.ios,
  entries: [
    _support(MetaOpIds.compositionGeometry),
    for (final id in _globalToneIds) _support(id),
    _support(MetaOpIds.filter),
    for (final id in MetaOpIds.hslChannels) _support(id),
    _support(MetaOpIds.noiseReduction),
    _support(MetaOpIds.lowLightRecovery),
    _support(MetaOpIds.hazeRemoval),
    _support(MetaOpIds.detailSharpening),
    _support(MetaOpIds.skinSmooth, maxTargets: 6),
    _support(MetaOpIds.skinToneLighting, maxTargets: 6),
    _support(MetaOpIds.blemishReduction, maxTargets: 6),
    _support(MetaOpIds.faceGeometry, maxTargets: 3),
    _support(MetaOpIds.bodyGeometry, maxTargets: 3),
    _support(MetaOpIds.semanticAdjustments, maxResourceBytes: 50 * 1024 * 1024),
  ],
);

final androidMetaOpCapabilities = PlatformMetaOpCapabilities(
  platform: EditPlatform.android,
  entries: [
    _support(MetaOpIds.compositionGeometry),
    for (final id in _globalToneIds) _support(id),
  ],
);

const _globalToneIds = [
  MetaOpIds.exposure,
  MetaOpIds.highlights,
  MetaOpIds.shadows,
  MetaOpIds.contrast,
  MetaOpIds.warmth,
  MetaOpIds.tint,
  MetaOpIds.saturation,
  MetaOpIds.clarity,
];

MetaOpExecutionSupport _support(
  String id, {
  int maxTargets = 0,
  int maxResourceBytes = 0,
}) => MetaOpExecutionSupport(
  metaOpId: id,
  metaOpVersion: 1,
  preview: true,
  export: true,
  maxTargets: maxTargets,
  maxResourceBytes: maxResourceBytes,
);

PlatformMetaOpCapabilities metaOpCapabilitiesForTargetPlatform(
  TargetPlatform platform,
) => platform == TargetPlatform.iOS
    ? iosMetaOpCapabilities
    : androidMetaOpCapabilities;
