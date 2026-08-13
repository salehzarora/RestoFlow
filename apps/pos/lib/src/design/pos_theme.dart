/// POS-PREMIUM-VISUAL-POLISH-001 — the POS app theme: the shared light brand
/// theme plus the bundled display/body font pairing.
///
/// POS-SCOPED ON PURPOSE. Fonts are applied here (the app entry's ThemeData),
/// never inside `packages/design_system`, so Dashboard / KDS / Admin keep the
/// system stack untouched. Colors, component themes and semantics all come
/// from [restoflowLightBrandTheme] unchanged.
///
/// Pairing (POS-DESIGN-HANDOFF-IMPLEMENTATION-004, approved v4 tokens §10):
/// Alexandria for display — headings, panel titles and primary action labels —
/// and Rubik for body text (one family covering Arabic, Hebrew AND Latin).
/// Money digits get Inter at their call sites ([kPosMoneyFontFamily]); the
/// receipt rasterizer's 'Roboto' path is untouched.
///
/// POS-THEME-NAVBAR-POLISH-001: the device's [PosThemePair] is registered as
/// a ThemeExtension AND the colorScheme's PRIMARY role follows the pair, so
/// every POS surface — including PIN/pairing — re-leads under the selected
/// device theme (colour-only; the owner-approved device-theme behaviour).
library;

import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

import 'pos_visual_tokens.dart';

/// POS-THEME-NAVBAR-POLISH-001: the theme is built per device-selected
/// [PosThemePair] (cached per pair). The pair's PRIMARY also becomes the
/// theme's primary role, so themed Material controls (filled buttons,
/// selections, focus, spinners) follow the device identity — a green-led
/// preset genuinely reads green-led, not navy-with-green-corners.
ThemeData posPremiumTheme({PosThemePair pair = PosThemePair.navyEmber}) =>
    // Cache PRESET pairs only: 'custom' is not a faithful identity (derive/
    // copyWith default to it), so two distinct custom pairs must never
    // collide on one cache slot. Non-preset pairs simply build fresh.
    pair.wire == 'custom' ? _build(pair) : _cached[pair.wire] ??= _build(pair);

final Map<String, ThemeData> _cached = {};

TextStyle? _display(TextStyle? s) => s?.copyWith(
  fontFamily: kPosDisplayFontFamily,
  fontFamilyFallback: kPosFontFallbacks,
);

TextStyle? _body(TextStyle? s) => s?.copyWith(
  fontFamily: kPosBodyFontFamily,
  fontFamilyFallback: kPosFontFallbacks,
);

ThemeData _build(PosThemePair pair) {
  final base = restoflowLightBrandTheme();
  final t = base.textTheme;
  return base.copyWith(
    // The two-token device identity. rf-primary/rf-action consumers read the
    // extension; the colorScheme primary follows the pair so every themed
    // Material control (buttons, selections, focus, progress) recolors too.
    extensions: [...base.extensions.values, pair],
    colorScheme: base.colorScheme.copyWith(
      primary: pair.primary,
      onPrimary: Colors.white,
    ),
    textTheme: t.copyWith(
      // Display voice: screen/section headings + prominent action labels.
      displayLarge: _display(t.displayLarge),
      displayMedium: _display(t.displayMedium),
      displaySmall: _display(t.displaySmall),
      headlineLarge: _display(t.headlineLarge),
      headlineMedium: _display(t.headlineMedium),
      headlineSmall: _display(t.headlineSmall),
      titleLarge: _display(t.titleLarge),
      labelLarge: _display(t.labelLarge),
      // Body voice: everything the cashier reads continuously — item names,
      // modifiers, meta, inputs, and every money figure.
      titleMedium: _body(t.titleMedium),
      titleSmall: _body(t.titleSmall),
      bodyLarge: _body(t.bodyLarge),
      bodyMedium: _body(t.bodyMedium),
      bodySmall: _body(t.bodySmall),
      labelMedium: _body(t.labelMedium),
      labelSmall: _body(t.labelSmall),
    ),
  );
}
