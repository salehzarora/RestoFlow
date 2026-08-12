import 'package:flutter/material.dart';

import 'brand_palette.dart';
import 'semantic_colors.dart';
import 'tokens.dart';

/// Shared button-style variants (design-polish sprint).
///
/// The theme already gives `FilledButton` (primary), `FilledButton.tonal`
/// (secondary), `OutlinedButton`, and `TextButton` (ghost) consistent shapes
/// and ≥44dp targets. These helpers add the remaining product variants —
/// TRUE-semantic danger/success fills and the big touch-first size POS/KDS
/// actions use — resolved from [RestoflowSemanticColors] with a [ColorScheme]
/// fallback so they render in bare test harnesses too.
abstract final class RestoflowButtonStyles {
  /// Large touch-first action (POS send/pay, KDS advance): full-height 52dp.
  static ButtonStyle big(BuildContext context) {
    return FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      textStyle: Theme.of(context).textTheme.titleMedium,
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.xl,
        vertical: RestoflowSpacing.md,
      ),
    );
  }

  // UI-ORANGE-BALANCE-POLISH-001 — the two PRIMARY-action roles.
  //
  // WHICH ONE TO USE. There is exactly one [accent] button in a view: the
  // single highest-value next step (POS "Send order" / "Pay", the Dashboard's
  // one primary CTA). Everything else that is still a primary action uses
  // [navyPrimary], which keeps the navy structure and earns its orange only on
  // focus/press. Two orange fills in one view is the failure mode this split
  // exists to prevent — the accent stops meaning "do this next" the moment it
  // is repeated.
  //
  // Orange here is BRAND identity, so it is read from [RestoflowBrandPalette].
  // It is deliberately NOT read from [RestoflowSemanticColors.accent]: those two
  // happen to hold the same value today, but they are independent types, and
  // sourcing a brand fill from the semantic role is how a future rebrand
  // silently repaints an attention state.

  /// THE single highest-value action in a view — orange fill, white label.
  ///
  /// Contrast: white on the light-preset orange measures 5.18:1, so the label
  /// passes AA at normal text size, not only as a large control.
  static ButtonStyle accent(BuildContext context) {
    final theme = Theme.of(context);
    final brand = RestoflowBrandPalette.of(theme.brightness);
    final fill = brand.accentOrange;
    final onFill = theme.brightness == Brightness.dark
        ? kRestoflowNavyDeep
        : Colors.white;
    return FilledButton.styleFrom(
      backgroundColor: fill,
      foregroundColor: onFill,
      // Depth is a hint, not a slab: the resting card shadow plus one step.
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
      animationDuration: RestoflowDurations.fast,
    ).copyWith(
      // Hover/press deepen the SAME hue rather than switching colour, so the
      // control never looks like it changed meaning mid-interaction.
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return kRestoflowNavyDeep.withValues(alpha: 0.22);
        }
        if (states.contains(WidgetState.hovered)) {
          return kRestoflowNavyDeep.withValues(alpha: 0.12);
        }
        return null;
      }),
      elevation: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return 0.0;
        if (states.contains(WidgetState.pressed)) return 0.0;
        if (states.contains(WidgetState.hovered)) return 3.0;
        return 1.0;
      }),
      // A focus ring the keyboard user can actually see on both grounds.
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return BorderSide(color: brand.primaryNavy, width: 2);
        }
        return BorderSide.none;
      }),
    );
  }

  /// A primary action that keeps the navy structure and earns orange on
  /// interaction — the default for "important, but not THE next step".
  static ButtonStyle navyPrimary(BuildContext context) {
    final theme = Theme.of(context);
    final brand = RestoflowBrandPalette.of(theme.brightness);
    return FilledButton.styleFrom(
      backgroundColor: brand.primaryNavy,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
      animationDuration: RestoflowDurations.fast,
    ).copyWith(
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return brand.accentOrange.withValues(alpha: 0.28);
        }
        if (states.contains(WidgetState.hovered)) {
          return brand.accentOrange.withValues(alpha: 0.16);
        }
        return null;
      }),
      elevation: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return 0.0;
        if (states.contains(WidgetState.pressed)) return 0.0;
        if (states.contains(WidgetState.hovered)) return 3.0;
        return 1.0;
      }),
      // The orange edge IS the focus signal here; the fill stays navy so the
      // structural colour never moves.
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return BorderSide(color: brand.accentOrange, width: 2);
        }
        return BorderSide.none;
      }),
    );
  }

  /// Destructive fill (delete/revoke confirmations).
  static ButtonStyle danger(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<RestoflowSemanticColors>();
    return FilledButton.styleFrom(
      backgroundColor: semantic?.danger ?? theme.colorScheme.error,
      foregroundColor: semantic?.onDanger ?? theme.colorScheme.onError,
    );
  }

  /// Positive fill (confirm/complete moments that deserve a green).
  static ButtonStyle success(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<RestoflowSemanticColors>();
    return FilledButton.styleFrom(
      backgroundColor: semantic?.success ?? theme.colorScheme.primary,
      foregroundColor: semantic?.onSuccess ?? theme.colorScheme.onPrimary,
    );
  }

  /// Low-emphasis destructive (text/outlined delete affordances).
  static ButtonStyle dangerGhost(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<RestoflowSemanticColors>();
    return TextButton.styleFrom(
      foregroundColor: semantic?.danger ?? theme.colorScheme.error,
    );
  }
}

/// The standard inline "busy" spinner that swaps into a button's icon slot
/// while an async action runs — replaces the seven hand-rolled
/// SizedBox+CircularProgressIndicator copies found in the audit.
class RestoflowInlineSpinner extends StatelessWidget {
  const RestoflowInlineSpinner({this.size = 18, this.color, super.key});

  final double size;

  /// Defaults to the ambient icon/foreground colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );
  }
}
