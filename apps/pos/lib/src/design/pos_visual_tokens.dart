/// POS-PREMIUM-VISUAL-POLISH-001 — the POS screen's premium token layer.
///
/// This file NAMES the palette the owner picked for the cashier surface and
/// scopes it to the POS app. It sits ON TOP of the global navy/white/orange
/// brand (RESTOFLOW-GLOBAL-VISUAL-V0, `RestoflowBrandPalette`) — it never
/// re-values a shared constant, so Dashboard / KDS / Admin are untouched.
///
/// POS-DESIGN-HANDOFF-IMPLEMENTATION-004: this file now also carries the
/// approved Claude Design v4 token deltas — the two-token restaurant theme
/// (rf-primary / rf-action, [PosThemePair]), the vivid ember action family,
/// and the warm neutral surfaces. The old COOL-LAW (every POS surface fill
/// navy-family) is deliberately superseded for the SURFACE NEUTRALS by the
/// approved warm ivory family (tokens doc §1/§8); the structural darks stay
/// navy and every shadow still inks with the navy-black family.
///
/// SEMANTIC COLOURS ARE NOT HERE. Success/warning/danger/info stay in
/// [RestoflowSemanticColors]; the per-device secondary accent must never
/// carry a semantic meaning (see pos_device_accent.dart).
library;

import 'package:flutter/material.dart';

import 'package:restoflow_design_system/restoflow_design_system.dart';

import 'pos_color_utils.dart';

/// Midnight Navy — the POS structural dark: cart operational header and the
/// phone bottom cart bar. Deeper than the brand navy so the dark plane reads
/// as furniture, not as a giant button.
const Color kPosMidnightNavy = Color(0xFF16263B);

/// Slate Ink — the secondary dark: hover/pressed lift on the midnight plane,
/// the sheet grip, quiet dark chips.
const Color kPosSlateInk = Color(0xFF2A3B4F);

/// Ivory Surface — the menu-grid canvas behind product cards. The one warm
/// note on the screen (owner decision: restaurant feel). Never a control
/// surface; controls stay on the white deck / cool fills.
const Color kPosIvorySurface = Color(0xFFF7F5F1);

/// Pure Card — product cards, the menu deck, the cart body.
const Color kPosPureCard = Color(0xFFFFFFFF);

/// Ember Orange — the base of the POS ACTION family. The approved v4 design
/// promotes ember from a decorative note to the rf-action role: the Send CTA
/// gradient, price digits, ×N in-cart marks, the stepper's plus and the cart
/// count chip all read ember (see [PosThemePair]). It still never REPLACES a
/// semantic colour — success/warning/danger/info keep their own hues.
const Color kPosEmberOrange = Color(0xFFC96A2B);

/// POS-DESIGN-HANDOFF-IMPLEMENTATION-004 — the approved two-token restaurant
/// theme (tokens doc §9/§10). Every PRIMARY structural surface (navbar,
/// selected segment thumb, Add buttons, phone bottom bar) and every ACTION
/// accent (Send CTA, prices, ×N marks, stepper plus, count chips) resolves
/// through this pair, so a restaurant can swap the identity (e.g. black +
/// green) without touching semantic or device-accent colours.
///
/// Registered on the POS theme as a [ThemeExtension]; [PosThemePair.of] falls
/// back to the default navy+ember preset so bare test themes keep working.
@immutable
class PosThemePair extends ThemeExtension<PosThemePair> {
  const PosThemePair({
    required this.primary,
    required this.primaryHi,
    required this.primaryDeep,
    required this.action,
    required this.actionHi,
    required this.actionDeep,
    required this.actionMark,
    required this.actionSoft,
    this.onAction = Colors.white,
    this.onPrimary = Colors.white,
    this.wire = 'custom',
  });

  /// Derives the lightness steps from a bare {primary, action} pair — the
  /// preset path for non-default restaurant identities.
  factory PosThemePair.derive({
    required Color primary,
    required Color action,
    Color onAction = Colors.white,
    Color onPrimary = Colors.white,
    String wire = 'custom',
  }) => PosThemePair(
    primary: primary,
    primaryHi: Color.lerp(primary, Colors.white, 0.12)!,
    primaryDeep: Color.lerp(primary, Colors.black, 0.16)!,
    action: action,
    actionHi: Color.lerp(action, Colors.white, 0.18)!,
    actionDeep: Color.lerp(action, Colors.black, 0.14)!,
    actionMark: Color.lerp(action, Colors.white, 0.08)!,
    actionSoft: Color.lerp(action, Colors.white, 0.44)!,
    onAction: onAction,
    onPrimary: onPrimary,
    wire: wire,
  );

  /// POS-CUSTOM-DEVICE-THEME-010 — an OWNER-TYPED two-color identity.
  ///
  /// Same derived-tone recipe as the presets (hover/pressed/soft/mark steps
  /// via the exact `derive()` lerps), with custom-only adjustments the
  /// arbitrary inputs make necessary:
  ///  * both foreground inks are DERIVED by actual contrast
  ///    ([posReadableInkOn]) — the primary's ink at a 4.5:1 white floor
  ///    (normal-size structural text), the action's at the shipped 3.6:1
  ///    CTA baseline. The chosen hexes themselves are never altered;
  ///  * [actionSoft] (the soft action note that sits ON the primary bed —
  ///    navbar tagline, phone-bar running total) starts from the presets'
  ///    exact lerp step and then KEEPS WALKING toward white/black until it
  ///    measures 4.5:1 against the primary ([posToneForContrast]) — a light
  ///    action on a light primary can otherwise land near-invisible.
  /// The wire encodes both hexes ([wireForCustom]), so the existing
  /// setTheme/fromWire persistence round-trips custom pairs with no schema
  /// change.
  factory PosThemePair.custom({required Color primary, required Color action}) {
    final onPrimary = posReadableInkOn(primary, whiteFloor: 4.5);
    final darkPrimaryBed = onPrimary == Colors.white;
    return PosThemePair(
      primary: primary,
      primaryHi: Color.lerp(primary, Colors.white, 0.12)!,
      primaryDeep: Color.lerp(primary, Colors.black, 0.16)!,
      action: action,
      actionHi: Color.lerp(action, Colors.white, 0.18)!,
      actionDeep: Color.lerp(action, Colors.black, 0.14)!,
      actionMark: Color.lerp(action, Colors.white, 0.08)!,
      actionSoft: posToneForContrast(
        action,
        primary,
        startT: darkPrimaryBed ? 0.44 : 0.30,
      ),
      onAction: posReadableInkOn(action),
      onPrimary: onPrimary,
      wire: wireForCustom(primary: primary, action: action),
    );
  }

  /// Structure: navbar, segmented thumb, Add buttons, phone bottom bar.
  final Color primary;

  /// The lighter gradient start of a primary surface.
  final Color primaryHi;

  /// Hover/pressed primary.
  final Color primaryDeep;

  /// Action: Send CTA, price digits, count chips.
  final Color action;

  /// The lighter gradient start of the Send CTA.
  final Color actionHi;

  /// Pressed CTA.
  final Color actionDeep;

  /// ×N in-cart marks + the stepper's plus.
  final Color actionMark;

  /// Soft action accents on the navy bar (cart glyph, count-chip bed).
  final Color actionSoft;

  /// The CTA/label ink ON [action] surfaces. White for the dark-enough
  /// actions; a near-black ink for light golds, so the Send label always
  /// clears contrast.
  final Color onAction;

  /// POS-CUSTOM-DEVICE-THEME-010 — the ink ON [primary] surfaces (navbar
  /// text, thumb label, Add-button label, phone-bar text). White for every
  /// curated preset (their primaries are all dark, so nothing repaints);
  /// contrast-derived for custom pairs, where the primary may be light.
  final Color onPrimary;

  /// Persisted preset identity (POS-THEME-NAVBAR-POLISH-001). Never rename a
  /// wire value without an adoption path. POS-CUSTOM-DEVICE-THEME-010: custom
  /// pairs persist as `custom:RRGGBB:RRGGBB` through the SAME key.
  final String wire;

  /// True for owner-typed pairs (both the encoded `custom:...` wires and the
  /// legacy bare `custom` default of `derive`/`copyWith`). Custom pairs are
  /// never theme-cached and get the custom swatch treatment in settings.
  bool get isCustom => wire == 'custom' || wire.startsWith('custom:');

  /// Whether the primary reads as a DARK bed (its ink is white) — the presets'
  /// world, and the branch every navbar-chrome getter keeps byte-identical.
  bool get _darkPrimaryBed => onPrimary == Colors.white;

  /// The navbar chrome ink (icon cluster, appbar icons). Exactly
  /// [kPosNavbarInk] whenever the primary is a dark bed — every preset — and
  /// a primary-tinted dark ink on light custom bars.
  Color get navInk =>
      _darkPrimaryBed ? kPosNavbarInk : Color.lerp(onPrimary, primary, 0.18)!;

  /// The translucent action-cluster bed on the navbar ([kPosNavbarBed] on
  /// dark bars; a quiet dark wash on light custom bars).
  Color get navBed => _darkPrimaryBed ? kPosNavbarBed : const Color(0x14000000);

  /// The restaurant-identity chip bed on the navbar (white-12% on dark bars —
  /// the approved values — mirrored to a dark wash on light custom bars).
  Color get identityBed =>
      _darkPrimaryBed ? const Color(0x1FFFFFFF) : const Color(0x1A000000);

  /// The identity chip's hairline edge.
  Color get identityEdge =>
      _darkPrimaryBed ? const Color(0x24FFFFFF) : const Color(0x26000000);

  /// The ink for the SMALL action-family marks — the cart count chip, the
  /// phone-bar count badge and the stepper's filled plus. These shipped
  /// WHITE on every curated preset (including saffron_gold, whose Send-CTA
  /// [onAction] is dark — an owner-shipped look this appearance ticket must
  /// not repaint), so presets keep the literal white and only CUSTOM pairs
  /// derive it (POS-CUSTOM-DEVICE-THEME-010 audit finding).
  Color get onActionMark => isCustom ? onAction : Colors.white;

  /// [primary] used AS TEXT INK on the light control beds (the in-cart
  /// "Add more" label on [kPosTonalAddBg]). Identical to [primary] for every
  /// preset (all dark, all already ≥4.5:1 there); a light CUSTOM primary is
  /// walked darker until it reads ([posToneForContrast]) instead of
  /// disappearing tone-on-tone.
  Color get primaryTextInk =>
      isCustom ? posToneForContrast(primary, kPosTonalAddBg) : primary;

  /// Canonical wire encoding for a custom pair: `custom:RRGGBB:RRGGBB`
  /// (uppercase, no `#`). Lives beside the preset wires in the same persisted
  /// key; [fromWire] decodes it and falls back to the default preset on any
  /// corruption.
  static String wireForCustom({required Color primary, required Color action}) {
    String hex(Color c) => posFormatHexColor(c).substring(1);
    return 'custom:${hex(primary)}:${hex(action)}';
  }

  /// Decodes a `custom:RRGGBB:RRGGBB` wire; `null` for anything malformed
  /// (wrong part count, bad hex, alpha forms) — the caller falls back.
  static PosThemePair? tryParseCustomWire(String wire) {
    final parts = wire.split(':');
    if (parts.length != 3 || parts[0] != 'custom') return null;
    final primary = posParseHexColor(parts[1]);
    final action = posParseHexColor(parts[2]);
    if (primary == null || action == null) return null;
    return PosThemePair.custom(primary: primary, action: action);
  }

  /// The primary structural gradient (brand tile, Add buttons, thumb).
  LinearGradient get primaryGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [primaryHi, primary],
  );

  /// The Send CTA gradient — the one vivid surface on screen.
  LinearGradient get actionGradient => LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [actionHi, action],
  );

  /// The CTA glow (the only glow on screen — states/motion doc §4).
  List<BoxShadow> get actionGlow => [
    BoxShadow(
      color: action.withValues(alpha: 0.35),
      offset: const Offset(0, 6),
      blurRadius: 16,
    ),
  ];

  /// The default approved identity — Midnight Navy + vivid Ember, with the
  /// exact reviewed hexes (tokens doc §8/§10) rather than lerp-derived steps.
  static const PosThemePair navyEmber = PosThemePair(
    primary: kPosMidnightNavy,
    primaryHi: Color(0xFF243650),
    primaryDeep: Color(0xFF101B2D),
    action: Color(0xFFD9642B),
    actionHi: Color(0xFFF08236),
    actionDeep: Color(0xFFBE531F),
    actionMark: Color(0xFFE8722C),
    actionSoft: Color(0xFFE8B98C),
    wire: 'navy_ember',
  );

  /// POS-THEME-NAVBAR-POLISH-001 — Forest Green + Charcoal: deep green
  /// structure, the shared ember action family (known-good CTA contrast).
  static final PosThemePair forestCharcoal = PosThemePair.derive(
    primary: const Color(0xFF1E4D3B),
    action: const Color(0xFFD9642B),
    wire: 'forest_charcoal',
  );

  /// Aubergine + Slate: deep aubergine structure with a warm brick action.
  static final PosThemePair aubergineSlate = PosThemePair.derive(
    primary: const Color(0xFF44264A),
    action: const Color(0xFFC65A4B),
    wire: 'aubergine_slate',
  );

  /// Saffron/Gold + Charcoal: charcoal structure, gold action — the one pair
  /// whose action is light, so its CTA ink is a near-black ([onAction]).
  static final PosThemePair saffronGold = PosThemePair.derive(
    primary: const Color(0xFF33312C),
    action: const Color(0xFFD89A2B),
    onAction: const Color(0xFF231A08),
    wire: 'saffron_gold',
  );

  /// The curated device-theme presets (POS-THEME-NAVBAR-POLISH-001): a small,
  /// tasteful set. Semantic + device-accent colours are independent of every
  /// one of them.
  static final List<PosThemePair> presets = [
    navyEmber,
    forestCharcoal,
    aubergineSlate,
    saffronGold,
  ];

  /// Wire lookup for the persisted device choice. Preset wires load exactly
  /// as before; `custom:RRGGBB:RRGGBB` wires decode to the owner-typed pair
  /// (POS-CUSTOM-DEVICE-THEME-010). Unknown/absent/corrupt tokens fall back
  /// to the default pair — a bad stored value must never break a till.
  static PosThemePair fromWire(String? wire) {
    if (wire == null) return navyEmber;
    for (final p in presets) {
      if (p.wire == wire) return p;
    }
    return tryParseCustomWire(wire) ?? navyEmber;
  }

  /// The active pair, falling back to [navyEmber] when the ambient theme does
  /// not carry the extension (bare test themes).
  static PosThemePair of(BuildContext context) =>
      Theme.of(context).extension<PosThemePair>() ?? navyEmber;

  @override
  PosThemePair copyWith({Color? primary, Color? action}) =>
      (primary == null && action == null)
      ? this
      : PosThemePair.derive(
          primary: primary ?? this.primary,
          action: action ?? this.action,
          onAction: onAction,
          onPrimary: onPrimary,
          wire: wire,
        );

  @override
  PosThemePair lerp(PosThemePair? other, double t) {
    if (other == null) return this;
    return PosThemePair(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryHi: Color.lerp(primaryHi, other.primaryHi, t)!,
      primaryDeep: Color.lerp(primaryDeep, other.primaryDeep, t)!,
      action: Color.lerp(action, other.action, t)!,
      actionHi: Color.lerp(actionHi, other.actionHi, t)!,
      actionDeep: Color.lerp(actionDeep, other.actionDeep, t)!,
      actionMark: Color.lerp(actionMark, other.actionMark, t)!,
      actionSoft: Color.lerp(actionSoft, other.actionSoft, t)!,
      onAction: Color.lerp(onAction, other.onAction, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      wire: t < 0.5 ? wire : other.wire,
    );
  }
}

/// The deliberately COOL card edge (tokens doc §8). 007 FRAMELESS: no longer
/// always-on — it appears only as the HOVER/FOCUS separation edge on the
/// otherwise frameless tile.
const Color kPosCardOutline = Color(0xFFDEE5F0);

/// Cart row separators.
const Color kPosRowSeparator = Color(0xFFF1EEE7);

/// The totals block / context-grid bed.
const Color kPosTotalsBed = Color(0xFFFBFAF6);

/// Unselected category-tab pill fill (v4 icon pills).
const Color kPosTabPillBg = Color(0xFFF6F5F1);

/// The tonal "Add more" bed (v4: a cooler tonal so the navy label reads).
const Color kPosTonalAddBg = Color(0xFFEDF2F9);

/// On-navy-bar chrome: the translucent bed the identity chip / sync pill /
/// icon cluster sit in, and their icon ink.
const Color kPosNavbarBed = Color(0x17FFFFFF);
const Color kPosNavbarInk = Color(0xFFE5EBF4);

/// POS-NAVBAR-BRAND-LOCKUP (2026-09-06) — the top-bar ladder and the official
/// BIZBOT lockup that sits at the bar's START edge.
///
/// The bar height ladder rises one modest step over POS-THEME-NAVBAR-POLISH-001
/// (68 / 62 / 56 → 76 / 70 / 62, +11.8 % / +12.9 % / +10.7 %) so the official
/// symbol + English wordmark artwork get breathing room without eating the
/// menu/cart area. The action cluster's 5px vertical margins keep every
/// action ≥ 52dp tall on every step.
///
/// The lockup is the shared [RestoflowBrandMark] (official symbol + the
/// official English wordmark PNG — never typed text), on a Light Neutral
/// brand plate ([kBizbotSurface]) so the charcoal `BIZ` reads on the dark
/// device-theme bar exactly as on the identity board. The plate replaces the
/// former white tile + typed brand name; the symbol side per ladder step is
/// [kPosNavbarBrandMarkWide] / [kPosNavbarBrandMarkTwoPane] /
/// [kPosNavbarBrandMarkCompact]. Below [kPosCompactAppBarWidth] the wordmark
/// yields (symbol-only plate), exactly as the typed title used to.
const double kPosTopBarHeightWide = 76;
const double kPosTopBarHeightTwoPane = 70;
const double kPosTopBarHeightCompact = 62;
const double kPosNavbarBrandMarkWide = 44;
const double kPosNavbarBrandMarkTwoPane = 40;
const double kPosNavbarBrandMarkCompact = 34;

/// Insets of the Light Neutral brand plate around the lockup (wordmark mode)
/// and around the symbol alone (compact mode — the plate must stay as narrow
/// as the former 38 px tile's slot allowed on a 320 px phone bar).
const EdgeInsets kPosNavbarBrandPlateInsets = EdgeInsets.symmetric(
  horizontal: 10,
  vertical: 6,
);
const EdgeInsets kPosNavbarBrandPlateCompactInsets = EdgeInsets.all(4);

/// The plate never takes more than this share of the title slot (the
/// restaurant identity keeps the rest) and never more than this many px; the
/// lockup scales down inside it (the wordmark image is `BoxFit.contain`, the
/// tagline ellipsizes) instead of pushing the bar.
const double kPosNavbarBrandPlateMaxShare = 0.5;
const double kPosNavbarBrandPlateMaxWidth = 200;

/// The least plate width at which the English wordmark is worth showing
/// beside a symbol of [markSize]: symbol + the mark's gap + plate insets +
/// 60 px of wordmark. Below it the plate is symbol-only (the same graceful
/// yield the typed title had), never a squeezed or clipped wordmark.
double posNavbarWordmarkMinPlateWidth(double markSize) =>
    markSize + RestoflowSpacing.md + kPosNavbarBrandPlateInsets.horizontal + 60;

/// The resolved top-bar metrics for a viewport [width]: bar height, symbol
/// side and whether the English wordmark artwork is shown beside the symbol.
typedef PosTopBarMetrics = ({double height, double markSize, bool wordmark});

PosTopBarMetrics posTopBarMetricsFor(double width) {
  final wordmark = width >= 480; // == kPosCompactAppBarWidth (pos_palette)
  if (width >= 1100) {
    return (
      height: kPosTopBarHeightWide,
      markSize: kPosNavbarBrandMarkWide,
      wordmark: wordmark,
    );
  }
  if (width >= RestoflowBreakpoints.posTwoPane) {
    return (
      height: kPosTopBarHeightTwoPane,
      markSize: kPosNavbarBrandMarkTwoPane,
      wordmark: wordmark,
    );
  }
  return (
    height: kPosTopBarHeightCompact,
    markSize: kPosNavbarBrandMarkCompact,
    wordmark: wordmark,
  );
}

/// Floating panel shadow — the borderless two-surface shell (tokens §8).
const List<BoxShadow> kPosPanelFloatShadow = <BoxShadow>[
  BoxShadow(color: Color(0x1416263B), offset: Offset(0, 8), blurRadius: 28),
];

/// POS-FRAMELESS-CARD-POLISH-007 — the product IMAGE TILE's signature
/// silhouette: three 16px corners and ONE small 5px corner at the bottom
/// inline-START (where the title begins). Directional, so it mirrors
/// intentionally between RTL and LTR; restrained on purpose — a quiet
/// asymmetric character, not a decorative cut.
const BorderRadiusDirectional kPosImageTileRadius =
    BorderRadiusDirectional.only(
      topStart: Radius.circular(16),
      topEnd: Radius.circular(16),
      bottomStart: Radius.circular(5),
      bottomEnd: Radius.circular(16),
    );

/// The image tile's soft RESTING shadow — the one floating element of the
/// frameless card (the card shell itself carries no rest shadow). Sized to
/// live inside the tile's 6px card insets: it reads as a soft under-tile
/// cue, never a bleed into the neighbouring cell.
const List<BoxShadow> kPosImageTileShadow = <BoxShadow>[
  BoxShadow(color: Color(0x1716263B), offset: Offset(0, 2), blurRadius: 8),
];

/// The default per-device secondary accent (Mint Leaf). The live value is a
/// device preference — read `posDeviceAccentColorProvider`, not this.
const Color kPosDefaultSecondaryAccent = Color(0xFF4E8B7A);

/// Display font family (headings, panel titles, primary button labels) — the
/// approved v4 FINAL pairing (tokens doc §10). Bundled 700/800; Arabic+Latin.
/// Hebrew display falls through the chain to Rubik.
const String kPosDisplayFontFamily = 'Alexandria';

/// Body font family — Rubik covers Arabic, Hebrew AND Latin in one family
/// (the reason v4 picked it). Bundled 400/500/600/700.
const String kPosBodyFontFamily = 'Rubik';

/// Money digits — Inter with true tabular figures, always inside forced-LTR
/// runs (the existing `posSplitFormattedMoney` promotion). Bundled 700/800;
/// lighter money weights fall back to Rubik's tabular-safe digits.
const String kPosMoneyFontFamily = 'Inter';

/// Shared fallback chain: Rubik first (ar/he/en), then the previous premium
/// pairing (still bundled) so no glyph ever regresses to tofu, then system.
const List<String> kPosFontFallbacks = <String>[
  'Rubik',
  'Tajawal',
  'IBMPlexSansArabic',
  'Segoe UI',
  'Tahoma',
  'Arial',
  'sans-serif',
];

/// Money fallback keeps digits on families with dependable numerals.
const List<String> kPosMoneyFontFallbacks = <String>[
  'Inter',
  'Rubik',
  'IBMPlexSansArabic',
  'Segoe UI',
  'Tahoma',
  'Arial',
  'sans-serif',
];

/// Hover lift for product cards — the approved v4 value (states/motion §7:
/// 0 12 26 @14%, navy-inked like every POS shadow).
const List<BoxShadow> kPosCardHoverShadow = <BoxShadow>[
  BoxShadow(color: Color(0x2416263B), offset: Offset(0, 12), blurRadius: 26),
];

/// The spring toast's shadow.
const List<BoxShadow> kPosToastShadow = <BoxShadow>[
  BoxShadow(color: Color(0x2E0B1526), offset: Offset(0, 8), blurRadius: 24),
];

/// Radius ranking: image tile 16 (007 — the floating hero outranks its
/// hover-edge card) > card 14 > Send 13 > controls 12 > track 10 >
/// pills/badges 7. Card/Send/control values already live in
/// `pos_palette.dart` (`kPosCardRadius`, `kPosSendRadius`, `RestoflowRadii.md`);
/// these two complete the published scale.
const double kPosBadgeRadius = 7;
const double kPosTrackRadius = 10;
