/// Table-driven kitchen-ticket transition validator (RF-034, STATE_MACHINES §3).
/// The allowed-edge table is the single source of legality; any transition not
/// listed is rejected. Pure Dart.
///
/// `bumped -> in_preparation` (recall) is intentionally NOT a normal transition:
/// recall is a separate, reason+actor-required, audited action — see [recall].
library;

import 'kitchen_state_exceptions.dart';
import 'kitchen_ticket_status.dart';
import 'recall_audit_event.dart';

abstract final class KitchenTicketStateMachine {
  /// Normal allowed edges (STATE_MACHINES §3.1) — EXCLUDING the recall edge
  /// `bumped -> in_preparation`, which is only reachable via [recall].
  static const Set<(KitchenTicketStatus, KitchenTicketStatus)> _edges = {
    (KitchenTicketStatus.newTicket, KitchenTicketStatus.acknowledged),
    (KitchenTicketStatus.acknowledged, KitchenTicketStatus.inPreparation),
    (KitchenTicketStatus.inPreparation, KitchenTicketStatus.ready),
    (KitchenTicketStatus.ready, KitchenTicketStatus.bumped),
    (KitchenTicketStatus.newTicket, KitchenTicketStatus.cancelled),
    (KitchenTicketStatus.acknowledged, KitchenTicketStatus.cancelled),
    (KitchenTicketStatus.inPreparation, KitchenTicketStatus.cancelled),
    (KitchenTicketStatus.ready, KitchenTicketStatus.cancelled),
  };

  /// Whether `from -> to` is a legal NORMAL kitchen-ticket transition. The
  /// recall action (`bumped -> in_preparation`) is NOT included here.
  static bool isLegal(KitchenTicketStatus from, KitchenTicketStatus to) =>
      _edges.contains((from, to));

  /// Returns [to] if the NORMAL transition is legal, else throws
  /// [IllegalKitchenTicketTransitionException]. Does not perform recall.
  static KitchenTicketStatus transition(
    KitchenTicketStatus from,
    KitchenTicketStatus to,
  ) {
    if (!isLegal(from, to)) {
      throw IllegalKitchenTicketTransitionException(from, to);
    }
    return to;
  }

  /// Recall action: `bumped -> in_preparation`. Requires a non-empty [reason]
  /// and a non-empty [actorId] (placeholder), and returns an in-memory
  /// [RecallAuditEvent] placeholder. Throws
  /// [IllegalKitchenTicketTransitionException] if [from] is not `bumped`,
  /// [MissingRecallReasonException] / [MissingRecallActorException] otherwise.
  static RecallAuditEvent recall({
    required String kitchenTicketId,
    required KitchenTicketStatus from,
    required String reason,
    required String actorId,
  }) {
    if (from != KitchenTicketStatus.bumped) {
      throw IllegalKitchenTicketTransitionException(
        from,
        KitchenTicketStatus.inPreparation,
      );
    }
    if (reason.trim().isEmpty) {
      throw const MissingRecallReasonException();
    }
    if (actorId.trim().isEmpty) {
      throw const MissingRecallActorException();
    }
    return RecallAuditEvent(
      kitchenTicketId: kitchenTicketId,
      reason: reason,
      actorId: actorId,
    );
  }
}
