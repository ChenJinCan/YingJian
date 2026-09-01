import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:yingjian/features/editor/domain/content_sha256.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';

/// The user-visible, versioned description of a creation style.
///
/// [recipe] is the deterministic local compilation stored with the definition
/// for the current MVP. Callers must not treat raw input text or a reference
/// image as an executable recipe.
@immutable
final class StyleDefinition {
  StyleDefinition({
    this.schemaVersion = currentSchemaVersion,
    required this.styleId,
    required this.revision,
    required this.origin,
    required this.title,
    required this.summary,
    required this.recipe,
    String? visualIntent,
    DateTime? createdAt,
    this.sourceText,
    this.referenceFingerprint,
  }) : visualIntent = visualIntent ?? summary,
       createdAt = (createdAt ?? DateTime.now()).toUtc() {
    if (schemaVersion != currentSchemaVersion) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'Unsupported style definition schema',
      );
    }
    if (!isValidStyleId(styleId)) {
      throw ArgumentError.value(
        styleId,
        'styleId',
        'Style ids must be lowercase stable identifiers',
      );
    }
    if (revision < 1) {
      throw RangeError.range(revision, 1, null, 'revision');
    }
    _validateText(title, 'title', maxLength: 120);
    _validateText(summary, 'summary', maxLength: 240);
    _validateText(
      this.visualIntent,
      'visualIntent',
      maxLength: maxAiRedrawIntentLength,
    );
    if (sourceText case final value?) {
      _validateText(value, 'sourceText', maxLength: 500);
    }
    if (referenceFingerprint case final value?
        when !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'referenceFingerprint',
        'Reference fingerprints must be lowercase SHA-256 values',
      );
    }
    switch (origin) {
      case StyleDefinitionOrigin.official:
        if (sourceText != null || referenceFingerprint != null) {
          throw ArgumentError(
            'Official styles cannot contain user-input provenance',
          );
        }
      case StyleDefinitionOrigin.text || StyleDefinitionOrigin.voice:
        if (sourceText == null || referenceFingerprint != null) {
          throw ArgumentError(
            '${origin.name} styles require confirmed text only',
          );
        }
      case StyleDefinitionOrigin.reference:
        if (referenceFingerprint == null || sourceText != null) {
          throw ArgumentError(
            'Reference styles require one reference fingerprint only',
          );
        }
      case StyleDefinitionOrigin.aiRedraw:
        if (sourceText == null ||
            referenceFingerprint != null ||
            sourceText != this.visualIntent ||
            recipe != EditRecipe.neutral) {
          throw ArgumentError(
            'AI redraw styles require one confirmed visual intent and no '
            'local edit recipe',
          );
        }
      case StyleDefinitionOrigin.mixed:
        if (sourceText == null || referenceFingerprint == null) {
          throw ArgumentError(
            'Mixed styles require confirmed text and a reference fingerprint',
          );
        }
    }
  }

  factory StyleDefinition.aiRedraw({
    required String confirmedVisualIntent,
    required String title,
    required String summary,
    int revision = 1,
    DateTime? createdAt,
  }) {
    final visualIntent = normalizeAiRedrawIntent(confirmedVisualIntent);
    final seed = ContentSha256.ofBytes(
      utf8.encode('ai-redraw-intent-v1:$visualIntent'),
    );
    return StyleDefinition(
      styleId: 'ai-redraw-${seed.substring(0, 24)}',
      revision: revision,
      origin: StyleDefinitionOrigin.aiRedraw,
      title: title,
      summary: summary,
      visualIntent: visualIntent,
      recipe: EditRecipe.neutral,
      createdAt: createdAt,
      sourceText: visualIntent,
    );
  }

  static const currentSchemaVersion = 1;
  static const maxAiRedrawIntentLength = 500;

  static final _styleIdPattern = RegExp(r'^[a-z0-9][a-z0-9._-]{0,95}$');
  static final _unsafeInputControlPattern = RegExp(
    r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\u200B\u200E\u200F\u202A-\u202E\u2060-\u2069\uFEFF]',
  );

  final int schemaVersion;
  final String styleId;
  final int revision;
  final StyleDefinitionOrigin origin;
  final String title;
  final String summary;
  final String visualIntent;
  final EditRecipe recipe;
  final DateTime createdAt;

  /// Locally persisted, user-confirmed text or transcription. It must never
  /// be sent to regular logs or telemetry.
  final String? sourceText;

  /// SHA-256 of a locally selected reference image. The image bytes themselves
  /// are intentionally not embedded in the style definition.
  final String? referenceFingerprint;

  static bool isValidStyleId(String value) => _styleIdPattern.hasMatch(value);

  /// Normalizes layout-only whitespace while preserving every user word.
  /// Hidden directionality and control characters are rejected instead of
  /// being silently removed or rewritten.
  static String normalizeAiRedrawIntent(String value) {
    if (_unsafeInputControlPattern.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'confirmedVisualIntent',
        'AI redraw intent cannot contain hidden or control characters',
      );
    }
    final normalized = value.replaceAll(RegExp(r'[ \t\r\n]+'), ' ').trim();
    if (normalized.isEmpty || normalized.length > maxAiRedrawIntentLength) {
      throw ArgumentError.value(
        value,
        'confirmedVisualIntent',
        'AI redraw intent must contain 1 to $maxAiRedrawIntentLength visible '
            'characters',
      );
    }
    return normalized;
  }

  String get versionedIdentity =>
      'style-definition-v$schemaVersion:$styleId:r$revision';

  /// Stable identity of the executable visual-intent projection. Local
  /// creation time and localized display copy are intentionally excluded.
  /// [versionedIdentity] separately binds the definition schema and revision.
  String get contentFingerprint =>
      ContentSha256.ofBytes(utf8.encode(visualIntent));

  Map<String, Object> toJson() => {
    'schemaVersion': schemaVersion,
    'styleId': styleId,
    'revision': revision,
    'origin': origin.name,
    'title': title,
    'summary': summary,
    'visualIntent': visualIntent,
    'recipe': recipe.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'sourceText': ?sourceText,
    'referenceFingerprint': ?referenceFingerprint,
  };

  factory StyleDefinition.fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion is! num ||
        schemaVersion.toInt() != schemaVersion ||
        schemaVersion.toInt() != currentSchemaVersion) {
      throw FormatException('Unsupported style definition schema');
    }
    final originName = json['origin'];
    final origin = originName is String
        ? StyleDefinitionOrigin.values
              .where((candidate) => candidate.name == originName)
              .firstOrNull
        : null;
    if (origin == null) {
      throw FormatException('Unsupported style definition origin');
    }
    final styleId = json['styleId'];
    final revision = json['revision'];
    final title = json['title'];
    final summary = json['summary'];
    final recipe = json['recipe'];
    final createdAt = json['createdAt'];
    if (styleId is! String ||
        revision is! num ||
        revision.toInt() != revision ||
        title is! String ||
        summary is! String ||
        recipe is! Map ||
        createdAt is! String) {
      throw FormatException('Invalid style definition');
    }
    try {
      return StyleDefinition(
        schemaVersion: schemaVersion.toInt(),
        styleId: styleId,
        revision: revision.toInt(),
        origin: origin,
        title: title,
        summary: summary,
        visualIntent: json['visualIntent'] as String?,
        recipe: EditRecipe.fromJson(Map<String, Object?>.from(recipe)),
        createdAt: DateTime.parse(createdAt),
        sourceText: json['sourceText'] as String?,
        referenceFingerprint: json['referenceFingerprint'] as String?,
      );
    } on RangeError catch (error) {
      throw FormatException('Invalid style definition: ${error.message}');
    } on ArgumentError catch (error) {
      throw FormatException('Invalid style definition: ${error.message}');
    }
  }

  static void _validateText(
    String value,
    String name, {
    required int maxLength,
  }) {
    if (value.trim().isEmpty ||
        value != value.trim() ||
        value.length > maxLength ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(value)) {
      throw ArgumentError.value(
        value,
        name,
        'Style definition text must be trimmed printable text up to '
        '$maxLength characters',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is StyleDefinition &&
      other.schemaVersion == schemaVersion &&
      other.styleId == styleId &&
      other.revision == revision &&
      other.origin == origin &&
      other.title == title &&
      other.summary == summary &&
      other.visualIntent == visualIntent &&
      other.recipe == recipe &&
      other.createdAt == createdAt &&
      other.sourceText == sourceText &&
      other.referenceFingerprint == referenceFingerprint;

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    styleId,
    revision,
    origin,
    title,
    summary,
    visualIntent,
    recipe,
    createdAt,
    sourceText,
    referenceFingerprint,
  );
}

enum StyleDefinitionOrigin { official, text, voice, reference, aiRedraw, mixed }
