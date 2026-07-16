import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A handle to the REAL open shift on this device (RF-113). Captured by
/// [PosSessionController] when it successfully opens a server shift (RF-055
/// auto-open) so the shift-close UI has the `shiftId` to close and the opening
/// float to display. Money is integer minor units (DECISION D-007). Null in demo
/// mode and until a real shift is opened (fail-closed: no handle => the close UI
/// shows an honest "no open shift" state rather than inventing one).
class PosOpenShift {
  const PosOpenShift({
    required this.shiftId,
    required this.cashDrawerSessionId,
    required this.openingFloatMinor,
    required this.openedAt,
    this.expectedCashMinor,
    this.canClose = true,
    this.ownerMismatch = false,
    this.openedByEmployeeProfileId,
  });

  final String shiftId;
  final String cashDrawerSessionId;
  final int openingFloatMinor;
  final DateTime openedAt;

  /// B1 (PILOT-OPERATIONS-CORRECTIONS-001): whether the CURRENT actor may close this
  /// shift (mirrors app.close_shift). False when the open shift belongs to another
  /// employee — the close UI then shows an owner-mismatch state, never a close form
  /// under the wrong name.
  final bool canClose;

  /// B1: the open shift on this device belongs to a DIFFERENT employee.
  final bool ownerMismatch;

  /// B1: the actual owner's employee-profile id (display only).
  final String? openedByEmployeeProfileId;

  /// The SERVER-authoritative expected cash captured when this handle was
  /// recovered (opening float + completed cash payments on the drawer, computed
  /// by the same SQL as `app.close_shift`). Null on a fresh auto-open (no prior
  /// payments) and when the server could not be reached. PILOT-OPERATIONS-CORRECTIONS-001:
  /// the shift-close UI uses this as the base so expected survives an app restart
  /// instead of collapsing to the opening float. Integer minor units (D-007).
  final int? expectedCashMinor;
}

/// Holds the current real open-shift handle (or null). Set by
/// [PosSessionController] after a successful `shift.open`, cleared on sign-out and
/// after a successful close.
class PosOpenShiftController extends Notifier<PosOpenShift?> {
  @override
  PosOpenShift? build() => null;

  void set(PosOpenShift shift) => state = shift;

  void clear() => state = null;
}

final posOpenShiftProvider =
    NotifierProvider<PosOpenShiftController, PosOpenShift?>(
      PosOpenShiftController.new,
    );
