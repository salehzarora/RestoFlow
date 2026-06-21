/// The PROPOSED kitchen-ticket status enumeration (RF-034, DECISION D-018;
/// transitions owned by docs/STATE_MACHINES.md §3). Pure Dart.
///
/// Dart reserves `new`, so the canonical D-018 state `new` is the enum value
/// [newTicket]; [KitchenTicketStatusX.canonicalName] maps it back to `"new"`
/// for display/serialization. `recalled` is NOT a state — it is the audited
/// action `bumped -> in_preparation` (see KitchenTicketStateMachine.recall).
/// Terminal states are `bumped` and `cancelled`.
library;

enum KitchenTicketStatus {
  newTicket,
  acknowledged,
  inPreparation,
  ready,
  bumped,
  cancelled,
}

extension KitchenTicketStatusX on KitchenTicketStatus {
  /// The canonical D-018 / D-017 snake_case state name (e.g. `newTicket` ->
  /// `"new"`, `inPreparation` -> `"in_preparation"`).
  String get canonicalName => switch (this) {
    KitchenTicketStatus.newTicket => 'new',
    KitchenTicketStatus.acknowledged => 'acknowledged',
    KitchenTicketStatus.inPreparation => 'in_preparation',
    KitchenTicketStatus.ready => 'ready',
    KitchenTicketStatus.bumped => 'bumped',
    KitchenTicketStatus.cancelled => 'cancelled',
  };

  /// Terminal ticket states accept no NORMAL transition (STATE_MACHINES §3).
  /// `bumped` is reversible only via the audited recall action.
  bool get isTerminal =>
      this == KitchenTicketStatus.bumped ||
      this == KitchenTicketStatus.cancelled;
}
