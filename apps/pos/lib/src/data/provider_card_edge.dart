/// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F — the POS side of the `pos-card-charge`
/// Edge exchange: the exact `start` / `status` / `release` bodies, the DIRECT
/// mapping of the 001C transport kinds and the closed parse of the answer
/// (execution packet §4.1, §4.2, §6).
///
/// The transport's failure kinds are mapped as they are — `notSent`,
/// `unauthenticated`, `notApplied`, `uncertain` — and never re-derived from an
/// HTTP status: the payment repository's generic transport classifier still
/// treats any 4xx but 408 / 425 / 429 as "not applied" and is not used here.
/// No kind is a provider decline or approval; only a closed HTTP-200 envelope
/// changes what the attempt knows.
///
/// The device-session token is a credential: it is read for each exchange,
/// placed in that one body, and never kept, logged or returned.
library;

import 'package:flutter/foundation.dart' show immutable;
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceSessionCredential, DeviceSessionSecretStore;
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'provider_card_attempt.dart';

/// What one Edge exchange proved about the attempt.
@immutable
sealed class ProviderCardEdgeResult {
  const ProviderCardEdgeResult();
}

/// A closed envelope for THIS attempt, matching its frozen amount, currency and
/// mode.
@immutable
final class ProviderCardEdgeEnvelope extends ProviderCardEdgeResult {
  const ProviderCardEdgeEnvelope(this.facts);
  final ProviderCardServerFacts facts;
}

/// A closed refusal (HTTP 200): the ledger was left untouched.
@immutable
final class ProviderCardEdgeRefusal extends ProviderCardEdgeResult {
  const ProviderCardEdgeRefusal(this.error, this.detail, {this.attemptState});
  final String error;
  final String? detail;

  /// The existing attempt's state when the refusal concerns one (`attempt_id` /
  /// `attempt_state` siblings), else null.
  final String? attemptState;
}

/// A well-formed envelope that contradicts the frozen attempt: a safety stop.
@immutable
final class ProviderCardEdgeContradiction extends ProviderCardEdgeResult {
  const ProviderCardEdgeContradiction(this.stop);
  final ProviderCardSafetyStop stop;
}

/// 001C `notSent`, or this device's own session / device check refused before
/// the transport was asked: nothing was handed off.
@immutable
final class ProviderCardEdgeNotSent extends ProviderCardEdgeResult {
  const ProviderCardEdgeNotSent(this.reason);

  /// The transport's reason, or null for this device's own pre-send check.
  final CardChargeFailureReason? reason;
}

/// 001C `unauthenticated` (HTTP 401): refused with no ledger effect.
@immutable
final class ProviderCardEdgeUnauthenticated extends ProviderCardEdgeResult {
  const ProviderCardEdgeUnauthenticated();
}

/// 001C `notApplied` (HTTP 400 / 403 / 404 / 405): refused before processing.
@immutable
final class ProviderCardEdgeNotApplied extends ProviderCardEdgeResult {
  const ProviderCardEdgeNotApplied(this.httpStatus);
  final int? httpStatus;
}

/// 001C `uncertain`: the request MAY have executed.
@immutable
final class ProviderCardEdgeUncertain extends ProviderCardEdgeResult {
  const ProviderCardEdgeUncertain(this.reason);
  final CardChargeFailureReason reason;
}

/// An HTTP-200 answer the closed parse refuses (an unknown key, a missing field,
/// a wrong type, an inconsistent shape): unreadable evidence that changes
/// nothing.
@immutable
final class ProviderCardEdgeUnreadable extends ProviderCardEdgeResult {
  const ProviderCardEdgeUnreadable(this.why);
  final String why;
}

/// Maps one transport result DIRECTLY (packet §6).
ProviderCardEdgeResult mapProviderCardTransportResult(
  CardChargeTransportResult result,
  ProviderCardAttempt attempt,
) => switch (result) {
  CardChargeAnswered(:final body) => parseProviderCardAnswer(body, attempt),
  CardChargeTransportFailure(:final kind, :final reason, :final httpStatus) =>
    switch (kind) {
      CardChargeFailureKind.notSent => ProviderCardEdgeNotSent(reason),
      CardChargeFailureKind.unauthenticated =>
        const ProviderCardEdgeUnauthenticated(),
      CardChargeFailureKind.notApplied => ProviderCardEdgeNotApplied(
        httpStatus,
      ),
      CardChargeFailureKind.uncertain => ProviderCardEdgeUncertain(reason),
    },
};

/// The keys the Edge envelope may carry (`envelope.mjs` projectEnvelope).
const Set<String> _envelopeRequired = <String>{
  'ok',
  'attempt_id',
  'state',
  'classification',
  'recorded',
  'amount_minor',
  'currency_code',
  'server_ts',
};
const Set<String> _envelopeOptional = <String>{
  'provider_return_code',
  'refusal_code',
  'anomaly_code',
  'resolution',
  'recoverable',
  'resume_count',
  'payment_id',
};

/// The keys an Edge refusal may carry (`envelope.mjs` projectRefusal and the
/// handler's own refusals).
const Set<String> _refusalKeys = <String>{
  'ok',
  'error',
  'detail',
  'attempt_id',
  'attempt_state',
  'server_ts',
};

/// The closed parse of an HTTP-200 answer for [attempt] (API §4.55.4). Total.
ProviderCardEdgeResult parseProviderCardAnswer(
  Map<String, Object?> body,
  ProviderCardAttempt attempt,
) {
  final ok = body['ok'];
  if (ok == true) return _parseEnvelope(body, attempt);
  if (ok == false) return _parseRefusal(body, attempt);
  return const ProviderCardEdgeUnreadable('ok');
}

ProviderCardEdgeResult _parseEnvelope(
  Map<String, Object?> body,
  ProviderCardAttempt attempt,
) {
  for (final k in body.keys) {
    if (!_envelopeRequired.contains(k) && !_envelopeOptional.contains(k)) {
      return const ProviderCardEdgeUnreadable('unknown envelope key');
    }
  }
  for (final k in _envelopeRequired) {
    if (!body.containsKey(k)) {
      return const ProviderCardEdgeUnreadable('missing envelope key');
    }
  }
  if (body['attempt_id'] != attempt.attemptId) {
    return const ProviderCardEdgeUnreadable('attempt_id');
  }
  final state = body['state'];
  final classification = body['classification'];
  final recorded = body['recorded'];
  final amount = body['amount_minor'];
  final currency = body['currency_code'];
  final serverTs = body['server_ts'];
  if (state is! String ||
      classification is! String ||
      recorded is! bool ||
      amount is! int ||
      currency is! String ||
      serverTs is! String) {
    return const ProviderCardEdgeUnreadable('envelope types');
  }
  // The provider's return code is validated for shape and then dropped: this
  // POS keeps and shows no provider value.
  if (body.containsKey('provider_return_code')) {
    final code = body['provider_return_code'];
    if (code is! int || code < -999999 || code > 999999) {
      return const ProviderCardEdgeUnreadable('provider_return_code');
    }
  }
  Object? opt(String k) => body.containsKey(k) ? body[k] : null;
  final refusal = opt('refusal_code');
  final anomaly = opt('anomaly_code');
  final resolution = opt('resolution');
  final recoverable = opt('recoverable');
  final resumeCount = opt('resume_count');
  final paymentId = opt('payment_id');
  // An optional key is either absent or carries a value of its type (the Edge
  // never emits an explicit null).
  for (final k in _envelopeOptional) {
    if (body.containsKey(k) && body[k] == null) {
      return const ProviderCardEdgeUnreadable('explicit null');
    }
  }
  if ((refusal != null && refusal is! String) ||
      (anomaly != null && anomaly is! String) ||
      (resolution != null && resolution is! String) ||
      (recoverable != null && recoverable is! bool) ||
      (resumeCount != null && resumeCount is! int) ||
      (paymentId != null && paymentId is! String)) {
    return const ProviderCardEdgeUnreadable('optional types');
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
  final problem = facts.consistencyProblem();
  if (problem != null) return ProviderCardEdgeUnreadable(problem);
  // Well-formed, but is it THIS attempt?
  if (amount != attempt.amountMinor || currency != attempt.currencyCode) {
    return const ProviderCardEdgeContradiction(
      ProviderCardSafetyStop.amountMismatch,
    );
  }
  if (facts.familyMode != attempt.mode) {
    return const ProviderCardEdgeContradiction(
      ProviderCardSafetyStop.modeMismatch,
    );
  }
  return ProviderCardEdgeEnvelope(facts);
}

ProviderCardEdgeResult _parseRefusal(
  Map<String, Object?> body,
  ProviderCardAttempt attempt,
) {
  for (final k in body.keys) {
    if (!_refusalKeys.contains(k)) {
      return const ProviderCardEdgeUnreadable('unknown refusal key');
    }
  }
  final error = body['error'];
  if (error is! String || !kProviderCardEdgeErrors.contains(error)) {
    return const ProviderCardEdgeUnreadable('error');
  }
  String? detail;
  if (body.containsKey('detail')) {
    final d = body['detail'];
    if (d is! String || !kProviderCardEdgeDetails.contains(d)) {
      return const ProviderCardEdgeUnreadable('detail');
    }
    detail = d;
  }
  final hasId = body.containsKey('attempt_id');
  final hasState = body.containsKey('attempt_state');
  if (hasId != hasState) {
    return const ProviderCardEdgeUnreadable('attempt_id / attempt_state');
  }
  String? attemptState;
  if (hasId) {
    final s = body['attempt_state'];
    if (body['attempt_id'] != attempt.attemptId ||
        s is! String ||
        !kProviderCardStates.contains(s)) {
      return const ProviderCardEdgeUnreadable('attempt facts');
    }
    attemptState = s;
  }
  if (body.containsKey('server_ts') &&
      !isProviderCardServerTs(body['server_ts'])) {
    return const ProviderCardEdgeUnreadable('server_ts');
  }
  return ProviderCardEdgeRefusal(error, detail, attemptState: attemptState);
}

/// The Edge exchanges of one attempt, over the SAME authenticated device
/// transport as every other device call (001C). Never retries, never polls,
/// never throws.
class ProviderCardEdgeClient {
  const ProviderCardEdgeClient({
    required SyncRpcTransport? transport,
    required SyncSession? session,
    required DeviceSessionSecretStore? secretStore,
    this.isCurrent,
  }) : _transport = transport,
       _session = session,
       _secretStore = secretStore;

  final SyncRpcTransport? _transport;
  final SyncSession? _session;
  final DeviceSessionSecretStore? _secretStore;

  /// Asked before the exchange and, through the transport, at the HTTP handoff:
  /// false when the session, scope or device context changed meanwhile.
  final bool Function()? isCurrent;

  /// `start` with the attempt's frozen inputs (packet §4.1).
  Future<ProviderCardEdgeResult> start(ProviderCardAttempt attempt) =>
      _exchange(attempt, 'start', attempt.startInputs());

  /// `status`; [operator] selects `source: operator` (Check status, manager
  /// actions) instead of `auto`; [recordingRefusedHint] reports a refused
  /// recording leg (API §4.55.7).
  Future<ProviderCardEdgeResult> status(
    ProviderCardAttempt attempt, {
    required bool operator,
    String? recordingRefusedHint,
  }) => _exchange(attempt, 'status', <String, dynamic>{
    'attempt_id': attempt.attemptId,
    'source': operator ? 'operator' : 'auto',
    if (recordingRefusedHint != null) 'recording_refused': true,
    if (recordingRefusedHint != null) 'refusal_code': recordingRefusedHint,
  });

  /// `release` — advisory (API §4.55.6).
  Future<ProviderCardEdgeResult> release(ProviderCardAttempt attempt) =>
      _exchange(attempt, 'release', <String, dynamic>{
        'attempt_id': attempt.attemptId,
      });

  /// The exact body: the action, the CURRENT session proof, then the attempt's
  /// frozen fields. The same attempt and session give the same bytes.
  Map<String, dynamic> bodyFor(
    String action,
    Map<String, dynamic> attemptFields, {
    required String pinSessionId,
    required String deviceId,
    required String deviceSessionToken,
  }) => <String, dynamic>{
    'action': action,
    'pin_session_id': pinSessionId,
    'device_id': deviceId,
    'device_session_token': deviceSessionToken,
    ...attemptFields,
  };

  Future<ProviderCardEdgeResult> _exchange(
    ProviderCardAttempt attempt,
    String action,
    Map<String, dynamic> attemptFields,
  ) async {
    final transport = _transport;
    final session = _session;
    final store = _secretStore;
    if (transport is! AuthenticatedCardChargeTransport) {
      return const ProviderCardEdgeNotSent(
        CardChargeFailureReason.capabilityUnavailable,
      );
    }
    if (session == null || store == null) {
      return const ProviderCardEdgeNotSent(null);
    }
    // A fresh session and device check before anything leaves the device.
    final DeviceSessionCredential? credential;
    try {
      credential = await store.read();
    } catch (_) {
      return const ProviderCardEdgeNotSent(null);
    }
    if (credential == null ||
        credential.deviceId != session.deviceId ||
        credential.sessionToken.isEmpty ||
        session.deviceId != attempt.deviceId ||
        !isProviderCardUuid(session.deviceId) ||
        !isProviderCardUuid(session.pinSessionId) ||
        isCurrent?.call() == false) {
      return const ProviderCardEdgeNotSent(null);
    }
    final body = bodyFor(
      action,
      attemptFields,
      pinSessionId: session.pinSessionId,
      deviceId: session.deviceId,
      deviceSessionToken: credential.sessionToken,
    );
    final CardChargeTransportResult result;
    try {
      result = await (transport as AuthenticatedCardChargeTransport)
          .sendCardCharge(body, isCurrent: isCurrent);
    } catch (_) {
      // The capability never throws; a defect still never reads as an answer.
      return const ProviderCardEdgeUncertain(CardChargeFailureReason.transport);
    }
    return mapProviderCardTransportResult(result, attempt);
  }
}
