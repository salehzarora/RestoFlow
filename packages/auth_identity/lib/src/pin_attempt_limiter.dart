/// Client-side PIN attempt limiting (RF-118). PURE Dart (no Flutter, no IO):
/// the persistence is a swappable [PinAttemptStore] seam and the clock is
/// injectable, so this is fully unit-testable.
///
/// This is a UX-facing MIRROR of the AUTHORITATIVE server lockout
/// (`app.start_pin_session` / `pin_attempt_states`, RF-051: 5 failures per
/// (employee, device) => a 15-minute lockout, checked before PIN verification).
/// The client limiter gives IMMEDIATE, visible feedback and a cooldown — even
/// before the server round-trip and even offline — but it is NOT the security
/// boundary: the server enforcement cannot be bypassed by clearing local
/// storage, so the two are defence-in-depth. Defaults mirror the server so the
/// client and server lock in lockstep.
///
/// SECURITY: no PIN, no verifier, no token, and no money is ever read or stored
/// here — only a per-scope failure count + an optional lockout timestamp.
library;

/// Immutable snapshot of the client PIN attempt/lockout state for ONE scope
/// (e.g. one `deviceId:employeeProfileId`, mirroring the server's per-(employee,
/// device) scope so one operator's failures never lock out the whole restaurant).
class PinAttemptState {
  const PinAttemptState({this.failedAttempts = 0, this.lockedUntil});

  /// Consecutive failed attempts since the last success/reset.
  final int failedAttempts;

  /// When the scope becomes unlocked again, or null when not locked.
  final DateTime? lockedUntil;

  /// The zero state (no failures, not locked).
  static const PinAttemptState empty = PinAttemptState();

  /// True when [now] is before [lockedUntil] (still cooling down).
  bool isLocked(DateTime now) {
    final until = lockedUntil;
    return until != null && until.isAfter(now);
  }

  /// Remaining cooldown at [now] (Duration.zero when not locked).
  Duration remaining(DateTime now) {
    final until = lockedUntil;
    if (until == null || !until.isAfter(now)) return Duration.zero;
    return until.difference(now);
  }

  /// Compact JSON for persistence. NO PIN/secret — a count + a timestamp only.
  Map<String, Object?> toJson() => <String, Object?>{
    'v': 1,
    'n': failedAttempts,
    'u': lockedUntil?.toUtc().toIso8601String(),
  };

  /// Tolerant parse: an unknown version or a malformed value yields [empty]
  /// (never throws — a corrupt local value must not brick sign-in).
  factory PinAttemptState.fromJson(Map<String, Object?> json) {
    if ((json['v'] as num?)?.toInt() != 1) return PinAttemptState.empty;
    final n = (json['n'] as num?)?.toInt() ?? 0;
    final rawUntil = json['u'];
    DateTime? until;
    if (rawUntil is String && rawUntil.isNotEmpty) {
      until = DateTime.tryParse(rawUntil);
    }
    return PinAttemptState(failedAttempts: n < 0 ? 0 : n, lockedUntil: until);
  }
}

/// Persistence seam for [PinAttemptLimiter] (survives a browser refresh / app
/// restart when backed by durable storage). Implementations MUST never store a
/// PIN/secret. Keyed by an opaque scope string.
abstract interface class PinAttemptStore {
  /// Loads the state for [scopeKey], or [PinAttemptState.empty] if none. Never
  /// throws — a corrupt value yields empty.
  Future<PinAttemptState> load(String scopeKey);

  /// Replaces the persisted state for [scopeKey].
  Future<void> persist(String scopeKey, PinAttemptState state);

  /// Clears the state for [scopeKey] (used on a successful sign-in).
  Future<void> clear(String scopeKey);
}

/// A process-memory [PinAttemptStore] (the demo/test default). Does NOT survive
/// a refresh; the app wires a durable (shared_preferences) store for the pilot.
class InMemoryPinAttemptStore implements PinAttemptStore {
  final Map<String, PinAttemptState> _states = <String, PinAttemptState>{};

  @override
  Future<PinAttemptState> load(String scopeKey) async =>
      _states[scopeKey] ?? PinAttemptState.empty;

  @override
  Future<void> persist(String scopeKey, PinAttemptState state) async =>
      _states[scopeKey] = state;

  @override
  Future<void> clear(String scopeKey) async => _states.remove(scopeKey);
}

/// The client PIN attempt limiter. Counts failures per scope, imposes a visible
/// cooldown at the cap, and resets on success — mirroring the server lockout.
class PinAttemptLimiter {
  PinAttemptLimiter({
    required PinAttemptStore store,
    int maxAttempts = 5,
    Duration lockoutDuration = const Duration(minutes: 15),
    DateTime Function()? clock,
  }) : assert(maxAttempts > 0),
       _store = store,
       _maxAttempts = maxAttempts,
       _lockoutDuration = lockoutDuration,
       _clock = clock ?? DateTime.now;

  final PinAttemptStore _store;
  final int _maxAttempts;
  final Duration _lockoutDuration;
  final DateTime Function() _clock;

  /// Failures allowed before a cooldown (default 5, mirroring RF-051).
  int get maxAttempts => _maxAttempts;

  /// Cooldown length once the cap is reached (default 15 min, mirroring RF-051).
  Duration get lockoutDuration => _lockoutDuration;

  /// The current state for [scopeKey] (for rendering a lockout banner).
  Future<PinAttemptState> stateFor(String scopeKey) => _store.load(scopeKey);

  /// Records ONE failed attempt for [scopeKey] and returns the new state. If a
  /// previous cooldown has already LAPSED, the counter starts fresh first (so a
  /// returning operator is not instantly re-locked by a single mistake). At the
  /// cap, a [lockoutDuration] cooldown begins.
  Future<PinAttemptState> recordFailure(String scopeKey) async {
    final now = _clock();
    var current = await _store.load(scopeKey);
    final lockedUntil = current.lockedUntil;
    if (lockedUntil != null && !lockedUntil.isAfter(now)) {
      // The previous cooldown lapsed — fresh slate before counting this failure.
      current = PinAttemptState.empty;
    }
    final next = current.failedAttempts + 1;
    final locked = next >= _maxAttempts ? now.add(_lockoutDuration) : null;
    final state = PinAttemptState(failedAttempts: next, lockedUntil: locked);
    await _store.persist(scopeKey, state);
    return state;
  }

  /// A successful sign-in clears the scope's counter (mirrors the server reset).
  Future<PinAttemptState> recordSuccess(String scopeKey) async {
    await _store.clear(scopeKey);
    return PinAttemptState.empty;
  }
}
