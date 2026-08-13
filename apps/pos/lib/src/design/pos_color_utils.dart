/// POS-CUSTOM-DEVICE-THEME-010 — small deterministic color utilities for the
/// per-device CUSTOM theme pair: `#RRGGBB` parsing/formatting and readable-ink
/// selection.
///
/// Pure functions, no Flutter state and no token imports (pos_visual_tokens
/// imports THIS file, so it must stay dependency-free). Appearance-only: none
/// of this ever touches semantic colors or business state.
library;

import 'dart:ui';

/// The dark ink candidate for light custom beds — the POS navy-black family,
/// so a light custom theme still inks like the rest of the surface.
const Color kPosReadableDarkInk = Color(0xFF141C26);

final RegExp _hexRrggbb = RegExp(r'^#?([0-9a-fA-F]{6})$');

/// Parses a user-entered `#RRGGBB` value; `null` when invalid.
///
/// Accepted: exactly six hex digits, either case, with or without the leading
/// `#` (a missing `#` is NORMALIZED, not rejected — cashiers paste bare
/// hexes). Everything else is rejected: shorthand `#RGB`, alpha forms
/// (`#AARRGGBB` / eight digits), separators, and non-hex characters. The
/// result is always fully opaque.
Color? posParseHexColor(String raw) {
  final match = _hexRrggbb.firstMatch(raw.trim());
  if (match == null) return null;
  return Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
}

/// Formats a color as canonical uppercase `#RRGGBB` (alpha dropped).
String posFormatHexColor(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// WCAG relative-contrast ratio between two colors (1..21).
double posContrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Picks the readable foreground ink for an arbitrary bed color: white or the
/// near-black [kPosReadableDarkInk], based on actual contrast.
///
/// White wins when it clears [whiteFloor] OR simply out-contrasts the dark
/// candidate (so the function never picks the measurably worse ink). The
/// default floor of **3.6:1** is the owner-approved shipped ACTION baseline
/// (the white-on-ember Send CTA measures 3.62:1, pinned in
/// pos_premium_visual_phase1_test T3) — custom pairs that pick an ember-like
/// action keep the exact preset ink. PRIMARY-bed callers pass `4.5` (normal
/// body text has no large-bold discount there; every preset primary measures
/// white at 9.6:1+, so presets are unaffected). The dark branch is only
/// taken when it genuinely beats white, so the chosen ink is always the
/// better of the two candidates.
Color posReadableInkOn(Color bed, {double whiteFloor = 3.6}) {
  const white = Color(0xFFFFFFFF);
  final w = posContrastRatio(white, bed);
  return (w >= whiteFloor || w >= posContrastRatio(kPosReadableDarkInk, bed))
      ? white
      : kPosReadableDarkInk;
}

/// Walks [tone] toward white or black — whichever direction suits [bed] —
/// until it measures at least [floor] against the bed, starting the walk at
/// [startT] (pass the legacy fixed-lerp step so already-passing values stay
/// byte-identical). Falls back to the plain readable ink when even the full
/// walk cannot clear the floor (a mid-tone bed where nothing can).
Color posToneForContrast(
  Color tone,
  Color bed, {
  double startT = 0.0,
  double floor = 4.5,
}) {
  const white = Color(0xFFFFFFFF);
  final lighten =
      posContrastRatio(white, bed) >=
      posContrastRatio(kPosReadableDarkInk, bed);
  final target = lighten ? white : const Color(0xFF000000);
  for (var t = startT; t <= 1.0 + 1e-9; t += 0.05) {
    final candidate = Color.lerp(tone, target, t.clamp(0.0, 1.0))!;
    if (posContrastRatio(candidate, bed) >= floor) return candidate;
  }
  return posReadableInkOn(bed, whiteFloor: floor);
}
