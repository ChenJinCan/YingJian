import 'package:flutter/material.dart';

abstract final class AppTheme {
  // Frozen Stitch MVP palette. Keep these values exact so every production
  // surface shares the same warm-black editorial language.
  static const _seed = Color(0xFFE6BC45);
  static const _darkBackground = Color(0xFF0B0D0E);
  static const _darkSurface = Color(0xFF151719);
  static const _darkSurfaceRaised = Color(0xFF202224);
  static const _darkInk = Color(0xFFF6F2EA);
  static const _darkMuted = Color(0xFFA7A39C);
  static const _darkAccent = Color(0xFFE6BC45);

  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    var colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    if (brightness == Brightness.dark) {
      colorScheme = colorScheme.copyWith(
        primary: _darkAccent,
        onPrimary: const Color(0xFF211A06),
        primaryContainer: const Color(0xFF3A3015),
        onPrimaryContainer: const Color(0xFFF8D875),
        surface: _darkBackground,
        surfaceContainerLowest: const Color(0xFF08090A),
        surfaceContainerLow: _darkSurface,
        surfaceContainer: _darkSurface,
        surfaceContainerHigh: _darkSurfaceRaised,
        surfaceContainerHighest: const Color(0xFF2B2D31),
        onSurface: _darkInk,
        onSurfaceVariant: _darkMuted,
        outline: const Color(0xFF444648),
        outlineVariant: const Color(0xFF2B2D2F),
      );
    }

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(160, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          side: BorderSide(color: colorScheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant),
    );
  }
}
