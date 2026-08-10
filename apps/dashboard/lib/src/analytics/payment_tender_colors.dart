/// GLOBAL-BRAND-DASHBOARD-V2 — the categorical colour for a payment tender.
///
/// A TENDER IS A CATEGORY, NOT A STATUS. Before V2 the payment donut borrowed
/// `semantic.info` for `bit` and `semantic.warning` for `external`, so an
/// ordinary tender read as a caution to any owner who had learned what amber
/// means elsewhere on the same page — and because the fallback arm was
/// `warning` too, a future server method would have been painted identically to
/// `external`, with no way to tell the two slices apart.
///
/// This lives beside [paymentMethodLabel] deliberately: the label mapper and
/// the colour mapper answer the same question about the same wire token, and
/// splitting them across files is how the legend and the donut drifted apart
/// once already (F0.5).
///
/// It is a PURE function of the palette, the brightness and the wire token, so
/// the mapping can be asserted for every token — including the ones no demo
/// fixture happens to contain, which is exactly where the semantic-tone leak
/// hid from the widget tests.
library;

import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// The categorical hues, named rather than inlined so the contract is legible.
///
/// These are Dashboard-local on purpose. Adding a tender group to
/// [RestoflowBrandPalette] would be a shared-package change, which carries its
/// own ticket (CLAUDE.md §4), and no other app renders a tender mix today.
class _Tender {
  const _Tender._();

  /// Digital wallet (Bit). A teal that no status tone uses.
  static const digitalLight = Color(0xFF0E7490);
  static const digitalDark = Color(0xFF67E8F9);

  /// External / third-party tender. Slate.
  static const externalLight = Color(0xFF64748B);
  static const externalDark = Color(0xFFCBD5E1);

  /// Any token this build does not know. Deliberately DISTINCT from
  /// [externalLight]/[externalDark] so a new server method can never be
  /// mistaken for `external` — the same honesty rule [paymentMethodLabel]
  /// follows when it degrades to the raw token.
  static const unknownLight = Color(0xFF334155);
  static const unknownDark = Color(0xFF94A3B8);
}

/// The colour for one payment [method] wire token.
///
/// `cash` takes the brand accent and `card` the brand navy: the tender an owner
/// physically counts at close is the one worth catching the eye. Neither is a
/// status tone — [RestoflowBrandPalette.accentOrange] is documented as a brand
/// role, not a semantic one.
Color paymentTenderColor({
  required RestoflowBrandPalette palette,
  required Brightness brightness,
  required String method,
}) {
  final dark = brightness == Brightness.dark;
  return switch (method) {
    'cash' => palette.accentOrange,
    'card' => palette.primaryNavy,
    'bit' => dark ? _Tender.digitalDark : _Tender.digitalLight,
    'external' => dark ? _Tender.externalDark : _Tender.externalLight,
    _ => dark ? _Tender.unknownDark : _Tender.unknownLight,
  };
}

/// Resolves [paymentTenderColor] from the ambient theme.
Color paymentTenderColorOf(BuildContext context, String method) =>
    paymentTenderColor(
      palette: RestoflowBrandPalette.from(context),
      brightness: Theme.of(context).brightness,
      method: method,
    );
