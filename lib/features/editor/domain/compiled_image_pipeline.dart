import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/editor/domain/render_plan.dart';

/// Production render envelope. A renderer never receives a legacy pixel
/// payload unless its canonical state has first compiled into a RenderPlan.
@immutable
final class CompiledImagePipeline implements ImagePipeline {
  const CompiledImagePipeline({required this.payload, required this.plan});

  final ImagePipeline payload;
  final RenderPlan plan;

  @override
  Map<String, Object> toPlatformArguments() => {
    'renderPlanV1': {
      ...plan.toJson(),
      'backendPayload': payload.toPlatformArguments(),
    },
  };
}
