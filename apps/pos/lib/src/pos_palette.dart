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

/// The green-CTA glow used on the primary add / send buttons.
const List<BoxShadow> kPosGreenGlow = [
  BoxShadow(color: Color(0x591B7A52), offset: Offset(0, 6), blurRadius: 16),
];

/// The responsive layout mode of the POS cashier screen, chosen from the
/// ACTUAL available width (and orientation) via [posLayoutModeFor] — never from
/// the platform. Keeps `RestoflowBreakpoints.posTwoPane` (820) as the phone
/// cutoff so the existing wide-viewport widget tests still see two panes.
enum PosLayoutMode {
  /// Menu pane + fixed side cart 380px.
  desktop,

  /// Menu pane + fixed side cart 340px.
  tablet,

  /// Landscape phone / small tablet: menu pane + compact side cart ~304px.
  compactLandscape,

  /// Menu full-width + a dark bottom bar and a slide-up cart sheet.
  phone,
}

/// Side-cart width for a two-pane [mode]; 0 for [PosLayoutMode.phone].
double posCartWidthFor(PosLayoutMode mode) => switch (mode) {
  PosLayoutMode.desktop => 380,
  PosLayoutMode.tablet => 340,
  PosLayoutMode.compactLandscape => 304,
  PosLayoutMode.phone => 0,
};

/// Chooses the [PosLayoutMode] from the available [width]/[height].
///
/// - `>= 1100` → desktop (side cart 380)
/// - `820 .. 1099` → tablet (side cart 340)
/// - `700 .. 819` AND landscape (`width > height`) → compact landscape split
///   (a compact ~304px side cart fits without a bottom bar)
/// - otherwise → phone (bottom bar + slide-up sheet)
///
/// The 820 phone cutoff for portrait is unchanged, so a rotated phone/tablet
/// widens into a side-cart layout instead of staying cramped like portrait.
PosLayoutMode posLayoutModeFor({
  required double width,
  required double height,
}) {
  if (width >= 1100) return PosLayoutMode.desktop;
  if (width >= RestoflowBreakpoints.posTwoPane) return PosLayoutMode.tablet;
  if (width >= 700 && width > height) return PosLayoutMode.compactLandscape;
  return PosLayoutMode.phone;
}
