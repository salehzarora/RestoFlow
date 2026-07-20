/// KITCHEN-MODE-001C2A — the CLOSED local kitchen-spool vocabularies.
///
/// The local spool mirrors the server dispatch ledger's NON-PHYSICAL
/// semantics: nothing here ever claims paper was printed. `transportAccepted`
/// means exactly "the transport accepted the bytes"; `possiblyPrinted` is the
/// permanent ambiguity hold; `superseded` is SERVER-DERIVED state only (a
/// void dispatch superseded this job's dispatch) and can never be fabricated
/// through a generic local transition.
library;

/// Local lifecycle of one encrypted kitchen-spool job.
///
/// Closed vocabulary (DECISION D-018 discipline): no generic status strings
/// exist anywhere in the repository API; unknown wire values are rejected.
enum KitchenSpoolJobStatus {
  /// Imported from the server dispatch feed; not yet queued for a printer.
  imported('imported'),

  /// Ready to print (destination pinned) and waiting its turn.
  queued('queued'),

  /// Claimed by the single-flight print path right now.
  printing('printing'),

  /// The transport accepted the bytes — NEVER a physical-paper claim.
  transportAccepted('transport_accepted'),

  /// A retryable transport failure; runnable again once due.
  failedRetryable('failed_retryable'),

  /// No runnable destination (e.g. no kitchen printer configured). The
  /// authoritative encrypted payload is preserved; never silently dropped.
  blockedConfiguration('blocked_configuration'),

  /// Crash/interruption while printing — paper MAY exist. Permanent hold:
  /// never auto-runnable again (a blind retry could duplicate paper).
  possiblyPrinted('possibly_printed'),

  /// SERVER EVIDENCE ONLY: the dispatch was superseded by its order's void.
  /// Never runnable again; set exclusively through
  /// `markSupersededFromServerEvidence`.
  superseded('superseded');

  const KitchenSpoolJobStatus(this.wireName);

  /// The stable stored/wire value.
  final String wireName;

  /// Parses a stored value; throws [ArgumentError] on anything unknown
  /// (closed vocabulary — never pass through arbitrary strings).
  static KitchenSpoolJobStatus fromWire(String wire) {
    for (final v in values) {
      if (v.wireName == wire) return v;
    }
    throw ArgumentError.value(wire, 'wire', 'Unknown KitchenSpoolJobStatus');
  }

  /// States the print path may pick up (subject to `nextAttemptAt` gating).
  static const Set<KitchenSpoolJobStatus> runnable = {
    imported,
    queued,
    failedRetryable,
  };

  /// States that still block leaving printer-only mode / still need action.
  /// `transportAccepted` and `superseded` are resolved; everything else is
  /// unresolved (including the permanent `possiblyPrinted` hold, which needs
  /// an operator).
  static const Set<KitchenSpoolJobStatus> unresolved = {
    imported,
    queued,
    printing,
    failedRetryable,
    blockedConfiguration,
    possiblyPrinted,
  };
}

/// The server dispatch type this job was imported from (closed; mirrors the
/// server ledger's CHECK).
enum KitchenSpoolDispatchType {
  initialOrder('initial_order'),
  serviceRound('service_round'),
  voidNotice('void');

  const KitchenSpoolDispatchType(this.wireName);

  final String wireName;

  static KitchenSpoolDispatchType fromWire(String wire) {
    for (final v in values) {
      if (v.wireName == wire) return v;
    }
    throw ArgumentError.value(wire, 'wire', 'Unknown KitchenSpoolDispatchType');
  }
}

/// The acknowledgement this device still owes the server for a job (closed;
/// mirrors the server RPC's non-physical vocabulary). Local print state and
/// the server acknowledgement pipeline are deliberately INDEPENDENT: a failed
/// acknowledgement can never make a printed job runnable again.
enum KitchenServerAckStatus {
  imported('imported'),
  transportAccepted('transport_accepted'),
  possiblyPrinted('possibly_printed'),
  failedRetryable('failed_retryable'),
  blockedConfiguration('blocked_configuration');

  const KitchenServerAckStatus(this.wireName);

  final String wireName;

  static KitchenServerAckStatus fromWire(String wire) {
    for (final v in values) {
      if (v.wireName == wire) return v;
    }
    throw ArgumentError.value(wire, 'wire', 'Unknown KitchenServerAckStatus');
  }
}
