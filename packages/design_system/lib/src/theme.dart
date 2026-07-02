import 'package:flutter/material.dart';

import 'semantic_colors.dart';
import 'tokens.dart';

/// Builds the RestoFlow base [ThemeData].
///
/// RF-100 turned the former RF-011 shell into a real, seeded Material 3 theme;
/// the design-polish sprint widens it into full product chrome: a typography
/// scale with baked-in weights, themed inputs/dialogs/sheets/navigation/
/// snackbars/menus, ≥44dp button targets, and the [RestoflowSemanticColors]
/// extension carrying the TRUE green/amber/red/blue status palette, the warm
/// restaurant accent, and the dark-sidebar colours. Backwards compatible —
/// `restoflowBaseTheme()` with no arguments still returns a valid light theme.
///
/// Pass a [brightness] of [Brightness.dark] for the dark variant (the KDS
/// kitchen board uses it). Brand colours are data-driven by [seedColor];
/// RTL/LTR remains handled by the localization delegates (DECISION D-014),
/// not the theme.
ThemeData? _cachedDefaultTheme;

ThemeData restoflowBaseTheme({
  Color seedColor = kRestoflowSeedColor,
  Brightness brightness = Brightness.light,
}) {
  // RF-140 perf: the DEFAULT light theme (used by the apps' MaterialApp
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
  final semantic = RestoflowSemanticColors.of(brightness);

  // Typography: bake the product's weights into the scale so screens stop
  // re-declaring `fontWeight:` per Text. Arabic-friendly: no letter-spacing
  // anywhere (spacing breaks Arabic glyph joining), system font stack with
  // fallbacks that render ar/he well on Windows/web.
  const fontFallbacks = <String>['Segoe UI', 'Tahoma', 'Arial', 'sans-serif'];
  TextStyle? weighted(TextStyle? style, FontWeight weight) => style?.copyWith(
    fontWeight: weight,
    letterSpacing: 0,
    fontFamilyFallback: fontFallbacks,
  );
  final textTheme = base.textTheme
      .copyWith(
        headlineSmall: weighted(base.textTheme.headlineSmall, FontWeight.w800),
        titleLarge: weighted(base.textTheme.titleLarge, FontWeight.w700),
        titleMedium: weighted(base.textTheme.titleMedium, FontWeight.w600),
        titleSmall: weighted(base.textTheme.titleSmall, FontWeight.w600),
        labelLarge: weighted(base.textTheme.labelLarge, FontWeight.w600),
      )
      .apply(fontFamilyFallback: fontFallbacks);

  final cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(RestoflowRadii.lg),
    side: BorderSide(color: colorScheme.outlineVariant),
  );
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(RestoflowRadii.md),
  );
  // Comfortable touch-first minimum for all standard buttons (POS/KDS action
  // buttons go bigger via RestoflowButtonStyles.big).
  const buttonMinSize = Size(64, 44);

  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[semantic],
    textTheme: textTheme,
    scaffoldBackgroundColor: colorScheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      surfaceTintColor: colorScheme.surfaceTint,
      elevation: 0,
      scrolledUnderElevation: 2,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(
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
        minimumSize: buttonMinSize,
        padding: const EdgeInsets.symmetric(
          horizontal: RestoflowSpacing.lg,
          vertical: RestoflowSpacing.md,
        ),
        textStyle: textTheme.titleSmall,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: buttonShape,
        minimumSize: buttonMinSize,
        padding: const EdgeInsets.symmetric(
          horizontal: RestoflowSpacing.lg,
          vertical: RestoflowSpacing.md,
        ),
        textStyle: textTheme.titleSmall,
        side: BorderSide(color: colorScheme.outline),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: buttonShape,
        minimumSize: buttonMinSize,
        textStyle: textTheme.titleSmall,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: buttonShape,
        textStyle: textTheme.titleSmall,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerLowest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        borderSide: BorderSide(color: colorScheme.error, width: 2),
      ),
    ),
    dialogTheme: DialogThemeData(
      elevation: 3,
      surfaceTintColor: Colors.transparent,
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.xl),
      ),
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: colorScheme.onSurface,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      surfaceTintColor: Colors.transparent,
      backgroundColor: colorScheme.surface,
      modalBackgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(RestoflowRadii.xl),
        ),
      ),
      dragHandleColor: colorScheme.outlineVariant,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colorScheme.surfaceContainer,
      indicatorColor: colorScheme.primaryContainer,
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
      iconColor: colorScheme.onSurfaceVariant,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      elevation: 3,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: buttonShape,
        side: BorderSide(color: colorScheme.outlineVariant),
        selectedBackgroundColor: colorScheme.primaryContainer,
        selectedForegroundColor: colorScheme.onPrimaryContainer,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.lg),
      ),
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
