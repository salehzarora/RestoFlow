/// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001C — the POS-to-Edge transport capability of
/// the `pos-card-charge` function (API_CONTRACT §4.55; execution packet
/// docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001C_EXECUTION.md).
///
/// One call is one exchange over the SAME authenticated device client: the
/// caller's body, encoded once, handed to the HTTP client at most once, within
/// [posCardChargeTimeout]. The answer is the function's 200 answer or a typed
/// transport failure. The transport never retries, never polls, never reads
/// what an answer means (no attempt state, decline or approval is derived
/// here), never logs a body and holds no credential, provider value or key.
/// No SDK import: the Supabase implementation lives in
/// `supabase_sync_rpc_transport.dart` and the one-handoff gate in
/// `kitchen_ack_http_boundary.dart`.
library;

/// The exact Edge function of the capability (POST only).
const String posCardChargeFunction = 'pos-card-charge';

/// The dedicated client deadline of ONE `pos-card-charge` exchange.
///
/// The function's configured worst case (001E `TIMING`, execution packet §5)
/// is `release`: the 5 s request-body read, four 5 s RPC deadlines and the 6 s
/// provider release = 31 s (`start` 18 s, `status` 26 s, `free_order` 15 s).
/// The handler's own CPU time between those wall-clock deadlines adds at most
/// the platform's documented 2 s per request (DEPLOYMENT §17.4 item 2, whose
/// hosted accounting is OPEN QUESTION Q-039) = 33 s. The remaining 7 s is an
/// engineering allowance, not a derived bound, for what no document bounds:
/// connection setup, gateway routing and request buffering, worker start,
/// other requests on the same worker, and the answer's return.
/// 31 s + 2 s + 7 s = 40 s. The deadline starts when the call starts; the
/// SDK's access-token step runs inside it (normally instant: the SDK refreshes
/// ahead of expiry). Once the deadline passes, the gate guarantees that
/// nothing of this request can be handed off any more.
///
/// It bounds one exchange, not the card payment: `start` answers within its
/// window and the terminal interaction is followed through later `status`
/// calls (initiate and poll). The general 15 s RPC timeout is not used here.
/// Changing this value needs a focused review and its tests
/// (`card_charge_static_test.dart` recomputes it from 001E's constants).
const Duration posCardChargeTimeout = Duration(seconds: 40);

/// Narrow card-charge boundary over the SAME authenticated device client as
/// every other device call. It never constructs another principal, never
/// falls back to an RPC and never retries.
abstract interface class AuthenticatedCardChargeTransport {
  /// Sends [body] — exactly as given — to `pos-card-charge` at most once and
  /// answers what that one exchange proves. [isCurrent], when given, is asked
  /// at the HTTP handoff, after the SDK has prepared the caller's access
  /// token; when it is false nothing is sent. The wrappers fold their own
  /// checks into it (the device-session guard's, the upgradable transport's),
  /// so the gate asks ONE composed check. Never throws.
  Future<CardChargeTransportResult> sendCardCharge(
    Map<String, dynamic> body, {
    bool Function()? isCurrent,
  });
}

/// The outcome of one `pos-card-charge` exchange.
sealed class CardChargeTransportResult {
  const CardChargeTransportResult();
}

/// HTTP 200 whose body is a JSON object with a boolean `ok` that belongs to
/// this request (see [classifyCardChargeAnswer]). Returned UNREAD and deeply
/// unmodifiable: 001F still validates the closed §4.55.4 envelope or refusal.
final class CardChargeAnswered extends CardChargeTransportResult {
  CardChargeAnswered(Map<String, Object?> body) : body = _frozenObject(body);

  final Map<String, Object?> body;

  @override
  String toString() => 'CardChargeAnswered'; // never the body
}

/// What a failed exchange proves about THIS request. No kind is a provider
/// decline or approval; an attempt's state is only ever read from an answer.
enum CardChargeFailureKind {
  /// Refused on this device: by a wrapper, the transport or the HTTP
  /// boundary's gate, before any handoff. Nothing was sent, and nothing can be.
  notSent,

  /// HTTP 401: the function refused the caller's authentication; refused with
  /// no ledger effect of this request.
  unauthenticated,

  /// HTTP 400, 403, 404 or 405 — a closed set: the statuses the function
  /// answers only before any ledger write (`invalid_request`; the boundary's
  /// 403 / 404 / 405). Refused with no ledger effect of this request (the
  /// POS's "not applied"). No other status is notApplied.
  notApplied,

  /// Transport-unknown (authorization §6): a timeout or a lost connection —
  /// even one before the HTTP handoff, though the gate then guarantees nothing
  /// can still be sent —, any status but 200, 400, 401, 403, 404 and 405 (407,
  /// 408, 409, 413, 415, 422, 425 and 429 among them; any non-200 2xx or 3xx;
  /// any 5xx), or an answer that is not readable for this request. The request
  /// MAY have executed; 001F keeps the same persisted attempt and learns its
  /// outcome through later `status` calls (the POS's UNCONFIRMED).
  uncertain,
}

/// Why an exchange failed (a closed set; never request or answer content).
enum CardChargeFailureReason {
  /// The device-session guard is blocked at entry, or the composed check asked
  /// at the HTTP handoff returned false (the guard's device session and, when a
  /// caller passes one, the caller's own `isCurrent`; the POS compositions pass
  /// none). A check that throws is [handoffRefused].
  deviceSessionUnverified,

  /// The degraded boot has no authenticated principal yet (hold mode).
  devicePrincipalPending,

  /// The transport cannot make a guarded card exchange.
  capabilityUnavailable,

  /// A web build: the function serves the native Android POS only.
  unsupportedPlatform,

  /// The body is not encodable as JSON.
  unencodableBody,

  /// The SDK could not prepare the caller's access token (its refresh could not
  /// reach the auth server): a lost connection, so uncertain.
  accessTokenUnavailable,

  /// The HTTP boundary refused the handoff: a closed client; not exactly the
  /// encoded POST of this exchange to this client's endpoint, with no query or
  /// fragment; or a composed handoff check that threw.
  handoffRefused,

  /// No answer within [posCardChargeTimeout].
  timeout,

  /// The connection failed or was reset, or another error occurred.
  transport,

  /// A complete non-200 HTTP answer ([CardChargeTransportFailure.httpStatus]).
  httpStatus,

  /// A 200 that is not a readable answer for this request, or an answer whose
  /// body could not be decoded.
  malformedAnswer,
}

/// A failed exchange: what it proves ([kind]), why ([reason]) and the HTTP
/// status of a complete answer whose body was decoded but that is not readable
/// for this request (any non-200, or a malformed 200); no status when the body
/// could not be decoded. It carries no body: a status already decides the
/// kind, and nothing in a body may turn an [uncertain] failure into anything
/// else.
///
/// [uncertain]: CardChargeFailureKind.uncertain
final class CardChargeTransportFailure extends CardChargeTransportResult {
  const CardChargeTransportFailure.notSent(this.reason)
    : kind = CardChargeFailureKind.notSent,
      httpStatus = null;

  const CardChargeTransportFailure.uncertain(this.reason)
    : kind = CardChargeFailureKind.uncertain,
      httpStatus = null;

  const CardChargeTransportFailure._status(
    this.kind,
    this.reason,
    int this.httpStatus,
  );

  final CardChargeFailureKind kind;
  final CardChargeFailureReason reason;
  final int? httpStatus;

  @override
  String toString() =>
      'CardChargeTransportFailure(${kind.name}, ${reason.name}'
      '${httpStatus == null ? '' : ', HTTP $httpStatus'})';
}

/// The function's refusal tokens that it only ever answers with a non-200
/// status — `statusOf`'s four (`lib/envelope.mjs`) and the boundary's three
/// (`handler.mjs`: 403, 404, 405): such a 200 is not the function's answer.
const Set<String> cardChargeNon200Errors = {
  'invalid_request',
  'invalid_session',
  'provider_unavailable',
  'unavailable',
  'origin_not_allowed',
  'not_found',
  'method_not_allowed',
};

/// Classifies one complete HTTP answer from its status and the SDK's decoded
/// body. Pure. It reads only the status and the body's shape — a JSON object
/// with a boolean `ok`, never a 200 refusal token the function sends with
/// another status, and an `attempt_id`, when present, equal to [attemptId] —
/// never what the answer means. Every status it does not list is uncertain.
CardChargeTransportResult classifyCardChargeAnswer(
  int status,
  Object? data, {
  String? attemptId,
}) {
  if (status == 200) {
    final object = _jsonObject(data);
    final ok = object?['ok'];
    final echoed = object?['attempt_id'];
    final readable =
        object != null &&
        ok is bool &&
        !(ok == false && cardChargeNon200Errors.contains(object['error'])) &&
        (attemptId == null ||
            echoed == attemptId ||
            (ok == false && echoed == null));
    return readable
        ? CardChargeAnswered(object)
        : const CardChargeTransportFailure._status(
            CardChargeFailureKind.uncertain,
            CardChargeFailureReason.malformedAnswer,
            200,
          );
  }
  // A closed policy: 401 and the statuses the function answers only before
  // any ledger write (400; the boundary's 403 / 404 / 405) are definitive.
  // Any other status — another 4xx, or the function's own 503, which can
  // follow a committed claim — does not prove that this request had no
  // ledger effect. The body never changes a status's kind.
  final kind = switch (status) {
    401 => CardChargeFailureKind.unauthenticated,
    400 || 403 || 404 || 405 => CardChargeFailureKind.notApplied,
    _ => CardChargeFailureKind.uncertain,
  };
  return CardChargeTransportFailure._status(
    kind,
    CardChargeFailureReason.httpStatus,
    status,
  );
}

/// A decoded JSON object with string keys, or null.
Map<String, Object?>? _jsonObject(Object? data) {
  if (data is! Map) return null;
  final out = <String, Object?>{};
  for (final entry in data.entries) {
    final key = entry.key;
    if (key is! String) return null;
    out[key] = entry.value;
  }
  return out;
}

Map<String, Object?> _frozenObject(Map<String, Object?> source) =>
    Map<String, Object?>.unmodifiable({
      for (final entry in source.entries) entry.key: _frozen(entry.value),
    });

Object? _frozen(Object? value) => switch (value) {
  final Map<Object?, Object?> map => Map<Object?, Object?>.unmodifiable({
    for (final entry in map.entries) entry.key: _frozen(entry.value),
  }),
  final List<Object?> list => List<Object?>.unmodifiable(list.map(_frozen)),
  _ => value,
};
