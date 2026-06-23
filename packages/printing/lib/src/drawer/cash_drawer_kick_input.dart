/// The authoritative, money-free input describing whether a payment should
/// open the cash drawer (RF-074).
///
/// It carries ONLY tenant/device scope, the payment id (idempotency anchor),
/// and three pre-evaluated booleans. There is NO money, tax, receipt, or
/// payment-method-enum field, and it imports no domain/data layer — the POS
/// call site (a deferred ticket) derives these flags from the `record_payment`
/// result. Keeping the contract narrow is what lets the drawer kick stay a
/// pure-Dart, at-most-once printer-port command.
class CashDrawerKickInput {
  const CashDrawerKickInput({
    required this.organizationId,
    required this.branchId,
    required this.deviceId,
    required this.paymentId,
    required this.isCompletedCashPayment,
    required this.isVoidedOrCancelled,
    required this.authorized,
  });

  /// Tenant + device scope (DECISION D-001/D-002, D-022 idempotency).
  final String organizationId;
  final String branchId;
  final String deviceId;

  /// The completed payment this kick is for (the idempotency anchor).
  final String paymentId;

  /// True ONLY after a CASH payment has been successfully completed/recorded.
  /// Non-cash or not-yet-completed payments are represented as `false` (the
  /// real payment-method mapper / call site is deferred).
  final bool isCompletedCashPayment;

  /// True for voided/cancelled payments — those must NEVER open the drawer.
  final bool isVoidedOrCancelled;

  /// Caller-provided assertion that the active POS/device session is authorized
  /// to open the drawer. Making this a required precondition means an
  /// unauthorized (or revoked-device) kick is impossible by construction
  /// (SECURITY R-007); the dispatcher refuses when it is false.
  final bool authorized;

  /// Whether this input represents a payment that should open the drawer: a
  /// completed cash payment that is not voided/cancelled. (Scope/authorization
  /// are checked separately by [validateForKick]; this is the no-op gate.)
  bool get shouldKick => isCompletedCashPayment && !isVoidedOrCancelled;

  /// Validate scope + authorization before a kick may be enqueued (RF-074).
  ///
  /// Throws [ArgumentError] for any missing required id and [StateError] when
  /// the session is not [authorized]. It does NOT decide whether to kick —
  /// that is [shouldKick] (a non-cash / voided input is a silent no-op, not an
  /// error).
  void validateForKick() {
    void requireField(String value, String name) {
      if (value.trim().isEmpty) {
        throw ArgumentError.value(value, name, 'must not be empty');
      }
    }

    requireField(organizationId, 'organizationId');
    requireField(branchId, 'branchId');
    requireField(deviceId, 'deviceId');
    requireField(paymentId, 'paymentId');

    if (!authorized) {
      throw StateError(
        'cash drawer kick requires an authorized device/POS session '
        '(paymentId=$paymentId)',
      );
    }
  }
}
