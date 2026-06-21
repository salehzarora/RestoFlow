/// In-memory shift ↔ cash-drawer-session binding guard (RF-037 AC#1): a drawer
/// session is bound to EXACTLY ONE shift, and a shift hosts at most one
/// non-terminal drawer session at a time. Pure Dart — no persistence.
library;

import 'cash_drawer_session.dart';
import 'shift.dart';
import 'shift_exceptions.dart';

class ShiftCashDrawerBinding {
  ShiftCashDrawerBinding();

  final List<CashDrawerSession> _bound = [];

  /// Read-only view of the drawer sessions bound so far.
  List<CashDrawerSession> get drawers => List.unmodifiable(_bound);

  /// Binds [drawer] to [shift]. Rejects a drawer bound to a different shift
  /// (`UnboundCashDrawerSessionException`), a tenant mismatch
  /// (`ShiftTenantMismatchException`), or a second OPEN (non-terminal) drawer on
  /// the same shift (`ShiftAlreadyHasDrawerException`). A drawer's `shiftId` is
  /// immutable, so it can never be rebound to another shift.
  void bind({required Shift shift, required CashDrawerSession drawer}) {
    if (drawer.shiftId != shift.shiftId) {
      throw const UnboundCashDrawerSessionException(
        'cash drawer session is bound to a different shift',
      );
    }
    if (drawer.organizationId != shift.organizationId ||
        drawer.restaurantId != shift.restaurantId ||
        drawer.branchId != shift.branchId) {
      throw const ShiftTenantMismatchException();
    }
    final hasOpenDrawer = _bound.any(
      (d) =>
          d.shiftId == shift.shiftId &&
          d.cashDrawerSessionId != drawer.cashDrawerSessionId &&
          !d.isTerminal,
    );
    if (hasOpenDrawer) {
      throw const ShiftAlreadyHasDrawerException();
    }
    _bound.add(drawer);
  }
}
