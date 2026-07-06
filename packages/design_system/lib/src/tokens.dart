import 'package:flutter/material.dart';

/// RestoFlow design tokens (RF-100, expanded by the design-polish sprint): the
/// shared scales every surface uses for consistent spacing, corner radius,
/// icon sizing, breakpoints, panel widths, motion, and brand colour.

/// The RestoFlow brand seed colour (a warm restaurant green). Used as the
/// `ColorScheme.fromSeed` seed by [restoflowBaseTheme].
const Color kRestoflowSeedColor = Color(0xFF1B7A52);

/// Warm-canvas neutrals (Dashboard "1c" / Warm-Bento direction). The dashboard
/// sits on a warm off-white canvas with a warm hairline instead of a cool grey,
/// and a three-step warm ink ramp for text. These are exact brand values used by
/// the gradient header, readiness strip, rank rows, and the light side rail; the
/// semantic status palette stays in [RestoflowSemanticColors].
const Color kRestoflowCanvas = Color(0xFFF6F3EC); // page background
const Color kRestoflowHairline = Color(0xFFECE5D8); // warm thin border
const Color kRestoflowInk = Color(0xFF17201B); // primary text
const Color kRestoflowInk2 = Color(0xFF5C665C); // secondary text
const Color kRestoflowInk3 = Color(0xFF9A9384); // muted text

/// Brand-green dark value (button hover / dark-on-white text on the gradient
/// header's white action button).
const Color kRestoflowBrandDark = Color(0xFF136343);

/// The 118° brand gradient used by the full-bleed [RestoflowGradientHeader] and
/// the side-rail logo tile: deep green-black → forest → brand green → a terracotta
/// corner pushed just past the frame. RTL-safe: begins at the directional
/// top-start and ends past the opposite side so it mirrors with the layout.
const LinearGradient kRestoflowBrandGradient = LinearGradient(
  begin: AlignmentDirectional.topStart,
  end: Alignment(-1.6, 1.0),
  colors: [
    Color(0xFF0F231A),
    Color(0xFF164E37),
    Color(0xFF1B7A52),
    Color(0xFFC2410C),
  ],
  stops: [0.0, 0.42, 0.70, 1.0],
);

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
/// tints. The shadow ink is the brand's green-black (`#10201A`) at low alpha,
/// so shadows read as the same material as the dark sidebar rather than a
/// neutral grey. Purely additive tokens — nothing consumes them implicitly.
abstract final class RestoflowShadows {
  /// Resting list items and quiet tiles.
  static const List<BoxShadow> xs = [
    BoxShadow(color: Color(0x0D10201A), offset: Offset(0, 1), blurRadius: 2),
  ];

  /// Standard cards on the tinted canvas.
  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x1210201A), offset: Offset(0, 1), blurRadius: 3),
    BoxShadow(color: Color(0x0A10201A), offset: Offset(0, 1), blurRadius: 2),
  ];

  /// Hover emphasis and popovers.
  static const List<BoxShadow> md = [
    BoxShadow(color: Color(0x1410201A), offset: Offset(0, 4), blurRadius: 14),
  ];

  /// Dialogs, sheets, and other top surfaces.
  static const List<BoxShadow> lg = [
    BoxShadow(color: Color(0x2410201A), offset: Offset(0, 12), blurRadius: 32),
  ];
}
