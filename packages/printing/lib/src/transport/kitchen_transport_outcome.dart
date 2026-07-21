import '../spool/print_spool.dart' show PrintRetryPolicy;

/// KITCHEN-MODE-001C2C — the CLOSED kitchen transport outcome model.
///
/// Kitchen tickets must never be duplicated by a blind retry, so a kitchen
/// send classifies its result by PHASE, not by exception type. The worker
/// mapping is FIXED (pinned by tests):
///
///   accepted                 -> transportAccepted
///   definitelyNotSent        -> failedRetryable
///   timeoutBeforeWrite       -> failedRetryable
///   unavailable (temporary)  -> failedRetryable
///   unsupported (permanent)  -> blockedConfiguration
///   ambiguous                -> possiblyPrinted
///   timeoutAfterPossibleWrite-> possiblyPrinted
///
/// There is deliberately NO catch-all "exception = retryable": anything the
/// adapter cannot PROVE unsent after the point of no safe retry is
/// ambiguous, and ambiguous is never retried automatically.
///
/// PRIVACY: an outcome carries only a closed [kind], a safe bounded
/// [reasonCode] token, and timing metadata — never an endpoint, payload
/// bytes, customer data, notes, money, a token, or a raw platform
/// exception.
enum KitchenTransportOutcomeKind {
  /// The adapter accepted/flushed the bytes per its contract. NEVER a
  /// physical paper claim (ESC/POS has no paper acknowledgement).
  accepted,

  /// PROVEN failure before any byte could reach the transport — the only
  /// class that is safe to retry.
  definitelyNotSent,

  /// The result after the point of no safe retry is unknown — paper MAY
  /// exist. Never retried automatically.
  ambiguous,

  /// The destination/platform can never serve this send (malformed
  /// destination, unsupported platform, unbonded device). Permanent.
  unsupported,

  /// The transport medium is temporarily unavailable (radio off, missing
  /// permission) — retryable once the medium returns.
  unavailable,

  /// Timed out strictly BEFORE any byte was handed over — retryable.
  timeoutBeforeWrite,

  /// Timed out AFTER bytes may have left the process — ambiguous by
  /// definition; never retried automatically.
  timeoutAfterPossibleWrite,
}

/// One classified kitchen transport attempt (safe scalars only).
final class KitchenTransportOutcome {
  const KitchenTransportOutcome(this.kind, this.reasonCode, {this.elapsed});

  final KitchenTransportOutcomeKind kind;

  /// Safe bounded token (e.g. `connect_refused`, `flush_timeout`,
  /// `partial_write`) — never endpoint/payload/exception text.
  final String reasonCode;

  final Duration? elapsed;

  /// Whether the WORKER may schedule an automatic retry for this outcome.
  /// ONLY provably-unsent classes qualify.
  bool get isSafeToRetry => switch (kind) {
    KitchenTransportOutcomeKind.definitelyNotSent ||
    KitchenTransportOutcomeKind.timeoutBeforeWrite ||
    KitchenTransportOutcomeKind.unavailable => true,
    KitchenTransportOutcomeKind.accepted ||
    KitchenTransportOutcomeKind.ambiguous ||
    KitchenTransportOutcomeKind.unsupported ||
    KitchenTransportOutcomeKind.timeoutAfterPossibleWrite => false,
  };

  @override
  String toString() =>
      'KitchenTransportOutcome(${kind.name}, $reasonCode'
      '${elapsed == null ? '' : ', ${elapsed!.inMilliseconds}ms'})';
}

/// KITCHEN-MODE-001C2C (LOCKED DECISION 4) — the kitchen retry contract:
/// retry ONLY definitely-not-sent outcomes; persisted attempt count;
/// exponential 2s × 2ⁿ backoff capped at 5 minutes; NO jitter (deterministic
/// for the lifecycle-cadence worker — no periodic timer exists, retries are
/// evaluated only on startup/resume/context refresh); INDEFINITE capped
/// policy (no arbitrary maximum-attempt parking in this phase).
const PrintRetryPolicy kitchenPrintRetryPolicy = PrintRetryPolicy(
  jitter: false,
);
