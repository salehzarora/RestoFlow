import 'media_profile.dart';
import 'print_document.dart';

/// PRINT-LAYOUT-001B — the ONE centralized, profile-aware typography config for
/// the thermal raster renderer.
///
/// It owns the per-role visual tokens for every [PrintLineStyle]: the font-size
/// MULTIPLIER (applied to [baseFontSize] then the profile font scale), the
/// CONCRETE paint weight, and the horizontal ALIGNMENT. Both the real dart:ui
/// renderer (which picks the font size / weight / alignment) and the pure
/// pagination height estimate read these SAME tokens, so a rendered page can
/// never drift from the height the planner reserved for it — the correctness
/// property PRINT-LAYOUT-001A established and 001B must preserve.
///
/// It is PROFILE-AWARE: the small 50×50 label uses a gentler [compact] hierarchy
/// (the same ordering, smaller steps) so the biggest headings still fit its
/// 384-dot width and the whole ticket needs fewer label pages; the continuous
/// 80mm roll and the 80×80 label use the full [standard] hierarchy. Geometry
/// (width / height / margins / fontScale / lineSpacing) still lives on
/// [MediaProfile] and is FROZEN — this only re-sizes / re-weights WITHIN that
/// envelope, so no media geometry changes.
///
/// All on-paper hierarchy comes from SIZE, not weight: the rasterizer collapses
/// every weight to the two concrete axes w400 / w700 (PILOT-PRINT-FIDELITY-001 —
/// synthetic w500 / w600 / w800 axes are never requested), which is why
/// [PrintFontWeight] has exactly two values and the size multipliers carry the
/// visual tiers.

/// The base (normal) glyph size in dots the renderer uses at 1:1.
const double kBaseReceiptFontSize = 22.0;

/// The renderer's built-in line-height multiplier when a profile does not
/// override it.
const double kBaseReceiptLineHeight = 1.3;

/// The CONCRETE paint weight for a styled line. Only two axes exist because the
/// rasterizer collapses every weight to w400 / w700 (PILOT-PRINT-FIDELITY-001);
/// hierarchy on paper therefore comes from SIZE, and weight is a clean
/// bold / regular switch.
enum PrintFontWeight { regular, bold }

/// The horizontal alignment role for a styled line. The raster renderer keys off
/// THIS (not the ESC/POS [PrintAlignment]) for on-device Arabic/Hebrew layout.
enum PrintTextAlignRole { start, center }

/// The two hierarchy densities. [standard] is the full hierarchy (continuous
/// 80mm roll + 80×80 label); [compact] is the gentler one for the small 50×50
/// label, where vertical room is scarce.
enum PrintTypographyDensity { standard, compact }

/// The centralized per-role typography tokens. Immutable; two canonical
/// instances ([standard], [compact]) cover every shipping media profile.
class PrintTypography {
  const PrintTypography({
    required this.density,
    this.baseFontSize = kBaseReceiptFontSize,
    this.lineHeight = kBaseReceiptLineHeight,
  });

  /// Which hierarchy tier this config renders.
  final PrintTypographyDensity density;

  /// Base (normal) glyph size in dots, before the per-role multiplier and the
  /// profile font scale.
  final double baseFontSize;

  /// Built-in line-height multiplier used when a profile does not override it.
  final double lineHeight;

  /// The full hierarchy — the continuous 80mm roll and the 80×80 label.
  static const PrintTypography standard = PrintTypography(
    density: PrintTypographyDensity.standard,
  );

  /// The gentler hierarchy for the small 50×50 label (same ordering, smaller
  /// steps) so headings still fit 384 dots and fewer label pages are needed.
  static const PrintTypography compact = PrintTypography(
    density: PrintTypographyDensity.compact,
  );

  /// Picks the hierarchy density for [profile]: [compact] for the small 50×50
  /// label, [standard] for every other profile (continuous 80mm, 80×80). Keyed
  /// by the profile's stable IDENTITY, never its (frozen) geometry.
  factory PrintTypography.forProfile(MediaProfile profile) =>
      profile.id == MediaProfileId.label50x50 ? compact : standard;

  bool get _compact => density == PrintTypographyDensity.compact;

  /// The per-role font-size MULTIPLIER (before the profile font scale). This is
  /// THE single source both the renderer and the pagination estimate read, so
  /// the two can never disagree. A heading is large, a modifier small, a
  /// separator a thin rule, a spacer a small blank gap.
  ///
  /// Hierarchy (standard): restaurant-name hero (headingLarge) > final total >
  /// secondary identifier (subheading) ≈ item name > body / meta / modifier >
  /// separator > spacer.
  double sizeMultiplier(PrintLineStyle style) => switch (style) {
    PrintLineStyle.headingLarge => _compact ? 1.4 : 1.7,
    // PRINT-LAYOUT-001C: the kitchen item is ~2 tiers above the receipt item
    // (1.25/1.15) yet still below the order-reference hero (1.7/1.4).
    PrintLineStyle.kitchenItem => _compact ? 1.3 : 1.5,
    PrintLineStyle.total => _compact ? 1.3 : 1.45,
    PrintLineStyle.subheading => _compact ? 1.15 : 1.3,
    PrintLineStyle.item => _compact ? 1.15 : 1.25,
    // PRINT-LAYOUT-001C: kitchen modifiers / preparation / notes — ~2 tiers
    // above the receipt sub (1.0/0.9), still below the kitchen item name.
    PrintLineStyle.kitchenModifier => _compact ? 1.1 : 1.25,
    PrintLineStyle.kitchenNote => _compact ? 1.1 : 1.25,
    PrintLineStyle.note => _compact ? 0.95 : 1.0,
    PrintLineStyle.centered => _compact ? 0.95 : 1.0,
    PrintLineStyle.normal => _compact ? 0.95 : 1.0,
    PrintLineStyle.sub => _compact ? 0.9 : 1.0,
    PrintLineStyle.separator => 0.85,
    PrintLineStyle.spacer => _compact ? 0.4 : 0.55,
  };

  /// The concrete paint weight for [style]: bold for the headings / item name /
  /// notes / total, regular for body / meta / modifiers / rules / spacers.
  PrintFontWeight weightFor(PrintLineStyle style) => switch (style) {
    PrintLineStyle.headingLarge ||
    PrintLineStyle.subheading ||
    PrintLineStyle.item ||
    PrintLineStyle.note ||
    PrintLineStyle.total ||
    PrintLineStyle.kitchenItem ||
    PrintLineStyle.kitchenNote => PrintFontWeight.bold,
    PrintLineStyle.centered ||
    PrintLineStyle.normal ||
    PrintLineStyle.sub ||
    PrintLineStyle.separator ||
    PrintLineStyle.spacer ||
    PrintLineStyle.kitchenModifier => PrintFontWeight.regular,
  };

  /// The alignment role for [style]: the headings and brand / secondary lines
  /// centre; item, total, body, modifier and note lines run from the start edge.
  PrintTextAlignRole alignFor(PrintLineStyle style) => switch (style) {
    PrintLineStyle.headingLarge ||
    PrintLineStyle.subheading ||
    PrintLineStyle.centered => PrintTextAlignRole.center,
    PrintLineStyle.item ||
    PrintLineStyle.note ||
    PrintLineStyle.total ||
    PrintLineStyle.normal ||
    PrintLineStyle.sub ||
    PrintLineStyle.separator ||
    PrintLineStyle.spacer ||
    PrintLineStyle.kitchenItem ||
    PrintLineStyle.kitchenModifier ||
    PrintLineStyle.kitchenNote => PrintTextAlignRole.start,
  };
}
