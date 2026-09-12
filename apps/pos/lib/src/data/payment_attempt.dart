/// PAYMENT-ATTEMPT-RECOVERY-001 (BCA-MONEY-001) — ONE DURABLE BUSINESS ATTEMPT.
///
/// A cashier's tender decision ("take ₪50 cash for order X") is ONE business
/// attempt with ONE immutable identity: the D-022 idempotency key
/// (`local_operation_id`) and the provisional payment `target_id`. Before this
/// ticket the identity lived in a local variable inside
/// `RealPaymentRepository.recordCashPayment` and died with the call, so after an
/// ambiguous response (the server committed, the reply was lost) the only thing
/// a retry could do was mint a NEW identity — which the server's same-key replay
/// can never recognise, and which its double-charge guard then refuses as a
/// generic failure in front of a customer who has already paid.
///
/// [PaymentAttempt] is that identity made durable: every business input is
/// FROZEN into it before the first network send, the record is persisted BEFORE
/// transmission (see `PaymentAttemptStore`), and every later resume — same
/// process, sheet reopen, restart — re-sends exactly these bytes under exactly
/// this key. The server's ledger (`sync_operations`, keyed
/// `(organization_id, device_id, local_operation_id)` + payload fingerprint)
/// then answers with the ORIGINAL outcome, whatever it was.
///
/// ALLOWLISTED SCHEMA. The record carries identifiers and integer minor-unit
/// money only. It NEVER carries a PIN, a PIN-session id (a bearer capability —
/// the current session stays in the protected runtime transport), a device
/// token, a JWT, a service-role value, customer name/phone/email, a whole order
/// snapshot, request headers, or raw provider/backend text.
library;

import 'ids.dart';
import 'order_identity.dart';
import 'payment.dart';

/// The lifecycle phase persisted with an attempt.
///
/// `pending` covers "persisted, may or may not have been sent, outcome unknown"
/// — the ONLY safe reading of a record that survives a crash. The finer
/// in-memory distinctions (persisted-unsent, in-flight, unconfirmed) live in
/// `PaymentAttemptOutcome` / the controller, never on disk, because a crash
/// between "sent" and "outcome received" makes them indistinguishable anyway.
enum PaymentAttemptPhase {
  /// Persisted; the authoritative outcome is not yet known.
  pending('pending'),

  /// The server applied THIS attempt (or replayed its applied result).
  accepted('accepted'),

  /// The server definitively refused THIS attempt (memoized or rolled back);
  /// this identity can never become a payment.
  refused('refused'),

  /// THIS attempt was refused AND the order is settled — by another attempt
  /// or another till. Not our payment; no receipt/drawer effects for us.
  settledElsewhere('settled_elsewhere');

  const PaymentAttemptPhase(this.wire);
  final String wire;

  static PaymentAttemptPhase? fromWire(Object? wire) {
    for (final p in values) {
      if (p.wire == wire) return p;
    }
    return null;
  }

  bool get isResolved => this != pending;
}

/// The last thing the client learned while the attempt stayed `pending`.
/// Persisted so a reopened sheet can say the right thing; never authoritative.
enum PaymentAttemptLastOutcome {
  none('none'),

  /// Sent; the reply was lost / unreadable — the server MAY have committed.
  unconfirmed('unconfirmed'),

  /// The transport proved the request did not commit (a rolled-back server
  /// error, a gateway refusal before execution). Safe to resume under the
  /// same key.
  notApplied('not_applied'),

  /// The session was refused; sign in again, then resume the SAME attempt.
  authRequired('auth_required'),

  /// The server holds a DIFFERENT operation under this key (a fingerprint
  /// collision). Cannot be resolved automatically; manager assistance.
  collision('collision');

  const PaymentAttemptLastOutcome(this.wire);
  final String wire;

  static PaymentAttemptLastOutcome? fromWire(Object? wire) {
    for (final o in values) {
      if (o.wire == wire) return o;
    }
    return null;
  }
}

/// The order statuses the authoritative payment path can report.
///
/// `app.record_payment` returns `order_status` as either the literal
/// `'completed'` (when it auto-completed a served order) or the order's own
/// current status
/// (`20260716090000_settlement_and_void_error_contracts.sql:400-409`), and the
/// order status column is constrained to exactly this set
/// (`20260621130000_rf052_submit_order_rpc.sql:73`). Anything else is a value
/// this build cannot interpret, so it is refused rather than displayed.
const Set<String> kAuthoritativeOrderStatuses = <String>{
  'draft',
  'submitted',
  'accepted',
  'preparing',
  'ready',
  'served',
  'completed',
  'cancelled',
  'voided',
};

/// The typed reason a server DEFINITIVELY refused an attempt. Every value maps
/// to the server's stable tokens (never a raw message, never a SQLSTATE the
/// client sniffed on its own).
enum PaymentRefusalCode {
  /// `order_not_chargeable` — a zero-total order owes nothing.
  notChargeable('order_not_chargeable'),

  /// SQLSTATE 40001 classified as `conflict` — the order moved.
  revisionConflict('conflict'),

  /// `detail: precondition_failed` — no open shift / active drawer on THIS
  /// device.
  shiftRequired('precondition_failed'),

  /// `permission_denied` — the actor's role may not record payments.
  permissionDenied('permission_denied'),

  /// `detail: revoked_employee` — the membership is no longer active.
  revokedEmployee('revoked_employee'),

  /// Every other memoized rejection (order not found / illegal state / already
  /// has a completed payment / …). The client never learns which; the
  /// authoritative order read decides whether the order is in fact settled.
  generic('rejected');

  const PaymentRefusalCode(this.wire);
  final String wire;

  /// The code for a wire value, or null when this build does not recognise it.
  ///
  /// PDR-008: this deliberately does NOT fall back to [generic]. A stored
  /// value written by a future build, or damaged in place, is evidence this
  /// build cannot interpret — and interpreting it as a known terminal refusal
  /// would let a corrupt record resolve an attempt and free a new payment
  /// identity. Unknown values are quarantined by [PaymentAttempt.fromJson]
  /// instead, with the raw bytes preserved.
  static PaymentRefusalCode? fromWire(Object? wire) {
    for (final c in values) {
      if (c.wire == wire) return c;
    }
    return null;
  }
}

/// Why an attempt is UNCONFIRMED rather than accepted or refused.
enum PaymentUnconfirmedReason {
  /// Timeout / connection loss / 5xx after the request may have been sent.
  transport,

  /// The reply was not a readable `sync_push` envelope.
  malformedResponse,

  /// The reply carried no result for OUR `local_operation_id`.
  mismatchedResult,

  /// The reply said `applied` but its money/identity fields were unusable.
  appliedUnparseable,

  /// The server holds a different operation/payload under our key.
  identityCollision,
}

/// The authoritative result of an ACCEPTED attempt, as persisted.
class PaymentAttemptResolution {
  const PaymentAttemptResolution({
    required this.paymentId,
    required this.receiptNumber,
    required this.changeDueMinor,
    required this.method,
    required this.replay,
    this.orderStatus,
  });

  /// SERVER-authoritative payment id (never the client target id).
  final String paymentId;
  final String receiptNumber;
  final int changeDueMinor;
  final PaymentMethod method;

  /// True when the server answered with `idempotency_replay: true`.
  final bool replay;
  final String? orderStatus;

  Map<String, Object?> toJson() => <String, Object?>{
    'payment_id': paymentId,
    'receipt_number': receiptNumber,
    'change_due_minor': changeDueMinor,
    'method': method.wire,
    'replay': replay,
    if (orderStatus != null) 'order_status': orderStatus,
  };

  /// The keys a resolution may carry. Anything else is a record this build
  /// did not write and may not interpret (S1-F003).
  static const Set<String> allowedKeys = <String>{
    'payment_id',
    'receipt_number',
    'change_due_minor',
    'method',
    'replay',
    'order_status',
  };

  /// STRICT decode. Every failure throws so the store quarantines the raw
  /// bytes verbatim rather than acting on a half-understood resolution.
  ///
  /// [tenderType] is the attempt's frozen tender: an accepted resolution must
  /// name the SAME tender, because a resolution that says the server recorded
  /// a different one is contradictory evidence about where the money went.
  static PaymentAttemptResolution fromJson(Object? raw, {String? tenderType}) {
    if (raw is! Map) throw const FormatException('resolution: not an object');
    for (final k in raw.keys) {
      if (!allowedKeys.contains(k)) {
        throw FormatException('resolution: unknown field $k');
      }
    }
    final paymentId = raw['payment_id'];
    final receipt = raw['receipt_number'];
    final change = raw['change_due_minor'];
    final method = PaymentMethod.fromWire(raw['method']);
    if (paymentId is! String || paymentId.trim().isEmpty) {
      throw const FormatException('resolution: payment_id');
    }
    if (receipt is! String || receipt.trim().isEmpty) {
      throw const FormatException('resolution: receipt_number');
    }
    // Integer minor units, and change handed back is never negative.
    if (change is! int || change < 0) {
      throw const FormatException('resolution: change');
    }
    if (method == null) throw const FormatException('resolution: method');
    if (tenderType != null && method.wire != tenderType) {
      throw const FormatException('resolution: method does not match tender');
    }
    // A wrongly typed replay flag is not "false".
    final replay = raw['replay'];
    if (replay is! bool) throw const FormatException('resolution: replay');
    final orderStatus = raw['order_status'];
    if (orderStatus != null &&
        (orderStatus is! String ||
            !kAuthoritativeOrderStatuses.contains(orderStatus))) {
      // S1-R3 / F003: a stored status outside the authoritative vocabulary is
      // a value this build cannot act on, not merely a non-blank string.
      throw const FormatException('resolution: order_status');
    }
    return PaymentAttemptResolution(
      paymentId: paymentId,
      receiptNumber: receipt,
      changeDueMinor: change,
      method: method,
      replay: replay,
      orderStatus: orderStatus as String?,
    );
  }
}

/// The frozen, durable business attempt. Immutable; every transition returns a
/// new value that keeps the identity and the frozen inputs byte-identical.
class PaymentAttempt {
  const PaymentAttempt({
    required this.localOperationId,
    required this.targetId,
    required this.clientCreatedAt,
    required this.identityKey,
    required this.orderId,
    required this.orderNumber,
    required this.expectedRevision,
    required this.tenderType,
    required this.amountMinor,
    required this.amountTenderedMinor,
    required this.currencyCode,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.deviceId,
    required this.employeeProfileId,
    required this.phase,
    required this.lastOutcome,
    required this.sentAt,
    required this.resolvedAt,
    required this.resolution,
    required this.refusal,
    required this.refusalMemoized,
    required this.autoEffectsReservedAt,
    required this.supersedes,
    this.mayHaveExecuted = false,
  });

  /// Bump ONLY on an incompatible record shape. An unknown version is
  /// QUARANTINED on load (kept verbatim, never dropped, never guessed).
  static const int schemaVersion = 1;

  /// Mints a NEW attempt: two fresh ids (the `local_operation_id`, then the
  /// provisional `target_id` — the same order RF-130 always used) and the
  /// frozen inputs. Called exactly once per cashier decision; a resume never
  /// mints.
  static PaymentAttempt mint({
    required ClientIdGenerator ids,
    required DateTime now,
    required String orderId,
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    required PaymentMethod method,
    required int? expectedRevision,
    required String organizationId,
    required String restaurantId,
    required String branchId,
    required String deviceId,
    required String? employeeProfileId,
    String? supersedes,
  }) {
    final localOperationId = ids.newId();
    final clientPaymentId = ids.newId();
    return PaymentAttempt(
      localOperationId: localOperationId,
      targetId: clientPaymentId,
      clientCreatedAt: now.toUtc().toIso8601String(),
      identityKey: PosOrderIdentity.of(
        orderId: orderId,
        orderNumber: orderNumber,
      ).key,
      orderId: orderId,
      orderNumber: orderNumber,
      expectedRevision: expectedRevision,
      tenderType: method.wire,
      amountMinor: amountMinor,
      // A NON-CASH tender has amount_tendered = the order total (the server
      // forces it anyway; for cash the physical tender is passed through).
      amountTenderedMinor: method.isCash ? tenderedMinor : amountMinor,
      currencyCode: currencyCode,
      organizationId: organizationId,
      restaurantId: restaurantId,
      branchId: branchId,
      deviceId: deviceId,
      employeeProfileId: employeeProfileId,
      phase: PaymentAttemptPhase.pending,
      lastOutcome: PaymentAttemptLastOutcome.none,
      sentAt: null,
      resolvedAt: null,
      resolution: null,
      refusal: null,
      refusalMemoized: false,
      autoEffectsReservedAt: null,
      supersedes: supersedes,
    );
  }

  // ---- immutable identity ----
  final String localOperationId;

  /// The client-provisional payment `target_id`. The RECORDED payment id is
  /// always the server's (see [resolution]).
  final String targetId;

  /// The frozen `client_created_at` wire string — re-sent verbatim.
  final String clientCreatedAt;

  // ---- frozen business inputs ----
  final String identityKey;
  final String orderId;
  final String orderNumber;
  final int? expectedRevision;

  /// `cash` | `card` | `bit` | `external` (RF-117 wire values).
  final String tenderType;

  /// The order total as the cashier saw it (display/guard only; the server
  /// reads its own total and never receives this).
  final int amountMinor;

  /// The physical tender for cash; the order total for non-cash (the server
  /// forces it anyway). Integer minor units.
  final int amountTenderedMinor;
  final String currencyCode;

  // ---- scope binding (plain identifiers, not capabilities) ----
  final String organizationId;
  final String restaurantId;
  final String branchId;
  final String deviceId;

  /// The signed-in employee profile id at confirmation — a NON-SECRET actor
  /// binding. Only the same actor may RESUME (re-send) the attempt; anyone
  /// permitted may read its status.
  final String? employeeProfileId;

  // ---- recovery / effect state ----
  final PaymentAttemptPhase phase;
  final PaymentAttemptLastOutcome lastOutcome;

  /// Set BEFORE the first send. Null only for a record that was persisted but
  /// whose send was never even started (a save-then-crash window).
  final String? sentAt;
  final String? resolvedAt;
  final PaymentAttemptResolution? resolution;

  /// S1-R3 / F004 — MONOTONIC. True once a dispatch for THIS identity has been
  /// started, and never cleared for the life of the attempt.
  ///
  /// It is stamped by [markSent], which the controller applies in the SAME
  /// durable write that creates the record and BEFORE any bytes leave the
  /// device. That ordering is the whole point: if the later write that would
  /// have recorded the ambiguity fails, the record already on disk still says
  /// this identity may have reached the server.
  ///
  /// Codex proved the R2 build could not do this: it carried only the LATEST
  /// outcome, so `unconfirmed -> authRequired` overwrote the ambiguity and a
  /// following non-memoized refusal retired an identity whose money may
  /// already have moved.
  final bool mayHaveExecuted;
  final PaymentRefusalCode? refusal;
  final bool refusalMemoized;

  /// The instant this attempt's AUTOMATIC receipt/drawer triggers were
  /// reserved (durably, BEFORE any I/O). Once set, no path fires them again:
  /// a later replay, restart, sheet reopen or late callback sees the
  /// reservation and leaves the physical outcome as honestly UNKNOWN (the
  /// manual reprint stays available).
  final String? autoEffectsReservedAt;

  /// The earlier (refused / settled-elsewhere) attempt this one corrects, so
  /// history is linked rather than erased.
  final String? supersedes;

  PaymentMethod get method =>
      PaymentMethod.fromWire(tenderType) ?? PaymentMethod.cash;

  bool get isPending => phase == PaymentAttemptPhase.pending;

  /// True when [orderId]/tender/amounts/currency describe the SAME cashier
  /// decision as this attempt (the expected revision is a concurrency token,
  /// not a business input — a refreshed revision does not make a new decision).
  bool sameDecision({
    required String orderId,
    required String tenderType,
    required int amountMinor,
    required int amountTenderedMinor,
    required String currencyCode,
  }) =>
      this.orderId == orderId &&
      this.tenderType == tenderType &&
      this.amountMinor == amountMinor &&
      this.amountTenderedMinor == amountTenderedMinor &&
      this.currencyCode == currencyCode;

  /// The EXACT `sync_push` operation this attempt sends — the same bytes on
  /// every send. `payment.create` is fingerprinted server-side as
  /// `md5(op_type || '|' || payload::text)`, so the payload keys and values
  /// below must never vary between sends of one attempt.
  Map<String, dynamic> toSyncOperation() => <String, dynamic>{
    'local_operation_id': localOperationId,
    'operation_type': 'payment.create',
    'target_entity': 'payment',
    'target_id': targetId,
    'client_created_at': clientCreatedAt,
    'payload': <String, dynamic>{
      'order_id': orderId,
      'tender_type': tenderType,
      'amount_tendered_minor': amountTenderedMinor,
      if (expectedRevision != null) 'expected_revision': expectedRevision,
    },
  };

  /// The [CashPayment] this attempt resolved to, or null while unresolved.
  CashPayment? get payment {
    final r = resolution;
    if (r == null) return null;
    return CashPayment(
      paymentId: r.paymentId,
      orderId: orderId.isEmpty ? null : orderId,
      orderNumber: orderNumber,
      deviceId: deviceId,
      localOperationId: localOperationId,
      method: r.method,
      status: PaymentStatus.completed,
      amountMinor: amountMinor,
      tenderedMinor: amountTenderedMinor,
      changeMinor: r.changeDueMinor,
      currencyCode: currencyCode,
      receiptNumber: r.receiptNumber,
      paidAt: DateTime.tryParse(clientCreatedAt) ?? DateTime.now(),
      orderStatus: r.orderStatus,
    );
  }

  PaymentAttempt _copy({
    PaymentAttemptPhase? phase,
    PaymentAttemptLastOutcome? lastOutcome,
    String? sentAt,
    String? resolvedAt,
    PaymentAttemptResolution? resolution,
    PaymentRefusalCode? refusal,
    bool? refusalMemoized,
    String? autoEffectsReservedAt,
    bool? markExecuted,
  }) => PaymentAttempt(
    localOperationId: localOperationId,
    targetId: targetId,
    clientCreatedAt: clientCreatedAt,
    identityKey: identityKey,
    orderId: orderId,
    orderNumber: orderNumber,
    expectedRevision: expectedRevision,
    tenderType: tenderType,
    amountMinor: amountMinor,
    amountTenderedMinor: amountTenderedMinor,
    currencyCode: currencyCode,
    organizationId: organizationId,
    restaurantId: restaurantId,
    branchId: branchId,
    deviceId: deviceId,
    employeeProfileId: employeeProfileId,
    phase: phase ?? this.phase,
    lastOutcome: lastOutcome ?? this.lastOutcome,
    sentAt: sentAt ?? this.sentAt,
    resolvedAt: resolvedAt ?? this.resolvedAt,
    resolution: resolution ?? this.resolution,
    refusal: refusal ?? this.refusal,
    refusalMemoized: refusalMemoized ?? this.refusalMemoized,
    autoEffectsReservedAt: autoEffectsReservedAt ?? this.autoEffectsReservedAt,
    supersedes: supersedes,
    // MONOTONIC: every copy inherits it, and nothing can turn it back off.
    mayHaveExecuted: mayHaveExecuted || (markExecuted ?? false),
  );

  /// Re-states this record with the one-way facts forced on. Used only by
  /// [reconcilePaymentAttempt]; nothing here can turn a fact back off.
  PaymentAttempt withPreservedFacts({
    required bool mayHaveExecuted,
    required String? sentAt,
    required String? autoEffectsReservedAt,
  }) => PaymentAttempt(
    localOperationId: localOperationId,
    targetId: targetId,
    clientCreatedAt: clientCreatedAt,
    identityKey: identityKey,
    orderId: orderId,
    orderNumber: orderNumber,
    expectedRevision: expectedRevision,
    tenderType: tenderType,
    amountMinor: amountMinor,
    amountTenderedMinor: amountTenderedMinor,
    currencyCode: currencyCode,
    organizationId: organizationId,
    restaurantId: restaurantId,
    branchId: branchId,
    deviceId: deviceId,
    employeeProfileId: employeeProfileId,
    phase: phase,
    lastOutcome: lastOutcome,
    sentAt: sentAt ?? this.sentAt,
    resolvedAt: resolvedAt,
    resolution: resolution,
    refusal: refusal,
    refusalMemoized: refusalMemoized,
    autoEffectsReservedAt: autoEffectsReservedAt ?? this.autoEffectsReservedAt,
    supersedes: supersedes,
    mayHaveExecuted: this.mayHaveExecuted || mayHaveExecuted,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentAttempt &&
          describesSameDecisionAs(other) &&
          phase == other.phase &&
          lastOutcome == other.lastOutcome &&
          sentAt == other.sentAt &&
          resolvedAt == other.resolvedAt &&
          refusal == other.refusal &&
          refusalMemoized == other.refusalMemoized &&
          autoEffectsReservedAt == other.autoEffectsReservedAt &&
          mayHaveExecuted == other.mayHaveExecuted &&
          resolution?.paymentId == other.resolution?.paymentId &&
          resolution?.receiptNumber == other.resolution?.receiptNumber &&
          resolution?.changeDueMinor == other.resolution?.changeDueMinor &&
          resolution?.method == other.resolution?.method &&
          resolution?.replay == other.resolution?.replay &&
          resolution?.orderStatus == other.resolution?.orderStatus;

  @override
  int get hashCode => Object.hash(
    localOperationId,
    targetId,
    phase,
    lastOutcome,
    sentAt,
    resolvedAt,
    refusal,
    refusalMemoized,
    autoEffectsReservedAt,
    mayHaveExecuted,
    resolution?.paymentId,
  );

  /// Marks the send as started (persisted BEFORE the bytes leave).
  ///
  /// S1-R3 / F004: this is also where the MONOTONIC may-have-executed fact is
  /// stamped, because this record is written to disk before the request is
  /// dispatched. A later failure to record the answer therefore cannot erase
  /// the knowledge that an answer is owed.
  PaymentAttempt markSent(String at) => _copy(
    sentAt: sentAt ?? at,
    lastOutcome: PaymentAttemptLastOutcome.none,
    markExecuted: true,
  );

  /// S1-R4: an in-flight note can only follow a dispatch, so recording one
  /// carries the monotonic history with it.
  PaymentAttempt withLastOutcome(PaymentAttemptLastOutcome outcome) => _copy(
    lastOutcome: outcome,
    markExecuted: outcome != PaymentAttemptLastOutcome.none,
  );

  /// Resolves as ACCEPTED. [reserveEffects] stamps the one-time automatic
  /// effect reservation when it is not yet set.
  PaymentAttempt accepted(
    PaymentAttemptResolution resolution, {
    required String at,
    required bool reserveEffects,
  }) => _copy(
    phase: PaymentAttemptPhase.accepted,
    lastOutcome: PaymentAttemptLastOutcome.none,
    // S1-R4: a server answer proves the request was dispatched, so both the
    // started-send marker and the monotonic history are stamped here. Without
    // this the writer could emit a terminal record with no send marker — a
    // shape its own decoder correctly refuses.
    sentAt: sentAt ?? at,
    markExecuted: true,
    resolvedAt: at,
    resolution: resolution,
    autoEffectsReservedAt: reserveEffects
        ? (autoEffectsReservedAt ?? at)
        : autoEffectsReservedAt,
  );

  PaymentAttempt refused(
    PaymentRefusalCode code, {
    required String at,
    required bool memoized,
  }) => _copy(
    phase: PaymentAttemptPhase.refused,
    lastOutcome: PaymentAttemptLastOutcome.none,
    sentAt: sentAt ?? at,
    markExecuted: true,
    resolvedAt: at,
    refusal: code,
    refusalMemoized: memoized,
  );

  PaymentAttempt settledElsewhere({required String at}) => _copy(
    phase: PaymentAttemptPhase.settledElsewhere,
    lastOutcome: PaymentAttemptLastOutcome.none,
    sentAt: sentAt ?? at,
    markExecuted: true,
    resolvedAt: at,
    refusal: refusal ?? PaymentRefusalCode.generic,
  );

  /// S1-R4 / F001 — the FROZEN identity of one payment decision.
  ///
  /// Two records describe the same decision only when every one of these
  /// agrees. A matching `local_operation_id` alone is NOT enough to select a
  /// record for update: Codex showed a stale caller replacing a newer accepted
  /// record wholesale because the operation id happened to match.
  bool describesSameDecisionAs(PaymentAttempt other) =>
      localOperationId == other.localOperationId &&
      targetId == other.targetId &&
      clientCreatedAt == other.clientCreatedAt &&
      identityKey == other.identityKey &&
      orderId == other.orderId &&
      orderNumber == other.orderNumber &&
      expectedRevision == other.expectedRevision &&
      tenderType == other.tenderType &&
      amountMinor == other.amountMinor &&
      amountTenderedMinor == other.amountTenderedMinor &&
      currencyCode == other.currencyCode &&
      organizationId == other.organizationId &&
      restaurantId == other.restaurantId &&
      branchId == other.branchId &&
      deviceId == other.deviceId &&
      employeeProfileId == other.employeeProfileId &&
      supersedes == other.supersedes;

  /// Whether this record carries a TERMINAL server answer.
  bool get isTerminal => phase.isResolved;

  /// Whether [other] is the same terminal answer as this one.
  bool sameTerminalAnswerAs(PaymentAttempt other) =>
      phase == other.phase &&
      refusal == other.refusal &&
      refusalMemoized == other.refusalMemoized &&
      resolution?.paymentId == other.resolution?.paymentId &&
      resolution?.receiptNumber == other.resolution?.receiptNumber &&
      resolution?.changeDueMinor == other.resolution?.changeDueMinor &&
      resolution?.method == other.resolution?.method &&
      resolution?.orderStatus == other.resolution?.orderStatus;

  Map<String, Object?> toJson() => <String, Object?>{
    'local_operation_id': localOperationId,
    'target_id': targetId,
    'client_created_at': clientCreatedAt,
    'identity_key': identityKey,
    'order_id': orderId,
    'order_number': orderNumber,
    'expected_revision': expectedRevision,
    'tender_type': tenderType,
    'amount_minor': amountMinor,
    'amount_tendered_minor': amountTenderedMinor,
    'currency_code': currencyCode,
    'organization_id': organizationId,
    'restaurant_id': restaurantId,
    'branch_id': branchId,
    'device_id': deviceId,
    'employee_profile_id': employeeProfileId,
    'phase': phase.wire,
    'last_outcome': lastOutcome.wire,
    'sent_at': sentAt,
    'resolved_at': resolvedAt,
    'resolution': resolution?.toJson(),
    'refusal': refusal?.wire,
    'refusal_memoized': refusalMemoized,
    'auto_effects_reserved_at': autoEffectsReservedAt,
    'supersedes': supersedes,
    'may_have_executed': mayHaveExecuted,
  };

  /// The allowlisted keys. Anything else in a stored record is a record this
  /// build did not write — treated as unreadable (quarantined), never merged.
  static const Set<String> allowedKeys = <String>{
    'local_operation_id',
    'target_id',
    'client_created_at',
    'identity_key',
    'order_id',
    'order_number',
    'expected_revision',
    'tender_type',
    'amount_minor',
    'amount_tendered_minor',
    'currency_code',
    'organization_id',
    'restaurant_id',
    'branch_id',
    'device_id',
    'employee_profile_id',
    'phase',
    'last_outcome',
    'sent_at',
    'resolved_at',
    'resolution',
    'refusal',
    'refusal_memoized',
    'auto_effects_reserved_at',
    'supersedes',
    'may_have_executed',
  };

  /// STRICT decode: a missing / wrongly-typed / non-allowlisted field throws
  /// [FormatException] so the caller QUARANTINES the record instead of
  /// interpreting a damaged attempt as a free order or a paid one.
  static PaymentAttempt fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('attempt: not an object');
    for (final k in raw.keys) {
      if (!allowedKeys.contains(k)) {
        throw FormatException('attempt: unknown field $k');
      }
    }
    String str(String k) {
      final v = raw[k];
      // S1-R3 / F003: a whitespace-only identity is not an identity. The value
      // is never trimmed or rewritten — a record whose frozen wire value is
      // unusable is quarantined verbatim instead.
      if (v is! String || v.trim().isEmpty) {
        throw FormatException('attempt: $k');
      }
      return v;
    }

    String? optStr(String k) {
      final v = raw[k];
      if (v == null) return null;
      if (v is! String || v.trim().isEmpty) {
        throw FormatException('attempt: $k');
      }
      return v;
    }

    /// A stored timestamp must be a real ISO instant, not a blank or a shape
    /// this build cannot compare.
    DateTime? optTime(String k) {
      final v = optStr(k);
      if (v == null) return null;
      final parsed = DateTime.tryParse(v);
      if (parsed == null) throw FormatException('attempt: $k');
      return parsed;
    }

    int intOf(String k) {
      final v = raw[k];
      if (v is! int) throw FormatException('attempt: $k');
      return v;
    }

    final rev = raw['expected_revision'];
    if (rev != null && (rev is! int || rev < 0)) {
      throw const FormatException('attempt: expected_revision');
    }
    // S1-R4 / F003 — the identity key is DERIVED, never merely stored.
    //
    // `PaymentAttempt.mint` computes it from the frozen order via
    // `PosOrderIdentity.of` (`order_identity.dart:45,68-77`), which yields
    // `srv:<orderId>` for a server order. Hydration keys attempts and money by
    // this value, so a stored key that does not match its own frozen order is
    // a record this build cannot address safely. It is quarantined rather than
    // normalised — repairing it would hide the corruption it represents.
    final derivedIdentity = PosOrderIdentity.of(
      orderId: raw['order_id'] is String ? raw['order_id'] as String : null,
      orderNumber: raw['order_number'] is String
          ? raw['order_number'] as String
          : '',
    ).key;
    if (raw['identity_key'] != derivedIdentity) {
      throw const FormatException('attempt: identity_key');
    }
    final phase = PaymentAttemptPhase.fromWire(raw['phase']);
    if (phase == null) throw const FormatException('attempt: phase');
    final last = PaymentAttemptLastOutcome.fromWire(raw['last_outcome']);
    if (last == null) throw const FormatException('attempt: last_outcome');
    final tender = str('tender_type');
    if (PaymentMethod.fromWire(tender) == null) {
      throw const FormatException('attempt: tender_type');
    }
    final amount = intOf('amount_minor');
    final tendered = intOf('amount_tendered_minor');
    if (amount < 0 || tendered < 0) {
      throw const FormatException('attempt: negative money');
    }
    final refusalRaw = raw['refusal'];
    final PaymentRefusalCode? refusal;
    if (refusalRaw == null) {
      refusal = null;
    } else {
      // PDR-008: an unknown or wrongly typed code is unreadable evidence, not
      // a generic refusal.
      refusal = PaymentRefusalCode.fromWire(refusalRaw);
      if (refusal == null) throw const FormatException('attempt: refusal');
    }
    // S1-R3 / F003: every record this build writes carries `refusal_memoized`
    // (see `toJson`), so a missing or null value is a record shape this build
    // did not produce. Coercing it to false would silently downgrade a
    // memoized terminal refusal into a re-sendable one.
    final memo = raw['refusal_memoized'];
    if (memo is! bool) {
      throw const FormatException('attempt: refusal_memoized');
    }
    final resolution = raw['resolution'] == null
        ? null
        : PaymentAttemptResolution.fromJson(
            raw['resolution'],
            tenderType: tender,
          );
    // S1-R4 / F004 — the execution-history codec, made COHERENT.
    //
    // This build's writer stamps `may_have_executed:true` and `sent_at`
    // together, in the same pre-dispatch write (`markSent`). Codex proved R3
    // accepted three shapes that writer cannot produce, and that the first of
    // them let a later non-memoized refusal retire an identity whose money may
    // already have moved:
    //
    //   * explicit `false` beside a non-null `sent_at` — the record itself
    //     says a dispatch started, so the flag contradicts it;
    //   * explicit `true` with no `sent_at` — nothing marked the send;
    //   * an explicit `false` on a record that already carries terminal or
    //     ambiguous history, which only a dispatch can produce.
    //
    // None is repaired into authority. Each is a FormatException, so the store
    // quarantines the record byte-verbatim and no attempt is loaded from it.
    final executedRaw = raw['may_have_executed'];
    if (executedRaw != null && executedRaw is! bool) {
      throw const FormatException('attempt: may_have_executed');
    }
    final createdAtTime = DateTime.tryParse(str('client_created_at'));
    if (createdAtTime == null) {
      throw const FormatException('attempt: client_created_at');
    }
    final sentAtTime = optTime('sent_at');
    final resolvedAtTime = optTime('resolved_at');
    final reservedAtTime = optTime('auto_effects_reserved_at');
    final resolvedAt = optStr('resolved_at');
    final reservedAt = optStr('auto_effects_reserved_at');
    // S1-R4 / F004 — the cross-field execution-history invariants.
    final hasStartedSend = raw['sent_at'] != null;
    final hasHistory =
        phase.isResolved || last != PaymentAttemptLastOutcome.none;
    if (executedRaw == false && hasStartedSend) {
      throw const FormatException(
        'attempt: may_have_executed false contradicts sent_at',
      );
    }
    if (executedRaw == true && !hasStartedSend) {
      throw const FormatException(
        'attempt: may_have_executed true without a started send',
      );
    }
    if (executedRaw == false && hasHistory) {
      throw const FormatException(
        'attempt: may_have_executed false contradicts stored history',
      );
    }
    // A record that carries in-flight or terminal history but no started-send
    // marker is not a shape this writer emits either. Quarantining is the
    // conservative reading: missing metadata is never read as "never sent".
    if (!hasStartedSend && !phase.isResolved && hasHistory) {
      throw const FormatException(
        'attempt: in-flight history without a started send',
      );
    }
    // Time only moves forward within one attempt.
    if (sentAtTime != null && sentAtTime.isBefore(createdAtTime)) {
      throw const FormatException('attempt: sent_at precedes creation');
    }
    if (resolvedAtTime != null && resolvedAtTime.isBefore(createdAtTime)) {
      throw const FormatException('attempt: resolved_at precedes creation');
    }
    if (reservedAtTime != null && resolvedAtTime == null) {
      throw const FormatException('attempt: effect claim without resolution');
    }
    // S1-R3 / F003: the writer stamps these from one clock in one order, so a
    // record whose answer predates its question, or whose one-time effect
    // claim predates the attempt itself, is contradictory evidence.
    if (resolvedAtTime != null &&
        sentAtTime != null &&
        resolvedAtTime.isBefore(sentAtTime)) {
      throw const FormatException('attempt: resolved_at precedes sent_at');
    }
    if (reservedAtTime != null && reservedAtTime.isBefore(createdAtTime)) {
      throw const FormatException('attempt: effect claim precedes creation');
    }

    // PDR-008 — the COMPLETE phase invariant. A record whose parts contradict
    // each other cannot be acted on, so it is refused here and quarantined
    // verbatim by the store rather than half-believed.
    // A resolved record cannot still be advertising an in-flight note, and an
    // unresolved one cannot carry a memoized-refusal marker.
    if (phase.isResolved && last != PaymentAttemptLastOutcome.none) {
      throw FormatException('attempt: ${phase.wire} with a pending note');
    }
    if (!phase.isResolved && memo) {
      throw const FormatException('attempt: pending with refusal_memoized');
    }
    if (phase == PaymentAttemptPhase.accepted && memo) {
      throw const FormatException('attempt: accepted with refusal_memoized');
    }
    switch (phase) {
      case PaymentAttemptPhase.pending:
        if (resolution != null) {
          throw const FormatException('attempt: pending with a resolution');
        }
        if (refusal != null) {
          throw const FormatException('attempt: pending with a refusal');
        }
        if (resolvedAt != null) {
          throw const FormatException('attempt: pending with resolved_at');
        }
        if (reservedAt != null) {
          throw const FormatException('attempt: pending with an effect claim');
        }
      case PaymentAttemptPhase.accepted:
        if (resolution == null) {
          throw const FormatException('attempt: accepted without resolution');
        }
        if (refusal != null) {
          throw const FormatException('attempt: accepted with a refusal');
        }
        if (resolvedAt == null) {
          throw const FormatException('attempt: accepted without resolved_at');
        }
        // The acceptance writer always reserves the one-time effect claim in
        // the same write, so an accepted record without it is contradictory.
        if (reservedAt == null) {
          throw const FormatException('attempt: accepted without effect claim');
        }
      case PaymentAttemptPhase.refused:
      case PaymentAttemptPhase.settledElsewhere:
        if (refusal == null) {
          throw FormatException('attempt: ${phase.wire} without a refusal');
        }
        if (resolution != null) {
          throw FormatException('attempt: ${phase.wire} with a resolution');
        }
        if (resolvedAt == null) {
          throw FormatException('attempt: ${phase.wire} without resolved_at');
        }
        if (reservedAt != null) {
          throw FormatException('attempt: ${phase.wire} with an effect claim');
        }
    }
    return PaymentAttempt(
      localOperationId: str('local_operation_id'),
      targetId: str('target_id'),
      clientCreatedAt: str('client_created_at'),
      identityKey: str('identity_key'),
      orderId: str('order_id'),
      orderNumber: str('order_number'),
      expectedRevision: rev as int?,
      tenderType: tender,
      amountMinor: amount,
      amountTenderedMinor: tendered,
      currencyCode: str('currency_code'),
      organizationId: str('organization_id'),
      restaurantId: str('restaurant_id'),
      branchId: str('branch_id'),
      deviceId: str('device_id'),
      employeeProfileId: optStr('employee_profile_id'),
      phase: phase,
      lastOutcome: last,
      sentAt: optStr('sent_at'),
      resolvedAt: resolvedAt,
      resolution: resolution,
      refusal: refusal,
      refusalMemoized: memo,
      autoEffectsReservedAt: reservedAt,
      supersedes: optStr('supersedes'),
      // COMPATIBILITY, conservative by construction: an older record with no
      // marker is NOT assumed never-sent. Any evidence of a dispatch — a
      // started-send stamp, a terminal answer, or an explicit in-flight note —
      // derives `true`. Only a record that proves it was never dispatched
      // starts false. Nothing is rewritten or discarded.
      mayHaveExecuted: executedRaw as bool? ?? (hasStartedSend || hasHistory),
    );
  }
}

/// How a proposed record was reconciled with the record already on disk.
enum PaymentAttemptMergeOutcome {
  /// The proposal advanced the stored record; the result is written.
  applied,

  /// The proposal said nothing the stored record did not already know. The
  /// stored record stands unchanged.
  redundant,

  /// The proposal is OLDER than what is stored — a stale caller. The stored
  /// record stands unchanged and nothing is downgraded.
  stale,

  /// The proposal contradicts the stored record: a different frozen identity,
  /// or a different terminal answer for the same one. Nothing is merged and
  /// the disagreement is reported rather than resolved by guessing.
  conflict,
}

/// The result of reconciling a proposed record with the stored one.
class PaymentAttemptMerge {
  const PaymentAttemptMerge(this.outcome, this.record);
  final PaymentAttemptMergeOutcome outcome;

  /// The record that should stand. For every outcome other than [applied] this
  /// is the record ALREADY stored, never the caller's proposal.
  final PaymentAttempt record;

  bool get writes => outcome == PaymentAttemptMergeOutcome.applied;
}

/// S1-R4 / F001 — reconcile [proposed] with the [current] stored record.
///
/// This is validated monotonicity, not last-write-wins and not a blind
/// max/OR over enums. The rules, in order:
///
///  1. The frozen decision identity must match exactly, or the two records are
///     not about the same decision and nothing is merged.
///  2. Facts that can only ever become MORE true are carried forward from
///     whichever record holds them: the may-have-executed history, the
///     started-send marker, and the one-time automatic-effect reservation. A
///     proposal can never erase them.
///  3. A record that already holds a TERMINAL answer is never downgraded to a
///     pending or diagnostic state. An identical terminal answer is redundant;
///     a different one is a conflict, and no composite is invented.
///  4. Otherwise the proposal advances the record, keeping every preserved
///     fact from rule 2.
PaymentAttemptMerge reconcilePaymentAttempt(
  PaymentAttempt current,
  PaymentAttempt proposed,
) {
  if (!current.describesSameDecisionAs(proposed)) {
    return PaymentAttemptMerge(PaymentAttemptMergeOutcome.conflict, current);
  }

  // Rule 2 — the one-way facts, taken from wherever they are already true.
  final mayHaveExecuted = current.mayHaveExecuted || proposed.mayHaveExecuted;
  final sentAt = current.sentAt ?? proposed.sentAt;
  final reservedAt =
      current.autoEffectsReservedAt ?? proposed.autoEffectsReservedAt;

  // Rule 3 — a terminal record is never downgraded.
  if (current.isTerminal) {
    if (!proposed.isTerminal) {
      return PaymentAttemptMerge(PaymentAttemptMergeOutcome.stale, current);
    }
    if (current.sameTerminalAnswerAs(proposed)) {
      final merged = current.withPreservedFacts(
        mayHaveExecuted: mayHaveExecuted,
        sentAt: sentAt,
        autoEffectsReservedAt: reservedAt,
      );
      return PaymentAttemptMerge(
        merged == current
            ? PaymentAttemptMergeOutcome.redundant
            : PaymentAttemptMergeOutcome.applied,
        merged,
      );
    }
    return PaymentAttemptMerge(PaymentAttemptMergeOutcome.conflict, current);
  }

  // Rule 4 — the stored record is not terminal, so the proposal may advance it.
  final merged = proposed.withPreservedFacts(
    mayHaveExecuted: mayHaveExecuted,
    sentAt: sentAt,
    autoEffectsReservedAt: reservedAt,
  );
  if (merged == current) {
    return PaymentAttemptMerge(PaymentAttemptMergeOutcome.redundant, current);
  }
  return PaymentAttemptMerge(PaymentAttemptMergeOutcome.applied, merged);
}

/// A compact, non-secret description of an attempt for the cashier-facing
/// surfaces (frozen tender + amount).
class PaymentAttemptSummary {
  const PaymentAttemptSummary({
    required this.localOperationId,
    required this.method,
    required this.amountMinor,
    required this.amountTenderedMinor,
    required this.currencyCode,
    required this.phase,
    required this.lastOutcome,
  });

  factory PaymentAttemptSummary.of(PaymentAttempt a) => PaymentAttemptSummary(
    localOperationId: a.localOperationId,
    method: a.method,
    amountMinor: a.amountMinor,
    amountTenderedMinor: a.amountTenderedMinor,
    currencyCode: a.currencyCode,
    phase: a.phase,
    lastOutcome: a.lastOutcome,
  );

  final String localOperationId;
  final PaymentMethod method;
  final int amountMinor;
  final int amountTenderedMinor;
  final String currencyCode;
  final PaymentAttemptPhase phase;
  final PaymentAttemptLastOutcome lastOutcome;
}
