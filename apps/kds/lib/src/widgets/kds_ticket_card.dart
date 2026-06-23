import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'kds_status_chip.dart';

/// A polished KDS ticket card: a header row (ticket id + colour-coded status
/// chip), large readable item lines, and the status-gated Bump/Recall action.
///
/// Presentation only — bump/recall are delegated to [onBump]/[onRecall] (driven
/// by the kitchen state machine on the screen). No money is shown anywhere
/// (the view models carry none; SECURITY T-003).
class KdsTicketCard extends StatelessWidget {
  const KdsTicketCard({
    required this.ticket,
    required this.l10n,
    required this.onBump,
    required this.onRecall,
    super.key,
  });

  final KdsTicketView ticket;
  final AppLocalizations l10n;
  final VoidCallback onBump;
  final VoidCallback onRecall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ticketHeader = '${l10n.kdsTicketLabel} ${ticket.kitchenTicketId}';

    return Card(
      margin: const EdgeInsets.only(bottom: RestoflowSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ticketHeader,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: RestoflowSpacing.sm),
                KdsStatusChip(status: ticket.status),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            const Divider(height: 1),
            const SizedBox(height: RestoflowSpacing.sm),
            for (final item in ticket.items) _ItemLine(item: item),
            _TicketAction(
              status: ticket.status,
              l10n: l10n,
              onBump: onBump,
              onRecall: onRecall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemLine extends StatelessWidget {
  const _ItemLine({required this.item});

  final KdsItemView item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Data text (item name + quantity), rendered as a single Text. Kept in the
    // exact '{name} ×{quantity}' form (U+00D7) — readable, money-free.
    final line = '${item.name} ×${item.quantity}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      child: Text(
        line,
        style: theme.textTheme.titleMedium?.copyWith(height: 1.2),
      ),
    );
  }
}

class _TicketAction extends StatelessWidget {
  const _TicketAction({
    required this.status,
    required this.l10n,
    required this.onBump,
    required this.onRecall,
  });

  final KitchenTicketStatus status;
  final AppLocalizations l10n;
  final VoidCallback onBump;
  final VoidCallback onRecall;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case KitchenTicketStatus.ready:
        return Padding(
          padding: const EdgeInsets.only(top: RestoflowSpacing.sm),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onBump,
              icon: const Icon(Icons.check),
              label: Text(l10n.kdsBumpAction),
            ),
          ),
        );
      case KitchenTicketStatus.bumped:
        return Padding(
          padding: const EdgeInsets.only(top: RestoflowSpacing.sm),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onRecall,
              icon: const Icon(Icons.undo),
              label: Text(l10n.kdsRecallAction),
            ),
          ),
        );
      case KitchenTicketStatus.newTicket:
      case KitchenTicketStatus.acknowledged:
      case KitchenTicketStatus.inPreparation:
      case KitchenTicketStatus.cancelled:
        return const SizedBox.shrink();
    }
  }
}
