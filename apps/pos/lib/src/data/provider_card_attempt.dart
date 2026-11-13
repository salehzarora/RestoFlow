/// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F — the provider-card attempt: a SEPARATELY
/// VERSIONED sibling record of the POS payment journal (**D-057** point 2;
/// execution packet docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001F_EXECUTION.md §5).
///
/// One integrated card payment is ONE business attempt with ONE immutable
/// identity: [ProviderCardAttempt.attemptId] is the Edge `attempt_id` AND the
/// `local_operation_id` of the recording `payment.create` (**D-054** point 1).
/// Everything the attempt was started with is frozen here before the first
/// request leaves the device, and every later `start` resend, `status` check,
/// recording send, restart and Resume reuses it.
///
/// WHY A SIBLING, NOT THE BASE RECORD: the 26-key `PaymentAttempt` and its
/// envelope are a frozen wire contract whose decoder quarantines any key it does
/// not know (`payment_attempt.dart`, `payment_attempt_store.dart`). The provider
/// record therefore lives in its own storage family (`provider_card_store.dart`)
/// with its own schema version, and follows the TOTAL decoding discipline of
/// `payment_replacement_block.dart`: every input yields a typed result, and a
/// record this build cannot read is quarantined, never repaired.
///
/// ALLOWLISTED SCHEMA. Identifiers, integer minor-unit money and closed tokens
/// only. Never a credential or device-session token, a PIN or PIN-session id, a
/// terminal / PinPad reference, a provider key, any card datum, the provider's
/// return code or text, a raw payload, or customer data.
library;

import 'package:flutter/foundation.dart' show immutable;

import 'order_identity.dart';
import 'payment_replacement_block.dart'
    show
        StrictMapBadKey,
        StrictMapNotAMap,
        StrictMapOk,
        canonicalInstant,
        exactKeys,
        isCanonicalInstant,
        strictStringObjectMap;

// ---------------------------------------------------------------------------
// Closed vocabularies (API_CONTRACT §4.55; pos-card-charge lib/envelope.mjs and
// lib/request.mjs; the 001D sync_push answers)
// ---------------------------------------------------------------------------

/// The attempt's mode. Chosen from the server posture, never from a local
/// toggle (packet §9).
enum ProviderCardMode {
  live('live'),
  test('test');

  const ProviderCardMode(this.wire);
  final String wire;

  static ProviderCardMode? fromWire(Object? wire) {
    for (final m in values) {
      if (m.wire == wire) return m;
    }
    return null;
  }
}

/// The five stored provider states (`envelope.mjs` STATES).
const Set<String> kProviderCardStates = <String>{
  'sent',
  'approved',
  'declined',
  'unknown',
  'released',
};

/// The LIVE classifications (`envelope.mjs` CLASSIFICATIONS).
const Set<String> kProviderCardLiveClassifications = <String>{
  'in_progress',
  'freed',
  'provider_anomaly',
  'declined',
  'recorded',
  'orphan_approved',
  'approved_unrecorded',
  'resolved',
};

/// The TEST classifications: always `test_` + the state (**D-056** point 6).
const Set<String> kProviderCardTestClassifications = <String>{
  'test_sent',
  'test_unknown',
  'test_released',
  'test_approved',
  'test_declined',
};

/// `envelope.mjs` ANOMALY_CODES.
const Set<String> kProviderCardAnomalyCodes = <String>{
  'amount_mismatch',
  'currency_mismatch',
  'preauthorization',
  'partial_refund',
  'refunded',
  'voided',
  'out_of_contract',
};

/// The recording refusal hints the POS may report through `status`
/// (`request.mjs` RECORDING_REFUSAL_HINTS; API §4.55.7).
const List<String> kProviderCardRecordingHints = <String>[
  'order_not_chargeable',
  'conflict',
  'precondition_failed',
  'revoked_employee',
  'permission_denied',
  'revoked_device',
  'amount_mismatch',
  'payment_in_progress',
  'card_context_lost',
  'provider_recording_refused',
  'nonrecoverable_refusal',
];

/// The envelope's stored `refusal_code` tokens.
const Set<String> kProviderCardEnvelopeRefusalCodes = <String>{
  'release_failed',
  ...kProviderCardRecordingHints,
};

/// `envelope.mjs` RESOLUTIONS.
const Set<String> kProviderCardResolutions = <String>{
  'provider_voided',
  'provider_refunded',
  'test_closed',
};

/// The refusal `error` tokens the Edge answers (`envelope.mjs` ERRORS).
const Set<String> kProviderCardEdgeErrors = <String>{
  'invalid_request',
  'invalid_session',
  'permission_denied',
  'conflict',
  'attempt_not_found',
  'precondition_failed',
  'card_payments_disabled',
  'provider_unavailable',
  'order_not_chargeable',
  'order_already_settled',
  'payment_in_progress',
  'amount_mismatch',
  'poll_limit',
};

/// The refusal `detail` tokens the Edge answers (`envelope.mjs` DETAILS).
const Set<String> kProviderCardEdgeDetails = <String>{
  'identity_in_use',
  'ineligible_order_state',
  'max_live_amount_exceeded',
  'no_open_shift',
  'no_active_drawer',
  'currency_not_supported',
  'max_test_amount_exceeded',
  'no_recording_attempt',
  'out_of_contract',
  'confirmation_required',
  'charge_may_exist',
  'attempt_not_freeable',
};

/// The `resume_denied` tokens of the D-054 Resume guard (API §4.55.7).
const Set<String> kProviderCardResumeDeniedTokens = <String>{
  'actor_not_active',
  'not_manager',
  'device_not_active',
  'operation_mismatch',
  'not_recoverable',
  'refusal_not_recorded',
  'resume_limit',
  'resume_stale',
  'order_not_chargeable',
  'context_lost',
  'amount_mismatch',
  'payment_exists',
  'claim_inactive',
};

/// The phase-1 maximum of authorized Resume recordings (**D-054** point 8).
const int kProviderCardMaxResumes = 3;

/// `amount_minor` bounds of the Edge `start` grammar (`money.mjs`).
const int kProviderCardMaxAmountMinor = 99999999999;

/// `expected_revision` bounds of the Edge `start` grammar (`request.mjs`).
const int kProviderCardMaxRevision = 2147483647;

/// The currencies the provider can encode (the pilot charges ILS only:
/// `lib/provider/engine.mjs` TWO_DECIMAL_CURRENCIES). Any other currency would be
/// answered 503 `provider_unavailable` before any database read — an
/// `uncertain` answer at the POS — so the POS never starts one.
const Set<String> kProviderCardCurrencies = <String>{'ILS'};

/// How long a `start` request can still create a claim after the POS began to
/// wait on it (packet §7.3): the platform's 150 s request idle timeout (the
/// bound the 001E timing budget relies on), which runs from the request's
/// arrival, plus the 001C exchange deadline (`posCardChargeTimeout`, 40 s,
/// which includes the SDK's access-token step), plus 10 s for transit. The
/// controller measures it on a process monotonic clock, bound to the send it
/// is about (`start_last_sent_at`, which each send of an attempt sets later
/// than the one before it, so no two sends share one): from the end of a
/// start exchange it ran (nothing of it can be handed off later), or from the
/// first time it saw a send it did not run (a hydration, or a check about
/// it). The latter is sound because a send that another controller world or
/// an earlier process began can no longer be handed off once that world has
/// ended (its handoff checks refuse) or that process has died; two live
/// controllers over one journal are not a configuration the POS ships. It
/// records an `attempt_not_found` answer only for a request about that same
/// send, sent once the window has passed: that recorded answer proves no
/// attempt exists, and no wall-clock step changes it.
const Duration kProviderCardStartSettleWindow = Duration(seconds: 200);

final RegExp _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final RegExp _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final RegExp _currency = RegExp(r'^[A-Z]{3}$');
final RegExp _serverTs = RegExp(
  r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}(?::?\d{2})?)$',
);

/// A canonical lowercase UUID (any version), as the Edge grammar requires for
/// `order_id`, `pin_session_id` and `device_id`.
bool isProviderCardUuid(Object? v) => v is String && _uuid.hasMatch(v);

/// A canonical lowercase UUID v4, as the Edge grammar requires for `attempt_id`
/// (and the ledger CHECK for `local_operation_id`).
bool isProviderCardUuidV4(Object? v) => v is String && _uuidV4.hasMatch(v);

/// The Edge `server_ts` grammar (`envelope.mjs` TIMESTAMP).
bool isProviderCardServerTs(Object? v) => v is String && _serverTs.hasMatch(v);

/// An integer amount the Edge `start` grammar accepts.
bool isProviderCardAmount(Object? v) =>
    v is int && v >= 1 && v <= kProviderCardMaxAmountMinor;

/// An ISO 4217 code shape.
bool isProviderCardCurrency(Object? v) => v is String && _currency.hasMatch(v);

// ---------------------------------------------------------------------------
// Local outcome vocabularies (packet §5.2)
// ---------------------------------------------------------------------------

/// What the last `start` call proved.
enum ProviderCardStartOutcome {
  /// Refused on this device before any handoff (001C `notSent`).
  notSent('not_sent'),

  /// HTTP 401: the session was refused, with no ledger effect of this request.
  authRequired('auth_required'),

  /// HTTP 400 / 403 / 404 / 405: refused before processing — an application or
  /// configuration refusal, never a decline.
  notApplied('not_applied'),

  /// The request MAY have executed (001C `uncertain`). `start` is never sent
  /// again for this attempt.
  uncertain('uncertain'),

  /// A closed envelope answered.
  answered('answered'),

  /// A closed 200 refusal answered (no claim was created; packet §6).
  refused('refused');

  const ProviderCardStartOutcome(this.wire);
  final String wire;

  static ProviderCardStartOutcome? fromWire(Object? wire) {
    for (final o in values) {
      if (o.wire == wire) return o;
    }
    return null;
  }
}

/// What the last recording-leg exchange proved (packet §8.3).
enum ProviderCardRecordingOutcome {
  applied('applied'),
  unconfirmed('unconfirmed'),
  notSent('not_sent'),
  authRequired('auth_required'),
  notApplied('not_applied'),
  pending('pending'),
  refused('refused'),
  collision('collision'),
  resumeAuthorityRequired('resume_authority_required'),
  resumeDenied('resume_denied');

  const ProviderCardRecordingOutcome(this.wire);
  final String wire;

  static ProviderCardRecordingOutcome? fromWire(Object? wire) {
    for (final o in values) {
      if (o.wire == wire) return o;
    }
    return null;
  }

  /// The same canonical leg may be sent again (it never charges again).
  bool get resendable => switch (this) {
    unconfirmed || notSent || authRequired || notApplied || pending => true,
    _ => false,
  };
}

/// A fail-closed stop: the attempt is shown as needing reconciliation and is
/// never sent again (status checks stay available).
enum ProviderCardSafetyStop {
  /// The recording leg was answered `test_attempt_not_recordable` — the POS never
  /// builds a TEST leg, so this is a defect (**D-058** point 7).
  testAttemptNotRecordable('test_attempt_not_recordable'),

  /// A well-formed envelope of the other mode's classification family.
  modeMismatch('mode_mismatch'),

  /// A well-formed envelope with another amount or currency.
  amountMismatch('amount_mismatch'),

  /// A `start` refusal `conflict` with attempt facts: the same identity holds
  /// different frozen fields on the server.
  attemptConflict('attempt_conflict'),

  /// The server refused the recording operation's own shape (a pre-dispatch
  /// `invalid_payload` / `invalid_envelope` / `unknown_operation_type`).
  recordingContract('recording_contract');

  const ProviderCardSafetyStop(this.wire);
  final String wire;

  static ProviderCardSafetyStop? fromWire(Object? wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }
}

/// A local closure the cashier chose (packet §7.3).
enum ProviderCardClosure {
  /// A request that never left this device, cancelled.
  abandoned('abandoned'),

  /// Set aside after a conclusive no-charge state, to take payment another way.
  setAside('set_aside');

  const ProviderCardClosure(this.wire);
  final String wire;

  static ProviderCardClosure? fromWire(Object? wire) {
    for (final c in values) {
      if (c.wire == wire) return c;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Nested values
// ---------------------------------------------------------------------------

/// A closed 200 `start` refusal: the Edge `error` and `detail` tokens only.
@immutable
class ProviderCardStartRefusal {
  const ProviderCardStartRefusal(this.error, this.detail);

  final String error;
  final String? detail;

  static const Set<String> keys = <String>{'error', 'detail'};

  Map<String, Object?> toJson() => <String, Object?>{
    'error': error,
    'detail': detail,
  };

  static ProviderCardStartRefusal? fromJson(Object? raw) {
    final m = strictStringObjectMap(raw);
    if (m is! StrictMapOk) return null;
    if (exactKeys(m.map, keys) != null) return null;
    final error = m.map['error'];
    final detail = m.map['detail'];
    if (error is! String || !kProviderCardEdgeErrors.contains(error)) {
      return null;
    }
    if (detail != null &&
        (detail is! String || !kProviderCardEdgeDetails.contains(detail))) {
      return null;
    }
    return ProviderCardStartRefusal(error, detail as String?);
  }

  @override
  bool operator ==(Object other) =>
      other is ProviderCardStartRefusal &&
      other.error == error &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(error, detail);
}

/// The last CLOSED server envelope of the attempt (API §4.55.4), minus the
/// provider's return code, which this record never keeps.
@immutable
class ProviderCardServerFacts {
  const ProviderCardServerFacts({
    required this.state,
    required this.classification,
    required this.recorded,
    required this.refusalCode,
    required this.anomalyCode,
    required this.resolution,
    required this.recoverable,
    required this.resumeCount,
    required this.paymentId,
    required this.serverTs,
  });

  final String state;
  final String classification;
  final bool recorded;
  final String? refusalCode;
  final String? anomalyCode;
  final String? resolution;
  final bool? recoverable;
  final int? resumeCount;
  final String? paymentId;
  final String serverTs;

  static const Set<String> keys = <String>{
    'state',
    'classification',
    'recorded',
    'refusal_code',
    'anomaly_code',
    'resolution',
    'recoverable',
    'resume_count',
    'payment_id',
    'server_ts',
  };

  /// The mode whose classification family these facts belong to.
  ProviderCardMode get familyMode =>
      kProviderCardTestClassifications.contains(classification)
      ? ProviderCardMode.test
      : ProviderCardMode.live;

  Map<String, Object?> toJson() => <String, Object?>{
    'state': state,
    'classification': classification,
    'recorded': recorded,
    'refusal_code': refusalCode,
    'anomaly_code': anomalyCode,
    'resolution': resolution,
    'recoverable': recoverable,
    'resume_count': resumeCount,
    'payment_id': paymentId,
    'server_ts': serverTs,
  };

  /// STRICT and total: null unless [raw] is exactly the ten-key shape with
  /// internally consistent values ([consistencyProblem]).
  static ProviderCardServerFacts? fromJson(Object? raw) {
    final m = strictStringObjectMap(raw);
    if (m is! StrictMapOk) return null;
    final map = m.map;
    if (exactKeys(map, keys) != null) return null;
    final state = map['state'];
    final classification = map['classification'];
    final recorded = map['recorded'];
    final refusal = map['refusal_code'];
    final anomaly = map['anomaly_code'];
    final resolution = map['resolution'];
    final recoverable = map['recoverable'];
    final resumeCount = map['resume_count'];
    final paymentId = map['payment_id'];
    final serverTs = map['server_ts'];
    if (state is! String ||
        classification is! String ||
        recorded is! bool ||
        (refusal != null && refusal is! String) ||
        (anomaly != null && anomaly is! String) ||
        (resolution != null && resolution is! String) ||
        (recoverable != null && recoverable is! bool) ||
        (resumeCount != null && resumeCount is! int) ||
        (paymentId != null && paymentId is! String) ||
        serverTs is! String) {
      return null;
    }
    final facts = ProviderCardServerFacts(
      state: state,
      classification: classification,
      recorded: recorded,
      refusalCode: refusal as String?,
      anomalyCode: anomaly as String?,
      resolution: resolution as String?,
      recoverable: recoverable as bool?,
      resumeCount: resumeCount as int?,
      paymentId: paymentId as String?,
      serverTs: serverTs,
    );
    return facts.consistencyProblem() == null ? facts : null;
  }

  /// Null when the facts are a shape the server can produce; otherwise why not.
  /// The rules follow `app.card_attempt_derive` / `app.card_attempt_envelope`
  /// and the Edge projection; anything else is unreadable evidence.
  String? consistencyProblem() {
    if (!kProviderCardStates.contains(state)) return 'state';
    final live = kProviderCardLiveClassifications.contains(classification);
    final test = kProviderCardTestClassifications.contains(classification);
    if (!live && !test) return 'classification';
    if (!isProviderCardServerTs(serverTs)) return 'server_ts';
    if (refusalCode != null &&
        !kProviderCardEnvelopeRefusalCodes.contains(refusalCode)) {
      return 'refusal_code';
    }
    if (anomalyCode != null &&
        !kProviderCardAnomalyCodes.contains(anomalyCode)) {
      return 'anomaly_code';
    }
    if (resolution != null && !kProviderCardResolutions.contains(resolution)) {
      return 'resolution';
    }
    if ((recoverable == null) != (resumeCount == null)) {
      return 'recoverable / resume_count';
    }
    final count = resumeCount;
    if (count != null && (count < 0 || count > kProviderCardMaxResumes)) {
      return 'resume_count range';
    }
    if (paymentId != null && (!recorded || !isProviderCardUuid(paymentId))) {
      return 'payment_id';
    }
    if (test) {
      if (classification != 'test_$state') return 'test classification';
      if (recorded ||
          anomalyCode != null ||
          recoverable != null ||
          (resolution != null && resolution != 'test_closed')) {
        return 'test fields';
      }
      return null;
    }
    // LIVE.
    if (resolution == 'test_closed') return 'live resolution';
    if ((classification == 'resolved') != (resolution != null)) {
      return 'resolution / resolved';
    }
    if (anomalyCode != null && classification != 'provider_anomaly') {
      return 'anomaly_code / classification';
    }
    if (recoverable != null &&
        classification != 'approved_unrecorded' &&
        classification != 'orphan_approved') {
      return 'recoverable / classification';
    }
    if (recorded &&
        classification != 'recorded' &&
        classification != 'resolved') {
      return 'recorded / classification';
    }
    if (classification == 'recorded' && !recorded) return 'recorded flag';
    final ok = switch (classification) {
      'in_progress' =>
        state == 'sent' || state == 'unknown' || state == 'released',
      'freed' ||
      'provider_anomaly' => state == 'unknown' || state == 'released',
      'declined' => state == 'declined',
      'recorded' ||
      'orphan_approved' ||
      'approved_unrecorded' => state == 'approved',
      _ => true, // 'resolved' may carry any state
    };
    return ok ? null : 'state / classification';
  }

  @override
  bool operator ==(Object other) =>
      other is ProviderCardServerFacts &&
      other.state == state &&
      other.classification == classification &&
      other.recorded == recorded &&
      other.refusalCode == refusalCode &&
      other.anomalyCode == anomalyCode &&
      other.resolution == resolution &&
      other.recoverable == recoverable &&
      other.resumeCount == resumeCount &&
      other.paymentId == paymentId &&
      other.serverTs == serverTs;

  @override
  int get hashCode => Object.hash(
    state,
    classification,
    recorded,
    refusalCode,
    anomalyCode,
    resolution,
    recoverable,
    resumeCount,
    paymentId,
    serverTs,
  );
}

/// The canonical provider recording operation (packet §8.1; API §4.55.7): the
/// existing `payment.create` under the attempt's own identity, with the exact
/// canonical payload and NO `expected_revision` — the provider-leg-only
/// exception to PDR-003 (**D-057** point 2). Built once, persisted before its
/// first send, then reused byte for byte.
@immutable
class ProviderCardRecordingOperation {
  const ProviderCardRecordingOperation({
    required this.localOperationId,
    required this.targetId,
    required this.clientCreatedAt,
    required this.orderId,
    required this.amountTenderedMinor,
  });

  final String localOperationId;
  final String targetId;
  final String clientCreatedAt;
  final String orderId;
  final int amountTenderedMinor;

  static const Set<String> keys = <String>{
    'local_operation_id',
    'operation_type',
    'target_entity',
    'target_id',
    'client_created_at',
    'payload',
  };

  static const Set<String> payloadKeys = <String>{
    'order_id',
    'tender_type',
    'amount_tendered_minor',
  };

  /// The canonical payload: exactly the server's
  /// `jsonb_build_object('order_id', a.order_id::text, 'tender_type', 'card',
  /// 'amount_tendered_minor', a.amount_minor)`.
  Map<String, dynamic> get payload => <String, dynamic>{
    'order_id': orderId,
    'tender_type': 'card',
    'amount_tendered_minor': amountTenderedMinor,
  };

  /// The persisted form — the same map [toSyncOperation] sends without a
  /// Resume control key.
  Map<String, Object?> toJson() => toSyncOperation();

  /// The EXACT `sync_push` operation. [recordingResume] adds only the
  /// fingerprint-excluded top-level sibling `recording_resume` beside `payload`
  /// (**D-056** point 10), never inside it.
  Map<String, dynamic> toSyncOperation({int? recordingResume}) =>
      <String, dynamic>{
        'local_operation_id': localOperationId,
        'operation_type': 'payment.create',
        'target_entity': 'payment',
        'target_id': targetId,
        'client_created_at': clientCreatedAt,
        'payload': payload,
        if (recordingResume != null) 'recording_resume': recordingResume,
      };

  /// STRICT and total: null unless [raw] is exactly the operation the attempt
  /// [attemptId] / [orderId] / [amountMinor] can produce.
  static ProviderCardRecordingOperation? fromJson(
    Object? raw, {
    required String attemptId,
    required String orderId,
    required int amountMinor,
  }) {
    final m = strictStringObjectMap(raw);
    if (m is! StrictMapOk) return null;
    final map = m.map;
    if (exactKeys(map, keys) != null) return null;
    if (map['local_operation_id'] != attemptId) return null;
    if (map['operation_type'] != 'payment.create') return null;
    if (map['target_entity'] != 'payment') return null;
    final targetId = map['target_id'];
    if (!isProviderCardUuidV4(targetId)) return null;
    final createdAt = map['client_created_at'];
    if (!isCanonicalInstant(createdAt)) return null;
    final p = strictStringObjectMap(map['payload']);
    if (p is! StrictMapOk) return null;
    if (exactKeys(p.map, payloadKeys) != null) return null;
    if (p.map['order_id'] != orderId ||
        p.map['tender_type'] != 'card' ||
        p.map['amount_tendered_minor'] != amountMinor) {
      return null;
    }
    return ProviderCardRecordingOperation(
      localOperationId: attemptId,
      targetId: targetId as String,
      clientCreatedAt: createdAt as String,
      orderId: orderId,
      amountTenderedMinor: amountMinor,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProviderCardRecordingOperation &&
      other.localOperationId == localOperationId &&
      other.targetId == targetId &&
      other.clientCreatedAt == clientCreatedAt &&
      other.orderId == orderId &&
      other.amountTenderedMinor == amountTenderedMinor;

  @override
  int get hashCode => Object.hash(
    localOperationId,
    targetId,
    clientCreatedAt,
    orderId,
    amountTenderedMinor,
  );
}

/// The authoritative recording this device's own `sync_push` reply carried.
@immutable
class ProviderCardPayment {
  const ProviderCardPayment({
    required this.paymentId,
    required this.receiptNumber,
    required this.orderStatus,
  });

  final String paymentId;
  final String receiptNumber;
  final String? orderStatus;

  static const Set<String> keys = <String>{
    'payment_id',
    'receipt_number',
    'order_status',
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'payment_id': paymentId,
    'receipt_number': receiptNumber,
    'order_status': orderStatus,
  };

  static ProviderCardPayment? fromJson(Object? raw) {
    final m = strictStringObjectMap(raw);
    if (m is! StrictMapOk) return null;
    if (exactKeys(m.map, keys) != null) return null;
    final id = m.map['payment_id'];
    final receipt = m.map['receipt_number'];
    final status = m.map['order_status'];
    if (id is! String || id.trim().isEmpty) return null;
    if (receipt is! String || receipt.trim().isEmpty) return null;
    if (status != null && status is! String) return null;
    return ProviderCardPayment(
      paymentId: id,
      receiptNumber: receipt,
      orderStatus: status as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProviderCardPayment &&
      other.paymentId == paymentId &&
      other.receiptNumber == receiptNumber &&
      other.orderStatus == orderStatus;

  @override
  int get hashCode => Object.hash(paymentId, receiptNumber, orderStatus);
}

// ---------------------------------------------------------------------------
// The record
// ---------------------------------------------------------------------------

/// The derived presentation of an attempt (packet §7.1). Transient overlays —
/// a request in flight, a status note — belong to the controller.
enum ProviderCardPhase {
  notSent,
  authRequired,
  notApplied,
  refused,
  uncertain,
  notFound,
  waiting,
  released,
  approvedRecording,
  recordingUnconfirmed,
  recordingRefused,
  managerMustSend,
  resumeRefused,
  recorded,
  declined,
  freed,
  resolved,
  reconciliation,
  testWaiting,
  testReleased,
  testApproved,
  testDeclined,
  testClosed,
  closed,
}

final class _Unset {
  const _Unset();
}

const _Unset _unset = _Unset();

/// One integrated card attempt, frozen at creation (packet §5.2). Immutable:
/// every transition returns a new value with the same identity and frozen
/// inputs.
@immutable
class ProviderCardAttempt {
  const ProviderCardAttempt({
    required this.attemptId,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.deviceId,
    required this.identityKey,
    required this.orderId,
    required this.orderNumber,
    required this.mode,
    required this.amountMinor,
    required this.currencyCode,
    required this.expectedRevision,
    required this.employeeProfileId,
    required this.clientCreatedAt,
    required this.updatedAt,
    this.startInDoubt = false,
    this.startMayHaveExecuted = false,
    this.startLastSentAt,
    this.startOutcome,
    this.startRefusal,
    this.server,
    this.serverNotFoundAt,
    this.recording,
    this.recordingInDoubt = false,
    this.recordingMayHaveExecuted = false,
    this.recordingOutcome,
    this.recordingRefusal,
    this.refusalReportPending,
    this.resumeDenied,
    this.payment,
    this.receiptReservedAt,
    this.safetyStop,
    this.closed,
  });

  /// Bump ONLY on an incompatible record shape. An unknown version is
  /// quarantined on load (kept, never dropped, never guessed).
  static const int schemaVersion = 1;

  /// A NEW attempt, frozen from the cashier's decision. The caller mints
  /// [attemptId] (a lowercase UUID v4) once; nothing here mints.
  static ProviderCardAttempt create({
    required String attemptId,
    required String organizationId,
    required String restaurantId,
    required String branchId,
    required String deviceId,
    required String orderId,
    required String orderNumber,
    required ProviderCardMode mode,
    required int amountMinor,
    required String currencyCode,
    required int? expectedRevision,
    required String? employeeProfileId,
    required DateTime now,
  }) {
    final at = canonicalInstant(now);
    return ProviderCardAttempt(
      attemptId: attemptId,
      organizationId: organizationId,
      restaurantId: restaurantId,
      branchId: branchId,
      deviceId: deviceId,
      identityKey: PosOrderIdentity.server(orderId).key,
      orderId: orderId,
      orderNumber: orderNumber,
      mode: mode,
      amountMinor: amountMinor,
      currencyCode: currencyCode,
      expectedRevision: mode == ProviderCardMode.live ? expectedRevision : null,
      employeeProfileId: employeeProfileId,
      clientCreatedAt: at,
      updatedAt: at,
    );
  }

  // ---- frozen identity and inputs ----
  final String attemptId;
  final String organizationId;
  final String restaurantId;
  final String branchId;
  final String deviceId;
  final String identityKey;
  final String orderId;
  final String orderNumber;
  final ProviderCardMode mode;
  final int amountMinor;
  final String currencyCode;
  final int? expectedRevision;
  final String? employeeProfileId;
  final String clientCreatedAt;

  // ---- start ----
  final bool startInDoubt;
  final bool startMayHaveExecuted;
  final String? startLastSentAt;
  final ProviderCardStartOutcome? startOutcome;
  final ProviderCardStartRefusal? startRefusal;

  // ---- server ----
  final ProviderCardServerFacts? server;
  final String? serverNotFoundAt;

  // ---- recording leg ----
  final ProviderCardRecordingOperation? recording;
  final bool recordingInDoubt;
  final bool recordingMayHaveExecuted;
  final ProviderCardRecordingOutcome? recordingOutcome;
  final String? recordingRefusal;
  final String? refusalReportPending;
  final String? resumeDenied;
  final ProviderCardPayment? payment;
  final String? receiptReservedAt;

  // ---- local ----
  final ProviderCardSafetyStop? safetyStop;
  final ProviderCardClosure? closed;
  final String updatedAt;

  bool get isLive => mode == ProviderCardMode.live;

  /// No `start` of this attempt can have had a ledger effect: nothing was
  /// handed off, or only definitive no-effect answers came back.
  bool get startHasNoPossibleEffect => !startMayHaveExecuted && !startInDoubt;

  /// The `start` body's frozen, credential-free inputs (packet §4.1). The
  /// session fields are added at send time and never kept.
  Map<String, dynamic> startInputs() => <String, dynamic>{
    'attempt_id': attemptId,
    'mode': mode.wire,
    'amount_minor': amountMinor,
    'currency_code': currencyCode,
    if (mode == ProviderCardMode.live) 'order_id': orderId,
    if (mode == ProviderCardMode.live) 'expected_revision': expectedRevision,
  };

  /// Whether a conclusive `attempt_not_found` was recorded for the last
  /// `start` send (packet §7.3). The controller records one only for a request
  /// sent after the settle window had passed on its monotonic clock, and every
  /// new send clears it, so the record itself carries the decision: no wall
  /// clock is consulted.
  bool get notFoundSettled => serverNotFoundAt != null;

  /// The derived phase (packet §7.1), first match wins.
  ProviderCardPhase get phase {
    if (closed != null) return ProviderCardPhase.closed;
    final stop = safetyStop;
    final facts = server;
    if (stop != null) {
      // A stop raised on THIS attempt's own proven LIVE approval (a leg answer
      // outside the contract) still yields to the server's final word about
      // it. A stop that means the server holds other facts for this identity
      // (conflict, mode or amount mismatch, a TEST identity answering a LIVE
      // leg `test_attempt_not_recordable`) never does: those facts may
      // describe another attempt.
      final own = stop == ProviderCardSafetyStop.recordingContract;
      if (own &&
          isLive &&
          facts != null &&
          facts.familyMode == ProviderCardMode.live) {
        if (facts.resolution != null) return ProviderCardPhase.resolved;
        if (payment != null || facts.recorded) {
          return ProviderCardPhase.recorded;
        }
      }
      return ProviderCardPhase.reconciliation;
    }
    if (facts == null) {
      final outcome = startOutcome;
      if (outcome == ProviderCardStartOutcome.refused) {
        return ProviderCardPhase.refused;
      }
      if (outcome == ProviderCardStartOutcome.notApplied) {
        return ProviderCardPhase.notApplied;
      }
      if (!startInDoubt && !startMayHaveExecuted) {
        return outcome == ProviderCardStartOutcome.authRequired
            ? ProviderCardPhase.authRequired
            : ProviderCardPhase.notSent;
      }
      return notFoundSettled
          ? ProviderCardPhase.notFound
          : ProviderCardPhase.uncertain;
    }
    if (mode == ProviderCardMode.test) {
      if (facts.resolution == 'test_closed')
        return ProviderCardPhase.testClosed;
      return switch (facts.classification) {
        'test_approved' => ProviderCardPhase.testApproved,
        'test_declined' => ProviderCardPhase.testDeclined,
        'test_released' => ProviderCardPhase.testReleased,
        _ => ProviderCardPhase.testWaiting,
      };
    }
    if (facts.resolution != null) return ProviderCardPhase.resolved;
    if (payment != null || facts.recorded) return ProviderCardPhase.recorded;
    switch (facts.classification) {
      case 'in_progress':
        return facts.state == 'released'
            ? ProviderCardPhase.released
            : ProviderCardPhase.waiting;
      case 'freed':
        return ProviderCardPhase.freed;
      case 'declined':
        return ProviderCardPhase.declined;
      case 'provider_anomaly' || 'orphan_approved':
        return ProviderCardPhase.reconciliation;
      case 'approved_unrecorded':
        final outcome = recordingOutcome;
        if (recording == null) return ProviderCardPhase.approvedRecording;
        if (outcome == null) {
          // A leg built and persisted whose send may have begun (a crash or a
          // write failure after it): the same leg may only be sent again
          // explicitly.
          return recordingInDoubt || recordingMayHaveExecuted
              ? ProviderCardPhase.recordingUnconfirmed
              : ProviderCardPhase.approvedRecording;
        }
        if (outcome == ProviderCardRecordingOutcome.resumeAuthorityRequired) {
          return ProviderCardPhase.managerMustSend;
        }
        if (outcome == ProviderCardRecordingOutcome.resumeDenied) {
          return ProviderCardPhase.resumeRefused;
        }
        if (outcome == ProviderCardRecordingOutcome.refused ||
            outcome == ProviderCardRecordingOutcome.collision) {
          if (facts.recoverable == false) {
            return ProviderCardPhase.reconciliation;
          }
          if ((facts.resumeCount ?? 0) >= kProviderCardMaxResumes) {
            return ProviderCardPhase.reconciliation;
          }
          return ProviderCardPhase.recordingRefused;
        }
        if (outcome == ProviderCardRecordingOutcome.applied) {
          return ProviderCardPhase.recorded;
        }
        return ProviderCardPhase.recordingUnconfirmed;
      default:
        return ProviderCardPhase.reconciliation;
    }
  }

  /// Whether this attempt blocks a NEW start of the same [mode] for its order
  /// and keeps the card view (packet §7.3). A TEST attempt never blocks a LIVE
  /// start (it claims no order).
  bool get isOpen => switch (phase) {
    ProviderCardPhase.notApplied ||
    ProviderCardPhase.refused ||
    ProviderCardPhase.declined ||
    ProviderCardPhase.freed ||
    ProviderCardPhase.resolved ||
    ProviderCardPhase.closed ||
    ProviderCardPhase.testApproved ||
    ProviderCardPhase.testDeclined ||
    ProviderCardPhase.testClosed => false,
    _ => true,
  };

  /// Whether the cashier may set this attempt aside and take payment another
  /// way: only where no charge can exist (packet §7.3), in either mode. An
  /// unresolved TEST attempt is never set aside (correction packet §4): it
  /// stays recoverable, and a final TEST result needs no set-aside.
  bool get mayBeSetAside => switch (phase) {
    ProviderCardPhase.notSent ||
    ProviderCardPhase.authRequired ||
    ProviderCardPhase.notFound => true,
    _ => false,
  };

  /// Whether this attempt is safe and final enough to be dropped to make room
  /// in the journal (packet §5.3; correction packet §5): a terminal attempt,
  /// or a recorded one (its order is paid on the server).
  bool get isRetentionPrunable =>
      !isOpen || phase == ProviderCardPhase.recorded;

  /// The transition writer: every field explicit, nullable ones through the
  /// [_unset] sentinel so a `null` can be written deliberately.
  ProviderCardAttempt copyWith({
    bool? startInDoubt,
    bool? startMayHaveExecuted,
    Object? startLastSentAt = _unset,
    Object? startOutcome = _unset,
    Object? startRefusal = _unset,
    Object? server = _unset,
    Object? serverNotFoundAt = _unset,
    Object? recording = _unset,
    bool? recordingInDoubt,
    bool? recordingMayHaveExecuted,
    Object? recordingOutcome = _unset,
    Object? recordingRefusal = _unset,
    Object? refusalReportPending = _unset,
    Object? resumeDenied = _unset,
    Object? payment = _unset,
    Object? receiptReservedAt = _unset,
    Object? safetyStop = _unset,
    Object? closed = _unset,
    required String updatedAt,
  }) => ProviderCardAttempt(
    attemptId: attemptId,
    organizationId: organizationId,
    restaurantId: restaurantId,
    branchId: branchId,
    deviceId: deviceId,
    identityKey: identityKey,
    orderId: orderId,
    orderNumber: orderNumber,
    mode: mode,
    amountMinor: amountMinor,
    currencyCode: currencyCode,
    expectedRevision: expectedRevision,
    employeeProfileId: employeeProfileId,
    clientCreatedAt: clientCreatedAt,
    updatedAt: updatedAt,
    startInDoubt: startInDoubt ?? this.startInDoubt,
    startMayHaveExecuted: startMayHaveExecuted ?? this.startMayHaveExecuted,
    startLastSentAt: identical(startLastSentAt, _unset)
        ? this.startLastSentAt
        : startLastSentAt as String?,
    startOutcome: identical(startOutcome, _unset)
        ? this.startOutcome
        : startOutcome as ProviderCardStartOutcome?,
    startRefusal: identical(startRefusal, _unset)
        ? this.startRefusal
        : startRefusal as ProviderCardStartRefusal?,
    server: identical(server, _unset)
        ? this.server
        : server as ProviderCardServerFacts?,
    serverNotFoundAt: identical(serverNotFoundAt, _unset)
        ? this.serverNotFoundAt
        : serverNotFoundAt as String?,
    recording: identical(recording, _unset)
        ? this.recording
        : recording as ProviderCardRecordingOperation?,
    recordingInDoubt: recordingInDoubt ?? this.recordingInDoubt,
    recordingMayHaveExecuted:
        recordingMayHaveExecuted ?? this.recordingMayHaveExecuted,
    recordingOutcome: identical(recordingOutcome, _unset)
        ? this.recordingOutcome
        : recordingOutcome as ProviderCardRecordingOutcome?,
    recordingRefusal: identical(recordingRefusal, _unset)
        ? this.recordingRefusal
        : recordingRefusal as String?,
    refusalReportPending: identical(refusalReportPending, _unset)
        ? this.refusalReportPending
        : refusalReportPending as String?,
    resumeDenied: identical(resumeDenied, _unset)
        ? this.resumeDenied
        : resumeDenied as String?,
    payment: identical(payment, _unset)
        ? this.payment
        : payment as ProviderCardPayment?,
    receiptReservedAt: identical(receiptReservedAt, _unset)
        ? this.receiptReservedAt
        : receiptReservedAt as String?,
    safetyStop: identical(safetyStop, _unset)
        ? this.safetyStop
        : safetyStop as ProviderCardSafetyStop?,
    closed: identical(closed, _unset)
        ? this.closed
        : closed as ProviderCardClosure?,
  );

  /// The allowlisted keys — exactly these, every one always written.
  static const Set<String> keys = <String>{
    'schema_version',
    'attempt_id',
    'organization_id',
    'restaurant_id',
    'branch_id',
    'device_id',
    'identity_key',
    'order_id',
    'order_number',
    'mode',
    'amount_minor',
    'currency_code',
    'expected_revision',
    'employee_profile_id',
    'client_created_at',
    'start_in_doubt',
    'start_may_have_executed',
    'start_last_sent_at',
    'start_outcome',
    'start_refusal',
    'server',
    'server_not_found_at',
    'recording',
    'recording_in_doubt',
    'recording_may_have_executed',
    'recording_outcome',
    'recording_refusal',
    'refusal_report_pending',
    'resume_denied',
    'payment',
    'receipt_reserved_at',
    'safety_stop',
    'closed',
    'updated_at',
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'schema_version': schemaVersion,
    'attempt_id': attemptId,
    'organization_id': organizationId,
    'restaurant_id': restaurantId,
    'branch_id': branchId,
    'device_id': deviceId,
    'identity_key': identityKey,
    'order_id': orderId,
    'order_number': orderNumber,
    'mode': mode.wire,
    'amount_minor': amountMinor,
    'currency_code': currencyCode,
    'expected_revision': expectedRevision,
    'employee_profile_id': employeeProfileId,
    'client_created_at': clientCreatedAt,
    'start_in_doubt': startInDoubt,
    'start_may_have_executed': startMayHaveExecuted,
    'start_last_sent_at': startLastSentAt,
    'start_outcome': startOutcome?.wire,
    'start_refusal': startRefusal?.toJson(),
    'server': server?.toJson(),
    'server_not_found_at': serverNotFoundAt,
    'recording': recording?.toJson(),
    'recording_in_doubt': recordingInDoubt,
    'recording_may_have_executed': recordingMayHaveExecuted,
    'recording_outcome': recordingOutcome?.wire,
    'recording_refusal': recordingRefusal,
    'refusal_report_pending': refusalReportPending,
    'resume_denied': resumeDenied,
    'payment': payment?.toJson(),
    'receipt_reserved_at': receiptReservedAt,
    'safety_stop': safetyStop?.wire,
    'closed': closed?.wire,
    'updated_at': updatedAt,
  };

  @override
  bool operator ==(Object other) =>
      other is ProviderCardAttempt && _deepEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hash(attemptId, updatedAt, startOutcome, server);
}

bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (!b.containsKey(e.key) || !_deepEquals(e.value, b[e.key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

// ---------------------------------------------------------------------------
// The total decoder
// ---------------------------------------------------------------------------

/// The typed result of decoding one stored record. Never an exception.
@immutable
sealed class ProviderCardDecode {
  const ProviderCardDecode();
}

@immutable
final class ProviderCardDecoded extends ProviderCardDecode {
  const ProviderCardDecoded(this.attempt);
  final ProviderCardAttempt attempt;
}

@immutable
final class ProviderCardMalformed extends ProviderCardDecode {
  const ProviderCardMalformed(this.rule, this.message);

  /// A stable rule code (`R0` …) for tests and evidence; [message] names the
  /// field, never a value.
  final String rule;
  final String message;
}

/// TOTAL. Decodes one stored record against the rules of packet §5.2.
ProviderCardDecode decodeProviderCardAttempt(Object? raw) {
  final sm = strictStringObjectMap(raw);
  switch (sm) {
    case StrictMapNotAMap(:final observedTypeName):
      return ProviderCardMalformed('R0', 'not an object ($observedTypeName)');
    case StrictMapBadKey(:final observedTypeName):
      return ProviderCardMalformed('R0', 'non-String key ($observedTypeName)');
    case StrictMapOk(:final map):
      return _decode(map);
  }
}

ProviderCardDecode _decode(Map<String, Object?> m) {
  // R1 the version first: a future shape is quarantined, never guessed.
  final version = m['schema_version'];
  if (version is! int || version != ProviderCardAttempt.schemaVersion) {
    return const ProviderCardMalformed('R1', 'schema_version');
  }
  // R2 exact keys, both directions.
  final bad = exactKeys(m, ProviderCardAttempt.keys);
  if (bad != null) return ProviderCardMalformed('R2', bad);

  // R3 frozen identity and inputs.
  String? nonEmpty(String k) {
    final v = m[k];
    return v is String && v.trim().isNotEmpty ? v : null;
  }

  final rawAttemptId = m['attempt_id'];
  if (!isProviderCardUuidV4(rawAttemptId)) {
    return const ProviderCardMalformed('R3a', 'attempt_id');
  }
  final attemptId = rawAttemptId as String;
  final org = nonEmpty('organization_id');
  final restaurant = nonEmpty('restaurant_id');
  final branch = nonEmpty('branch_id');
  final device = nonEmpty('device_id');
  if (org == null || restaurant == null || branch == null || device == null) {
    return const ProviderCardMalformed('R3b', 'scope');
  }
  final orderId = nonEmpty('order_id');
  if (orderId == null) return const ProviderCardMalformed('R3c', 'order_id');
  if (m['identity_key'] != PosOrderIdentity.server(orderId).key) {
    return const ProviderCardMalformed('R3d', 'identity_key');
  }
  final orderNumber = m['order_number'];
  if (orderNumber is! String ||
      orderNumber.trim().isEmpty ||
      orderNumber.length > 64) {
    return const ProviderCardMalformed('R3e', 'order_number');
  }
  final mode = ProviderCardMode.fromWire(m['mode']);
  if (mode == null) return const ProviderCardMalformed('R3f', 'mode');
  final rawAmount = m['amount_minor'];
  if (!isProviderCardAmount(rawAmount)) {
    return const ProviderCardMalformed('R3g', 'amount_minor');
  }
  final amount = rawAmount as int;
  final rawCurrency = m['currency_code'];
  if (!isProviderCardCurrency(rawCurrency)) {
    return const ProviderCardMalformed('R3h', 'currency_code');
  }
  final currency = rawCurrency as String;
  final revision = m['expected_revision'];
  if (mode == ProviderCardMode.live) {
    if (!isProviderCardUuid(orderId)) {
      return const ProviderCardMalformed('R3i', 'live order_id');
    }
    if (revision is! int ||
        revision < 0 ||
        revision > kProviderCardMaxRevision) {
      return const ProviderCardMalformed('R3j', 'live expected_revision');
    }
  } else if (revision != null) {
    return const ProviderCardMalformed('R3k', 'test expected_revision');
  }
  final employee = m['employee_profile_id'];
  if (employee != null && (employee is! String || employee.trim().isEmpty)) {
    return const ProviderCardMalformed('R3l', 'employee_profile_id');
  }
  if (!isCanonicalInstant(m['client_created_at'])) {
    return const ProviderCardMalformed('R3m', 'client_created_at');
  }
  if (!isCanonicalInstant(m['updated_at'])) {
    return const ProviderCardMalformed('R3n', 'updated_at');
  }

  // R4 start.
  final inDoubt = m['start_in_doubt'];
  final mayHave = m['start_may_have_executed'];
  if (inDoubt is! bool || mayHave is! bool) {
    return const ProviderCardMalformed('R4a', 'start flags');
  }
  final lastSent = m['start_last_sent_at'];
  if (lastSent != null && !isCanonicalInstant(lastSent)) {
    return const ProviderCardMalformed('R4b', 'start_last_sent_at');
  }
  final rawOutcome = m['start_outcome'];
  final outcome = ProviderCardStartOutcome.fromWire(rawOutcome);
  if (rawOutcome != null && outcome == null) {
    return const ProviderCardMalformed('R4c', 'start_outcome');
  }
  if ((outcome != null || inDoubt || mayHave) && lastSent == null) {
    return const ProviderCardMalformed('R4d', 'start_last_sent_at missing');
  }
  final rawRefusal = m['start_refusal'];
  final refusal = rawRefusal == null
      ? null
      : ProviderCardStartRefusal.fromJson(rawRefusal);
  if (rawRefusal != null && refusal == null) {
    return const ProviderCardMalformed('R4e', 'start_refusal');
  }
  if ((outcome == ProviderCardStartOutcome.refused) != (refusal != null)) {
    return const ProviderCardMalformed('R4f', 'start_refusal / start_outcome');
  }

  // R5 server facts.
  final rawServer = m['server'];
  final server = rawServer == null
      ? null
      : ProviderCardServerFacts.fromJson(rawServer);
  if (rawServer != null && server == null) {
    return const ProviderCardMalformed('R5a', 'server');
  }
  if (server != null && !mayHave) {
    return const ProviderCardMalformed('R5b', 'server without a sent start');
  }
  if (server != null && server.familyMode != mode) {
    return const ProviderCardMalformed('R5d', 'server family / mode');
  }
  final notFoundAt = m['server_not_found_at'];
  if (notFoundAt != null && !isCanonicalInstant(notFoundAt)) {
    return const ProviderCardMalformed('R5c', 'server_not_found_at');
  }
  // A recorded not-found settles an attempt whose start may have executed and
  // that the server never answered for (packet §7.3).
  if (notFoundAt != null && (server != null || !(inDoubt || mayHave))) {
    return const ProviderCardMalformed('R5e', 'server_not_found_at context');
  }

  // R6 recording leg.
  final rawRecording = m['recording'];
  final recording = rawRecording == null
      ? null
      : ProviderCardRecordingOperation.fromJson(
          rawRecording,
          attemptId: attemptId,
          orderId: orderId,
          amountMinor: amount,
        );
  if (rawRecording != null && recording == null) {
    return const ProviderCardMalformed('R6a', 'recording');
  }
  if (recording != null && (mode != ProviderCardMode.live || server == null)) {
    return const ProviderCardMalformed(
      'R6b',
      'recording without a live approval',
    );
  }
  final recInDoubt = m['recording_in_doubt'];
  final recMayHave = m['recording_may_have_executed'];
  if (recInDoubt is! bool || recMayHave is! bool) {
    return const ProviderCardMalformed('R6c', 'recording flags');
  }
  final rawRecOutcome = m['recording_outcome'];
  final recOutcome = ProviderCardRecordingOutcome.fromWire(rawRecOutcome);
  if (rawRecOutcome != null && recOutcome == null) {
    return const ProviderCardMalformed('R6d', 'recording_outcome');
  }
  if (recording == null && (recInDoubt || recMayHave || recOutcome != null)) {
    return const ProviderCardMalformed('R6e', 'recording state without a leg');
  }
  final recRefusal = m['recording_refusal'];
  if (recRefusal != null &&
      (recRefusal is! String ||
          !kProviderCardRecordingHints.contains(recRefusal))) {
    return const ProviderCardMalformed('R6f', 'recording_refusal');
  }
  if (recording == null && recRefusal != null) {
    // A refusal hint without a leg breaks the same rule as the other
    // recording values.
    return const ProviderCardMalformed('R6e', 'recording state without a leg');
  }
  final reportPending = m['refusal_report_pending'];
  if (reportPending != null &&
      (reportPending is! String ||
          !kProviderCardRecordingHints.contains(reportPending))) {
    return const ProviderCardMalformed('R6g', 'refusal_report_pending');
  }
  if (reportPending != null &&
      recOutcome != ProviderCardRecordingOutcome.refused &&
      recOutcome != ProviderCardRecordingOutcome.collision) {
    return const ProviderCardMalformed('R6h', 'report without a refusal');
  }
  final denied = m['resume_denied'];
  if (denied != null &&
      (denied is! String ||
          !kProviderCardResumeDeniedTokens.contains(denied))) {
    return const ProviderCardMalformed('R6i', 'resume_denied');
  }
  if ((denied != null) !=
      (recOutcome == ProviderCardRecordingOutcome.resumeDenied)) {
    return const ProviderCardMalformed('R6j', 'resume_denied / outcome');
  }
  final rawPayment = m['payment'];
  final payment = rawPayment == null
      ? null
      : ProviderCardPayment.fromJson(rawPayment);
  if (rawPayment != null && payment == null) {
    return const ProviderCardMalformed('R6k', 'payment');
  }
  if ((payment != null) !=
      (recOutcome == ProviderCardRecordingOutcome.applied)) {
    return const ProviderCardMalformed('R6l', 'payment / outcome');
  }
  final reserved = m['receipt_reserved_at'];
  if (reserved != null && !isCanonicalInstant(reserved)) {
    return const ProviderCardMalformed('R6m', 'receipt_reserved_at');
  }
  if (reserved != null && payment == null) {
    return const ProviderCardMalformed('R6n', 'receipt without a payment');
  }

  // R7 local.
  final rawStop = m['safety_stop'];
  final stop = ProviderCardSafetyStop.fromWire(rawStop);
  if (rawStop != null && stop == null) {
    return const ProviderCardMalformed('R7a', 'safety_stop');
  }
  final rawClosed = m['closed'];
  final closed = ProviderCardClosure.fromWire(rawClosed);
  if (rawClosed != null && closed == null) {
    return const ProviderCardMalformed('R7b', 'closed');
  }
  if (closed == ProviderCardClosure.abandoned && (mayHave || inDoubt)) {
    return const ProviderCardMalformed(
      'R7c',
      'abandoned after a possible send',
    );
  }

  final attempt = ProviderCardAttempt(
    attemptId: attemptId,
    organizationId: org,
    restaurantId: restaurant,
    branchId: branch,
    deviceId: device,
    identityKey: m['identity_key']! as String,
    orderId: orderId,
    orderNumber: orderNumber,
    mode: mode,
    amountMinor: amount,
    currencyCode: currency,
    expectedRevision: revision as int?,
    employeeProfileId: employee as String?,
    clientCreatedAt: m['client_created_at']! as String,
    updatedAt: m['updated_at']! as String,
    startInDoubt: inDoubt,
    startMayHaveExecuted: mayHave,
    startLastSentAt: lastSent as String?,
    startOutcome: outcome,
    startRefusal: refusal,
    server: server,
    serverNotFoundAt: notFoundAt as String?,
    recording: recording,
    recordingInDoubt: recInDoubt,
    recordingMayHaveExecuted: recMayHave,
    recordingOutcome: recOutcome,
    recordingRefusal: recRefusal as String?,
    refusalReportPending: reportPending as String?,
    resumeDenied: denied as String?,
    payment: payment,
    receiptReservedAt: reserved as String?,
    safetyStop: stop,
    closed: closed,
  );
  // R7d a closure never hides an unresolved attempt (correction packet §4):
  // without it the record must be final already, or one the cashier may set
  // aside because no charge can exist. A closure of an open attempt that may
  // still have charged, a TEST one included, is quarantined, never honoured
  // as closed.
  if (closed != null) {
    final unclosed = attempt.copyWith(
      closed: null,
      updatedAt: attempt.updatedAt,
    );
    if (unclosed.isOpen && !unclosed.mayBeSetAside) {
      return const ProviderCardMalformed(
        'R7d',
        'closure of an unresolved attempt',
      );
    }
  }
  return ProviderCardDecoded(attempt);
}
