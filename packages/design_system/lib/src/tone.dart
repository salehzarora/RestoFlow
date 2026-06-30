import 'package:flutter/material.dart';

/// The shared SEMANTIC tone used by the RestoFlow components (RF-141A).
///
/// One tone vocabulary across every app so a "warning" chip in POS looks like a
/// "warning" chip in the dashboard. Each tone resolves to standard Material 3
/// [ColorScheme] roles only — there are NO hardcoded colours, so tones stay
/// fully themeable (and adapt to a future dark theme / re-seed). The banner's
/// "caution" maps to [RestoflowTone.warning] (a single tone model, by design).
enum RestoflowTone {
  /// Quiet, default chrome (e.g. an ordinary status pill).
  neutral,

  /// Informational (e.g. a demo-data notice).
  info,

  /// Positive / healthy (e.g. an active, paid, or live state).
  success,

  /// Needs attention but not an error (e.g. a stale/limited state).
  warning,

  /// Error / blocking (e.g. a failure or a suspended/voided state).
  danger,
}

/// The resolved colours + default icon for a [RestoflowTone], derived from a
/// [ColorScheme]. [container]/[onContainer] are for filled chips and banners;
/// [accent] is the emphasis colour to use on a plain surface (e.g. a card or
/// scaffold background) where a container fill would be wrong.
@immutable
class RestoflowToneStyle {
  const RestoflowToneStyle({
    required this.container,
    required this.onContainer,
    required this.accent,
    required this.icon,
  });

  /// Filled background for chips/banners.
  final Color container;

  /// Text/icon colour that sits on [container].
  final Color onContainer;

  /// Emphasis colour for use on a plain surface (cards, scaffold).
  final Color accent;

  /// The tone's default leading icon.
  final IconData icon;
}

/// Resolves a [RestoflowTone] to its [RestoflowToneStyle]. Each tone maps to a
/// DISTINCT, standard [ColorScheme] container role (surface / primary /
/// secondary / tertiary / error), so the five tones are visually separable
/// without any custom palette.
extension RestoflowToneResolver on RestoflowTone {
  RestoflowToneStyle style(ColorScheme scheme) {
    switch (this) {
      case RestoflowTone.neutral:
        return RestoflowToneStyle(
          container: scheme.surfaceContainerHighest,
          onContainer: scheme.onSurfaceVariant,
          accent: scheme.onSurfaceVariant,
          icon: Icons.info_outline,
        );
      case RestoflowTone.info:
        return RestoflowToneStyle(
          container: scheme.primaryContainer,
          onContainer: scheme.onPrimaryContainer,
          accent: scheme.primary,
          icon: Icons.info_outline,
        );
      case RestoflowTone.success:
        return RestoflowToneStyle(
          container: scheme.secondaryContainer,
          onContainer: scheme.onSecondaryContainer,
          accent: scheme.secondary,
          icon: Icons.check_circle_outline,
        );
      case RestoflowTone.warning:
        return RestoflowToneStyle(
          container: scheme.tertiaryContainer,
          onContainer: scheme.onTertiaryContainer,
          accent: scheme.tertiary,
          icon: Icons.warning_amber_outlined,
        );
      case RestoflowTone.danger:
        return RestoflowToneStyle(
          container: scheme.errorContainer,
          onContainer: scheme.onErrorContainer,
          accent: scheme.error,
          icon: Icons.error_outline,
        );
    }
  }
}
