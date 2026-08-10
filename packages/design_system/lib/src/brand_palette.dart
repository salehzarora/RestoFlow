import 'package:flutter/material.dart';

import 'tokens.dart';

/// RESTOFLOW-GLOBAL-VISUAL-V0 — the BRAND surface palette, as a theme extension.
///
/// Deliberately separate from [RestoflowSemanticColors]. That one carries
/// MEANING — success, warning, danger, info — and must survive any rebrand
/// untouched. This one carries IDENTITY: navy, orange, and the cool neutral
/// surfaces they sit on. Merging them would be the fastest route back to a
/// rebrand that silently turns a "synced" badge into a brand highlight.
///
/// Field names are semantic, never app names: KDS is not the only dark surface
/// and the Dashboard is not the only light one, so `surfaceDark` says what it is
/// rather than who uses it.
///
/// Both presets carry BOTH the light and dark values. A widget on a dark rail
/// inside a light app needs `surfaceDark` without switching theme brightness,
/// and a chart needs both grid inks to draw a dark tooltip over a light plot.
@immutable
class RestoflowBrandPalette extends ThemeExtension<RestoflowBrandPalette> {
  const RestoflowBrandPalette({
    required this.primaryNavy,
    required this.primaryNavyHover,
    required this.primaryNavyContainer,
    required this.accentOrange,
    required this.accentOrangeContainer,
    required this.canvasLight,
    required this.surfaceLight,
    required this.surfaceDark,
    required this.borderLight,
    required this.borderDark,
    required this.textPrimaryLight,
    required this.textSecondaryLight,
    required this.textPrimaryDark,
    required this.textSecondaryDark,
    required this.chartGridLight,
    required this.chartGridDark,
  });

  /// The brand primary. Buttons, selected segments, chart lines, rail active.
  final Color primaryNavy;

  /// Hover / pressed / deep brand text on white.
  final Color primaryNavyHover;

  /// Quiet brand tint — selection beds, hover washes, soft containers.
  final Color primaryNavyContainer;

  /// The brand ACCENT. Sparing by design: a highlight, never a second primary,
  /// and never a substitute for a semantic status colour.
  final Color accentOrange;

  /// Soft accent bed. Decorative — see the contrast note on [accentOrange].
  final Color accentOrangeContainer;

  /// Page background behind cards in light surfaces.
  final Color canvasLight;

  /// Card / sheet surface in light surfaces.
  final Color surfaceLight;

  /// Card / board surface on dark surfaces (KDS, dark rails).
  final Color surfaceDark;

  final Color borderLight;
  final Color borderDark;

  final Color textPrimaryLight;
  final Color textSecondaryLight;
  final Color textPrimaryDark;
  final Color textSecondaryDark;

  /// Chart gridlines / axis rules. Separate from [borderLight] because a grid
  /// must sit UNDER data without competing with a card edge drawn at full
  /// border weight.
  final Color chartGridLight;
  final Color chartGridDark;

  /// The light preset. Values are the frozen brand constants.
  static const light = RestoflowBrandPalette(
    primaryNavy: kRestoflowSeedColor,
    primaryNavyHover: kRestoflowNavyDeep,
    primaryNavyContainer: kRestoflowNavyContainer,
    accentOrange: Color(0xFFC2410C),
    accentOrangeContainer: Color(0xFFFFEDD5),
    canvasLight: kRestoflowCanvas,
    surfaceLight: kRestoflowSurface,
    surfaceDark: Color(0xFF0F2038),
    borderLight: kRestoflowHairline,
    borderDark: Color(0xFF223A5E),
    textPrimaryLight: kRestoflowInk,
    textSecondaryLight: kRestoflowInk2,
    textPrimaryDark: Color(0xFFE8EDF5),
    textSecondaryDark: Color(0xFF9AA7BC),
    chartGridLight: Color(0xFFEDF1F7),
    chartGridDark: Color(0xFF1E2F4B),
  );

  /// The dark preset. The brand accent brightens (an orange that reads on white
  /// is muddy on navy) and the neutral roles swap; the navy family itself does
  /// not move, because it IS the surface here.
  static const dark = RestoflowBrandPalette(
    primaryNavy: Color(0xFF7FA3DA),
    primaryNavyHover: Color(0xFF9CBAE8),
    primaryNavyContainer: Color(0xFF1B3A63),
    accentOrange: Color(0xFFFB923C),
    accentOrangeContainer: Color(0xFF431407),
    canvasLight: kRestoflowCanvas,
    surfaceLight: kRestoflowSurface,
    surfaceDark: Color(0xFF0F2038),
    borderLight: kRestoflowHairline,
    borderDark: Color(0xFF223A5E),
    textPrimaryLight: kRestoflowInk,
    textSecondaryLight: kRestoflowInk2,
    textPrimaryDark: Color(0xFFE8EDF5),
    textSecondaryDark: Color(0xFF9AA7BC),
    chartGridLight: Color(0xFFEDF1F7),
    chartGridDark: Color(0xFF1E2F4B),
  );

  /// The palette for [brightness].
  static RestoflowBrandPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// The palette from [context], falling back to the light preset so a widget
  /// used outside a RestoFlow theme still renders brand-correct rather than
  /// throwing.
  static RestoflowBrandPalette from(BuildContext context) =>
      Theme.of(context).extension<RestoflowBrandPalette>() ??
      of(Theme.of(context).brightness);

  @override
  RestoflowBrandPalette copyWith({
    Color? primaryNavy,
    Color? primaryNavyHover,
    Color? primaryNavyContainer,
    Color? accentOrange,
    Color? accentOrangeContainer,
    Color? canvasLight,
    Color? surfaceLight,
    Color? surfaceDark,
    Color? borderLight,
    Color? borderDark,
    Color? textPrimaryLight,
    Color? textSecondaryLight,
    Color? textPrimaryDark,
    Color? textSecondaryDark,
    Color? chartGridLight,
    Color? chartGridDark,
  }) => RestoflowBrandPalette(
    primaryNavy: primaryNavy ?? this.primaryNavy,
    primaryNavyHover: primaryNavyHover ?? this.primaryNavyHover,
    primaryNavyContainer: primaryNavyContainer ?? this.primaryNavyContainer,
    accentOrange: accentOrange ?? this.accentOrange,
    accentOrangeContainer: accentOrangeContainer ?? this.accentOrangeContainer,
    canvasLight: canvasLight ?? this.canvasLight,
    surfaceLight: surfaceLight ?? this.surfaceLight,
    surfaceDark: surfaceDark ?? this.surfaceDark,
    borderLight: borderLight ?? this.borderLight,
    borderDark: borderDark ?? this.borderDark,
    textPrimaryLight: textPrimaryLight ?? this.textPrimaryLight,
    textSecondaryLight: textSecondaryLight ?? this.textSecondaryLight,
    textPrimaryDark: textPrimaryDark ?? this.textPrimaryDark,
    textSecondaryDark: textSecondaryDark ?? this.textSecondaryDark,
    chartGridLight: chartGridLight ?? this.chartGridLight,
    chartGridDark: chartGridDark ?? this.chartGridDark,
  );

  @override
  RestoflowBrandPalette lerp(
    ThemeExtension<RestoflowBrandPalette>? other,
    double t,
  ) {
    if (other is! RestoflowBrandPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return RestoflowBrandPalette(
      primaryNavy: c(primaryNavy, other.primaryNavy),
      primaryNavyHover: c(primaryNavyHover, other.primaryNavyHover),
      primaryNavyContainer: c(primaryNavyContainer, other.primaryNavyContainer),
      accentOrange: c(accentOrange, other.accentOrange),
      accentOrangeContainer: c(
        accentOrangeContainer,
        other.accentOrangeContainer,
      ),
      canvasLight: c(canvasLight, other.canvasLight),
      surfaceLight: c(surfaceLight, other.surfaceLight),
      surfaceDark: c(surfaceDark, other.surfaceDark),
      borderLight: c(borderLight, other.borderLight),
      borderDark: c(borderDark, other.borderDark),
      textPrimaryLight: c(textPrimaryLight, other.textPrimaryLight),
      textSecondaryLight: c(textSecondaryLight, other.textSecondaryLight),
      textPrimaryDark: c(textPrimaryDark, other.textPrimaryDark),
      textSecondaryDark: c(textSecondaryDark, other.textSecondaryDark),
      chartGridLight: c(chartGridLight, other.chartGridLight),
      chartGridDark: c(chartGridDark, other.chartGridDark),
    );
  }
}
