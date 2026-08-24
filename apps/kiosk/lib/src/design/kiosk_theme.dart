import 'package:flutter/material.dart';

import 'kiosk_theme_pair.dart';

export 'kiosk_theme_pair.dart';

/// KIOSK-001 Phase 1 — the V2 design lock, token for token.
///
/// Every constant here is transcribed from the approved artifact
/// `design-references/kiosk-v2/Kiosk Prototype v2.dc.html` (untracked,
/// read-only reference). The canonical design frame is 1080×1920 portrait;
/// every measurement below is expressed in that coordinate space and rendered
/// through [KioskStage]'s uniform scale, so a value that reads "px" in the
/// artifact is the same number here. Do not "improve" values — the design is
/// locked; deviations must be surfaced in the difference register.
///
/// KIOSK-001-107: the IDENTITY tokens (navy structural family + orange
/// action family) now RESOLVE through the bound [KioskThemePair] so the
/// owner's global device theme recolors the whole kiosk consistently. The
/// bound default is the exact locked pair, so untouched devices, demo mode
/// and bare widget tests render byte-identical V2 colors. NEUTRALS,
/// SEMANTICS (success/danger/table states) and the RECEIPT SLIP stay
/// constants — a restaurant theme must never carry meaning or repaint the
/// receipt paper.
abstract final class KioskColors {
  /// The bound global device theme. The composition root (KioskShell) keeps
  /// this in sync with the device's saved appearance; widgets keep reading
  /// the stable `KioskColors.x` roles.
  static KioskThemePair pair = KioskThemePair.navyEmber;

  /// Test/hot-restart hygiene.
  static void resetToDefault() => pair = KioskThemePair.navyEmber;

  // Canvas / depth (structural identity — theme-resolved).
  static Color get canvasTop => pair.structuralCanvasTop;
  static Color get canvasBottom => pair.structuralCanvasBottom;
  static Color get canvasGlow => pair.structuralGlow; // radial at 82% 4%
  static Color get frameRing => pair.structuralFrameRing;
  static Color get frameLine => pair.structuralBorder;
  static Color get frameLineHi => pair.structuralBorderHi;

  // Action family — the ONE accent, reserved for primary action + selection
  // (theme-resolved; default = the locked orange family).
  static Color get ring => pair.actionRing;
  static Color get accentTop => pair.actionHi;
  static Color get accentBottom => pair.actionDeep;

  /// Ink on action-filled surfaces (CTA labels). White on the locked ember;
  /// contrast-derived for light custom actions (e.g. gold).
  static Color get onAction => pair.onAction;

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

  // Sheet surfaces (structural identity — theme-resolved).
  static Color get sheetTop => pair.structuralPanel;
  static Color get sheetBottom => pair.structuralPanelDeep;
  static Color get pinCardBottom => pair.structuralPinCard;
  static Color get imageWell => pair.structuralPanelSoft;
  static Color get wheelActiveTop => pair.structuralWheelActive;

  // The printed-slip facsimile is the ONE white surface.
  static const slipPaper = Color(0xFFFFFFFF);
  static const slipInk = Color(0xFF101828);
  static const slipSoft = Color(0xFF5B6472);
  static const slipFaint = Color(0xFF98A2B3);
  static const slipAccent = Color(0xFFC2410C);
  static const slipHairline = Color(0xFFE4E9F0);

  // Glass fills/borders (white at the artifact's opacities).
  static Color glass(double opacity) => Colors.white.withValues(alpha: opacity);

  // Media scrims stay NEUTRAL near-black (readability over photos/video is
  // independent of the restaurant identity — KIOSK-001-107 §10).
  static const scrim = Color(0xB303060C); // rgba(3,6,12,.7)
  static const scrimDeep = Color(0xCC03060C); // rgba(3,6,12,.8)

  // Tinted glass bars/cards derive from the structural family at the
  // artifact's exact opacities.
  static Color get barGlass =>
      pair.structuralBarBase.withValues(alpha: 0xC7 / 255); // .78
  static Color get cardGlass =>
      pair.structuralCardBase.withValues(alpha: 0xA8 / 255); // .66

  /// The letterbox behind [KioskStage] (was the literal 0xFF05080F).
  static Color get stageBase => pair.structuralStageBase;

  /// Structural bar tints at arbitrary artifact opacities (settings headers,
  /// attract scrim stops and similar identity-tinted washes).
  static Color barTint(double opacity) =>
      pair.structuralBarBase.withValues(alpha: opacity);
  static Color canvasTint(double opacity) =>
      pair.structuralCanvasBottom.withValues(alpha: opacity);
  static Color cardTint(double opacity) =>
      pair.structuralCardBase.withValues(alpha: opacity);
}

/// Action gradient used by every primary control (V2: linear 180deg;
/// theme-resolved — default is the locked orange pair).
LinearGradient get kioskAccentGradient => LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [KioskColors.accentTop, KioskColors.accentBottom],
);

const kioskSuccessGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [KioskColors.successTop, KioskColors.successBottom],
);

LinearGradient get kioskSheetGradient => LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  stops: const [0, .3],
  colors: [KioskColors.sheetTop, KioskColors.sheetBottom],
);

/// The canonical design frame (portrait FHD).
const kioskDesignSize = Size(1080, 1920);

/// KIOSK-UI-113 — the stage's design WIDTH is aspect-adaptive: on portrait
/// viewports WIDER than 9:16 (both owner tablets are 16:10) the canvas
/// widens from the canonical 1080 up to this cap so the kiosk surface is
/// full-bleed instead of leaving app-painted side gutters. 1280 covers every
/// 16:10 / 3:2 tablet exactly (16:10 -> 1200); 4:3-class viewports clamp
/// here and keep small, deliberate gutters. The SCALE never changes —
/// [KioskStageScale] keeps its canonical min(w/1080, h/1920) meaning, so
/// pointer transforms and decode caps are untouched, and a 1080-wide
/// viewport renders the canonical composition byte-identically.
const double kioskStageMaxDesignWidth = 1280;

/// Category wheel constants — the artifact's exact interaction model.
/// KIOSK-CATEGORY-RAIL-115 turns the rail into a curved, focus-anchored
/// carousel (owner-approved geometry): a dominant active disc, per-distance
/// outward/inward x-offsets, and the Model B FOCUS BAND — the active row
/// rests at [focusTop] and the whole stack translates on selection exactly
/// like the shipped wheel, clamping only at the list tail (never a pinned
/// stack, never wrapping). Drag-follow, snap math, tap slop and easing are
/// untouched.
abstract final class KioskWheel {
  /// One category row in the rail (px in design space).
  static const double rowExtent = 200;

  /// Model B focus band (clip-local design px, measured below the top swipe
  /// hint): the active row's preferred TOP…
  static const double focusTop = 220;

  /// …and the lowest active-row top the tail clamp may reach. The active
  /// disc center therefore rests at focusTop + rowExtent/2 = 320 for every
  /// index except the final clamped one (420 for N=5).
  static const double focusBottom = 320;

  /// The resting rail translation for [activeIndex] of [categoryCount]
  /// categories: the active row sits at [focusTop], clamped near the list
  /// end so real neighbors stay on stage instead of exposing a dead rail.
  /// The tail/[focusTop] min-guard keeps the clamp well-ordered for
  /// 1–2-category menus.
  static double baseShiftFor(int activeIndex, int categoryCount) {
    final tail = focusBottom - (categoryCount - 1) * rowExtent;
    final lower = tail < focusTop ? tail : focusTop;
    return (focusTop - activeIndex * rowExtent).clamp(lower, focusTop);
  }

  /// Disc diameter by distance from the active index: 0 / 1 / 2 / 3+.
  static const List<double> discByDistance = [210, 132, 100, 78];

  /// Horizontal bow by distance, in OUTWARD units (toward the screen edge:
  /// +x in RTL where the rail sits on the right; mirrored in LTR). The
  /// active node swings outward, neighbors recess progressively inward —
  /// with the size falloff this is the curved-carousel silhouette.
  static const List<double> xOffsetByDistance = [22, -4, -20, -34];

  /// Label font size by distance.
  static const List<double> labelSizeByDistance = [28, 20, 17];

  /// Opacity falloff by distance.
  static const List<double> opacityByDistance = [1, .75, .45, .28];

  /// Movement past this (design px) turns a tap into a drag.
  static const double tapSlop = 8;

  /// Snap-back/settle animation after release.
  static const snapDuration = Duration(milliseconds: 450);

  /// Per-disc size/style transition while the active index changes.
  static const discDuration = Duration(milliseconds: 400);

  /// cubic-bezier(.22,.9,.26,1) — the V2 easing for surfaces and the wheel.
  static const curve = Cubic(.22, .9, .26, 1);

  /// Rail column width (115: 272 hosts the 210 active disc, its 5px ring
  /// and the +22 outward bow inside the clip).
  static const double railWidth = 272;

  // ---- 115A: the orange guide's STATIC spine -----------------------------
  // The guide is split into a fixed full-height spine (this curve, painted
  // faint) and a moving marker layer that travels ALONG it — so a category
  // swipe moves the highlighted point, never the whole line.

  /// Spine x at both fading ends (inside the 120-wide guide paint box).
  static const double railSpineInnerX = 36;

  /// Cubic control x — puts the spine's belly at ≈97.5 at mid-height.
  static const double railSpineControlX = 118;

  /// x of the STATIC spine at height [y] within a guide viewport of
  /// [height]: the cubic (innerX, 0) → ctrl(controlX, .32h)/(controlX,
  /// .68h) → (innerX, height), inverted by binary search (y(t) is
  /// monotone). Both guide painters and the marker share this, so the
  /// marker always sits exactly ON the rail.
  static double railSpineX(double y, double height) {
    if (height <= 0) return railSpineInnerX;
    final target = y.clamp(0.0, height);
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 32; i++) {
      final mid = (lo + hi) / 2;
      final u = 1 - mid;
      final yMid =
          height *
          (3 * .32 * mid * u * u + 3 * .68 * mid * mid * u + mid * mid * mid);
      if (yMid < target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final t = (lo + hi) / 2;
    final u = 1 - t;
    return railSpineInnerX * u * u * u +
        3 * railSpineControlX * t * u * u +
        3 * railSpineControlX * t * t * u +
        railSpineInnerX * t * t * t;
  }
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
  colorScheme: ColorScheme.dark(
    primary: KioskColors.ring,
    secondary: KioskColors.accentTop,
    surface: KioskColors.canvasTop,
    error: KioskColors.danger,
  ),
  splashFactory: NoSplash.splashFactory,
  highlightColor: Colors.transparent,
);
