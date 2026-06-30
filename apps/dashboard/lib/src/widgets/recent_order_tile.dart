import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_report.dart';
import '../format/money_format.dart';

/// One recent-orders row: the order number + net total on the first line, then a
/// muted meta line (time · type · table) with a status pill and a paid/unpaid
/// chip. Money is rendered from integer minor units (DECISION D-007); the order
/// number/time/status are data, the paid/unpaid and type/table words are
/// localized chrome.
class RecentOrderTile extends StatelessWidget {
  const RecentOrderTile({required this.row, super.key});

  final RecentOrderRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final type = row.isDineIn
        ? l10n.posOrderTypeDineIn
        : l10n.posOrderTypeTakeaway;
    final table = row.isDineIn && row.tableLabel != null
        ? ' · ${l10n.posTableLabel} ${row.tableLabel}'
        : '';
    final meta = '${row.timeLabel} · $type$table';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.orderNumber,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: RestoflowSpacing.md),
              Text(
                MoneyFormatter.formatMinor(row.totalMinor, row.currencyCode),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.xs),
          Wrap(
            spacing: RestoflowSpacing.sm,
            runSpacing: RestoflowSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                meta,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              // RF-141C: shared status pills (info = order status, success/
              // neutral = paid/unpaid).
              RestoflowStatusPill(label: row.status, tone: RestoflowTone.info),
              RestoflowStatusPill(
                label: row.isPaid ? l10n.dashboardPaid : l10n.dashboardUnpaid,
                tone: row.isPaid
                    ? RestoflowTone.success
                    : RestoflowTone.neutral,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
