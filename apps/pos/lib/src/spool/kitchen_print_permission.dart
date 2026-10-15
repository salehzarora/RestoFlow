/// A policy read is not a boolean ownership verdict. In particular, missing
/// authority may stop a sender but cannot displace a queued printer owner.
enum KitchenPrintPermission {
  permitted,

  /// Exact, positively established immutable dispatch hold. Only this case
  /// may exclude a queued owner without fabricating a print-state transition.
  held,

  /// Known branch/target restriction. It can later change, so ownership stays.
  blocked,

  /// No trustworthy current authorization: failed read, stale scope/session,
  /// unvalidated restart, or uncertain persistence. Ownership stays intact.
  unknown;

  bool get mayTransmit => this == permitted;
  bool get mayExcludeQueuedOwner => this == held;
}

/// Import/ACK permission includes the operation, not just absence of a hold.
/// Authentic target finish/status uses its separate reserved-attempt contract.
enum KitchenPrintOperation {
  ordinaryImport,
  ordinaryAck,
  targetImport,
  targetAck;

  bool get isTarget => this == targetImport || this == targetAck;
}

/// The exact authenticated claim tuple validated by the target runtime before
/// admission. This is never inferred from a local job name or customer input.
class KitchenPrintTarget {
  KitchenPrintTarget({
    required this.requestId,
    required this.orderId,
    required this.dispatchId,
    required this.decisionId,
    required this.printerAssignmentId,
    bool Function()? isCurrent,
  }) : _isCurrent = isCurrent ?? (() => true);

  final String requestId, orderId, dispatchId, decisionId, printerAssignmentId;
  final bool Function() _isCurrent;
  bool get isCurrent => _isCurrent();
}

/// A per-operation observation. Callers must check [isCurrent] synchronously
/// at invocation, after their last await. It is not a distributed RPC lock.
class KitchenPrintAuthorization {
  KitchenPrintAuthorization({
    required this.operation,
    required this.dispatchId,
    required this.target,
    required bool Function() isCurrent,
    required bool Function(String deviceId, String sessionToken)
    matchesCredential,
  }) : _isCurrent = isCurrent,
       _matchesCredential = matchesCredential;

  final KitchenPrintOperation operation;
  final String dispatchId;
  final KitchenPrintTarget? target;
  final bool Function() _isCurrent;
  final bool Function(String, String) _matchesCredential;

  bool get isCurrent => _isCurrent();
  bool matchesCredential(String deviceId, String sessionToken) =>
      isCurrent && _matchesCredential(deviceId, sessionToken);

  KitchenPrintAuthorization guardedBy(bool Function() current) =>
      KitchenPrintAuthorization(
        operation: operation,
        dispatchId: dispatchId,
        target: target,
        isCurrent: () => current() && isCurrent,
        matchesCredential: _matchesCredential,
      );
}

typedef KitchenPrintAuthorizer =
    Future<KitchenPrintAuthorization?> Function(
      KitchenPrintOperation operation, {
      required String dispatchId,
      KitchenPrintTarget? target,
    });
