/// Sync-operation lifecycle state (RF-018).
///
/// PROPOSED state enumeration per DECISION D-018 (approved into the frozen M0A
/// baseline at RF-004). Owned by docs/STATE_MACHINES.md section 10 and
/// referenced by docs/OFFLINE_SYNC_SPEC.md section 4 — this enum implements that
/// vocabulary; it does NOT redefine, add, rename, or repurpose states.
///
/// This is pure Dart (no Drift import) so the enum and its transition guard are
/// trivially unit-testable. The Drift `TypeConverter` that stores it lives in
/// `converters.dart`; the stored value is the [wireName] (snake_case).
///
/// Scope note: RF-018 only models the *vocabulary* and *legal transitions*. The
/// engine that drives operations through these states (push/pull/retry/backoff,
/// poison-op handling, conflict resolution) is RF-056/RF-057 and is OUT of scope.
library;

/// The eight sync-operation states (DECISION D-018). Do not add states here.
enum SyncOperationState {
  /// Locally created, not yet queued for delivery.
  created('created'),

  /// Queued for delivery.
  pending('pending'),

  /// Sent to the server; outcome not yet known.
  inFlight('in_flight'),

  /// Server applied the operation. Terminal.
  applied('applied'),

  /// Permanently rejected (auth/validation); never auto-retried. Terminal.
  rejected('rejected'),

  /// Poison operation: exceeded max retries on a transient-looking error.
  /// Terminal.
  dead('dead'),

  /// Server detected a concurrent change; awaiting resolution.
  conflict('conflict'),

  /// Conflict resolution finished; re-routes to [applied] or [rejected].
  resolved('resolved');

  const SyncOperationState(this.wireName);

  /// The canonical persisted/transported value (snake_case), e.g. `in_flight`.
  final String wireName;

  /// Parse a [wireName] back to its state. Throws [ArgumentError] if unknown.
  static SyncOperationState fromWire(String wire) {
    for (final s in SyncOperationState.values) {
      if (s.wireName == wire) return s;
    }
    throw ArgumentError.value(wire, 'wire', 'Unknown SyncOperationState');
  }

  /// Terminal states cannot transition onward.
  static const Set<SyncOperationState> terminals = {applied, rejected, dead};

  /// Whether this is a terminal state.
  bool get isTerminal => terminals.contains(this);

  /// The legal forward transitions for each state (OFFLINE_SYNC_SPEC section 4,
  /// STATE_MACHINES.md section 10). Terminal states map to the empty set.
  static const Map<SyncOperationState, Set<SyncOperationState>> _allowed = {
    created: {pending},
    pending: {inFlight},
    inFlight: {applied, rejected, dead, conflict},
    conflict: {resolved},
    resolved: {applied, rejected},
    applied: <SyncOperationState>{},
    rejected: <SyncOperationState>{},
    dead: <SyncOperationState>{},
  };

  /// Transition guard: `true` iff [from] -> [to] is a legal sync-operation
  /// transition. Terminal states never transition onward (always `false`).
  static bool canTransition(SyncOperationState from, SyncOperationState to) =>
      _allowed[from]!.contains(to);

  /// Whether this state may transition to [next].
  bool canTransitionTo(SyncOperationState next) => canTransition(this, next);
}
