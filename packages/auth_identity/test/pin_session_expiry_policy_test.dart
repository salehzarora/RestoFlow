import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:test/test.dart';

void main() {
  final start = DateTime.utc(2026, 7, 4, 9, 0, 0);
  const policy = PinSessionExpiryPolicy(
    maxAge: Duration(hours: 8),
    inactivityTimeout: Duration(minutes: 30),
  );

  group('PinSessionExpiryPolicy', () {
    test('a fresh, active session is not expired', () {
      expect(
        policy.isExpired(
          startedAt: start,
          lastActivityAt: start.add(const Duration(minutes: 20)),
          now: start.add(const Duration(minutes: 25)),
        ),
        isFalse,
      );
    });

    test('inactivity beyond the timeout expires the session', () {
      expect(
        policy.isExpired(
          startedAt: start,
          lastActivityAt: start, // last active at sign-in
          now: start.add(const Duration(minutes: 31)),
        ),
        isTrue,
      );
    });

    test('activity keeps a long-but-active session alive (until max age)', () {
      // 5 hours in, but active 5 minutes ago => not expired (under 8h max age).
      expect(
        policy.isExpired(
          startedAt: start,
          lastActivityAt: start.add(const Duration(hours: 5)),
          now: start.add(const Duration(hours: 5, minutes: 5)),
        ),
        isFalse,
      );
    });

    test('the absolute max age expires even a continuously active session', () {
      expect(
        policy.isExpired(
          startedAt: start,
          lastActivityAt: start.add(const Duration(hours: 8)), // active at 8h
          now: start.add(const Duration(hours: 8)), // exactly max age
        ),
        isTrue,
      );
    });

    test('boundaries are inclusive (== deadline counts as expired)', () {
      expect(
        policy.isExpired(
          startedAt: start,
          lastActivityAt: start,
          now: start.add(const Duration(minutes: 30)), // exactly inactivity
        ),
        isTrue,
      );
    });

    test('staleAt returns the soonest of the two deadlines', () {
      // Inactivity (30 min) fires before max age (8h) for a just-started session.
      expect(
        policy.staleAt(startedAt: start, lastActivityAt: start),
        start.add(const Duration(minutes: 30)),
      );
      // Recent activity pushes the idle deadline past max age => max age wins.
      expect(
        policy.staleAt(
          startedAt: start,
          lastActivityAt: start.add(const Duration(hours: 7, minutes: 50)),
        ),
        start.add(const Duration(hours: 8)),
      );
    });
  });
}
