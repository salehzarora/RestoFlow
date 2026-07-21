/// KITCHEN-MODE-001C2C — the smallest TYPED internal operational state of
/// the kitchen spool/worker. WEB-SAFE and pure (zero imports): safe scalars
/// only — never an endpoint, payload, customer data, money, token, or raw
/// exception. No UI consumes it yet (that is a later phase); the lifecycle
/// updates it from each run's typed report.
enum PosKitchenSpoolCapability {
  /// Nothing to do / everything reconciled.
  idle,

  /// At least one job waits on the capped retry backoff.
  waitingRetry,

  /// A worker run is actively printing (reserved for live updates in the
  /// UX phase; report-derived updates never leave a run in this state).
  printing,

  /// At least one job is blocked on configuration/payload grounds.
  blockedConfiguration,

  /// The spool key is missing-over-rows / corrupted / unavailable (D3).
  keyUnavailable,

  /// The dedicated spool database could not be opened.
  databaseUnavailable,

  /// The transport medium is temporarily unavailable (radio/permission).
  transportUnavailable,

  /// The pinned destination can never be served (permanent incapability).
  destinationUnsupported,

  /// At least one job is possiblyPrinted — operator review required.
  possiblyPrintedReviewRequired,

  /// The server issued a terminal ownership/conflict verdict.
  terminalOwnershipConflict,

  /// An unexpected failure was contained at the runtime boundary.
  unexpectedFailure,
}
