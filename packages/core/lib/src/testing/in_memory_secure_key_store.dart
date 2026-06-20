/// TEST-SUPPORT ONLY (RF-021). Import via `package:restoflow_core/testing.dart`.
library;

import '../secret_value.dart';
import '../secure_key_store.dart';

/// An in-memory [SecureKeyStore] for TESTS ONLY.
///
/// NOT for production: it holds secrets in plaintext in process memory. It lets
/// tests simulate the fail-closed triggers: an unavailable store, a missing key,
/// a corrupted key, and a wiped/revoked store.
final class InMemorySecureKeyStore implements SecureKeyStore {
  InMemorySecureKeyStore({bool available = true}) : _available = available;

  bool _available;
  final Map<String, SecretValue> _store = <String, SecretValue>{};
  final Set<String> _corrupted = <String>{};

  /// Simulate the platform secure store becoming (un)available — the
  /// fail-closed trigger.
  void setAvailable({required bool available}) => _available = available;

  /// Simulate a stored value for [ref] being corrupted so [read] throws.
  void markCorrupted(SecretRef ref) => _corrupted.add(ref.value);

  @override
  Future<bool> isAvailable() async => _available;

  @override
  Future<SecretValue?> read(SecretRef ref) async {
    if (!_available) throw const SecureStorageUnavailableException();
    if (_corrupted.contains(ref.value)) throw SecretCorruptedException(ref);
    return _store[ref.value];
  }

  @override
  Future<void> write(SecretRef ref, SecretValue value) async {
    if (!_available) throw const SecureStorageUnavailableException();
    _store[ref.value] = value;
  }

  @override
  Future<void> delete(SecretRef ref) async {
    if (!_available) throw const SecureStorageUnavailableException();
    _store.remove(ref.value);
    _corrupted.remove(ref.value);
  }

  @override
  Future<void> wipeAll() async {
    // Best-effort crypto-erase: succeeds even when otherwise unavailable.
    _store.clear();
    _corrupted.clear();
  }
}
