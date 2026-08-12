/// POS-PREMIUM-VISUAL-POLISH-001 — the POS screen's premium token layer.
///
/// This file NAMES the palette the owner picked for the cashier surface and
/// scopes it to the POS app. It sits ON TOP of the global navy/white/orange
/// brand (RESTOFLOW-GLOBAL-VISUAL-V0, `RestoflowBrandPalette`) — it never
/// re-values a shared constant, so Dashboard / KDS / Admin are untouched.
///
/// COOL-LAW compliance (pos_visual_v4_test D-251/D-302): the two structural
/// darks below are navy-family (`b > r`, `b > g`). The ONE deliberate warm
/// value is [kPosIvorySurface] — the owner's "restaurant, not SaaS" menu
/// canvas. It is a CANVAS behind merchandise, is not a member of the pinned
/// cool surface family, and must never be used for a control surface.
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

/// Ember Orange — the POS's warm brand note for DECORATIVE moments only:
/// the ambient canvas wash and the CTA shimmer tint. Interactive orange
/// stays the shared brand accent (`RestoflowBrandPalette.accentOrange`);
/// ember never marks a state and never carries text.
const Color kPosEmberOrange = Color(0xFFC96A2B);

/// The default per-device secondary accent (Mint Leaf). The live value is a
/// device preference — read `posDeviceAccentColorProvider`, not this.
const Color kPosDefaultSecondaryAccent = Color(0xFF4E8B7A);

/// Display font family (headings, CTA labels). Bundled — the POS is
/// offline-first, so no runtime font fetching. Tajawal ships 500/700/800
/// (the family has no 600 cut; w600 resolves to the 700 cut).
const String kPosDisplayFontFamily = 'Tajawal';

/// Body font family (everything else, including money digits — IBM Plex has
/// true tabular figures). Bundled weights 400/500/600.
const String kPosBodyFontFamily = 'IBMPlexSansArabic';

/// Shared fallback chain. Hebrew glyphs are not covered by either Arabic
/// family and intentionally fall through to the system stack.
const List<String> kPosFontFallbacks = <String>[
  'IBMPlexSansArabic',
  'Tajawal',
  'Segoe UI',
  'Tahoma',
  'Arial',
  'sans-serif',
];

/// Hover lift for product cards (e2). Navy-inked like every POS shadow
/// (`kRestoflowShadowInk` family — b >= g holds).
const List<BoxShadow> kPosCardHoverShadow = <BoxShadow>[
  BoxShadow(color: Color(0x1A0B1526), offset: Offset(0, 6), blurRadius: 18),
];

/// The spring toast's shadow.
const List<BoxShadow> kPosToastShadow = <BoxShadow>[
  BoxShadow(color: Color(0x2E0B1526), offset: Offset(0, 8), blurRadius: 24),
];

/// Radius ranking (POS_MAIN_VISUAL_SPEC §5): card 14 > Send 13 > controls 12
/// > track 10 > pills/badges 7. Card/Send/control values already live in
/// `pos_palette.dart` (`kPosCardRadius`, `kPosSendRadius`, `RestoflowRadii.md`);
/// these two complete the published scale.
const double kPosBadgeRadius = 7;
const double kPosTrackRadius = 10;
