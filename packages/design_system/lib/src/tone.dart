import 'package:flutter/material.dart';

import 'semantic_colors.dart';

/// The shared SEMANTIC tone used by the RestoFlow components (RF-141A).
///
/// One tone vocabulary across every app so a "warning" chip in POS looks like a
/// "warning" chip in the dashboard. Since the design-polish sprint, tones
/// resolve through [RestoflowSemanticColors] (TRUE green/amber/red/blue) when
/// the RestoFlow theme is present, and fall back to standard Material 3
/// [ColorScheme] roles otherwise — so components stay renderable in bare
/// [MaterialApp] test harnesses. The banner's "caution" maps to
/// [RestoflowTone.warning] (a single tone model, by design).
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

/// The resolved colours + default icon for a [RestoflowTone].
/// [container]/[onContainer] are for filled chips and banners; [accent] is the
/// emphasis colour to use on a plain surface (e.g. a card or scaffold
/// background) where a container fill would be wrong.
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

/// Resolves a [RestoflowTone] to its [RestoflowToneStyle].
extension RestoflowToneResolver on RestoflowTone {
  /// Scheme-only resolution (the pre-sprint mapping, kept as the fallback and
  /// for callers without a [ThemeData]): each tone maps to a DISTINCT,
  /// standard [ColorScheme] container role.
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

  /// Theme-aware resolution: TRUE semantic colours from
  /// [RestoflowSemanticColors] when present (the RestoFlow theme registers
  /// it), otherwise the [style] scheme fallback. Components should prefer
  /// this.
  RestoflowToneStyle styleOf(ThemeData theme) {
    final semantic = theme.extension<RestoflowSemanticColors>();
    if (semantic == null) return style(theme.colorScheme);
    switch (this) {
      case RestoflowTone.neutral:
        return RestoflowToneStyle(
          container: theme.colorScheme.surfaceContainerHighest,
          onContainer: theme.colorScheme.onSurfaceVariant,
          accent: theme.colorScheme.onSurfaceVariant,
          icon: Icons.info_outline,
        );
      case RestoflowTone.info:
        return RestoflowToneStyle(
          container: semantic.infoContainer,
          onContainer: semantic.onInfoContainer,
          accent: semantic.info,
          icon: Icons.info_outline,
        );
      case RestoflowTone.success:
        return RestoflowToneStyle(
          container: semantic.successContainer,
          onContainer: semantic.onSuccessContainer,
          accent: semantic.success,
          icon: Icons.check_circle_outline,
        );
      case RestoflowTone.warning:
        return RestoflowToneStyle(
          container: semantic.warningContainer,
          onContainer: semantic.onWarningContainer,
          accent: semantic.warning,
          icon: Icons.warning_amber_outlined,
        );
      case RestoflowTone.danger:
        return RestoflowToneStyle(
          container: semantic.dangerContainer,
          onContainer: semantic.onDangerContainer,
          accent: semantic.danger,
          icon: Icons.error_outline,
        );
    }
  }
}

/// Elapsed-time urgency thresholds for kitchen surfaces (DESIGN-001).
///
/// The demo kitchen board shipped these thresholds (design-polish sprint,
/// `elapsedTone` in the demo order card): under [warningMinutes] a ticket is
/// calm, from [warningMinutes] it needs eyes, from [dangerMinutes] it is
/// overdue. Hoisted here so the demo and live boards resolve urgency through
/// ONE map and can never disagree. Deliberately returns one of the EXISTING
/// five [RestoflowTone]s — the tone enum is a frozen 5-value contract
/// (`components_test` pins `RestoflowTone.values` at length 5).
abstract final class RestoflowUrgency {
  /// From this many minutes a ticket renders in the warning tone.
  static const int warningMinutes = 10;

  /// From this many minutes a ticket renders in the danger tone.
  static const int dangerMinutes = 20;

  /// The urgency tone for a ticket open for [minutes] (values below
  /// [warningMinutes], including negatives from clock skew, are calm info).
  static RestoflowTone toneForMinutes(int minutes) {
    if (minutes >= dangerMinutes) return RestoflowTone.danger;
    if (minutes >= warningMinutes) return RestoflowTone.warning;
    return RestoflowTone.info;
  }

  /// Convenience overload for a [Duration] since submit.
  static RestoflowTone toneForElapsed(Duration elapsed) =>
      toneForMinutes(elapsed.inMinutes);
}
