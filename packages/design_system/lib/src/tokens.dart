import 'package:flutter/material.dart';

/// RestoFlow design tokens (RF-100, expanded by the design-polish sprint): the
/// shared scales every surface uses for consistent spacing, corner radius,
/// icon sizing, breakpoints, panel widths, motion, and brand colour.

/// RESTOFLOW-GLOBAL-VISUAL-V0 — the brand identity is NAVY / WHITE / ORANGE, and
/// it is deliberately global: Dashboard, POS, Admin and KDS all inherit it.
///
/// These constants are RE-VALUED IN PLACE rather than added alongside the old
/// warm-green set, because the owner wants every surface to move together. The
/// names stay because they are consumed in ~40 files across four apps and a
/// rename would bury the colour change in unrelated churn; the one exception is
/// [kRestoflowSeedColor], whose "seed" meaning is unchanged.
///
/// SEMANTIC STATUS COLOURS ARE NOT PART OF THIS. Success stays green, danger
/// red, warning amber, info blue — they carry meaning, not identity, and live in
/// [RestoflowSemanticColors].

/// The brand seed. Navy is the primary; [ColorScheme.fromSeed] derives the rest
/// and the theme pins the exact primary roles back on top.
const Color kRestoflowSeedColor = Color(0xFF16335E);

/// Navy deep — hover/pressed and dark-on-white text on brand surfaces.
const Color kRestoflowNavyDeep = Color(0xFF0F2547);

/// Navy container — quiet brand tint (selection, hover wash, rail active bed).
const Color kRestoflowNavyContainer = Color(0xFFE9EEF6);

/// Cool light neutrals. The canvas is a near-white with a hint of blue so white
/// cards read as raised against it, with a cool hairline and a three-step cool
/// ink ramp for text.
const Color kRestoflowCanvas = Color(0xFFF7F9FC); // page background
const Color kRestoflowSurface = Color(0xFFFFFFFF); // card / sheet surface
const Color kRestoflowHairline = Color(0xFFE4E9F0); // cool thin border
const Color kRestoflowInk = Color(0xFF101828); // primary text
const Color kRestoflowInk2 = Color(0xFF5B6472); // secondary text
const Color kRestoflowInk3 = Color(0xFF667085); // muted text

/// NOTE on the muted step: it is DARKER than a conventional grey-400 on purpose.
/// This token is used for real `bodySmall` text in ~33 places, and the previous
/// warm value (#9A9384 on #F6F3EC) scored 2.75:1 — below AA. A literal cool
/// translation (#98A2B3) would have been 2.44:1, i.e. worse. #667085 reads as
/// clearly muted next to the primary and secondary inks while clearing AA at
/// 4.72:1, so the rebrand fixes an inherited contrast failure instead of
/// carrying it forward.

/// Brand dark value (button hover / dark-on-white text on brand surfaces).
/// Kept under its original name; the value is now navy deep.
const Color kRestoflowBrandDark = kRestoflowNavyDeep;

/// The 118° brand gradient used by the side-rail logo tile (and the legacy
/// [RestoflowGradientHeader]): navy-black → navy → brand navy → a restrained
/// orange corner pushed just past the frame. RTL-safe: begins at the directional
/// top-start and ends past the opposite side so it mirrors with the layout.
///
/// The orange endpoint is deliberately the LAST stop and sits mostly outside the
/// frame, so it reads as a warm edge rather than a second background hue.
const LinearGradient kRestoflowBrandGradient = LinearGradient(
  begin: AlignmentDirectional.topStart,
  end: Alignment(-1.6, 1.0),
  colors: [
    Color(0xFF0B1526),
    Color(0xFF0F2547),
    Color(0xFF16335E),
    Color(0xFFC2410C),
  ],
  stops: [0.0, 0.42, 0.70, 1.0],
);

/// The ink every elevation tier tints with — the brand's navy-black. Exposed so
/// a surface that needs a one-off shadow tints with the same material.
const Color kRestoflowShadowInk = Color(0xFF0B1526);

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
/// tints. The shadow ink is the brand's navy-black ([kRestoflowShadowInk],
/// `#0B1526`) at low alpha, so shadows read as the same material as the dark
/// rail rather than a neutral grey. Purely additive — nothing consumes them
/// implicitly.
abstract final class RestoflowShadows {
  /// Resting list items and quiet tiles.
  static const List<BoxShadow> xs = [
    BoxShadow(color: Color(0x0D0B1526), offset: Offset(0, 1), blurRadius: 2),
  ];

  /// Standard cards on the tinted canvas.
  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x120B1526), offset: Offset(0, 1), blurRadius: 3),
    BoxShadow(color: Color(0x0A0B1526), offset: Offset(0, 1), blurRadius: 2),
  ];

  /// Hover emphasis and popovers.
  static const List<BoxShadow> md = [
    BoxShadow(color: Color(0x140B1526), offset: Offset(0, 4), blurRadius: 14),
  ];

  /// Dialogs, sheets, and other top surfaces.
  static const List<BoxShadow> lg = [
    BoxShadow(color: Color(0x240B1526), offset: Offset(0, 12), blurRadius: 32),
  ];
}
