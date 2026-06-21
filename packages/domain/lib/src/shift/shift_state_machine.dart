/// Table-driven shift transition validator (RF-037, STATE_MACHINES.md §6). The
/// allowed-edge table is the single source of legality; any transition not
/// listed is rejected. Pure Dart.
///
/// `closing -> open` is the manager REOPEN edge; the reason requirement + real
/// authorization are aggregate-level (placeholder) / server-side (RF-055).
library;

import 'shift_exceptions.dart';
import 'shift_status.dart';

abstract final class ShiftStateMachine {
  static const Set<(ShiftStatus, ShiftStatus)> _edges = {
    (ShiftStatus.opening, ShiftStatus.open),
    (ShiftStatus.open, ShiftStatus.closing),
    (ShiftStatus.closing, ShiftStatus.closed),
    (ShiftStatus.closing, ShiftStatus.open), // reopen (correction)
    (ShiftStatus.closed, ShiftStatus.reconciled),
  };

  /// Whether `from -> to` is a legal shift transition.
  static bool isLegal(ShiftStatus from, ShiftStatus to) =>
      _edges.contains((from, to));

  /// Returns [to] if legal, else throws [IllegalShiftTransitionException].
  static ShiftStatus transition(ShiftStatus from, ShiftStatus to) {
    if (!isLegal(from, to)) {
      throw IllegalShiftTransitionException(from, to);
    }
    return to;
  }
}
