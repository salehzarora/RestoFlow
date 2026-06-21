/// The PROPOSED cash-drawer-session status enumeration (RF-037, DECISION D-018;
/// transitions owned by docs/STATE_MACHINES.md §7). Pure Dart.
///
/// Exact baseline values — do not add, rename, or repurpose. `opened` is the
/// stored INITIAL status (the row is created directly into it, with the opening
/// float). Terminal state is `reconciled`. A session is bound to a shift.
library;

enum CashDrawerSessionStatus { opened, active, counting, closed, reconciled }

extension CashDrawerSessionStatusX on CashDrawerSessionStatus {
  /// The terminal session state accepts no further transition (STATE_MACHINES §7).
  bool get isTerminal => this == CashDrawerSessionStatus.reconciled;
}
