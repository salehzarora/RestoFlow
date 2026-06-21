/// The PROPOSED order status enumeration (RF-032, DECISION D-018; transitions
/// owned by docs/STATE_MACHINES.md §1). Pure Dart; no Flutter/Drift/IO.
///
/// These are the exact baseline values — do not add, rename, or repurpose any
/// (CLAUDE.md invariant 10). Terminal states are `completed`, `cancelled`,
/// `voided`.
library;

enum OrderStatus {
  draft,
  submitted,
  accepted,
  preparing,
  ready,
  served,
  completed,
  cancelled,
  voided,
}

extension OrderStatusX on OrderStatus {
  /// Terminal order states accept no further transitions (STATE_MACHINES §1).
  bool get isTerminal =>
      this == OrderStatus.completed ||
      this == OrderStatus.cancelled ||
      this == OrderStatus.voided;
}
