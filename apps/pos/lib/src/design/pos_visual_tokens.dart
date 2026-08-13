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
    this.wire = 'custom',
  });

  /// Derives the lightness steps from a bare {primary, action} pair — the
  /// preset path for non-default restaurant identities.
  factory PosThemePair.derive({
    required Color primary,
    required Color action,
    Color onAction = Colors.white,
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
    wire: wire,
  );

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

  /// Persisted preset identity (POS-THEME-NAVBAR-POLISH-001). Never rename a
  /// wire value without an adoption path.
  final String wire;

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

  /// Wire lookup for the persisted device choice. Unknown/absent tokens fall
  /// back to the default pair — a bad stored value must never break a till.
  static PosThemePair fromWire(String? wire) =>
      presets.firstWhere((p) => p.wire == wire, orElse: () => navyEmber);

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
