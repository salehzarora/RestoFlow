import 'package:flutter/material.dart';

/// RestoFlow design tokens (RF-100): the small shared scales every surface uses
/// for consistent spacing, corner radius, and brand colour. Intentionally
/// minimal — richer tokens/components land in later UI tickets (DECISION D-014).

/// The RestoFlow brand seed colour (a warm restaurant green). Used as the
/// `ColorScheme.fromSeed` seed by [restoflowBaseTheme].
const Color kRestoflowSeedColor = Color(0xFF1B7A52);

/// 4-point spacing scale (logical pixels).
abstract final class RestoflowSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner-radius scale (logical pixels).
abstract final class RestoflowRadii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;

  /// Fully rounded (pill / circle) radius.
  static const double pill = 999;
}
