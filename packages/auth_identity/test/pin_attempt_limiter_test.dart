import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:test/test.dart';

/// A store that records how many times each method ran, so a test can assert
/// persistence happened (mirrors the "survives refresh" contract via a fresh
/// limiter over the same store).
class _CountingStore implements PinAttemptStore {
  final Map<String, PinAttemptState> states = <String, PinAttemptState>{};
  int persists = 0;
  int clears = 0;

  @override
  Future<PinAttemptState> load(String scopeKey) async =>
      states[scopeKey] ?? PinAttemptState.empty;

  @override
  Future<void> persist(String scopeKey, PinAttemptState state) async {
    persists++;
    states[scopeKey] = state;
  }

  @override
  Future<void> clear(String scopeKey) async {
    clears++;
    states.remove(scopeKey);
  }
}

void main() {
  const scope = 'device-1:employee-9';
  final t0 = DateTime.utc(2026, 7, 4, 12, 0, 0);
  DateTime clock = t0;

  PinAttemptLimiter limiterOver(
    PinAttemptStore store, {
    int maxAttempts = 5,
    Duration lockout = const Duration(minutes: 15),
  }) => PinAttemptLimiter(
    store: store,
    maxAttempts: maxAttempts,
    lockoutDuration: lockout,
    clock: () => clock,
  );

  setUp(() => clock = t0);

  group('PinAttemptState', () {
    test('isLocked/remaining reflect lockedUntil vs now', () {
      final s = PinAttemptState(
        failedAttempts: 5,
        lockedUntil: t0.add(const Duration(minutes: 15)),
      );
      expect(s.isLocked(t0), isTrue);
      expect(s.remaining(t0), const Duration(minutes: 15));
      // exactly at lockedUntil => no longer locked.
      expect(s.isLocked(t0.add(const Duration(minutes: 15))), isFalse);
      expect(s.remaining(t0.add(const Duration(minutes: 15))), Duration.zero);
    });

    test('json round-trips; a bad/unknown version yields empty', () {
      final s = PinAttemptState(failedAttempts: 3, lockedUntil: t0);
      final back = PinAttemptState.fromJson(s.toJson());
      expect(back.failedAttempts, 3);
      expect(back.lockedUntil, t0);
      // no PIN/secret leaks into the JSON.
      expect(s.toJson().values.join(' '), isNot(contains('pin')));
      expect(
        PinAttemptState.fromJson(<String, Object?>{'v': 99}).failedAttempts,
        0,
      );
      expect(
        PinAttemptState.fromJson(<String, Object?>{'n': 'x'}).failedAttempts,
        0,
      );
    });
  });

  group('PinAttemptLimiter', () {
    test('a wrong attempt increments the counter (persisted)', () async {
      final store = _CountingStore();
      final limiter = limiterOver(store);
      final s1 = await limiter.recordFailure(scope);
      expect(s1.failedAttempts, 1);
      expect(s1.isLocked(clock), isFalse);
      expect((await limiter.stateFor(scope)).failedAttempts, 1);
      expect(store.persists, 1);
    });

    test('locks out at the threshold and blocks further attempts', () async {
      final store = _CountingStore();
      final limiter = limiterOver(store);
      PinAttemptState s = PinAttemptState.empty;
      for (var i = 0; i < 5; i++) {
        s = await limiter.recordFailure(scope);
      }
      expect(s.failedAttempts, 5);
      expect(s.isLocked(clock), isTrue, reason: 'cap reached => locked');
      expect(s.remaining(clock), const Duration(minutes: 15));
      // Still locked while the cooldown is in progress (14 min later).
      expect(s.isLocked(clock.add(const Duration(minutes: 14))), isTrue);
    });

    test('the lockout lapses after the cooldown', () async {
      final store = _CountingStore();
      final limiter = limiterOver(store);
      for (var i = 0; i < 5; i++) {
        await limiter.recordFailure(scope);
      }
      final locked = await limiter.stateFor(scope);
      expect(locked.isLocked(clock.add(const Duration(minutes: 16))), isFalse);
    });

    test('a lapsed lockout starts fresh (not instantly re-locked)', () async {
      final store = _CountingStore();
      final limiter = limiterOver(store);
      for (var i = 0; i < 5; i++) {
        await limiter.recordFailure(scope);
      }
      // Advance past the cooldown, then a single new failure => count 1, unlocked.
      clock = t0.add(const Duration(minutes: 16));
      final s = await limiter.recordFailure(scope);
      expect(s.failedAttempts, 1);
      expect(s.isLocked(clock), isFalse);
    });

    test('success resets the counter', () async {
      final store = _CountingStore();
      final limiter = limiterOver(store);
      await limiter.recordFailure(scope);
      await limiter.recordFailure(scope);
      final s = await limiter.recordSuccess(scope);
      expect(s.failedAttempts, 0);
      expect(s.isLocked(clock), isFalse);
      expect((await limiter.stateFor(scope)).failedAttempts, 0);
      expect(store.clears, 1);
    });

    test(
      'lockout survives a refresh (new limiter over the same store)',
      () async {
        final store = _CountingStore();
        final l1 = limiterOver(store);
        for (var i = 0; i < 5; i++) {
          await l1.recordFailure(scope);
        }
        // Simulate a refresh: a brand-new limiter reads the persisted state.
        final l2 = limiterOver(store);
        final restored = await l2.stateFor(scope);
        expect(
          restored.isLocked(clock),
          isTrue,
          reason: 'lockout persisted across refresh',
        );
      },
    );

    test('scopes are isolated (one operator does not lock another)', () async {
      final store = _CountingStore();
      final limiter = limiterOver(store);
      for (var i = 0; i < 5; i++) {
        await limiter.recordFailure('device-1:employee-A');
      }
      final other = await limiter.stateFor('device-1:employee-B');
      expect(other.isLocked(clock), isFalse);
      expect(other.failedAttempts, 0);
    });
  });
}
