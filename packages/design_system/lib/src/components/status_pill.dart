import 'package:flutter/material.dart';

import '../tokens.dart';
import '../tone.dart';

/// A small, rounded status chip with a semantic [tone] (RF-141A).
///
/// Replaces the per-app status pills (POS/KDS/dashboard/admin) with one shared
/// widget. [label] is a pre-built string (data or localized chrome — the widget
/// renders it verbatim); colours come from [tone] via the theme, so the chip is
/// themeable and RTL-agnostic (the optional leading [icon] sits at the
/// reading-start via a [Row], which mirrors automatically in RTL).
class RestoflowStatusPill extends StatelessWidget {
  const RestoflowStatusPill({
    required this.label,
    this.tone = RestoflowTone.neutral,
    this.icon,
    super.key,
  });

  final String label;
  final RestoflowTone tone;

  /// Optional leading icon. When null, no icon is shown (the pill is text-only).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = tone.style(theme.colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.sm,
        vertical: RestoflowSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: style.container,
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: style.onContainer),
            const SizedBox(width: RestoflowSpacing.xs),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: style.onContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
