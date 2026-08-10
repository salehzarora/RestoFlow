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
    final value = trailingValue;
    final trailingWidget = trailing;
    final hasTrailing = value != null || trailingWidget != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          // THE TRAILING CLUSTER CAN GIVE GROUND; IT USED TO BE UNABLE TO.
          //
          // The plan value and the status pill were both NON-FLEX children of
          // this Row, so each measured its full intrinsic width however little
          // the row had left, and the row overflowed instead — up to 272px at
          // 390 / 2x, painting the striped bar across an organization's status.
          // A Flexible-bounded Wrap caps the pair at half the row and lets the
          // pill drop under the value when the two no longer fit side by side.
          // The label keeps its Expanded, so the cluster still sits at the
          // reading end at every width that has room for it.
          if (hasTrailing) ...[
            const SizedBox(width: RestoflowSpacing.md),
            Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: RestoflowSpacing.sm,
                runSpacing: RestoflowSpacing.xs,
                children: [
                  if (value != null)
                    Text(
                      value,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (trailingWidget != null) trailingWidget,
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One recent-activity row: the readable summary leads; the raw action key
/// (a wire identifier, deliberately untranslated) is de-emphasized into a
/// small muted pill on the meta line next to the timestamp — danger-toned
/// when the event is a warning (RF-141C).
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
          Text(
            event.summary,
            style: theme.textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: RestoflowSpacing.xs),
          // A Wrap, not a Row. The action key is a RAW WIRE IDENTIFIER
          // (`device.enrollment_code.issued`), deliberately untranslated and
          // arbitrarily long, and it sat in a non-flex pill beside an Expanded
          // timestamp — so the pill took its full intrinsic width and the row
          // overflowed by up to 148px at 390 / 2x. Wrapping lets the timestamp
          // move under the pill instead, which keeps BOTH readable; shortening
          // either would be hiding audit information to save a line.
          Wrap(
            spacing: RestoflowSpacing.sm,
            runSpacing: RestoflowSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              RestoflowStatusPill(
                label: event.action,
                tone: warn ? RestoflowTone.danger : RestoflowTone.neutral,
              ),
              Text(
                event.timestampLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
