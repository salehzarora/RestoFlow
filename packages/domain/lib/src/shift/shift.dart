/// In-memory shift aggregate (RF-037): an operational work period at a branch,
/// driving the shift state machine and holding the integer minor-unit
/// reconciliation rollup (DOMAIN_MODEL.md §8.2). Pure Dart — NOT persisted, NOT
/// synced, NO audit write, NO authorization (server reconciliation = RF-055).
///
/// Money is plain integer minor units (DECISION D-007); no `packages/money`
/// dependency. Variance = `counted - expected` (MONEY_AND_TAX_SPEC §14).
library;

import 'shift_exceptions.dart';
import 'shift_state_machine.dart';
import 'shift_status.dart';

class Shift {
  Shift({
    required this.shiftId,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    this.openedByEmployeeId,
  }) {
    _requireNonEmpty(shiftId, 'shiftId');
    _requireNonEmpty(organizationId, 'organizationId');
    _requireNonEmpty(restaurantId, 'restaurantId');
    _requireNonEmpty(branchId, 'branchId');
  }

  final String shiftId;
  final String organizationId;
  final String restaurantId;
  final String branchId;

  /// Placeholder actor id only (NOT a real identity; real auth is RF-050).
  final String? openedByEmployeeId;

  ShiftStatus _status = ShiftStatus.opening;
  ShiftStatus get status => _status;
  bool get isTerminal => _status.isTerminal;

  // Reconciliation rollup (integer minor units), set at close/count.
  int? _expectedTotalMinor;
  int? _countedTotalMinor;
  int? _varianceMinor;
  int? get expectedTotalMinor => _expectedTotalMinor;
  int? get countedTotalMinor => _countedTotalMinor;
  int? get varianceMinor => _varianceMinor;

  void open() => _to(ShiftStatus.open);

  void startClosing() => _to(ShiftStatus.closing);

  /// Manager reopen (`closing -> open`). Requires a non-empty [reason]
  /// (placeholder; real manager authorization is RF-055).
  void reopen(String reason) {
    _requireReason(reason);
    _to(ShiftStatus.open);
  }

  /// Close/count step (`closing -> closed`): records the expected + counted
  /// totals and computes `varianceMinor = countedTotalMinor - expectedTotalMinor`.
  /// Expected is an injected input (not computed from payments — RF-054).
  void closeAndCount({
    required int expectedTotalMinor,
    required int countedTotalMinor,
  }) {
    _status = ShiftStateMachine.transition(_status, ShiftStatus.closed);
    _expectedTotalMinor = expectedTotalMinor;
    _countedTotalMinor = countedTotalMinor;
    _varianceMinor = countedTotalMinor - expectedTotalMinor;
  }

  /// Reconciliation finalization (`closed -> reconciled`). Terminal afterward.
  void reconcile() => _to(ShiftStatus.reconciled);

  void _to(ShiftStatus to) {
    _status = ShiftStateMachine.transition(_status, to);
  }

  static void _requireNonEmpty(String value, String field) {
    if (value.trim().isEmpty) {
      throw InvalidShiftException('$field must not be empty');
    }
  }

  void _requireReason(String reason) {
    if (reason.trim().isEmpty) {
      throw const MissingShiftReasonException();
    }
  }
}
