import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'kds_status_chip.dart';

/// A polished KDS ticket card: a header row (ticket id + colour-coded status
/// chip), large readable item lines, and the status-gated lifecycle action.
///
/// RF-103: the action advances the ticket through its existing lifecycle —
/// Acknowledge / Start / Mark ready / Bump (forward, via [onAdvance]) and Recall
/// (via [onRecall]). Presentation only; the screen runs the existing
/// `KitchenTicketStateMachine`. No money is shown anywhere (SECURITY T-003).
class KdsTicketCard extends StatelessWidget {
  const KdsTicketCard({
    required this.ticket,
    required this.l10n,
    required this.onAdvance,
    required this.onRecall,
    super.key,
  });

  final KdsTicketView ticket;
  final AppLocalizations l10n;

  /// Advance the ticket to [to] via the existing state machine (forward edges).
  final void Function(KitchenTicketStatus to) onAdvance;

  /// Recall a bumped ticket (existing audited `bumped -> in_preparation`).
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
              onAdvance: onAdvance,
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

/// The single status-gated lifecycle action for a ticket. Forward transitions
/// are filled buttons that call [onAdvance] with the next status; recall is an
/// outlined button. Terminal/no-action statuses render nothing.
class _TicketAction extends StatelessWidget {
  const _TicketAction({
    required this.status,
    required this.l10n,
    required this.onAdvance,
    required this.onRecall,
  });

  final KitchenTicketStatus status;
  final AppLocalizations l10n;
  final void Function(KitchenTicketStatus to) onAdvance;
  final VoidCallback onRecall;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case KitchenTicketStatus.newTicket:
        return _ForwardButton(
          icon: Icons.visibility_outlined,
          label: l10n.kdsAcknowledgeAction,
          onPressed: () => onAdvance(KitchenTicketStatus.acknowledged),
        );
      case KitchenTicketStatus.acknowledged:
        return _ForwardButton(
          icon: Icons.play_arrow_rounded,
          label: l10n.kdsStartAction,
          onPressed: () => onAdvance(KitchenTicketStatus.inPreparation),
        );
      case KitchenTicketStatus.inPreparation:
        return _ForwardButton(
          icon: Icons.check_circle_outline,
          label: l10n.kdsReadyAction,
          onPressed: () => onAdvance(KitchenTicketStatus.ready),
        );
      case KitchenTicketStatus.ready:
        return _ForwardButton(
          icon: Icons.check,
          label: l10n.kdsBumpAction,
          onPressed: () => onAdvance(KitchenTicketStatus.bumped),
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

class _ForwardButton extends StatelessWidget {
  const _ForwardButton({
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
        ),
      ),
    );
  }
}
