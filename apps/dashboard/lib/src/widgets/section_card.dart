import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// A simple leading-label / trailing-value row for a section card (RF-141C: the
/// section container is now the shared [RestoflowSectionCard]). [label] and
/// [trailingValue] are pre-built data strings; [secondary] is an optional muted
/// sub-line under the label (e.g. an item quantity).
class SectionRow extends StatelessWidget {
  const SectionRow({
    required this.label,
    required this.trailingValue,
    this.secondary,
    super.key,
  });

  final String label;
  final String trailingValue;
  final String? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (secondary != null)
                  Text(
                    secondary!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: RestoflowSpacing.md),
          // CLIENT-D: flexible with a LOOSE fit — natural width whenever there
          // is room (so nothing that renders today moves), ellipsized only when
          // a four-figure amount at a large text scale would otherwise push the
          // row past the card edge.
          Flexible(
            child: Text(
              trailingValue,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
