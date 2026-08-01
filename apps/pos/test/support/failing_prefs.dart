import 'package:shared_preferences/shared_preferences.dart';

/// A [SharedPreferences] double whose writes can be made to fail the way the real
/// one does on a full disk, a quota-exhausted browser, or a browser refusing
/// localStorage: `setString` returns **FALSE without throwing**.
///
/// That is the whole point. Code which ignores the returned bool cannot tell
/// that failure apart from success, so it goes on to describe the operation as
/// durably stored — the exact class of defect MONEY-DURABLE-STORES-003B closes.
///
/// DELEGATING by design: everything except the refusal goes to a real
/// (mock-initialised) [SharedPreferences]. A test can therefore write genuine
/// data, flip [failWrites], attempt a write, and then assert on what is STILL on
/// disk — proving that a refused write left the previous durable set intact
/// rather than half-rewritten.
///
/// Promoted here from `parked_carts_store_test.dart` (where it was file-local)
/// so every durable-store suite injects the same failure the same way.
class FailingPrefs implements SharedPreferences {
  FailingPrefs(this._inner);

  final SharedPreferences _inner;

  /// While true, every [setString] refuses: it returns false and writes nothing.
  bool failWrites = false;

  /// Every [setString] call, including refused ones.
  int writeAttempts = 0;

  /// The keys [setString] was called with, in call order (refusals included), so
  /// a test can prove WHICH key a store touched — e.g. that a quarantine sidecar
  /// was written before the primary key was overwritten.
  final List<String> writtenKeys = <String>[];

  /// Forgets the recorded attempts (not the stored data).
  void resetCounters() {
    writeAttempts = 0;
    writtenKeys.clear();
  }

  @override
  Future<bool> setString(String key, String value) async {
    writeAttempts++;
    writtenKeys.add(key);
    if (failWrites) return false;
    return _inner.setString(key, value);
  }

  @override
  String? getString(String key) => _inner.getString(key);

  @override
  Future<bool> remove(String key) => _inner.remove(key);

  @override
  bool containsKey(String key) => _inner.containsKey(key);

  @override
  Set<String> getKeys() => _inner.getKeys();

  @override
  noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'FailingPrefs deliberately supports only the string/key operations the POS '
    'durable stores use — an unexpected call means the store under test changed '
    'shape: ${invocation.memberName}',
  );
}
