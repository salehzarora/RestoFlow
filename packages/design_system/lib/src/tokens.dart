import 'package:flutter/material.dart';

/// RestoFlow design tokens (RF-100, expanded by the design-polish sprint): the
/// shared scales every surface uses for consistent spacing, corner radius,
/// icon sizing, breakpoints, panel widths, motion, and brand colour.

/// The RestoFlow brand seed colour (a warm restaurant green). Used as the
/// `ColorScheme.fromSeed` seed by [restoflowBaseTheme].
const Color kRestoflowSeedColor = Color(0xFF1B7A52);

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
