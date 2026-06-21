/// In-memory cash-drawer-session aggregate (RF-037): a cash accounting session
/// BOUND to exactly one shift, driving the drawer state machine and holding the
/// integer minor-unit reconciliation values (DOMAIN_MODEL.md §8.3). Pure Dart —
/// NOT persisted, NOT synced, NO audit write, NO authorization (RF-055).
///
/// Money is plain integer minor units (DECISION D-007); no `packages/money`
/// dependency. Variance = `counted - expected` (MONEY_AND_TAX_SPEC §14).
library;

import 'cash_drawer_session_state_machine.dart';
import 'cash_drawer_session_status.dart';
import 'shift_exceptions.dart';

class CashDrawerSession {
  CashDrawerSession({
    required this.cashDrawerSessionId,
    required this.shiftId,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.openingFloatMinor,
    this.deviceId,
  }) {
    if (shiftId.trim().isEmpty) {
      // A session MUST be bound to a shift (RF-037 AC#1).
      throw const UnboundCashDrawerSessionException();
    }
    _requireNonEmpty(cashDrawerSessionId, 'cashDrawerSessionId');
    _requireNonEmpty(organizationId, 'organizationId');
    _requireNonEmpty(restaurantId, 'restaurantId');
    _requireNonEmpty(branchId, 'branchId');
    if (openingFloatMinor < 0) {
      throw const InvalidMinorAmountException(
        'openingFloatMinor must not be negative',
      );
    }
  }

  final String cashDrawerSessionId;

  /// The bound shift (required, immutable — a session cannot be rebound).
  final String shiftId;

  final String organizationId;
  final String restaurantId;
  final String branchId;

  /// Optional originating device (placeholder; not a real device identity).
  final String? deviceId;

  /// Opening float in integer minor units (DECISION D-007); non-negative.
  final int openingFloatMinor;

  CashDrawerSessionStatus _status = CashDrawerSessionStatus.opened;
  CashDrawerSessionStatus get status => _status;
  bool get isTerminal => _status.isTerminal;

  // Reconciliation values (integer minor units), set at count.
  int? _expectedCashMinor;
  int? _countedAmountMinor;
  int? _varianceMinor;
  int? get expectedCashMinor => _expectedCashMinor;
  int? get countedAmountMinor => _countedAmountMinor;
  int? get varianceMinor => _varianceMinor;

  void activate() => _to(CashDrawerSessionStatus.active);

  void startCounting() => _to(CashDrawerSessionStatus.counting);

  /// Recount (`counting -> active`). Requires a non-empty [reason] (placeholder;
  /// real manager authorization is RF-055).
  void recount(String reason) {
    _requireReason(reason);
    _to(CashDrawerSessionStatus.active);
  }

  /// Close/count step (`counting -> closed`): records expected + counted and
  /// computes `varianceMinor = countedAmountMinor - expectedCashMinor`. Expected
  /// is an injected input (not computed from payments — RF-054).
  void recordCount({
    required int expectedCashMinor,
    required int countedAmountMinor,
  }) {
    _status = CashDrawerSessionStateMachine.transition(
      _status,
      CashDrawerSessionStatus.closed,
    );
    _expectedCashMinor = expectedCashMinor;
    _countedAmountMinor = countedAmountMinor;
    _varianceMinor = countedAmountMinor - expectedCashMinor;
  }

  /// Reconciliation finalization (`closed -> reconciled`). Terminal afterward.
  void reconcile() => _to(CashDrawerSessionStatus.reconciled);

  void _to(CashDrawerSessionStatus to) {
    _status = CashDrawerSessionStateMachine.transition(_status, to);
  }

  static void _requireNonEmpty(String value, String field) {
    if (value.trim().isEmpty) {
      throw InvalidCashDrawerSessionException('$field must not be empty');
    }
  }

  void _requireReason(String reason) {
    if (reason.trim().isEmpty) {
      throw const MissingShiftReasonException();
    }
  }
}
