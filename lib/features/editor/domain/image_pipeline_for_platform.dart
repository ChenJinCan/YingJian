import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/compiled_image_pipeline.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/image_pipeline.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v1.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v2.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_v12.dart';
import 'package:yingjian/features/editor/domain/legacy_edit_recipe_adapter.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/render_plan.dart';

bool get supportsImagePipelineV2 =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;

ImagePipeline imagePipelineForCurrentPlatform(
  EditRecipe recipe, {
  String sourceId = 'render-source',
  EditState? editState,
  EditContext context = EditContext.ios,
  RenderOutputRequirements outputRequirements =
      const RenderOutputRequirements.preview(),
}) {
  final canonicalState =
      editState ??
      const LegacyEditRecipeAdapter().read(recipe, photoId: sourceId);
  final resourceIds = <String>{...context.resourceIds};
  final targetIds = <String>{...context.targetIds};
  final photoIds = <String>{...context.photoIds, sourceId};
  final applicability = <String>{...context.applicability, 'photo'};
  for (final entry in canonicalState.values.entries) {
    if (entry.key.targetId case final targetId?) targetIds.add(targetId);
    final definition = MetaOpCatalog.standard.find(entry.key.metaOpId);
    if (definition != null) {
      applicability.addAll(definition.applicability);
      final parameter = definition.parameter(entry.key.parameterId);
      if (parameter?.type == MetaOpValueType.resource &&
          entry.value is String) {
        resourceIds.add(entry.value as String);
      }
    }
  }
  final renderContext = EditContext(
    platform: context.platform,
    photoIds: photoIds,
    targetIds: targetIds,
    capabilities: context.capabilities,
    applicability: applicability,
    resourceIds: resourceIds,
    resourceByteLengths: context.resourceByteLengths,
    metaOpCapabilities: context.metaOpCapabilities,
  );
  final compilation = const RenderPlanCompiler().compile(
    sourceId: sourceId,
    state: canonicalState,
    context: renderContext,
    outputRequirements: outputRequirements,
  );
  if (compilation is! AcceptedRenderPlan) {
    final rejection = compilation as RejectedRenderPlan;
    throw StateError('Render plan rejected: ${rejection.reason.name}');
  }
  final payload = defaultTargetPlatform == TargetPlatform.iOS
      ? ImagePipelineV12.fromRecipe(recipe)
      : supportsImagePipelineV2
      ? ImagePipelineV2.fromRecipe(recipe)
      : ImagePipelineV1.fromRecipe(recipe);
  return CompiledImagePipeline(payload: payload, plan: compilation.plan);
}
