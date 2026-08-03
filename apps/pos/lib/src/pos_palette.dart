import 'package:flutter/widgets.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// POS-local warm surface tints (DESIGN-004 Warm/Bento handoff §4).
///
/// The core warm palette — canvas, hairline, ink ramp, brand green/dark,
/// terracotta accent, and the semantic status colours — already lives in
/// `packages/design_system` (`kRestoflowCanvas`, `kRestoflowInk*`,
/// `kRestoflowBrandDark`, `RestoflowSemanticColors`). These four are the extra
/// POS-only surface fills the handoff calls out that had no shared token yet.
/// Kept here (not in design_system) so the redesign stays scoped to `apps/pos`.

/// Inner surface for line cards / amount strips (a hair warmer than white).
const Color kPosInnerSurface = Color(0xFFFBF9F3);

/// Chip / segmented-track / neutral pill background.
const Color kPosChipBg = Color(0xFFF4EFE6);

/// Selected-option tint (paired with a 1.5px brand-green border).
const Color kPosSelectedTint = Color(0xFFF2FBF6);

/// Disabled control background (a CTA the cashier can't use yet).
const Color kPosDisabledBg = Color(0xFFE7E1D4);

/// The dark phone bottom-cart bar (== `kRestoflowInk`).
const Color kPosBottomBar = kRestoflowInk;

/// The warm terracotta brand accent + its container/text (handoff §4). These
/// match `RestoflowSemanticColors.light.accent/accentContainer/onAccentContainer`
/// exactly; kept as plain constants so widgets can use them without a theme
/// extension lookup (safe in bare test themes).
const Color kPosTerracotta = Color(0xFFC2410C);
const Color kPosTerracottaContainer = Color(0xFFFFEDD5);
const Color kPosTerracottaText = Color(0xFF7C2D12);

/// POS-VISUAL-REDESIGN-PHASE-1-007 — the three warm surface values and the
/// muted body ink the Phase-1 spec adds (§10). POS-local by design: Step 1 must
/// not touch `packages/design_system`.

/// Input / search-field border — a hair darker than the hairline so a FILLED
/// field still reads as interactive on a warm fill.
const Color kPosInputBorder = Color(0xFFEAE2D3);

/// The quiet count-badge fill behind a category chip's number.
const Color kPosCountBadgeBg = Color(0xFFE7DFCE);

/// Body ink between ink2 and ink3 — product descriptions.
const Color kPosMutedBodyInk = Color(0xFF7A8479);

/// Card / cart-line rest elevation (spec §7 "e1"). One layer, not two: the
/// second layer of `RestoflowShadows.sm` was invisible at card size and doubled
/// the paint cost across ~19 cards.
const List<BoxShadow> kPosCardShadow = [
  BoxShadow(color: Color(0x0D10201A), offset: Offset(0, 1), blurRadius: 2),
];

/// The menu deck's downward shadow (spec §7 "deck").
const List<BoxShadow> kPosDeckShadow = [
  BoxShadow(color: Color(0x0A10201A), offset: Offset(0, 2), blurRadius: 6),
];

/// The SELECTED category chip's brand shadow (spec §7 "brand-s") — softer than
/// [kPosGreenGlow]; the selected chip is the only chip carrying elevation.
const List<BoxShadow> kPosChipSelectedShadow = [
  BoxShadow(color: Color(0x471B7A52), offset: Offset(0, 3), blurRadius: 10),
];

/// Product-card corner radius (spec §5 — the biggest object on screen).
const double kPosCardRadius = 14;

/// The green-CTA glow used on the primary add / send buttons.
const List<BoxShadow> kPosGreenGlow = [
  BoxShadow(color: Color(0x591B7A52), offset: Offset(0, 6), blurRadius: 16),
];

/// The responsive layout mode of the POS cashier screen, chosen from the
/// ACTUAL available width (and orientation) via [posLayoutModeFor] — never from
/// the platform. Keeps `RestoflowBreakpoints.posTwoPane` (820) as the phone
/// cutoff so the existing wide-viewport widget tests still see two panes.
enum PosLayoutMode {
  /// >= 1360: menu pane + 400px side cart, 5 product columns.
  desktop,

  /// 1100-1359: menu pane + 360px side cart, 4 product columns.
  tablet,

  /// 900-1099: menu pane + 340px side cart, 3 product columns.
  smallTablet,

  /// 820-899: menu pane + 320px side cart, 3 product columns.
  narrowTablet,

  /// Short or narrow LANDSCAPE (1024x600): 320px side cart, 3 columns and the
  /// tighter grid paddings.
  compactLandscape,

  /// Menu full-width + a dark bottom bar and a slide-up cart sheet.
  phone,
}

/// POS-VISUAL-REDESIGN-PHASE-1-007 — the approved product-column count per
/// mode (spec §3).
///
/// This replaces a max-cross-axis-extent formula that could not express the
/// approved layout at all: a single 230px extent yields 4 columns at BOTH 1440
/// and 1280, so desktop could never reach 5 while the tablet stayed at 4.
/// 5 columns are deliberately NOT forced at 1280 — a 213px cell keeps the photo
/// band 160px tall, and five 168px cells would cost more legibility than the
/// extra column buys.
int posMenuColumnsFor(PosLayoutMode mode) => switch (mode) {
  PosLayoutMode.desktop => 5,
  PosLayoutMode.tablet => 4,
  PosLayoutMode.smallTablet => 3,
  PosLayoutMode.narrowTablet => 3,
  PosLayoutMode.compactLandscape => 3,
  PosLayoutMode.phone => 2,
};

/// At or below this height a LANDSCAPE viewport is compact however wide it is —
/// this is what puts 1024x600 in [PosLayoutMode.compactLandscape] while
/// 1024x768 stays [PosLayoutMode.smallTablet].
const double kPosCompactHeight = 640;

/// Side-cart width for a two-pane [mode]; 0 for [PosLayoutMode.phone].
double posCartWidthFor(PosLayoutMode mode) => switch (mode) {
  PosLayoutMode.desktop => 400,
  PosLayoutMode.tablet => 360,
  PosLayoutMode.smallTablet => 340,
  PosLayoutMode.narrowTablet => 320,
  PosLayoutMode.compactLandscape => 320,
  PosLayoutMode.phone => 0,
};

/// Chooses the [PosLayoutMode] from the available [width]/[height]
/// (POS-VISUAL-REDESIGN-PHASE-1-007, spec §3).
///
/// - landscape AND `>= 700` wide AND (narrower than 820 OR no taller than
///   [kPosCompactHeight]) → compact landscape (side cart 320)
/// - `>= 1360` → desktop (400) · `1100..1359` → tablet (360)
/// - `900..1099` → small tablet (340) · `820..899` → narrow tablet (320)
/// - otherwise → phone (bottom bar + slide-up sheet)
///
/// The compact test runs FIRST and on height as well as width, because a short
/// landscape tablet (1024x600) needs the compact paddings even though its width
/// alone would read as a small tablet. It keeps the existing **700** floor, so a
/// small landscape phone still gets the bottom bar rather than a 320px cart
/// eating half its screen. The 820 portrait cutoff is unchanged.
PosLayoutMode posLayoutModeFor({
  required double width,
  required double height,
}) {
  final landscape = width > height;
  if (landscape &&
      width >= 700 &&
      (width < RestoflowBreakpoints.posTwoPane ||
          height <= kPosCompactHeight)) {
    return PosLayoutMode.compactLandscape;
  }
  if (width >= 1360) return PosLayoutMode.desktop;
  if (width >= 1100) return PosLayoutMode.tablet;
  if (width >= 900) return PosLayoutMode.smallTablet;
  if (width >= RestoflowBreakpoints.posTwoPane) {
    return PosLayoutMode.narrowTablet;
  }
  return PosLayoutMode.phone;
}

/// PSC-001A: below this width the POS app bar goes COMPACT — the textual
/// title hides (the brand tile stays) and the outbox indicator collapses to
/// its icon (tooltip + full semantics retained), so the five operational
/// actions (ready bell, orders, outbox, language, device menu) always fit
/// without a RenderFlex overflow on narrow phones. Chosen from real 320/360/
/// 390 widget-test evidence, not taste.
const double kPosCompactAppBarWidth = 480;
