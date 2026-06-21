/// The PROPOSED order-item status enumeration (RF-032, DECISION D-018;
/// transitions owned by docs/STATE_MACHINES.md §2). Pure Dart.
///
/// Exact baseline values — do not add, rename, or repurpose. Terminal states
/// are ONLY `voided` and `cancelled`. Note: `served` is the happy-path resting
/// end-of-life but is **non-terminal** because `served -> voided` is allowed.
library;

enum OrderItemStatus {
  pending,
  queued,
  preparing,
  ready,
  served,
  voided,
  cancelled,
}

extension OrderItemStatusX on OrderItemStatus {
  /// Only `voided`/`cancelled` are terminal; `served` is NOT (STATE_MACHINES §2).
  bool get isTerminal =>
      this == OrderItemStatus.voided || this == OrderItemStatus.cancelled;
}
