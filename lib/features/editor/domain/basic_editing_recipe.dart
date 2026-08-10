import 'package:flutter/foundation.dart';

enum PhotoFilter {
  none,
  clean,
  portrait,
  cinematic,
  film,
  warmSun,
  coolAir,
  vivid,
  faded,
  noir,
  food,
  landscape,
  night,
}

enum HslChannel { red, orange, yellow, green, cyan, blue, purple, magenta }

@immutable
final class HslAdjustment {
  factory HslAdjustment({
    double hue = 0,
    double saturation = 0,
    double lightness = 0,
  }) {
    _validate(hue, 'hue');
    _validate(saturation, 'saturation');
    _validate(lightness, 'lightness');
    return HslAdjustment._(
      hue: hue,
      saturation: saturation,
      lightness: lightness,
    );
  }

  const HslAdjustment._({
    required this.hue,
    required this.saturation,
    required this.lightness,
  });

  static const neutral = HslAdjustment._(hue: 0, saturation: 0, lightness: 0);
  final double hue;
  final double saturation;
  final double lightness;
  bool get isNeutral => this == neutral;

  Map<String, Object> toJson() => {
    'hue': hue,
    'saturation': saturation,
    'lightness': lightness,
  };

  factory HslAdjustment.fromJson(Map<String, Object?> json) => HslAdjustment(
    hue: (json['hue'] as num?)?.toDouble() ?? 0,
    saturation: (json['saturation'] as num?)?.toDouble() ?? 0,
    lightness: (json['lightness'] as num?)?.toDouble() ?? 0,
  );

  static void _validate(double value, String name) {
    if (!value.isFinite || value < -100 || value > 100) {
      throw RangeError.range(value, -100, 100, name);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is HslAdjustment &&
      other.hue == hue &&
      other.saturation == saturation &&
      other.lightness == lightness;

  @override
  int get hashCode => Object.hash(hue, saturation, lightness);
}

@immutable
final class BasicEditingRecipe {
  factory BasicEditingRecipe({
    bool flipHorizontal = false,
    bool flipVertical = false,
    double perspectiveHorizontal = 0,
    double perspectiveVertical = 0,
    PhotoFilter filter = PhotoFilter.none,
    double filterStrength = 0,
    Map<HslChannel, HslAdjustment> hsl = const {},
  }) {
    _validate(perspectiveHorizontal, -30, 30, 'perspectiveHorizontal');
    _validate(perspectiveVertical, -30, 30, 'perspectiveVertical');
    _validate(filterStrength, 0, 100, 'filterStrength');
    final normalized = <HslChannel, HslAdjustment>{};
    for (final channel in HslChannel.values) {
      final adjustment = hsl[channel] ?? HslAdjustment.neutral;
      if (!adjustment.isNeutral) normalized[channel] = adjustment;
    }
    return BasicEditingRecipe._(
      flipHorizontal: flipHorizontal,
      flipVertical: flipVertical,
      perspectiveHorizontal: perspectiveHorizontal,
      perspectiveVertical: perspectiveVertical,
      filter: filter,
      filterStrength: filter == PhotoFilter.none ? 0 : filterStrength,
      hsl: Map.unmodifiable(normalized),
    );
  }

  const BasicEditingRecipe._({
    required this.flipHorizontal,
    required this.flipVertical,
    required this.perspectiveHorizontal,
    required this.perspectiveVertical,
    required this.filter,
    required this.filterStrength,
    required this.hsl,
  });

  static const neutral = BasicEditingRecipe._(
    flipHorizontal: false,
    flipVertical: false,
    perspectiveHorizontal: 0,
    perspectiveVertical: 0,
    filter: PhotoFilter.none,
    filterStrength: 0,
    hsl: {},
  );

  final bool flipHorizontal;
  final bool flipVertical;
  final double perspectiveHorizontal;
  final double perspectiveVertical;
  final PhotoFilter filter;
  final double filterStrength;
  final Map<HslChannel, HslAdjustment> hsl;

  bool get isNeutral => this == neutral;

  Map<String, Object> toJson() => {
    'recipeVersion': 1,
    'flipHorizontal': flipHorizontal,
    'flipVertical': flipVertical,
    'perspectiveHorizontal': perspectiveHorizontal,
    'perspectiveVertical': perspectiveVertical,
    'filter': filter.name,
    'filterStrength': filterStrength,
    'hsl': {
      for (final entry in hsl.entries) entry.key.name: entry.value.toJson(),
    },
  };

  factory BasicEditingRecipe.fromJson(Map<String, Object?> json) {
    final rawFilter = json['filter'];
    final filter = PhotoFilter.values
        .where((value) => value.name == rawFilter)
        .firstOrNull;
    if (rawFilter != null && filter == null) {
      throw const FormatException('Invalid photo filter');
    }
    final rawHsl = json['hsl'];
    if (rawHsl != null && rawHsl is! Map) {
      throw const FormatException('Invalid HSL payload');
    }
    final hsl = <HslChannel, HslAdjustment>{};
    if (rawHsl is Map) {
      for (final entry in rawHsl.entries) {
        final channel = HslChannel.values
            .where((value) => value.name == entry.key)
            .firstOrNull;
        if (channel == null || entry.value is! Map) {
          throw const FormatException('Invalid HSL channel');
        }
        hsl[channel] = HslAdjustment.fromJson(
          Map<String, Object?>.from(entry.value as Map),
        );
      }
    }
    return BasicEditingRecipe(
      flipHorizontal: json['flipHorizontal'] as bool? ?? false,
      flipVertical: json['flipVertical'] as bool? ?? false,
      perspectiveHorizontal:
          (json['perspectiveHorizontal'] as num?)?.toDouble() ?? 0,
      perspectiveVertical:
          (json['perspectiveVertical'] as num?)?.toDouble() ?? 0,
      filter: filter ?? PhotoFilter.none,
      filterStrength: (json['filterStrength'] as num?)?.toDouble() ?? 0,
      hsl: hsl,
    );
  }

  BasicEditingRecipe copyWith({
    bool? flipHorizontal,
    bool? flipVertical,
    double? perspectiveHorizontal,
    double? perspectiveVertical,
    PhotoFilter? filter,
    double? filterStrength,
    Map<HslChannel, HslAdjustment>? hsl,
  }) => BasicEditingRecipe(
    flipHorizontal: flipHorizontal ?? this.flipHorizontal,
    flipVertical: flipVertical ?? this.flipVertical,
    perspectiveHorizontal: perspectiveHorizontal ?? this.perspectiveHorizontal,
    perspectiveVertical: perspectiveVertical ?? this.perspectiveVertical,
    filter: filter ?? this.filter,
    filterStrength: filterStrength ?? this.filterStrength,
    hsl: hsl ?? this.hsl,
  );

  static void _validate(
    double value,
    double minimum,
    double maximum,
    String name,
  ) {
    if (!value.isFinite || value < minimum || value > maximum) {
      throw RangeError.value(
        value,
        name,
        'Must be between $minimum and $maximum',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is BasicEditingRecipe &&
      other.flipHorizontal == flipHorizontal &&
      other.flipVertical == flipVertical &&
      other.perspectiveHorizontal == perspectiveHorizontal &&
      other.perspectiveVertical == perspectiveVertical &&
      other.filter == filter &&
      other.filterStrength == filterStrength &&
      mapEquals(other.hsl, hsl);

  @override
  int get hashCode => Object.hash(
    flipHorizontal,
    flipVertical,
    perspectiveHorizontal,
    perspectiveVertical,
    filter,
    filterStrength,
    Object.hashAll(hsl.entries),
  );
}
