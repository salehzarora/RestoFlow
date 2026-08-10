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
const Color kPosInnerSurface = Color(0xFFFAFBFD);

/// Chip / segmented-track / neutral pill background.
const Color kPosChipBg = Color(0xFFEDF1F7);

/// Selected-option tint (paired with a 1.5px brand-green border).
const Color kPosSelectedTint = kRestoflowNavyContainer;

/// Disabled control background (a CTA the cashier can't use yet).
const Color kPosDisabledBg = Color(0xFFE3E8EF);

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
const Color kPosInputBorder = Color(0xFFDDE3EC);

/// The quiet count-badge fill behind a category chip's number.
const Color kPosCountBadgeBg = Color(0xFFE3E8EF);

/// Body ink between ink2 and ink3 — product descriptions.
const Color kPosMutedBodyInk = Color(0xFF616B7B);

/// Card / cart-line rest elevation (spec §7 "e1"). One layer, not two: the
/// second layer of `RestoflowShadows.sm` was invisible at card size and doubled
/// the paint cost across ~19 cards.
const List<BoxShadow> kPosCardShadow = [
  BoxShadow(color: Color(0x0D0B1526), offset: Offset(0, 1), blurRadius: 2),
];

/// The menu deck's downward shadow (spec §7 "deck").
const List<BoxShadow> kPosDeckShadow = [
  BoxShadow(color: Color(0x0A0B1526), offset: Offset(0, 2), blurRadius: 6),
];

/// The SELECTED category chip's brand shadow (spec §7 "brand-s") — softer than
/// [kPosPrimaryGlow]; the selected chip is the only chip carrying elevation.
const List<BoxShadow> kPosChipSelectedShadow = [
  BoxShadow(color: Color(0x4716335E), offset: Offset(0, 3), blurRadius: 10),
];

/// Product-card corner radius (spec §5 — the biggest object on screen).
const double kPosCardRadius = 14;

/// POS-VISUAL-REDESIGN-PHASE-1-007 Step 2 — the cart's operational plane.
///
/// One dark ink block heads the cart and replaces four full-width dividers as
/// the separator, so the white body below it reads as the live order. Every
/// on-dark pair below is contrast-checked against the ink surface (spec §6b):
/// white title 16.9:1, [kPosOnDarkPrimary] 9.4:1, [kPosOnDarkMuted] 4.9:1,
/// amber 11.6:1, Clear at white-68% 7.6:1 — nothing operational below 4.5:1.

/// The cart's dark operational surface.
///
/// POS-PHASE1-FOLLOWUP-FIXES-008: this was `kRestoflowInk` (#17201B), which
/// read as near-black beside the warm menu canvas — harsher than the rest of
/// the Phase-1 palette. It is now a lighter, muted deep GREEN drawn from the
/// same brand family: still unmistakably the operational plane, still far
/// darker than the canvas, but no longer a black slab. Every on-dark pair below
/// is re-checked against THIS value (see the 008 contrast test), and the muted
/// tone was lightened to keep its 4.5:1.
const Color kPosCartHeaderInk = Color(0xFF1F2E4A);

/// Primary on-dark body text (shift name, drawer figures).
const Color kPosOnDarkPrimary = Color(0xFFC6D4E8);

/// Secondary on-dark text (the shift note, which ellipsises first). Lightened
/// with the 008 surface change so it keeps >=4.5:1 on the new green ink.
const Color kPosOnDarkMuted = Color(0xFFA3B4CC);

/// The on-dark accent glyph (cart icon, status dot).
const Color kPosOnDarkAccent = Color(0xFF7FA3DA);

/// Clear-cart at rest on the dark header; it is destructive but rank 4, so it
/// is never filled and never louder than the title.
const Color kPosOnDarkGhost = Color(0xC7FFFFFF);
const Color kPosOnDarkGhostDisabled = Color(0x42FFFFFF);

/// Operational sync states ON THE DARK header (background / foreground). These
/// are POS-local pairs around the EXISTING sync presentation — no shared status
/// component is modified, and the failure state is never hidden.
const Color kPosSyncPendingBg = Color(0x2EFBBF24);
const Color kPosSyncPendingFg = Color(0xFFFCD34D);
const Color kPosSyncFailedBg = Color(0x29F87171);
const Color kPosSyncFailedFg = Color(0xFFFCA5A5);
const Color kPosSyncSyncedBg = Color(0x296EE7B7);
const Color kPosSyncSyncedFg = Color(0xFF6EE7B7);
const Color kPosSyncOfflineBg = Color(0x1AFFFFFF);
const Color kPosSyncOfflineFg = Color(0xB3FFFFFF);

/// The order-setup block's soft bottom edge — the dark header above already
/// does the separating, so this is quieter than a full hairline.
const Color kPosSetupEdge = Color(0xFFE8EDF4);

/// The warm track the white cart lines sit on, and the line's own edge.
const Color kPosCartTrack = kPosInnerSurface;

/// The quantity stepper's own track, so minus/plus read as ONE control.
const Color kPosStepperTrack = Color(0xFFF4F7FB);
const Color kPosStepperTrackEdge = kRestoflowHairline;

/// Neutral ghost icons on a cart line — destructive intent is revealed on
/// approach, not advertised at rest.
const Color kPosGhostIcon = kPosMutedBodyInk;
const Color kPosGhostIconQuiet = kRestoflowInk3;

/// Below this cart-section width the paired customer fields stack, the footer's
/// duplicated summary chips hide, and the setup stacks its label. At 320 the
/// difference is a table row fitting instead of truncating.
const double kPosCartPairedFieldsMinWidth = 352;

/// Send is the only control on screen with a glow, a 54px height and an 800
/// weight (spec §15). POS-local — `RestoflowButtonStyles.big` is untouched.
const double kPosSendHeight = 54;
const double kPosSendRadius = 13;

/// Splits a formatted money string into (lead, core, trail) where
/// lead + core + trail == the input EXACTLY, so the digits can be promoted and
/// the currency symbol demoted without altering a single character of
/// `MoneyFormatter` output.
///
/// NOTE: `menu_item_card.dart` carries an identical private split from Step 1.
/// It is deliberately NOT refactored here — that file is out of Step-2 scope —
/// and unifying the two belongs to Step 3.
(String, String, String) posSplitFormattedMoney(String formatted) {
  bool isDigit(int c) => c >= 0x30 && c <= 0x39;
  var start = 0;
  while (start < formatted.length && !isDigit(formatted.codeUnitAt(start))) {
    start++;
  }
  if (start == formatted.length) return ('', formatted, '');
  var end = formatted.length;
  while (end > start && !isDigit(formatted.codeUnitAt(end - 1))) {
    end--;
  }
  return (
    formatted.substring(0, start),
    formatted.substring(start, end),
    formatted.substring(end),
  );
}

/// The primary-CTA glow used on the add / send buttons (navy, was green).
const List<BoxShadow> kPosPrimaryGlow = [
  BoxShadow(color: Color(0x5916335E), offset: Offset(0, 6), blurRadius: 16),
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
