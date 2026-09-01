import 'dart:convert';

import 'package:yingjian/features/creation/application/local_reference_style_analyzer.dart';
import 'package:yingjian/features/creation/domain/style_definition.dart';
import 'package:yingjian/features/editor/domain/basic_editing_recipe.dart';
import 'package:yingjian/features/editor/domain/content_sha256.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';

/// Builds bounded, deterministic local style snapshots.
///
/// It is deliberately not a pixel-generation API. Text is compiled through
/// the existing admitted edit planner, while a reference photo contributes
/// only aggregate color, lighting, and texture signals.
abstract final class LocalStyleDefinitionFactory {
  /// Compiles a small, explicit vocabulary into a deterministic local look.
  ///
  /// This is intentionally fail-closed. Unsupported or conflicting style
  /// families return `null`; callers must keep the user's current state and
  /// ask them to edit the same input instead of guessing a nearby style.
  static EditRecipe? recipeFromPrompt(String rawPrompt) {
    final prompt = rawPrompt.trim().toLowerCase();
    if (prompt.isEmpty) return null;

    final families = <PhotoFilter>{
      if (_containsAny(prompt, const ['电影感', '电影色调', 'cinematic']))
        PhotoFilter.cinematic,
      if (_containsAny(prompt, const ['胶片感', '胶片风', 'film look', 'film style']))
        PhotoFilter.film,
      if (_containsAny(prompt, const ['日系', '日杂', 'japanese style']))
        PhotoFilter.clean,
      if (_containsAny(prompt, const [
        '黑白',
        '单色',
        'black and white',
        'monochrome',
      ]))
        PhotoFilter.noir,
      if (_containsAny(prompt, const ['清冷', '冷调', 'cool tone', 'cooler']))
        PhotoFilter.coolAir,
      if (_containsAny(prompt, const ['暖阳', '暖调', 'warm sunlight']))
        PhotoFilter.warmSun,
      if (_containsAny(prompt, const ['鲜艳', '通透', 'vivid'])) PhotoFilter.vivid,
      if (_containsAny(prompt, const ['褪色', '低饱和', 'faded'])) PhotoFilter.faded,
    };
    if (families.length > 1) return null;

    final warmer = _containsAny(prompt, const ['暖一点', '更暖', 'warmer']);
    final cooler = _containsAny(prompt, const ['冷一点', '更冷', 'cooler']);
    final brighter = _containsAny(prompt, const [
      '亮一点',
      '更亮',
      '提亮',
      'brighter',
    ]);
    final darker = _containsAny(prompt, const ['暗一点', '更暗', '压暗', 'darker']);
    final moreVivid = _containsAny(prompt, const ['鲜艳一点', '更鲜艳', 'more vivid']);
    final lessVivid = _containsAny(prompt, const [
      '低饱和',
      '少点颜色',
      'less saturated',
    ]);
    if ((warmer && cooler) ||
        (brighter && darker) ||
        (moreVivid && lessVivid)) {
      return null;
    }
    if (families.isEmpty &&
        !warmer &&
        !cooler &&
        !brighter &&
        !darker &&
        !moreVivid &&
        !lessVivid) {
      return null;
    }

    final filter = families.firstOrNull ?? PhotoFilter.clean;
    final baseWarmth = switch (filter) {
      PhotoFilter.film || PhotoFilter.warmSun => 0.05,
      PhotoFilter.coolAir => -0.05,
      _ => 0.0,
    };
    final baseSaturation = switch (filter) {
      PhotoFilter.vivid => 0.06,
      PhotoFilter.faded => -0.06,
      _ => 0.0,
    };
    return EditRecipe(
      exposure: brighter
          ? 0.06
          : darker
          ? -0.06
          : 0,
      warmth:
          (baseWarmth +
                  (warmer
                      ? 0.05
                      : cooler
                      ? -0.05
                      : 0))
              .clamp(-0.12, 0.12),
      saturation:
          (baseSaturation +
                  (moreVivid
                      ? 0.06
                      : lessVivid
                      ? -0.06
                      : 0))
              .clamp(-0.12, 0.12),
      contrast: filter == PhotoFilter.cinematic ? 0.05 : 0,
      basicEditingRecipe: BasicEditingRecipe(
        filter: filter,
        filterStrength: switch (filter) {
          PhotoFilter.cinematic => 45,
          PhotoFilter.film => 42,
          PhotoFilter.noir => 50,
          _ => 38,
        },
      ),
    );
  }

  static String identifierFor({
    required StyleDefinitionOrigin origin,
    required String stableSeed,
  }) {
    final hash = ContentSha256.ofBytes(utf8.encode('$origin:$stableSeed'));
    return '${origin.name}-${hash.substring(0, 24)}';
  }

  static EditRecipe recipeFromReference(ReferenceStyleSignals signals) {
    for (final entry in <String, double>{
      'red': signals.red,
      'green': signals.green,
      'blue': signals.blue,
      'luminance': signals.luminance,
      'saturation': signals.saturation,
      'contrast': signals.contrast,
      'edgeStrength': signals.edgeStrength,
    }.entries) {
      if (!entry.value.isFinite || entry.value < 0 || entry.value > 1) {
        throw ArgumentError.value(
          entry.value,
          entry.key,
          'Reference style signals must be finite values from 0 to 1',
        );
      }
    }
    final warmth = ((signals.red - signals.blue) * 0.16)
        .clamp(-0.12, 0.12)
        .toDouble();
    final exposure = ((signals.luminance - 0.5) * 0.18)
        .clamp(-0.08, 0.08)
        .toDouble();
    final saturation = ((signals.saturation - 0.45) * 0.18)
        .clamp(-0.08, 0.1)
        .toDouble();
    final contrast = ((signals.contrast - 0.5) * 0.12)
        .clamp(-0.06, 0.06)
        .toDouble();
    final clarity = ((signals.edgeStrength - 0.2) * 0.1)
        .clamp(-0.02, 0.06)
        .toDouble();
    final filter = warmth > 0.03
        ? PhotoFilter.warmSun
        : warmth < -0.03
        ? PhotoFilter.coolAir
        : PhotoFilter.clean;
    return EditRecipe(
      exposure: exposure,
      warmth: warmth,
      saturation: saturation,
      contrast: contrast,
      clarity: clarity,
      basicEditingRecipe: BasicEditingRecipe(
        filter: filter,
        filterStrength: 34 + signals.saturation * 16,
      ),
    );
  }

  static bool _containsAny(String input, List<String> phrases) =>
      phrases.any(input.contains);
}
