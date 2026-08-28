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

  static const canvas = Color(0xFF0B0D0E);
  static const gold = Color(0xFFE6BC45);
  static const softWhite = Color(0xFFF6F2EA);
  static const muted = Color(0xFFA7A39C);
  static const dock = Color(0xE6141617);

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
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(colorScheme),
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
          foregroundColor: const Color(0xFF211A06),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          side: BorderSide(color: colorScheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: const Color(0xFF181A1B),
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? _darkAccent
                : _darkMuted,
            size: 25,
          );
        }),
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme colors) => TextTheme(
    displayLarge: TextStyle(
      fontSize: 32,
      height: 1.25,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.64,
      color: colors.onSurface,
    ),
    headlineMedium: TextStyle(
      fontSize: 24,
      height: 1.33,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.24,
      color: colors.onSurface,
    ),
    bodyLarge: TextStyle(
      fontSize: 18,
      height: 1.55,
      fontWeight: FontWeight.w400,
      color: colors.onSurface,
    ),
    bodyMedium: TextStyle(
      fontSize: 16,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: colors.onSurface,
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      height: 1.43,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.28,
      color: colors.onSurface,
    ),
    labelSmall: TextStyle(
      fontSize: 12,
      height: 1.33,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.12,
      color: colors.onSurfaceVariant,
    ),
  );
}
