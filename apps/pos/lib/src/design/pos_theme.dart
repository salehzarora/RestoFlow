/// POS-PREMIUM-VISUAL-POLISH-001 — the POS app theme: the shared light brand
/// theme plus the bundled display/body font pairing.
///
/// POS-SCOPED ON PURPOSE. Fonts are applied here (the app entry's ThemeData),
/// never inside `packages/design_system`, so Dashboard / KDS / Admin keep the
/// system stack untouched. Colors, component themes and semantics all come
/// from [restoflowLightBrandTheme] unchanged.
///
/// Pairing (owner brief): Tajawal for display — headings and action labels —
/// and IBM Plex Sans Arabic for body text, including money digits (IBM Plex
/// carries true tabular figures; `FontFeature.tabularFigures()` call sites
/// keep working). Hebrew falls through [kPosFontFallbacks] to the system
/// stack, and the receipt rasterizer's 'Roboto' path is untouched.
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
