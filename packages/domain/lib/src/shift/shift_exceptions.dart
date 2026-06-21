/// Domain exceptions for the local shift + cash-drawer-session machines (RF-037).
///
/// Messages carry only domain values (state names, short fixed text) — never
/// secrets. Pure Dart.
library;

import 'cash_drawer_session_status.dart';
import 'shift_status.dart';

/// Base type for all shift / cash-drawer-session failures.
abstract class ShiftException implements Exception {
  const ShiftException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// A shift transition not present in the allowed table (STATE_MACHINES §6).
class IllegalShiftTransitionException extends ShiftException {
  IllegalShiftTransitionException(this.from, this.to)
    : super('illegal shift transition: ${from.name} -> ${to.name}');

  final ShiftStatus from;
  final ShiftStatus to;
}

/// A cash-drawer-session transition not present in the allowed table
/// (STATE_MACHINES §7).
class IllegalCashDrawerSessionTransitionException extends ShiftException {
  IllegalCashDrawerSessionTransitionException(this.from, this.to)
    : super(
        'illegal cash drawer session transition: '
        '${from.name} -> ${to.name}',
      );

  final CashDrawerSessionStatus from;
  final CashDrawerSessionStatus to;
}

/// A cash drawer session was missing its (required) shift binding, or was bound
/// to a different shift than the one given.
class UnboundCashDrawerSessionException extends ShiftException {
  const UnboundCashDrawerSessionException([
    super.message = 'a cash drawer session must be bound to exactly one shift',
  ]);
}

/// The shift already hosts an open (non-terminal) cash drawer session.
class ShiftAlreadyHasDrawerException extends ShiftException {
  const ShiftAlreadyHasDrawerException([
    super.message =
        'the shift already has an open (non-terminal) cash drawer session',
  ]);
}

/// The drawer's tenant scope (org/restaurant/branch) does not match the shift's.
class ShiftTenantMismatchException extends ShiftException {
  const ShiftTenantMismatchException([
    super.message = 'shift and cash drawer session tenant scope do not match',
  ]);
}

/// Invalid [Shift] construction data (e.g. an empty required field).
class InvalidShiftException extends ShiftException {
  const InvalidShiftException(super.message);
}

/// Invalid cash-drawer-session construction data (e.g. an empty required field).
class InvalidCashDrawerSessionException extends ShiftException {
  const InvalidCashDrawerSessionException(super.message);
}

/// A reason-requiring action (reopen/recount) was attempted without a reason.
class MissingShiftReasonException extends ShiftException {
  const MissingShiftReasonException([
    super.message = 'a non-empty reason is required',
  ]);
}

/// An integer minor-unit money field was out of its valid range.
class InvalidMinorAmountException extends ShiftException {
  const InvalidMinorAmountException(super.message);
}
