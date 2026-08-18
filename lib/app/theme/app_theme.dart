import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _seed = Color(0xFFDAB34B);
  static const _darkBackground = Color(0xFF0D0F10);
  static const _darkSurface = Color(0xFF17191C);
  static const _darkSurfaceRaised = Color(0xFF202226);
  static const _darkInk = Color(0xFFF5F2EA);
  static const _darkMuted = Color(0xFFAAA69E);
  static const _darkAccent = Color(0xFFDAB34B);

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
        primaryContainer: const Color(0xFF41340E),
        onPrimaryContainer: const Color(0xFFFFE59A),
        surface: _darkBackground,
        surfaceContainerLowest: const Color(0xFF08090A),
        surfaceContainerLow: _darkSurface,
        surfaceContainer: _darkSurface,
        surfaceContainerHigh: _darkSurfaceRaised,
        surfaceContainerHighest: const Color(0xFF2B2D31),
        onSurface: _darkInk,
        onSurfaceVariant: _darkMuted,
        outline: const Color(0xFF46484D),
        outlineVariant: const Color(0xFF303237),
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
          borderRadius: BorderRadius.circular(22),
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
            borderRadius: BorderRadius.circular(16),
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
