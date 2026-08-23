import 'dart:math' as math;

import 'package:flutter/material.dart';

/// KIOSK-001-107 — the GLOBAL two-color kiosk device theme.
///
/// The same product idea as the POS restaurant theme
/// (POS-THEME-NAVBAR-POLISH-001 / POS-CUSTOM-DEVICE-THEME-010), ported into
/// the kiosk's own dark-premium visual language with NO import from
/// `apps/pos`:
///  * TWO roles — PRIMARY (structural identity) + ACTION (CTA/selection
///    family). Semantic colors (success/danger/warning/table states) and the
///    receipt slip NEVER read from this pair.
///  * The kiosk is a full-bleed dark 1080×1920 surface, so an arbitrary
///    primary never becomes a blinding wall: the huge canvas/panel family is
///    derived by a HUE-TRANSPLANT — each locked V2 navy token keeps its own
///    LIGHTNESS while taking the seed's hue (saturation damped), so a green
///    seed yields a dark forest canvas, burgundy a dark wine, and a light
///    cream a tasteful tinted dark. The two SELECTED colors themselves are
///    never altered — only derived supporting tones adapt.
///  * Foreground inks ([onPrimary]/[onAction]) are picked by MEASURED
///    contrast; [actionSoft]/[actionRing] walk toward visibility against the
///    dark structural bed so a dark custom action can't vanish.
///  * The DEFAULT pair is the exact locked V2 Navy + Ember constants —
///    ARGB-identical to the pre-107 kiosk, pinned by test.

// ---------------------------------------------------------------------------
// Pure color utilities (the POS pos_color_utils.dart recipe, kiosk-local).
// ---------------------------------------------------------------------------

/// The dark ink candidate for light custom beds (near-black navy family).
const Color kKioskReadableDarkInk = Color(0xFF10141C);

final RegExp _hexRrggbb = RegExp(r'^#?([0-9a-fA-F]{6})$');

/// Parses `#RRGGBB` (case-insensitive, `#` optional); null when invalid.
Color? kioskParseWireHex(String raw) {
  final match = _hexRrggbb.firstMatch(raw.trim());
  if (match == null) return null;
  return Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
}

/// Canonical uppercase `RRGGBB` (no `#`, alpha dropped).
String kioskFormatWireHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
}

/// WCAG relative-contrast ratio between two colors (1..21).
double kioskContrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Readable foreground ink for an arbitrary bed: white when it clears
/// [whiteFloor] or simply out-contrasts the dark candidate; else the
/// near-black ink. (The POS `posReadableInkOn` rule.)
Color kioskReadableInkOn(Color bed, {double whiteFloor = 3.6}) {
  const white = Color(0xFFFFFFFF);
  final w = kioskContrastRatio(white, bed);
  return (w >= whiteFloor ||
          w >= kioskContrastRatio(kKioskReadableDarkInk, bed))
      ? white
      : kKioskReadableDarkInk;
}

/// Walks [tone] toward white/black (whichever suits [bed]) until it measures
/// at least [floor] against the bed. An already-passing tone returns
/// UNCHANGED (`startT` 0), so the locked default family stays byte-identical.
Color kioskToneForContrast(
  Color tone,
  Color bed, {
  double startT = 0.0,
  double floor = 4.5,
}) {
  const white = Color(0xFFFFFFFF);
  final lighten =
      kioskContrastRatio(white, bed) >=
      kioskContrastRatio(kKioskReadableDarkInk, bed);
  final target = lighten ? white : const Color(0xFF000000);
  for (var t = startT; t <= 1.0 + 1e-9; t += 0.05) {
    final candidate = Color.lerp(tone, target, t.clamp(0.0, 1.0))!;
    if (kioskContrastRatio(candidate, bed) >= floor) return candidate;
  }
  return kioskReadableInkOn(bed, whiteFloor: floor);
}

/// HUE-TRANSPLANT: recolor a locked dark structural token with the seed's
/// identity while keeping the token's own LIGHTNESS (the dark-premium
/// guarantee) — hue from the seed, saturation damped so neon seeds stay
/// tasteful and near-grey seeds yield a neutral dark.
Color kioskStructuralTone(Color seed, Color lockedToken) {
  final s = HSLColor.fromColor(seed);
  final t = HSLColor.fromColor(lockedToken);
  final sat =
      math.min(s.saturation, 0.65) * (t.saturation / 0.58).clamp(0.5, 1.1);
  return HSLColor.fromAHSL(
    1.0,
    s.hue,
    sat.clamp(0.0, 0.70),
    t.lightness,
  ).toColor();
}

// ---------------------------------------------------------------------------
// The locked V2 identity constants (exact artifact values — the defaults).
// ---------------------------------------------------------------------------

const Color _lockCanvasTop = Color(0xFF0A1526);
const Color _lockCanvasBottom = Color(0xFF070E1B);
const Color _lockCanvasGlow = Color(0xFF13233E);
const Color _lockFrameRing = Color(0xFF101B2E);
const Color _lockFrameLine = Color(0xFF223A5E);
const Color _lockFrameLineHi = Color(0xFF3B527A);
const Color _lockSheetTop = Color(0xFF12233F);
const Color _lockSheetBottom = Color(0xFF0A1526);
const Color _lockPinCard = Color(0xFF0B1830);
const Color _lockImageWell = Color(0xFF0E1C31);
const Color _lockWheelActive = Color(0xFF1A2C49);
const Color _lockBarBase = Color(0xFF080F1C);
const Color _lockCardBase = Color(0xFF0A1220);
const Color _lockStageBase = Color(0xFF05080F);

@immutable
class KioskThemePair {
  const KioskThemePair({
    required this.primary,
    required this.primaryHi,
    required this.primaryDeep,
    required this.onPrimary,
    required this.structuralCanvasTop,
    required this.structuralCanvasBottom,
    required this.structuralGlow,
    required this.structuralFrameRing,
    required this.structuralBorder,
    required this.structuralBorderHi,
    required this.structuralPanel,
    required this.structuralPanelDeep,
    required this.structuralPanelSoft,
    required this.structuralPinCard,
    required this.structuralWheelActive,
    required this.structuralBarBase,
    required this.structuralCardBase,
    required this.structuralStageBase,
    required this.action,
    required this.actionHi,
    required this.actionDeep,
    required this.actionMark,
    required this.actionSoft,
    required this.actionRing,
    required this.onAction,
    required this.wire,
  });

  /// Preset/custom derivation from a bare {primary, action} seed pair. The
  /// two seeds are stored EXACTLY; every structural surface is a
  /// hue-transplant of the locked V2 dark family; supporting action tones
  /// use the POS lerp recipe plus visibility walks against the dark bed.
  factory KioskThemePair.derive({
    required Color primary,
    required Color action,
    required String wire,
  }) {
    final canvasBottom = kioskStructuralTone(primary, _lockCanvasBottom);
    final sheetTop = kioskStructuralTone(primary, _lockSheetTop);
    return KioskThemePair(
      primary: primary,
      primaryHi: Color.lerp(primary, Colors.white, 0.12)!,
      primaryDeep: Color.lerp(primary, Colors.black, 0.16)!,
      onPrimary: kioskReadableInkOn(primary, whiteFloor: 4.5),
      structuralCanvasTop: kioskStructuralTone(primary, _lockCanvasTop),
      structuralCanvasBottom: canvasBottom,
      structuralGlow: kioskStructuralTone(primary, _lockCanvasGlow),
      structuralFrameRing: kioskStructuralTone(primary, _lockFrameRing),
      structuralBorder: kioskStructuralTone(primary, _lockFrameLine),
      structuralBorderHi: kioskStructuralTone(primary, _lockFrameLineHi),
      structuralPanel: sheetTop,
      structuralPanelDeep: kioskStructuralTone(primary, _lockSheetBottom),
      structuralPanelSoft: kioskStructuralTone(primary, _lockImageWell),
      structuralPinCard: kioskStructuralTone(primary, _lockPinCard),
      structuralWheelActive: kioskStructuralTone(primary, _lockWheelActive),
      structuralBarBase: kioskStructuralTone(primary, _lockBarBase),
      structuralCardBase: kioskStructuralTone(primary, _lockCardBase),
      structuralStageBase: kioskStructuralTone(primary, _lockStageBase),
      action: action,
      actionHi: Color.lerp(action, Colors.white, 0.18)!,
      actionDeep: Color.lerp(action, Colors.black, 0.14)!,
      actionMark: Color.lerp(action, Colors.white, 0.08)!,
      // Soft/ring tones must stay VISIBLE on the dark structural bed; an
      // already-visible tone returns unchanged (§5: only supporting tones
      // may be adjusted, never the selected seeds).
      actionSoft: kioskToneForContrast(action, sheetTop, floor: 4.5),
      actionRing: kioskToneForContrast(action, canvasBottom, floor: 2.2),
      // The kiosk's OWN shipped CTA baseline: the locked design paints WHITE
      // on the ember action (white vs #F97316 measures 2.80), so 2.6 is the
      // owner-approved floor with margin — ember-family customs keep the
      // exact preset ink while true golds (#D89A2B ≈ 2.45) and creams still
      // flip to a dark label. CTA text is large/bold, where ~3:1 is the
      // WCAG large-text bar the shipped design was approved against.
      onAction: kioskReadableInkOn(action, whiteFloor: 2.6),
      wire: wire,
    );
  }

  /// An OWNER-PICKED two-color identity, persisted as
  /// `custom:RRGGBB:RRGGBB` (the POS wire idea) inside the appearance JSON.
  factory KioskThemePair.custom({
    required Color primary,
    required Color action,
  }) => KioskThemePair.derive(
    primary: primary,
    action: action,
    wire: wireForCustom(primary: primary, action: action),
  );

  // ---- primary / structural family ----------------------------------------
  final Color primary;
  final Color primaryHi;
  final Color primaryDeep;
  final Color onPrimary;
  final Color structuralCanvasTop;
  final Color structuralCanvasBottom;
  final Color structuralGlow;
  final Color structuralFrameRing;
  final Color structuralBorder;
  final Color structuralBorderHi;
  final Color structuralPanel;
  final Color structuralPanelDeep;
  final Color structuralPanelSoft;
  final Color structuralPinCard;
  final Color structuralWheelActive;
  final Color structuralBarBase;
  final Color structuralCardBase;
  final Color structuralStageBase;

  // ---- action family -------------------------------------------------------
  final Color action;
  final Color actionHi;
  final Color actionDeep;
  final Color actionMark;
  final Color actionSoft;
  final Color actionRing;
  final Color onAction;

  final String wire;

  bool get isCustom => wire.startsWith('custom:');

  /// The action glow used behind CTAs/rings.
  Color get actionGlow => action.withValues(alpha: 0.35);

  static String wireForCustom({
    required Color primary,
    required Color action,
  }) => 'custom:${kioskFormatWireHex(primary)}:${kioskFormatWireHex(action)}';

  /// Decodes `custom:RRGGBB:RRGGBB`; null for anything malformed.
  static KioskThemePair? tryParseCustomWire(String wire) {
    final parts = wire.split(':');
    if (parts.length != 3 || parts[0] != 'custom') return null;
    final primary = kioskParseWireHex(parts[1]);
    final action = kioskParseWireHex(parts[2]);
    if (primary == null || action == null) return null;
    return KioskThemePair.custom(primary: primary, action: action);
  }

  /// The DEFAULT — the exact locked V2 Navy + Ember identity, constant for
  /// constant (never lerp-derived), so an un-themed kiosk is byte-identical
  /// to the shipped v4 look.
  static const KioskThemePair navyEmber = KioskThemePair(
    primary: Color(0xFF16263B),
    primaryHi: Color(0xFF243650),
    primaryDeep: Color(0xFF101B2D),
    onPrimary: Colors.white,
    structuralCanvasTop: _lockCanvasTop,
    structuralCanvasBottom: _lockCanvasBottom,
    structuralGlow: _lockCanvasGlow,
    structuralFrameRing: _lockFrameRing,
    structuralBorder: _lockFrameLine,
    structuralBorderHi: _lockFrameLineHi,
    structuralPanel: _lockSheetTop,
    structuralPanelDeep: _lockSheetBottom,
    structuralPanelSoft: _lockImageWell,
    structuralPinCard: _lockPinCard,
    structuralWheelActive: _lockWheelActive,
    structuralBarBase: _lockBarBase,
    structuralCardBase: _lockCardBase,
    structuralStageBase: _lockStageBase,
    action: Color(0xFFF97316),
    actionHi: Color(0xFFFB923C),
    actionDeep: Color(0xFFEA580C),
    actionMark: Color(0xFFFB923C),
    actionSoft: Color(0xFFFB923C),
    actionRing: Color(0xFFF97316),
    onAction: Colors.white,
    wire: 'navy_ember',
  );

  /// Forest + Ember — deep green structure, the proven kiosk ember action.
  static final KioskThemePair forestEmber = KioskThemePair.derive(
    primary: const Color(0xFF1E4D3B),
    action: const Color(0xFFF97316),
    wire: 'forest_ember',
  );

  /// Aubergine + Brick (the POS pairing, kiosk-dark derivation).
  static final KioskThemePair aubergineBrick = KioskThemePair.derive(
    primary: const Color(0xFF44264A),
    action: const Color(0xFFC65A4B),
    wire: 'aubergine_brick',
  );

  /// Charcoal + Gold — the one light-action preset; its CTA ink derives dark.
  static final KioskThemePair charcoalGold = KioskThemePair.derive(
    primary: const Color(0xFF33312C),
    action: const Color(0xFFD89A2B),
    wire: 'charcoal_gold',
  );

  static final List<KioskThemePair> presets = [
    navyEmber,
    forestEmber,
    aubergineBrick,
    charcoalGold,
  ];

  /// Wire lookup: preset ids load exactly; `custom:RRGGBB:RRGGBB` decodes;
  /// null/unknown/corrupt => the locked default (a bad stored value must
  /// never break a kiosk).
  static KioskThemePair fromWire(String? wire) {
    if (wire == null || wire.isEmpty) return navyEmber;
    for (final p in presets) {
      if (p.wire == wire) return p;
    }
    return tryParseCustomWire(wire) ?? navyEmber;
  }
}
