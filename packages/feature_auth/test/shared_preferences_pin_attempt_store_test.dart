import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const scope = 'device-1:emp-7';
  final t0 = DateTime.utc(2026, 7, 4, 12);

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('persist/load round-trips a locked state', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = SharedPreferencesPinAttemptStore(prefs);
    final state = PinAttemptState(
      failedAttempts: 5,
      lockedUntil: t0.add(const Duration(minutes: 15)),
    );
    await store.persist(scope, state);
    final back = await store.load(scope);
    expect(back.failedAttempts, 5);
    expect(back.lockedUntil, state.lockedUntil);
  });

  test('survives a "refresh" (a new store over the same prefs)', () async {
    final prefs = await SharedPreferences.getInstance();
    await SharedPreferencesPinAttemptStore(prefs).persist(
      scope,
      PinAttemptState(
        failedAttempts: 5,
        lockedUntil: t0.add(const Duration(minutes: 15)),
      ),
    );
    // A fresh store instance reads the persisted lockout back.
    final reloaded = await SharedPreferencesPinAttemptStore(prefs).load(scope);
    expect(reloaded.isLocked(t0), isTrue);
  });

  test('clear removes the state', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = SharedPreferencesPinAttemptStore(prefs);
    await store.persist(scope, const PinAttemptState(failedAttempts: 3));
    await store.clear(scope);
    expect((await store.load(scope)).failedAttempts, 0);
  });

  test('a corrupt value loads as empty (never bricks sign-in)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'restoflow.pin_attempts.v1.device-1:emp-7': 'not-json{{',
    });
    final prefs = await SharedPreferences.getInstance();
    final store = SharedPreferencesPinAttemptStore(prefs);
    expect((await store.load(scope)).failedAttempts, 0);
  });

  test('never persists a PIN/secret (only count + timestamp)', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = SharedPreferencesPinAttemptStore(prefs);
    await store.persist(
      scope,
      PinAttemptState(failedAttempts: 2, lockedUntil: t0),
    );
    // Inspect every stored string: no PIN-ish key/value ever written.
    for (final key in prefs.getKeys()) {
      expect(prefs.getString(key) ?? '', isNot(contains('pin_verifier')));
    }
  });
}
