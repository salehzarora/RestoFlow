import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

import '../data/platform_overview.dart';

/// A leading-label / trailing-value row for a [RestoflowSectionCard] (RF-141C:
/// the metric/section/pill/banner chrome now comes from the shared design
/// system; this row + the activity tile stay admin-local). [label] and
/// [trailingValue] are pre-built data strings; [secondary] is an optional muted
/// sub-line; [trailing] is an optional widget (e.g. a warning chip) after the
/// value.
class PlatformSectionRow extends StatelessWidget {
  const PlatformSectionRow({
    required this.label,
    this.trailingValue,
    this.secondary,
    this.trailing,
    super.key,
  });

  final String label;
  final String? trailingValue;
  final String? secondary;
  final Widget? trailing;

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
          if (trailingValue != null) ...[
            const SizedBox(width: RestoflowSpacing.md),
            Text(
              trailingValue!,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: RestoflowSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// One recent-activity row: a shared status pill for the action (danger when it
/// is a warning event, neutral otherwise) + the readable summary on the first
/// line, with the timestamp muted beneath (RF-141C).
class PlatformActivityTile extends StatelessWidget {
  const PlatformActivityTile({required this.event, super.key});

  final ActivityEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warn = event.isWarning;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RestoflowStatusPill(
                label: event.action,
                tone: warn ? RestoflowTone.danger : RestoflowTone.neutral,
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              Expanded(
                child: Text(
                  event.summary,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.xs),
          Text(
            event.timestampLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
