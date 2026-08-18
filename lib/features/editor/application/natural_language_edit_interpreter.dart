import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/portrait_retouch_recipe.dart';

enum EditableParameter {
  exposure,
  warmth,
  textureSmoothing,
  skinToneLighting,
  blemishReduction,
}

@immutable
final class EditParameterChange {
  const EditParameterChange({
    required this.parameter,
    required this.before,
    required this.after,
  });

  final EditableParameter parameter;
  final num before;
  final num after;
}

@immutable
final class NaturalLanguageEditResult {
  const NaturalLanguageEditResult({
    required this.recipe,
    required this.changes,
  });

  final EditRecipe recipe;
  final List<EditParameterChange> changes;

  bool get isApplicable => changes.isNotEmpty;
}

abstract interface class NaturalLanguageEditInterpreter {
  NaturalLanguageEditResult interpret(
    String transcript, {
    required EditRecipe current,
  });
}

/// A deterministic, fail-closed interpreter for the first voice-editing slice.
///
/// Future AI adapters must return this same bounded result instead of mutating
/// pixels or bypassing the visible recipe contract.
final class LocalNaturalLanguageEditInterpreter
    implements NaturalLanguageEditInterpreter {
  const LocalNaturalLanguageEditInterpreter();

  @override
  NaturalLanguageEditResult interpret(
    String transcript, {
    required EditRecipe current,
  }) {
    final normalized = transcript.trim().toLowerCase();
    if (normalized.isEmpty) {
      return NaturalLanguageEditResult(recipe: current, changes: const []);
    }

    var recipe = current;
    final changes = <EditParameterChange>[];

    void updateDouble(
      EditableParameter parameter,
      double before,
      double after,
      EditRecipe Function(double value) update,
    ) {
      final bounded = after.clamp(-1.0, 1.0);
      if (bounded == before) return;
      recipe = update(bounded);
      changes.add(
        EditParameterChange(
          parameter: parameter,
          before: before,
          after: bounded,
        ),
      );
    }

    if (_containsAny(normalized, const ['亮一点', '更亮', '提亮', 'brighter'])) {
      final before = recipe.exposure;
      updateDouble(
        EditableParameter.exposure,
        before,
        before + 0.12,
        (value) => recipe.copyWith(exposure: value),
      );
    } else if (_containsAny(normalized, const ['暗一点', '更暗', '压暗', 'darker'])) {
      final before = recipe.exposure;
      updateDouble(
        EditableParameter.exposure,
        before,
        before - 0.12,
        (value) => recipe.copyWith(exposure: value),
      );
    }

    if (_containsAny(normalized, const ['暖一点', '更暖', 'warmer'])) {
      final before = recipe.warmth;
      updateDouble(
        EditableParameter.warmth,
        before,
        before + 0.12,
        (value) => recipe.copyWith(warmth: value),
      );
    } else if (_containsAny(normalized, const ['冷一点', '更冷', 'cooler'])) {
      final before = recipe.warmth;
      updateDouble(
        EditableParameter.warmth,
        before,
        before - 0.12,
        (value) => recipe.copyWith(warmth: value),
      );
    }

    final disablesSmoothing = _containsAny(normalized, const [
      '不要磨皮',
      '关闭磨皮',
      '取消磨皮',
      'no smoothing',
    ]);
    if (disablesSmoothing) {
      final portrait = recipe.portraitRecipe;
      if (portrait.textureSmoothing != 0) {
        recipe = recipe.copyWith(
          portraitRecipe: portrait.copyWith(textureSmoothing: 0),
        );
        changes.add(
          EditParameterChange(
            parameter: EditableParameter.textureSmoothing,
            before: portrait.textureSmoothing,
            after: 0,
          ),
        );
      }
    } else if (_containsAny(normalized, const [
      '皮肤自然',
      '自然美化',
      '皮肤干净',
      'natural skin',
    ])) {
      final before = recipe.portraitRecipe;
      const after = PortraitRetouchRecipe.naturalBeautificationRecommended;
      recipe = recipe.copyWith(portraitRecipe: after);
      _recordPortraitChange(
        changes,
        EditableParameter.textureSmoothing,
        before.textureSmoothing,
        after.textureSmoothing,
      );
      _recordPortraitChange(
        changes,
        EditableParameter.skinToneLighting,
        before.skinToneLighting,
        after.skinToneLighting,
      );
      _recordPortraitChange(
        changes,
        EditableParameter.blemishReduction,
        before.blemishReduction,
        after.blemishReduction,
      );
    }

    return NaturalLanguageEditResult(
      recipe: recipe,
      changes: List<EditParameterChange>.unmodifiable(changes),
    );
  }

  static bool _containsAny(String input, List<String> phrases) =>
      phrases.any(input.contains);

  static void _recordPortraitChange(
    List<EditParameterChange> changes,
    EditableParameter parameter,
    int before,
    int after,
  ) {
    if (before == after) return;
    changes.add(
      EditParameterChange(parameter: parameter, before: before, after: after),
    );
  }
}
