import 'package:drift/drift.dart';
import 'package:restoflow_core/restoflow_core.dart';

import 'local_database.dart';

/// Strategy that turns an encryption key into an ENCRYPTED on-disk Drift
/// executor (RF-021).
///
/// The real SQLCipher-backed strategy is DEFERRED until platform targets exist
/// (no native platform folders in the repo today). RF-021 ships the abstraction
/// plus a fail-closed default so a persistent database is never opened
/// unencrypted. Implementations MUST apply [key] at the crypto boundary (e.g. a
/// SQLCipher `PRAGMA key`) and MUST NOT open an unencrypted database.
abstract interface class DatabaseEncryptionStrategy {
  /// Whether real data-at-rest encryption is available on this platform.
  Future<bool> isAvailable();

  /// Opens an encrypted executor at [path] using [key]. Called only after
  /// [isAvailable] returns `true`.
  QueryExecutor openEncrypted(String path, SecretValue key);
}

/// Default persistent strategy when no real encryption backend is wired:
/// always unavailable, so [ProtectedLocalDatabaseFactory] FAILS CLOSED rather
/// than opening plaintext. Replaced by a real SQLCipher strategy once platform
/// targets exist (RF-021 platform-wiring deferral).
final class UnavailableEncryptionStrategy
    implements DatabaseEncryptionStrategy {
  const UnavailableEncryptionStrategy();

  @override
  Future<bool> isAvailable() async => false;

  @override
  QueryExecutor openEncrypted(String path, SecretValue key) =>
      throw const DataAtRestProtectionUnavailableException();
}

/// Opens the local Drift database under a FAIL-CLOSED data-at-rest policy
/// (RF-021), reusing the existing `LocalDatabase(QueryExecutor)` seam — no Drift
/// schema change and no regeneration of the committed generated code.
///
/// **Normal open never creates key material.** [openPersistent] requires an
/// already-provisioned key and fails closed on any
/// missing/wiped/revoked/corrupted/unavailable condition — it has no key
/// generator at all, so it cannot silently (re)create a key or open
/// unencrypted/plaintext storage. First-time key creation is the separate,
/// explicit [provisionPersistentKey] flow.
final class ProtectedLocalDatabaseFactory {
  ProtectedLocalDatabaseFactory({
    required this.keyStore,
    this.encryption = const UnavailableEncryptionStrategy(),
  });

  /// Platform secure storage for the data-at-rest key (and device secrets).
  final SecureKeyStore keyStore;

  /// Strategy that produces an encrypted on-disk executor.
  final DatabaseEncryptionStrategy encryption;

  /// The opaque secure-storage reference for the local data-at-rest key.
  static final SecretRef dbKeyRef = SecretRef('ref:local-db-key');

  /// Opens the PERSISTENT, encrypted local database — ALWAYS FAIL-CLOSED.
  ///
  /// Throws (and opens nothing) when:
  /// - secure storage is unavailable ([SecureStorageUnavailableException]);
  /// - encryption is unavailable ([DataAtRestProtectionUnavailableException]);
  /// - the stored key is corrupted ([SecretCorruptedException]);
  /// - **no key is stored** — missing, wiped, or revoked
  ///   ([SecretNotFoundException]).
  ///
  /// It NEVER creates a key and NEVER opens an unencrypted on-disk database.
  /// Provision a key first with [provisionPersistentKey].
  Future<LocalDatabase> openPersistent({required String path}) async {
    await _requireProtections();

    // May throw SecretCorruptedException (fail-closed) for a tampered key.
    final key = await keyStore.read(dbKeyRef);
    if (key == null) {
      // Missing / wiped / revoked key -> FAIL CLOSED. Never (re)create here.
      throw SecretNotFoundException(dbKeyRef);
    }

    return LocalDatabase(encryption.openEncrypted(path, key));
  }

  /// EXPLICIT first-time provisioning of the data-at-rest key (RF-021).
  ///
  /// This is NOT part of a normal open and is never called by [openPersistent].
  /// It requires secure storage and encryption to be available, generates a key
  /// via [generateKey], and stores it ONLY through [SecureKeyStore]. It does NOT
  /// open the database and NEVER returns or logs raw key material.
  ///
  /// It REFUSES to overwrite an existing key
  /// ([SecretAlreadyExistsException]) — rotation/recovery is a separate,
  /// explicit flow (deferred). A corrupted existing key propagates
  /// [SecretCorruptedException] (recovery, not silent overwrite).
  Future<void> provisionPersistentKey({
    required SecretValue Function() generateKey,
  }) async {
    await _requireProtections();

    final existing = await keyStore.read(dbKeyRef); // throws if corrupted
    if (existing != null) {
      throw SecretAlreadyExistsException(dbKeyRef);
    }
    await keyStore.write(dbKeyRef, generateKey());
  }

  /// Fail-closed precondition shared by open and provisioning: both secure
  /// storage and a real encryption strategy must be available.
  Future<void> _requireProtections() async {
    if (!await keyStore.isAvailable()) {
      throw const SecureStorageUnavailableException();
    }
    if (!await encryption.isAvailable()) {
      throw const DataAtRestProtectionUnavailableException();
    }
  }
}
