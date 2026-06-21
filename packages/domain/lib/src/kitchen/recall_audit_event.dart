/// In-memory PLACEHOLDER audit event for a kitchen-ticket recall (RF-034).
///
/// A recall (`bumped -> in_preparation`) is an audited action (D-018/D-013
/// target). RF-034 is local-only: this is a pure-Dart value object describing
/// the recall — it is NOT a backend `audit_events` row and is NOT written to any
/// store. The real audited write is owned by the server-side void/audit path
/// (RF-053), not here.
library;

import 'kitchen_ticket_status.dart';

class RecallAuditEvent {
  const RecallAuditEvent({
    required this.kitchenTicketId,
    required this.reason,
    required this.actorId,
  });

  final String kitchenTicketId;

  /// Recall is always `bumped -> in_preparation`.
  KitchenTicketStatus get fromStatus => KitchenTicketStatus.bumped;
  KitchenTicketStatus get toStatus => KitchenTicketStatus.inPreparation;

  /// The required, non-empty recall reason.
  final String reason;

  /// Placeholder actor identifier (NOT a real identity; real auth is RF-050/053).
  final String actorId;

  @override
  bool operator ==(Object other) =>
      other is RecallAuditEvent &&
      other.kitchenTicketId == kitchenTicketId &&
      other.reason == reason &&
      other.actorId == actorId;

  @override
  int get hashCode => Object.hash(kitchenTicketId, reason, actorId);
}
