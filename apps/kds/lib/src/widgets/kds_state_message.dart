import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// A centered icon (or spinner) plus a localized message, used for the KDS
/// loading / error / re-auth / empty states so each state reads clearly from a
/// distance instead of being an unexplained icon.
///
/// Design-polish sprint: kitchen-scale restyle — the icon sits in a soft
/// tone-tinted circle (pass [tone] so an error reads red-ish, a re-auth
/// warning amber) and the message uses larger type. Semantics are unchanged:
/// spinner XOR icon, the exact localized [message], and the icon stays
/// reachable via `find.byIcon`.
class KdsStateMessage extends StatelessWidget {
  const KdsStateMessage({
    required this.message,
    this.icon,
    this.showSpinner = false,
    this.tone,
    super.key,
  }) : assert(
         icon != null || showSpinner,
         'KdsStateMessage needs an icon or a spinner',
       );

  final String message;
  final IconData? icon;
  final bool showSpinner;

  /// Semantic accent for the icon circle. Null keeps the quiet neutral look
  /// (loading / empty states).
  final RestoflowTone? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = tone?.styleOf(theme);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: RestoflowPanelWidths.statePanel,
        ),
        child: Padding(
          padding: const EdgeInsets.all(RestoflowSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSpinner)
                const CircularProgressIndicator()
              else
                Container(
                  width: RestoflowIconSizes.hero,
                  height: RestoflowIconSizes.hero,
                  decoration: BoxDecoration(
                    color:
                        style?.container ??
                        theme.colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: RestoflowIconSizes.xl,
                    color:
                        style?.onContainer ??
                        theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: RestoflowSpacing.lg),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
