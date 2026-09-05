import 'package:flutter/material.dart';

/// RestoFlow design tokens (RF-100, expanded by the design-polish sprint): the
/// shared scales every surface uses for consistent spacing, corner radius,
/// icon sizing, breakpoints, panel widths, motion, and brand colour.

// ─────────────────────────────────────────────────────────────────────────────
// BIZBOT OFFICIAL BRAND PALETTE (identity board, 2026-09-05)
// ─────────────────────────────────────────────────────────────────────────────
//
// Four official colours. They are the platform identity — never a merchant or
// device theme (those stay tenant-owned), and never a semantic status colour
// (success/warning/danger/info live in `RestoflowSemanticColors` and carry
// meaning, not identity).
//
// The legacy `kRestoflow*` names below are RE-VALUED IN PLACE onto this palette
// (exactly as RESTOFLOW-GLOBAL-VISUAL-V0 did for navy/orange): they are consumed
// across four apps and renaming them would bury the identity change in churn.
// New code should prefer the semantic `BizbotBrand` names.

/// Charcoal — FOUNDATION. Primary text ink, dark chrome, the high-emphasis CTA.
const Color kBizbotFoundation = Color(0xFF1F2937);

/// Emerald — PRIMARY. Buttons, selection, focus, progress, links, active rail.
const Color kBizbotPrimary = Color(0xFF059669);

/// Mint — HIGHLIGHT. Selection beds, hover washes, highlight badges; the
/// primary tone on dark surfaces.
const Color kBizbotHighlight = Color(0xFFA7F3D0);

/// Light Neutral — SUPPORT. The page canvas and icon/avatar tile ground.
const Color kBizbotSurface = Color(0xFFF4F6F5);

/// Semantic names for the official palette. Values are frozen; if the owner
/// ever ships a revised board, change them HERE and nowhere else.
abstract final class BizbotBrand {
  static const Color foundation = kBizbotFoundation;
  static const Color primary = kBizbotPrimary;
  static const Color highlight = kBizbotHighlight;
  static const Color surface = kBizbotSurface;

  /// Alias of [surface] under the board's own name.
  static const Color lightNeutral = kBizbotSurface;

  /// The public brand token — always Latin uppercase, never localized.
  static const String name = 'BIZBOT';

  /// The brand-board marketing line. For landing / marketing / presentation
  /// surfaces only — the compact in-app tagline stays the localized
  /// `authBrandTagline` ("POS & Operations").
  static const String marketingTagline = 'SMART POS. SMOOTH OPERATIONS.';
}

// Derived FUNCTIONAL shades. These are tone steps of the official colours used
// where a fill needs a hover/pressed partner or where text on a light surface
// needs more contrast than the raw primary offers (emerald on white is 3.77:1 —
// fine for large text and controls, short of AA for body copy). They are not a
// fifth and sixth brand colour and must not be used decoratively.

/// Emerald, one step deeper (pressed / hover / deep brand text on light).
/// 5.48:1 on white, 5.05:1 on Light Neutral.
const Color kBizbotPrimaryDeep = Color(0xFF047857);

/// Charcoal-black — the dark canvas behind charcoal cards and the shadow ink.
const Color kBizbotFoundationDeep = Color(0xFF111827);

/// Charcoal, one step lighter — hairlines and quiet beds on dark surfaces.
const Color kBizbotFoundationSoft = Color(0xFF374151);

/// Mint at ~50% over white — the quiet hover / selection wash on light
/// surfaces where full Mint would shout.
const Color kBizbotHighlightSoft = Color(0xFFD1FAE5);

/// The brand seed. Emerald is the primary; [ColorScheme.fromSeed] derives the
/// rest and the theme pins the exact primary roles back on top.
const Color kRestoflowSeedColor = kBizbotPrimary;

/// Deep primary — hover/pressed and deep brand text on light brand surfaces.
/// (Name kept from the navy era; value is now [kBizbotPrimaryDeep].)
const Color kRestoflowNavyDeep = kBizbotPrimaryDeep;

/// Quiet brand tint (selection, hover wash, rail active bed).
/// (Name kept from the navy era; value is now [kBizbotHighlightSoft].)
const Color kRestoflowNavyContainer = kBizbotHighlightSoft;

/// Light neutrals. The canvas is the official Light Neutral so white cards read
/// as raised against it, with a neutral hairline and a three-step charcoal ink
/// ramp for text.
const Color kRestoflowCanvas = kBizbotSurface; // page background
const Color kRestoflowSurface = Color(0xFFFFFFFF); // card / sheet surface
const Color kRestoflowHairline = Color(0xFFE3E8E5); // neutral thin border
const Color kRestoflowInk = kBizbotFoundation; // primary text (Charcoal)
const Color kRestoflowInk2 = Color(0xFF4B5563); // secondary text
const Color kRestoflowInk3 = Color(0xFF626D79); // muted text

/// NOTE on the muted step: it is DARKER than a conventional grey-400 on purpose.
/// This token is used for real `bodySmall` text in ~33 places; #626D79 reads as
/// clearly muted next to the primary and secondary inks while clearing AA on
/// both the white card (5.27:1) and the Light Neutral canvas (4.86:1).

/// Brand dark value (button hover / dark-on-white text on brand surfaces).
/// Kept under its original name; the value is now the deep emerald.
const Color kRestoflowBrandDark = kBizbotPrimaryDeep;

/// The 118° brand gradient used by the legacy [RestoflowGradientHeader]:
/// charcoal-black → charcoal → emerald → a mint corner pushed just past the
/// frame. RTL-safe: begins at the directional top-start and ends past the
/// opposite side so it mirrors with the layout.
///
/// The mint endpoint is deliberately the LAST stop and sits mostly outside the
/// frame, so it reads as a light edge rather than a second background hue.
const LinearGradient kRestoflowBrandGradient = LinearGradient(
  begin: AlignmentDirectional.topStart,
  end: Alignment(-1.6, 1.0),
  colors: [
    kBizbotFoundationDeep,
    kBizbotFoundation,
    kBizbotPrimary,
    kBizbotHighlight,
  ],
  stops: [0.0, 0.42, 0.70, 1.0],
);

/// The ink every elevation tier tints with — the brand's charcoal-black.
/// Exposed so a surface that needs a one-off shadow tints with the same
/// material.
const Color kRestoflowShadowInk = kBizbotFoundationDeep;

/// 4-point spacing scale (logical pixels).
abstract final class RestoflowSpacing {
  /// Hairline gap (title-to-subtitle inside a tile).
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner-radius scale (logical pixels).
abstract final class RestoflowRadii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;

  /// Prominent surfaces: dialogs, sheets, hero cards.
  static const double xl = 20;

  /// Fully rounded (pill / circle) radius.
  static const double pill = 999;
}

/// Icon-size scale (logical pixels). Use these instead of literal `size:`
/// values so icons stay consistent across surfaces.
abstract final class RestoflowIconSizes {
  /// Inline pill/meta icons.
  static const double xs = 14;

  /// Compact chrome (footnotes, secondary rows).
  static const double sm = 16;

  /// Default control icons (buttons, list leading).
  static const double md = 20;

  /// Emphasis icons (headers, success/failed marks).
  static const double lg = 24;

  /// Large state/illustration icons.
  static const double xl = 40;

  /// Hero/empty-state icons inside a circle container.
  static const double hero = 64;
}

/// Shared responsive breakpoints (logical pixels). The values are the ones the
/// widget-test corpus was written against — keep behaviour at the tested
/// viewports identical when consuming these.
abstract final class RestoflowBreakpoints {
  /// Below this: single-column KPI grids and stacked compact layouts.
  static const double compact = 560;

  /// POS menu/cart two-pane split (kept below the 1100px narrowest wide POS
  /// test viewport).
  static const double posTwoPane = 820;

  /// The shared wide breakpoint (dashboard shell/reports, KDS boards, menu
  /// builder, admin overview).
  static const double wide = 900;
}

/// Standard fixed panel widths (logical pixels).
abstract final class RestoflowPanelWidths {
  /// KDS board column.
  static const double kdsColumn = 340;

  /// Menu builder master (category) pane.
  static const double masterPane = 360;

  /// POS cart side panel.
  static const double cartPanel = 400;

  /// Standard dialog / centered auth card.
  static const double dialog = 440;

  /// Wider single-purpose forms (PIN login).
  static const double formPanel = 520;

  /// Help/how-to pages (unconfigured, sign-in unavailable).
  static const double helpPanel = 560;

  /// Max width of empty/error state bodies.
  static const double statePanel = 380;
}

/// Motion durations for the subtle-interaction layer. All animations built on
/// these must be FINITE (test harnesses `pumpAndSettle`).
abstract final class RestoflowDurations {
  /// Micro feedback (hover, pressed, selection tint).
  static const Duration fast = Duration(milliseconds: 120);

  /// Standard implicit transitions (state swaps, container moves).
  static const Duration base = Duration(milliseconds: 200);

  /// Larger reveals (panels, sheets).
  static const Duration slow = Duration(milliseconds: 300);
}

/// Soft elevation tiers (design language v2, DESIGN-001).
///
/// The product keeps its hairline-outlined flat cards; these shadows ADD depth
/// selectively (hover/popover/dialog moments) instead of Material elevation
/// tints. The shadow ink is the brand's charcoal-black ([kRestoflowShadowInk],
/// `#111827`) at low alpha, so shadows read as the same material as the dark
/// chrome rather than a neutral grey. Purely additive — nothing consumes them
/// implicitly.
abstract final class RestoflowShadows {
  /// Resting list items and quiet tiles.
  static const List<BoxShadow> xs = [
    BoxShadow(color: Color(0x0D111827), offset: Offset(0, 1), blurRadius: 2),
  ];

  /// Standard cards on the tinted canvas.
  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x12111827), offset: Offset(0, 1), blurRadius: 3),
    BoxShadow(color: Color(0x0A111827), offset: Offset(0, 1), blurRadius: 2),
  ];

  /// Hover emphasis and popovers.
  static const List<BoxShadow> md = [
    BoxShadow(color: Color(0x14111827), offset: Offset(0, 4), blurRadius: 14),
  ];

  /// Dialogs, sheets, and other top surfaces.
  static const List<BoxShadow> lg = [
    BoxShadow(color: Color(0x24111827), offset: Offset(0, 12), blurRadius: 32),
  ];
}
