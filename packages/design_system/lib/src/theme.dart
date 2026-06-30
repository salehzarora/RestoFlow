import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds the RestoFlow base [ThemeData].
///
/// RF-100 turns the former RF-011 shell into a real, seeded Material 3 theme:
/// a [ColorScheme] derived from [seedColor] plus consistent app-bar, button,
/// chip, and divider styling built from the shared [RestoflowSpacing] /
/// [RestoflowRadii] tokens. Backwards compatible — `restoflowBaseTheme()` with
/// no arguments still returns a valid theme.
///
/// Pass a [brightness] of [Brightness.dark] for a dark variant. Brand colours
/// are data-driven by [seedColor]; RTL/LTR remains handled by the localization
/// delegates (DECISION D-014), not the theme.
ThemeData? _cachedDefaultTheme;

ThemeData restoflowBaseTheme({
  Color seedColor = kRestoflowSeedColor,
  Brightness brightness = Brightness.light,
}) {
  // RF-140 perf: the DEFAULT light theme (used by all four apps' MaterialApp
  // `theme:`) is built ONCE and reused, so the `ColorScheme.fromSeed`
  // harmonization pass is not recomputed on every app rebuild (e.g. on each
  // locale switch). Non-default args still build a fresh theme.
  if (seedColor == kRestoflowSeedColor && brightness == Brightness.light) {
    return _cachedDefaultTheme ??= _buildRestoflowTheme(seedColor, brightness);
  }
  return _buildRestoflowTheme(seedColor, brightness);
}

ThemeData _buildRestoflowTheme(Color seedColor, Brightness brightness) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  );
  final base = ThemeData(colorScheme: colorScheme);

  final cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(RestoflowRadii.lg),
    side: BorderSide(color: colorScheme.outlineVariant),
  );
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(RestoflowRadii.md),
  );

  return base.copyWith(
    scaffoldBackgroundColor: colorScheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      surfaceTintColor: colorScheme.surfaceTint,
      elevation: 0,
      scrolledUnderElevation: 2,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: cardShape,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: buttonShape,
        padding: const EdgeInsets.symmetric(
          horizontal: RestoflowSpacing.lg,
          vertical: RestoflowSpacing.md,
        ),
        textStyle: base.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: buttonShape),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      ),
      side: BorderSide(color: colorScheme.outlineVariant),
      showCheckmark: false,
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
  );
}
