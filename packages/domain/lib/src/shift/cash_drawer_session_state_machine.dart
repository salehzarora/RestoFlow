/// Table-driven cash-drawer-session transition validator (RF-037,
/// STATE_MACHINES.md §7). The allowed-edge table is the single source of
/// legality; any transition not listed is rejected. Pure Dart.
///
/// `counting -> active` is the RECOUNT edge; the reason requirement + real
/// authorization are aggregate-level (placeholder) / server-side (RF-055).
library;

import 'cash_drawer_session_status.dart';
import 'shift_exceptions.dart';

abstract final class CashDrawerSessionStateMachine {
  static const Set<(CashDrawerSessionStatus, CashDrawerSessionStatus)> _edges =
      {
        (CashDrawerSessionStatus.opened, CashDrawerSessionStatus.active),
        (CashDrawerSessionStatus.active, CashDrawerSessionStatus.counting),
        (CashDrawerSessionStatus.counting, CashDrawerSessionStatus.closed),
        (
          CashDrawerSessionStatus.counting,
          CashDrawerSessionStatus.active,
        ), // recount
        (CashDrawerSessionStatus.closed, CashDrawerSessionStatus.reconciled),
      };

  /// Whether `from -> to` is a legal cash-drawer-session transition.
  static bool isLegal(
    CashDrawerSessionStatus from,
    CashDrawerSessionStatus to,
  ) => _edges.contains((from, to));

  /// Returns [to] if legal, else throws
  /// [IllegalCashDrawerSessionTransitionException].
  static CashDrawerSessionStatus transition(
    CashDrawerSessionStatus from,
    CashDrawerSessionStatus to,
  ) {
    if (!isLegal(from, to)) {
      throw IllegalCashDrawerSessionTransitionException(from, to);
    }
    return to;
  }
}
