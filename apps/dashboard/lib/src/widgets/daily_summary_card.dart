import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// One label/value row in the daily summary. Provide either a [value] string
/// (e.g. formatted money) or a [trailing] widget (e.g. a status pill).
class SummaryRow {
  const SummaryRow({required this.label, this.value, this.trailing});

  final String label;
  final String? value;
  final Widget? trailing;
}

/// The daily summary card: a heading plus a list of label/value rows
/// (net sales, discounts, voids, cash collected, cash variance, shift status).
class DailySummaryCard extends StatelessWidget {
  const DailySummaryCard({required this.title, required this.rows, super.key});

  final String title;
  final List<SummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    // RF-141C: built on the shared section card for consistent chrome.
    return RestoflowSectionCard(
      title: title,
      children: [for (final row in rows) _SummaryRowTile(row: row)],
    );
  }
}

class _SummaryRowTile extends StatelessWidget {
  const _SummaryRowTile({required this.row});

  final SummaryRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
      child: Row(
        children: [
          // RF-127: the label flexes (and wraps) so a long label + value never
          // overflows horizontally at narrow widths; the value stays at natural
          // size at the reading-end.
          Expanded(
            child: Text(
              row.label,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: RestoflowSpacing.md),
          row.trailing ??
              Text(
                row.value ?? '',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.end,
              ),
        ],
      ),
    );
  }
}
