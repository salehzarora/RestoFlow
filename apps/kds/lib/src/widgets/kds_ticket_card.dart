import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'kds_status_chip.dart';

/// A polished KDS ticket card: a header row (the HUMAN order number — the same
/// `displayOrderCode` the POS shows — + colour-coded status chip), order-type/
/// table/station pills, large readable item lines with their modifier and note
/// sub-lines, the order-level note, and the status-gated lifecycle action.
///
/// RF-103: the action advances the ticket through its existing lifecycle —
/// Acknowledge / Start / Mark ready / Bump (forward, via [onAdvance]) and Recall
/// (via [onRecall]). Presentation only; the screen runs the existing
/// `KitchenTicketStateMachine`. No money is shown anywhere (SECURITY T-003).
///
/// Design-polish sprint: kitchen-readable type scale (the order number and item
/// lines read from across a pass), a 4px status-accent start edge matching the
/// chip's tone, warning-accent notes, and ≥48dp full-width actions.
class KdsTicketCard extends StatelessWidget {
  const KdsTicketCard({
    required this.ticket,
    required this.l10n,
    required this.onAdvance,
    required this.onRecall,
    this.printStatus,
    super.key,
  });

  final KdsTicketView ticket;
  final AppLocalizations l10n;

  /// Advance the ticket to [to] via the existing state machine (forward edges).
  final void Function(KitchenTicketStatus to) onAdvance;

  /// Recall a bumped ticket (existing audited `bumped -> in_preparation`).
  /// Null hides the action (the LIVE board — forward-only backend).
  final VoidCallback? onRecall;

  /// Optional kitchen print-job status label (device settings sprint,
  /// Part D): a small honest line ("prepared — bridge required" etc.) after
  /// the acknowledge trigger. Null renders nothing (demo boards). Never
  /// money — it is a chrome label from l10n.
  final String? printStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The HUMAN number leads; demo fixtures without one keep the ticket id.
    final ticketHeader =
        ticket.orderNumber ??
        '${l10n.kdsTicketLabel} ${ticket.kitchenTicketId}';
    final dineIn = ticket.orderType == 'dine_in';
    final takeaway = ticket.orderType == 'takeaway';
    final tableLabel = ticket.tableLabel;
    final showStation =
        ticket.stationId != KdsTicketMapper.unassignedStation &&
        ticket.stationId.isNotEmpty;
    // The status accent shares the chip's tone map, so the edge and the chip
    // can never disagree; notes use the warning accent (a kitchen instruction
    // demands attention, and `tertiary` was unreadable on the dark board).
    final statusAccent = kdsStatusTone(ticket.status).styleOf(theme).accent;
    final noteColor = RestoflowTone.warning.styleOf(theme).accent;

    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: RestoflowSpacing.md),
      color: theme.colorScheme.surfaceContainerLow,
      child: Container(
        decoration: BoxDecoration(
          border: BorderDirectional(
            start: BorderSide(color: statusAccent, width: 4),
          ),
        ),
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
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: RestoflowSpacing.sm),
                  KdsStatusChip(status: ticket.status),
                ],
              ),
              if (dineIn || takeaway || tableLabel != null || showStation) ...[
                const SizedBox(height: RestoflowSpacing.sm),
                Wrap(
                  spacing: RestoflowSpacing.sm,
                  runSpacing: RestoflowSpacing.xs,
                  children: [
                    if (dineIn)
                      RestoflowStatusPill(
                        icon: Icons.restaurant,
                        label: l10n.posOrderTypeDineIn,
                      ),
                    if (takeaway)
                      RestoflowStatusPill(
                        icon: Icons.takeout_dining,
                        label: l10n.posOrderTypeTakeaway,
                      ),
                    if (tableLabel != null)
                      RestoflowStatusPill(
                        icon: Icons.event_seat,
                        label: '${l10n.posTableLabel} $tableLabel',
                      ),
                    if (showStation)
                      RestoflowStatusPill(
                        icon: Icons.kitchen_outlined,
                        label: '${l10n.kdsStationLabel}: ${ticket.stationId}',
                      ),
                  ],
                ),
              ],
              const SizedBox(height: RestoflowSpacing.sm),
              const Divider(height: 1),
              const SizedBox(height: RestoflowSpacing.sm),
              for (final item in ticket.items)
                _ItemLine(item: item, l10n: l10n, noteColor: noteColor),
              if (ticket.notes case final note?) ...[
                const SizedBox(height: RestoflowSpacing.xs),
                Text(
                  '${l10n.kdsNoteLabel}: $note',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: noteColor,
                  ),
                ),
              ],
              if (printStatus case final status?) ...[
                const SizedBox(height: RestoflowSpacing.xs),
                Row(
                  key: const Key('ticket-print-status'),
                  children: [
                    Icon(
                      Icons.print_outlined,
                      size: RestoflowIconSizes.sm,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: RestoflowSpacing.xs),
                    Expanded(
                      child: Text(
                        '${l10n.kdsTicketPrintLabel}: $status',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              _TicketAction(
                status: ticket.status,
                l10n: l10n,
                onAdvance: onAdvance,
                onRecall: onRecall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemLine extends StatelessWidget {
  const _ItemLine({
    required this.item,
    required this.l10n,
    required this.noteColor,
  });

  final KdsItemView item;
  final AppLocalizations l10n;
  final Color noteColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Data text (item name + quantity), rendered as a single Text. Kept in the
    // exact '{name} ×{quantity}' form (U+00D7) — readable, money-free.
    final line = '${item.name} ×${item.quantity}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          // Modifier options as their own readable sub-lines (never money).
          for (final modifier in item.modifiers)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: RestoflowSpacing.md,
              ),
              child: Text(
                '+ $modifier',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (item.note case final note?)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: RestoflowSpacing.md,
              ),
              child: Text(
                '${l10n.kdsNoteLabel}: $note',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: noteColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The single status-gated lifecycle action for a ticket. Forward transitions
/// are filled buttons that call [onAdvance] with the next status; recall is an
/// outlined button. Terminal/no-action statuses render nothing. All actions
/// are full-width and ≥48dp tall (greasy-finger targets); Bump — the action a
/// kitchen hits most — uses the big touch-first style.
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
  final VoidCallback? onRecall;

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
          style: RestoflowButtonStyles.big(context),
          onPressed: () => onAdvance(KitchenTicketStatus.bumped),
        );
      case KitchenTicketStatus.bumped:
        // No recall sink (the LIVE board): a bumped ticket shows no action —
        // never a button whose effect would silently revert on the next poll.
        if (onRecall == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsetsDirectional.only(top: RestoflowSpacing.sm),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onRecall,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
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
    this.style,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: RestoflowSpacing.sm),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onPressed,
          style:
              style ??
              FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: Icon(icon),
          label: Text(label),
        ),
      ),
    );
  }
}
