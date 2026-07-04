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
  });

  final String shiftId;
  final String cashDrawerSessionId;
  final int openingFloatMinor;
  final DateTime openedAt;
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
