import 'package:flutter/material.dart';

import 'tokens.dart';

/// The BRAND surface palette, as a theme extension.
///
/// BIZBOT OFFICIAL IDENTITY (2026-09-05): the values are the official palette —
/// Charcoal `#1F2937` (foundation), Emerald `#059669` (primary), Mint `#A7F3D0`
/// (highlight), Light Neutral `#F4F6F5` (support) — plus the derived functional
/// shades in tokens.dart. The FIELD NAMES still say navy/orange: they are read
/// in ~15 files across four apps and were kept (exactly as V0 kept the warm
/// names) so the identity change is not buried in a rename. Read them as roles:
///
///   primaryNavy          → the brand PRIMARY fill   (Emerald; Mint on dark)
///   primaryNavyHover     → its pressed/hover partner
///   primaryNavyContainer → the brand selection bed  (Mint; deep emerald on dark)
///   accentOrange         → the high-emphasis ACCENT: the one CTA per view, the
///                          active marker, the attention hue (Charcoal on light,
///                          Light Neutral on dark — the foundation colour
///                          inverted per surface, so it is always legible)
///   accentOrangeContainer→ the accent's soft bed    (Mint; charcoal-soft on dark)
///
/// Deliberately separate from [RestoflowSemanticColors]. That one carries
/// MEANING — success, warning, danger, info — and must survive any rebrand
/// untouched. This one carries IDENTITY. Merging them would be the fastest
/// route back to a rebrand that silently turns a "synced" badge into a brand
/// highlight.
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

  /// The brand primary (Emerald). Buttons, selected segments, chart lines,
  /// rail active. Mint on dark surfaces.
  final Color primaryNavy;

  /// Hover / pressed / deep brand text on white (deep emerald).
  final Color primaryNavyHover;

  /// Brand selection bed — selected segments, nav indicator (Mint).
  final Color primaryNavyContainer;

  /// The brand ACCENT (Charcoal on light, Light Neutral on dark). Sparing by
  /// design: the one CTA per view and the attention marker, never a second
  /// primary, and never a substitute for a semantic status colour.
  final Color accentOrange;

  /// Soft accent bed (Mint on light). Decorative — charcoal ink sits on it at
  /// 11.4:1.
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

  /// The light preset. Values are the official BIZBOT constants.
  static const light = RestoflowBrandPalette(
    primaryNavy: kBizbotPrimary,
    primaryNavyHover: kBizbotPrimaryDeep,
    primaryNavyContainer: kBizbotHighlight,
    accentOrange: kBizbotFoundation,
    accentOrangeContainer: kBizbotHighlight,
    canvasLight: kRestoflowCanvas,
    surfaceLight: kRestoflowSurface,
    surfaceDark: kBizbotFoundation,
    borderLight: kRestoflowHairline,
    borderDark: kBizbotFoundationSoft,
    textPrimaryLight: kRestoflowInk,
    textSecondaryLight: kRestoflowInk2,
    textPrimaryDark: kBizbotSurface,
    textSecondaryDark: Color(0xFF9CA3AF),
    chartGridLight: Color(0xFFEBF0ED),
    chartGridDark: kBizbotFoundationSoft,
  );

  /// The dark preset. On charcoal surfaces the primary is the light Mint tone
  /// (charcoal ink on it, 11.4:1) with a deep-emerald bed, and the accent is
  /// the Light Neutral — the foundation colour inverted — so "the one CTA" and
  /// the attention marker stay the brightest thing on a dark board. The
  /// neutral roles carry both values and do not move.
  static const dark = RestoflowBrandPalette(
    primaryNavy: kBizbotHighlight,
    primaryNavyHover: kBizbotHighlightSoft,
    primaryNavyContainer: kBizbotPrimaryDeep,
    accentOrange: kBizbotSurface,
    accentOrangeContainer: kBizbotFoundationSoft,
    canvasLight: kRestoflowCanvas,
    surfaceLight: kRestoflowSurface,
    surfaceDark: kBizbotFoundation,
    borderLight: kRestoflowHairline,
    borderDark: kBizbotFoundationSoft,
    textPrimaryLight: kRestoflowInk,
    textSecondaryLight: kRestoflowInk2,
    textPrimaryDark: kBizbotSurface,
    textSecondaryDark: Color(0xFF9CA3AF),
    chartGridLight: Color(0xFFEBF0ED),
    chartGridDark: kBizbotFoundationSoft,
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
