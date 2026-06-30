import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kitchen_order.dart';
import 'kds_status_chip.dart';
import 'kitchen_ticket_print_preview.dart';

/// A large, kitchen-readable order ticket card (RF-117): order number + status
/// chip, order-type / table / elapsed-time chips, the itemised lines with
/// quantities + modifiers/notes, and the single status-gated lifecycle action
/// (Start / Mark ready / Complete / Recall). Money-free (SECURITY T-003).
class KitchenOrderCard extends StatelessWidget {
  const KitchenOrderCard({
    required this.ticket,
    required this.now,
    required this.onStart,
    required this.onMarkReady,
    required this.onComplete,
    required this.onRecall,
    super.key,
  });

  final KitchenOrderTicket ticket;
  final DateTime now;
  final VoidCallback onStart;
  final VoidCallback onMarkReady;
  final VoidCallback onComplete;
  final VoidCallback onRecall;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dineIn = ticket.orderType == OrderType.dineIn;
    final typeLabel = dineIn
        ? l10n.posOrderTypeDineIn
        : l10n.posOrderTypeTakeaway;
    final minutes = now.difference(ticket.submittedAt).inMinutes;
    final elapsed = l10n.kdsElapsedMinutes(minutes < 0 ? 0 : minutes);

    return Card(
      key: Key('kitchen-card-${ticket.ticketId}'),
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
                    ticket.orderNumber,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: RestoflowSpacing.sm),
                KdsStatusChip(status: ticket.status),
                IconButton(
                  key: Key('preview-ticket-${ticket.ticketId}'),
                  onPressed: () => KitchenTicketPrintPreview.show(
                    context,
                    ticket: ticket,
                    now: now,
                  ),
                  icon: const Icon(Icons.print_outlined),
                  tooltip: l10n.kdsPreviewTicketAction,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            Wrap(
              spacing: RestoflowSpacing.sm,
              runSpacing: RestoflowSpacing.xs,
              children: [
                RestoflowStatusPill(
                  icon: dineIn ? Icons.restaurant : Icons.takeout_dining,
                  label: typeLabel,
                ),
                if (dineIn && ticket.tableLabel != null)
                  RestoflowStatusPill(
                    icon: Icons.table_restaurant,
                    label: '${l10n.posTableLabel} ${ticket.tableLabel}',
                  ),
                // Elapsed time is emphasised (info tone) — it's the field the
                // kitchen scans most.
                RestoflowStatusPill(
                  key: Key('elapsed-${ticket.ticketId}'),
                  icon: Icons.schedule,
                  label: elapsed,
                  tone: RestoflowTone.info,
                ),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            const Divider(height: 1),
            const SizedBox(height: RestoflowSpacing.sm),
            for (final item in ticket.items)
              _ItemBlock(item: item, noteLabel: l10n.kdsNoteLabel),
            _ActionButton(
              status: ticket.status,
              l10n: l10n,
              onStart: onStart,
              onMarkReady: onMarkReady,
              onComplete: onComplete,
              onRecall: onRecall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemBlock extends StatelessWidget {
  const _ItemBlock({required this.item, required this.noteLabel});

  final KitchenOrderItem item;
  final String noteLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = '${item.name} ×${item.quantity}';
    final note = item.note;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          if (item.modifiers.isNotEmpty)
            Text(
              '+ ${item.modifiers.join(', ')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (note != null)
            Text(
              '$noteLabel: $note',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}

/// The single status-gated lifecycle action. Forward actions are full-width
/// filled buttons; recall is an outlined button; terminal/no-action renders
/// nothing.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.status,
    required this.l10n,
    required this.onStart,
    required this.onMarkReady,
    required this.onComplete,
    required this.onRecall,
  });

  final KitchenTicketStatus status;
  final AppLocalizations l10n;
  final VoidCallback onStart;
  final VoidCallback onMarkReady;
  final VoidCallback onComplete;
  final VoidCallback onRecall;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case KitchenTicketStatus.newTicket:
      case KitchenTicketStatus.acknowledged:
        return _Forward(
          icon: Icons.play_arrow_rounded,
          label: l10n.kdsStartAction,
          onPressed: onStart,
        );
      case KitchenTicketStatus.inPreparation:
        return _Forward(
          icon: Icons.check_circle_outline,
          label: l10n.kdsReadyAction,
          onPressed: onMarkReady,
        );
      case KitchenTicketStatus.ready:
        return _Forward(
          icon: Icons.done_all,
          label: l10n.kdsCompleteAction,
          onPressed: onComplete,
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
      case KitchenTicketStatus.cancelled:
        return const SizedBox.shrink();
    }
  }
}

class _Forward extends StatelessWidget {
  const _Forward({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: RestoflowSpacing.sm),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ),
    );
  }
}
