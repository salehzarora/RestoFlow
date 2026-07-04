/// Client-side staff PIN-session expiry policy (RF-118). PURE logic — no clock,
/// no IO: the caller supplies `now`, the session `startedAt`, and the last
/// activity time, so it is fully unit-testable and side-effect free.
///
/// It MIRRORS + COMPLEMENTS the authoritative server bound: `start_pin_session`
/// sets `pin_sessions.expires_at = now() + app.pin_session_offline_window()`
/// (RF-051, an 8-hour ABSOLUTE max age enforced server-side). The client adds an
/// INACTIVITY timeout — a device left idle re-requires the PIN — which the server
/// window alone does not express.
///
/// RECOVERABILITY / SAFETY: expiry is advisory UX — it drops the surface back to
/// the money-free PIN screen so the operator re-authenticates. It must be checked
/// only at SAFE boundaries (e.g. app resume), never mid-order, so a cashier is
/// never interrupted while ringing up a sale. It voids no money and no order.
class PinSessionExpiryPolicy {
  const PinSessionExpiryPolicy({
    this.maxAge = const Duration(hours: 8),
    this.inactivityTimeout = const Duration(minutes: 30),
  });

  /// Absolute lifetime of a PIN session from sign-in (mirrors the server 8h
  /// offline window). After this, re-authentication is required regardless of
  /// activity.
  final Duration maxAge;

  /// Idle window: if no activity within this span, the session is stale. Kept
  /// generous for a supervised pilot so a normal service session never trips.
  final Duration inactivityTimeout;

  /// True when the session is stale at [now]: either the absolute [maxAge] since
  /// [startedAt] has elapsed, or the [inactivityTimeout] since [lastActivityAt].
  bool isExpired({
    required DateTime startedAt,
    required DateTime lastActivityAt,
    required DateTime now,
  }) {
    // now >= startedAt + maxAge
    if (!now.isBefore(startedAt.add(maxAge))) return true;
    // now >= lastActivityAt + inactivityTimeout
    if (!now.isBefore(lastActivityAt.add(inactivityTimeout))) return true;
    return false;
  }

  /// The soonest time the session becomes stale (the min of the max-age and
  /// inactivity deadlines). Handy for a "signing you out soon" hint; not required
  /// for enforcement.
  DateTime staleAt({
    required DateTime startedAt,
    required DateTime lastActivityAt,
  }) {
    final byAge = startedAt.add(maxAge);
    final byIdle = lastActivityAt.add(inactivityTimeout);
    return byAge.isBefore(byIdle) ? byAge : byIdle;
  }
}
