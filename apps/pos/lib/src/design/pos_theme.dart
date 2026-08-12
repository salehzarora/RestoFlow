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
/// receipt rasterizer's 'Roboto' path is untouched. The approved two-token
/// restaurant theme ([PosThemePair]) is registered here as a ThemeExtension —
/// colours on the shared colorScheme are deliberately NOT re-valued, so the
/// PIN/pairing surfaces (out of this phase's scope) keep today's exact look.
library;

import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

import 'pos_visual_tokens.dart';

ThemeData posPremiumTheme() => _cached ??= _build();

ThemeData? _cached;

TextStyle? _display(TextStyle? s) => s?.copyWith(
  fontFamily: kPosDisplayFontFamily,
  fontFamilyFallback: kPosFontFallbacks,
);

TextStyle? _body(TextStyle? s) => s?.copyWith(
  fontFamily: kPosBodyFontFamily,
  fontFamilyFallback: kPosFontFallbacks,
);

ThemeData _build() {
  final base = restoflowLightBrandTheme();
  final t = base.textTheme;
  return base.copyWith(
    // The approved two-token restaurant identity (default navy+ember). Only
    // rf-primary/rf-action consumers recolor when a restaurant swaps the pair.
    extensions: [...base.extensions.values, PosThemePair.navyEmber],
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
