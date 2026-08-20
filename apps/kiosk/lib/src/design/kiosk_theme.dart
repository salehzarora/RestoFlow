import 'package:flutter/material.dart';

/// KIOSK-001 Phase 1 — the V2 design lock, token for token.
///
/// Every constant here is transcribed from the approved artifact
/// `design-references/kiosk-v2/Kiosk Prototype v2.dc.html` (untracked,
/// read-only reference). The canonical design frame is 1080×1920 portrait;
/// every measurement below is expressed in that coordinate space and rendered
/// through [KioskStage]'s uniform scale, so a value that reads "px" in the
/// artifact is the same number here. Do not "improve" values — the design is
/// locked; deviations must be surfaced in the difference register.
abstract final class KioskColors {
  // Canvas / depth.
  static const canvasTop = Color(0xFF0A1526);
  static const canvasBottom = Color(0xFF070E1B);
  static const canvasGlow = Color(0xFF13233E); // radial at 82% 4%
  static const frameRing = Color(0xFF101B2E);
  static const frameLine = Color(0xFF223A5E);

  // Orange family — the ONE accent, reserved for primary action + selection.
  static const ring = Color(0xFFF97316);
  static const accentTop = Color(0xFFFB923C);
  static const accentBottom = Color(0xFFEA580C);

  // Text on dark.
  static const textPrimary = Color(0xFFF4F7FB);
  static const textSoft = Color(0xFFC9D3E2);
  static const textMuted = Color(0xFF93A1B8);
  static const textFaint = Color(0xFF7C8AA5);
  static const textDisabled = Color(0xFF5B6B85);
  static const textGhost = Color(0xFF4A5A75);
  static const wheelLabel = Color(0xFFB9C4D6);

  // Table state dots (semantic colors stay reserved for table states).
  static const tableFree = Color(0xFF4ADE80);
  static const tableOccupied = Color(0xFFF87171);
  static const tableReserved = Color(0xFFFBBF24);
  static const tableOutOfService = Color(0xFF64748B);

  // Success (confirmation check only).
  static const successTop = Color(0xFF22C55E);
  static const successBottom = Color(0xFF15803D);

  // Errors (required-missing + wrong PIN only).
  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFF87171);

  // Sheet surfaces.
  static const sheetTop = Color(0xFF12233F);
  static const sheetBottom = Color(0xFF0A1526);
  static const pinCardBottom = Color(0xFF0B1830);
  static const imageWell = Color(0xFF0E1C31);
  static const wheelActiveTop = Color(0xFF1A2C49);

  // The printed-slip facsimile is the ONE white surface.
  static const slipPaper = Color(0xFFFFFFFF);
  static const slipInk = Color(0xFF101828);
  static const slipSoft = Color(0xFF5B6472);
  static const slipFaint = Color(0xFF98A2B3);
  static const slipAccent = Color(0xFFC2410C);
  static const slipHairline = Color(0xFFE4E9F0);

  // Glass fills/borders (white at the artifact's opacities).
  static Color glass(double opacity) => Colors.white.withValues(alpha: opacity);
  static const scrim = Color(0xB303060C); // rgba(3,6,12,.7)
  static const scrimDeep = Color(0xCC03060C); // rgba(3,6,12,.8)
  static const barGlass = Color(0xC7080F1C); // rgba(8,15,28,.78)
  static const cardGlass = Color(0xA80A1220); // rgba(10,18,32,.66)
}

/// Orange gradient used by every primary control (V2: linear 180deg).
const kioskAccentGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [KioskColors.accentTop, KioskColors.accentBottom],
);

const kioskSuccessGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [KioskColors.successTop, KioskColors.successBottom],
);

const kioskSheetGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  stops: [0, .3],
  colors: [KioskColors.sheetTop, KioskColors.sheetBottom],
);

/// The canonical design frame (portrait FHD).
const kioskDesignSize = Size(1080, 1920);

/// Category wheel constants — the artifact's exact interaction model.
abstract final class KioskWheel {
  /// One category row in the rail (px in design space).
  static const double rowExtent = 172;

  /// The active row's center offset: railShift = [centerShift] − idx·[rowExtent].
  static const double centerShift = 550;

  /// Disc diameter by distance from the active index: 0 / 1 / 2 / 3+.
  static const List<double> discByDistance = [150, 98, 78, 64];

  /// Label font size by distance.
  static const List<double> labelSizeByDistance = [24, 20, 17];

  /// Opacity falloff by distance.
  static const List<double> opacityByDistance = [1, .78, .5, .32];

  /// Movement past this (design px) turns a tap into a drag.
  static const double tapSlop = 8;

  /// Snap-back/settle animation after release.
  static const snapDuration = Duration(milliseconds: 450);

  /// Per-disc size/style transition while the active index changes.
  static const discDuration = Duration(milliseconds: 400);

  /// cubic-bezier(.22,.9,.26,1) — the V2 easing for surfaces and the wheel.
  static const curve = Cubic(.22, .9, .26, 1);

  /// Rail column width.
  static const double railWidth = 218;
}

/// Motion tokens (V2: fast waiter, never bouncy).
abstract final class KioskMotion {
  static const screenFade = Duration(milliseconds: 350);
  static const sheetRise = Duration(milliseconds: 380);
  static const gridSwap = Duration(milliseconds: 400);
  static const pressFeedback = Duration(milliseconds: 120);
  static const shake = Duration(milliseconds: 400);
  static const toastLife = Duration(milliseconds: 2400);
  static const kenBurns = Duration(seconds: 16);
  static const curve = Cubic(.22, .9, .26, 1);
}

/// Idle/attract timing (V2 defaults; the seconds value is a device setting).
abstract final class KioskTiming {
  static const int idleDefaultSeconds = 60;
  static const int idleWarningSeconds = 10;
  static const int confirmReturnSeconds = 24;
  static const List<int> idleOptions = [30, 60, 90, 120];
}

/// Typography. Latin display = Anton (400, +letter-spacing); RTL display =
/// Rubik 900 with ZERO letter-spacing (Arabic joining rule). Body/UI = Rubik
/// for every script.
abstract final class KioskType {
  static const latinDisplayFamily = 'Anton';
  static const family = 'Rubik';

  /// Display headline in the current direction.
  static TextStyle display(
    bool rtl,
    double size, {
    Color color = KioskColors.textPrimary,
    double height = 1.04,
  }) => TextStyle(
    fontFamily: rtl ? family : latinDisplayFamily,
    fontWeight: rtl ? FontWeight.w900 : FontWeight.w400,
    letterSpacing: rtl ? 0 : 1,
    fontSize: size,
    height: height,
    color: color,
  );

  static TextStyle body(
    double size,
    FontWeight weight, {
    Color color = KioskColors.textPrimary,
    double? height,
    double letterSpacing = 0,
  }) => TextStyle(
    fontFamily: family,
    fontWeight: weight,
    fontSize: size,
    height: height,
    letterSpacing: letterSpacing,
    color: color,
  );
}

/// The kiosk deliberately does NOT use the shared RestoFlow Material theme —
/// the customer surface is its own locked visual language. Material widgets
/// that leak through (text fields, ink) get neutral dark defaults here.
ThemeData kioskTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  fontFamily: KioskType.family,
  scaffoldBackgroundColor: KioskColors.canvasBottom,
  colorScheme: const ColorScheme.dark(
    primary: KioskColors.ring,
    secondary: KioskColors.accentTop,
    surface: KioskColors.canvasTop,
    error: KioskColors.danger,
  ),
  splashFactory: NoSplash.splashFactory,
  highlightColor: Colors.transparent,
);
