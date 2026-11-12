/// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F — the provider recording leg: the
/// canonical `payment.create` of an approved LIVE attempt, pushed alone through
/// the existing `sync_push` transport, and its answer read exactly
/// (execution packet §4.3, §8).
///
/// The leg's bytes come only from the sibling record's frozen
/// [ProviderCardRecordingOperation]: the attempt's own identity, the canonical
/// payload, NO `expected_revision` — and, for a D-054 Resume, the one
/// fingerprint-excluded `recording_resume` key beside the payload. Nothing here
/// mints, retries, polls or calls the provider.
///
/// The applied tuple and the base refusal tuples are read by the unchanged
/// [RealPaymentRepository.classifyEnvelope] on a transient, never-persisted
/// [PaymentAttempt] VIEW of the leg; the provider-leg answers of the 001D guard
/// are matched first, exactly. Transport failures are mapped here, explicitly:
/// the generic transport classifier is not used.
library;

import 'package:flutter/foundation.dart' show immutable;
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'payment_attempt.dart';
import 'payment_repository.dart';
import 'provider_card_attempt.dart';

/// What one recording-leg exchange proved.
@immutable
sealed class ProviderCardRecordingResult {
  const ProviderCardRecordingResult();
}

/// The server recorded the leg (first application or a verified replay).
@immutable
final class ProviderCardRecordingApplied extends ProviderCardRecordingResult {
  const ProviderCardRecordingApplied(this.payment, {required this.replay});
  final ProviderCardPayment payment;
  final bool replay;
}

/// A definitive refusal of the leg; [hint] is the token reported through
/// `status` (API §4.55.7).
@immutable
final class ProviderCardRecordingRefused extends ProviderCardRecordingResult {
  const ProviderCardRecordingRefused(this.hint);
  final String hint;
}

/// The server holds a different operation under this identity.
@immutable
final class ProviderCardRecordingCollision extends ProviderCardRecordingResult {
  const ProviderCardRecordingCollision();
}

/// Not executed yet: `transient_failure`, `dependency_not_ready` or
/// `single_operation_required` — the same leg is sent again, alone.
@immutable
final class ProviderCardRecordingPending extends ProviderCardRecordingResult {
  const ProviderCardRecordingPending(this.code);
  final String code;
}

/// A row a Resume reopened answers any non-manager session this way; it stays
/// pending (**D-057** point 3).
@immutable
final class ProviderCardRecordingResumeAuthorityRequired
    extends ProviderCardRecordingResult {
  const ProviderCardRecordingResumeAuthorityRequired();
}

/// The Resume guard refused: nothing was dispatched and no count was consumed.
@immutable
final class ProviderCardRecordingResumeDenied
    extends ProviderCardRecordingResult {
  const ProviderCardRecordingResumeDenied(this.token);
  final String token;
}

/// The leg MAY have executed: a lost or unreadable reply.
@immutable
final class ProviderCardRecordingUnconfirmed
    extends ProviderCardRecordingResult {
  const ProviderCardRecordingUnconfirmed(this.why);
  final String why;
}

/// The device guard refused before the wire: nothing was sent.
@immutable
final class ProviderCardRecordingNotSent extends ProviderCardRecordingResult {
  const ProviderCardRecordingNotSent();
}

/// A session-class refusal of the whole call: sign in again.
@immutable
final class ProviderCardRecordingAuthRequired
    extends ProviderCardRecordingResult {
  const ProviderCardRecordingAuthRequired();
}

/// A raised server error refused the whole call (rolled back; nothing
/// memoized), e.g. an active support session.
@immutable
final class ProviderCardRecordingNotApplied
    extends ProviderCardRecordingResult {
  const ProviderCardRecordingNotApplied(this.code);
  final String code;
}

/// A defect: never retried, never reported.
@immutable
final class ProviderCardRecordingSafetyStop
    extends ProviderCardRecordingResult {
  const ProviderCardRecordingSafetyStop(this.stop);
  final ProviderCardSafetyStop stop;
}

/// The `detail` tokens of a `provider_recording_refused` guard answer.
const Set<String> kProviderRecordingRefusedDetails = <String>{
  'attempt_resolved',
  'attempt_freed',
  'provider_anomaly',
  'attempt_not_approved',
  'order_mismatch',
  'tender_mismatch',
  'payment_exists',
  'claim_inactive',
};

/// The pre-dispatch validation answers `sync_push` gives a malformed operation.
const Set<String> _contractErrors = <String>{
  'invalid_payload',
  'invalid_envelope',
  'unknown_operation_type',
  'invalid_depends_on',
};

/// The `pending` answers that are re-sent under the same identity.
const Set<String> _pendingCodes = <String>{
  'transient_failure',
  'dependency_not_ready',
  'single_operation_required',
};

/// Sends the frozen recording leg of an attempt.
class ProviderCardRecordingSender {
  const ProviderCardRecordingSender({
    required SyncRpcTransport? transport,
    required SyncSession? session,
  }) : _transport = transport,
       _session = session;

  final SyncRpcTransport? _transport;
  final SyncSession? _session;

  /// Pushes [attempt]'s stored leg as the ONLY operation of one `sync_push`
  /// call. [recordingResume] is the `resume_count` a manager acted on (a D-054
  /// Resume); null for a first send or a resend. Never throws.
  Future<ProviderCardRecordingResult> send(
    ProviderCardAttempt attempt, {
    int? recordingResume,
  }) async {
    final leg = attempt.recording;
    final transport = _transport;
    final session = _session;
    if (leg == null) {
      return const ProviderCardRecordingSafetyStop(
        ProviderCardSafetyStop.recordingContract,
      );
    }
    // NEVER transmit another device's leg: the key is (device, op).
    if (transport == null ||
        session == null ||
        session.deviceId != attempt.deviceId) {
      return const ProviderCardRecordingNotSent();
    }
    final Object? raw;
    try {
      raw = await transport.invoke('sync_push', <String, dynamic>{
        'p_pin_session_id': session.pinSessionId,
        'p_device_id': session.deviceId,
        'p_operations': <dynamic>[
          leg.toSyncOperation(recordingResume: recordingResume),
        ],
      });
    } on SyncTransportException catch (e) {
      return mapProviderRecordingTransportFailure(e);
    } catch (_) {
      return const ProviderCardRecordingUnconfirmed('transport');
    }
    return classifyProviderRecordingReply(
      raw,
      attempt,
      resumed: recordingResume != null,
    );
  }
}

/// The leg's transport failures, explicitly (packet §8.3).
ProviderCardRecordingResult mapProviderRecordingTransportFailure(
  SyncTransportException e,
) {
  if (e.kind == SyncTransportErrorKind.auth) {
    return const ProviderCardRecordingAuthRequired();
  }
  if (e.kind == SyncTransportErrorKind.transient &&
      e.code == 'device_session_unverified') {
    return const ProviderCardRecordingNotSent();
  }
  final code = e.code;
  if (e.kind == SyncTransportErrorKind.server &&
      code != null &&
      RegExp(r'^[0-9A-Z]{5}$').hasMatch(code)) {
    // A raised server error: the whole call rolled back, nothing memoized.
    return ProviderCardRecordingNotApplied(code);
  }
  return const ProviderCardRecordingUnconfirmed('transport');
}

/// The transient, never-persisted base view of the leg the unchanged base
/// classifier reads (identity, order and the `card` tender).
PaymentAttempt providerCardLegView(ProviderCardAttempt attempt) {
  final leg = attempt.recording!;
  return PaymentAttempt(
    localOperationId: attempt.attemptId,
    targetId: leg.targetId,
    clientCreatedAt: leg.clientCreatedAt,
    identityKey: attempt.identityKey,
    orderId: attempt.orderId,
    orderNumber: attempt.orderNumber,
    expectedRevision: null,
    tenderType: 'card',
    amountMinor: attempt.amountMinor,
    amountTenderedMinor: attempt.amountMinor,
    currencyCode: attempt.currencyCode,
    organizationId: attempt.organizationId,
    restaurantId: attempt.restaurantId,
    branchId: attempt.branchId,
    deviceId: attempt.deviceId,
    employeeProfileId: attempt.employeeProfileId,
    phase: PaymentAttemptPhase.pending,
    lastOutcome: PaymentAttemptLastOutcome.none,
    sentAt: null,
    resolvedAt: null,
    resolution: null,
    refusal: null,
    refusalMemoized: false,
    autoEffectsReservedAt: null,
    supersedes: null,
  );
}

/// Reads one `sync_push` reply for [attempt]'s leg. Total; never throws.
ProviderCardRecordingResult classifyProviderRecordingReply(
  Object? raw,
  ProviderCardAttempt attempt, {
  required bool resumed,
}) {
  if (attempt.recording == null) {
    return const ProviderCardRecordingSafetyStop(
      ProviderCardSafetyStop.recordingContract,
    );
  }
  if (raw is! Map || raw['ok'] != true) {
    return const ProviderCardRecordingUnconfirmed('malformed');
  }
  final outerTs = raw['server_ts'];
  if (outerTs is! String || DateTime.tryParse(outerTs) == null) {
    return const ProviderCardRecordingUnconfirmed('malformed');
  }
  final results = raw['results'];
  if (results is! List || results.length != 1) {
    return const ProviderCardRecordingUnconfirmed('mismatched');
  }
  final op = results.single;
  if (op is! Map ||
      op['local_operation_id'] != attempt.attemptId ||
      op['operation_type'] != 'payment.create') {
    return const ProviderCardRecordingUnconfirmed('mismatched');
  }
  final status = op['status'];
  final error = op['error'];
  final detail = op['detail'];
  final replay = op['idempotency_replay'];

  // A refused Resume rides on the replayed stored rejection (D-054 guard).
  if (op.containsKey('resume_denied')) {
    final token = op['resume_denied'];
    if (resumed &&
        status == 'rejected' &&
        replay == true &&
        token is String &&
        kProviderCardResumeDeniedTokens.contains(token)) {
      return ProviderCardRecordingResumeDenied(token);
    }
    return const ProviderCardRecordingUnconfirmed('malformed');
  }

  if (status == 'pending') {
    if (op['ok'] != false || replay is! bool || op['retryable'] != true) {
      return const ProviderCardRecordingUnconfirmed('malformed');
    }
    if (error == 'resume_authority_required') {
      return const ProviderCardRecordingResumeAuthorityRequired();
    }
    if (error is String && _pendingCodes.contains(error)) {
      return ProviderCardRecordingPending(error);
    }
    return const ProviderCardRecordingUnconfirmed('malformed');
  }

  if (status == 'rejected' || status == 'dead') {
    if (op['ok'] != false || replay is! bool) {
      return const ProviderCardRecordingUnconfirmed('malformed');
    }
    final sqlstate = op['sqlstate'];
    final serverTs = op['server_ts'];
    final orderId = op['order_id'];
    final guardTuple =
        sqlstate == null &&
        serverTs is String &&
        DateTime.tryParse(serverTs) != null &&
        orderId == attempt.orderId;
    if (error == 'test_attempt_not_recordable') {
      return const ProviderCardRecordingSafetyStop(
        ProviderCardSafetyStop.testAttemptNotRecordable,
      );
    }
    if (error == 'provider_recording_refused' &&
        detail is String &&
        kProviderRecordingRefusedDetails.contains(detail) &&
        guardTuple) {
      return const ProviderCardRecordingRefused('provider_recording_refused');
    }
    if (error == 'amount_mismatch' && detail == null && guardTuple) {
      return const ProviderCardRecordingRefused('amount_mismatch');
    }
    if (error == 'card_context_lost' && detail == null && guardTuple) {
      return const ProviderCardRecordingRefused('card_context_lost');
    }
    // The revoked-device path: never recoverable (**D-056** point 2).
    if (error == 'rejected' && detail == 'revoked_device' && sqlstate == null) {
      return const ProviderCardRecordingRefused('revoked_device');
    }
    if (error is String && _contractErrors.contains(error)) {
      return const ProviderCardRecordingSafetyStop(
        ProviderCardSafetyStop.recordingContract,
      );
    }
  }

  // The applied tuple, the idempotency conflict and the base refusal tuples:
  // the unchanged base classifier decides.
  final base = RealPaymentRepository.classifyEnvelope(
    raw,
    providerCardLegView(attempt),
  );
  return switch (base) {
    PaymentSendAccepted(:final resolution) => ProviderCardRecordingApplied(
      ProviderCardPayment(
        paymentId: resolution.paymentId,
        receiptNumber: resolution.receiptNumber,
        orderStatus: resolution.orderStatus,
      ),
      replay: resolution.replay,
    ),
    PaymentSendRefused(:final code, :final memoized) =>
      memoized
          ? ProviderCardRecordingRefused(switch (code) {
              PaymentRefusalCode.notChargeable => 'order_not_chargeable',
              PaymentRefusalCode.revisionConflict => 'conflict',
              PaymentRefusalCode.shiftRequired => 'precondition_failed',
              PaymentRefusalCode.permissionDenied => 'permission_denied',
              PaymentRefusalCode.revokedEmployee => 'revoked_employee',
              PaymentRefusalCode.generic => 'nonrecoverable_refusal',
            })
          : const ProviderCardRecordingSafetyStop(
              ProviderCardSafetyStop.recordingContract,
            ),
    PaymentSendUnconfirmed(:final reason) =>
      reason == PaymentUnconfirmedReason.identityCollision
          ? const ProviderCardRecordingCollision()
          : ProviderCardRecordingUnconfirmed(reason.name),
    PaymentSendNotApplied(:final code) => ProviderCardRecordingUnconfirmed(
      'not applied: $code',
    ),
    PaymentSendAuthRequired() => const ProviderCardRecordingAuthRequired(),
  };
}
