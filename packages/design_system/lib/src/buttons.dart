import 'package:flutter/material.dart';

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
