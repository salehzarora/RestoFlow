/// The PROPOSED shift status enumeration (RF-037, DECISION D-018; transitions
/// owned by docs/STATE_MACHINES.md §6). Pure Dart.
///
/// Exact baseline values — do not add, rename, or repurpose. `opening` is the
/// stored INITIAL status (the row is created directly into it). Terminal state
/// is `reconciled`.
library;

enum ShiftStatus { opening, open, closing, closed, reconciled }

extension ShiftStatusX on ShiftStatus {
  /// The terminal shift state accepts no further transition (STATE_MACHINES §6).
  bool get isTerminal => this == ShiftStatus.reconciled;
}
