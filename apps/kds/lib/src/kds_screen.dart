import 'package:flutter/material.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'widgets/kds_board.dart';
import 'widgets/kds_state_message.dart';

/// Local Kitchen Display screen (RF-034, restyled in RF-102): renders
/// fake/local tickets grouped by station with bump/recall actions. Pure UI +
/// the local kitchen state machines — NO repository, backend, persistence, or
/// printing. All chrome text comes from `AppLocalizations`; item/station/ticket
/// data is rendered as-is. No money appears anywhere (SECURITY T-003).
class KdsScreen extends StatefulWidget {
  const KdsScreen({required this.tickets, this.onRecall, super.key});

  /// Local fixture/view models supplied by the caller (no repository).
  final List<KdsTicketView> tickets;

  /// Optional sink for the in-memory recall audit placeholder (test/observer).
  final void Function(RecallAuditEvent event)? onRecall;

  @override
  State<KdsScreen> createState() => _KdsScreenState();
}

class _KdsScreenState extends State<KdsScreen> {
  // Internal placeholders for the recall audit event (RF-034): not user-facing
  // chrome, not persisted, not a real audit row.
  static const String _recallReason = 'recalled from KDS';
  static const String _actorId = 'kds-device';

  /// Last recall audit placeholder produced on this screen (test-accessible).
  RecallAuditEvent? lastRecallEvent;

  /// Advance [ticket] to [to] via the existing forward state-machine edges
  /// (acknowledge / start / mark-ready / bump). Local in-memory only.
  void _advance(KdsTicketView ticket, KitchenTicketStatus to) {
    setState(() {
      ticket.status = KitchenTicketStateMachine.transition(ticket.status, to);
    });
  }

  void _recall(KdsTicketView ticket) {
    final event = KitchenTicketStateMachine.recall(
      kitchenTicketId: ticket.kitchenTicketId,
      from: ticket.status,
      reason: _recallReason,
      actorId: _actorId,
    );
    setState(() {
      ticket.status = event.toStatus; // bumped -> inPreparation
      lastRecallEvent = event;
    });
    widget.onRecall?.call(event);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.kdsAppTitle)),
      body: widget.tickets.isEmpty
          ? KdsStateMessage(
              icon: Icons.restaurant_outlined,
              message: l10n.kdsEmptyState,
            )
          : KdsBoard(
              tickets: widget.tickets,
              l10n: l10n,
              onAdvance: _advance,
              onRecall: _recall,
            ),
    );
  }
}
