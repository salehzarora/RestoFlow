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
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            const Divider(height: 1),
            for (final row in rows) _SummaryRowTile(row: row),
          ],
        ),
      ),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            row.label,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          row.trailing ??
              Text(
                row.value ?? '',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
        ],
      ),
    );
  }
}
