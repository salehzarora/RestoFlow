/// Pure-Dart secure key-store abstraction + fail-closed error types (RF-021).
///
/// [SecureKeyStore] is the platform-agnostic contract for storing device/session
/// secrets and the local data-at-rest key. The real platform-backed adapter
/// (iOS Keychain / Android Keystore via flutter_secure_storage) is deferred
/// until platform targets exist; see the RF-021 sections in the package READMEs.
/// Exceptions here NEVER contain raw secret material — only [SecretRef]s.
library;

import 'secret_value.dart';

/// Stores and retrieves secret material in platform secure storage.
///
/// All raw secrets cross this boundary only as [SecretValue]; callers identify
/// them by [SecretRef]. Implementations MUST NOT log raw secrets and MUST drive
/// fail-closed behavior via [isAvailable].
abstract interface class SecureKeyStore {
  /// Whether platform secure storage is currently usable. Callers treat `false`
  /// as a hard, fail-closed stop (never fall back to plaintext).
  Future<bool> isAvailable();

  /// Reads the secret for [ref], or `null` if none is stored.
  ///
  /// Throws [SecureStorageUnavailableException] if the store is unavailable, or
  /// [SecretCorruptedException] if a stored value cannot be decrypted/decoded.
  Future<SecretValue?> read(SecretRef ref);

  /// Writes [value] under [ref]. Throws [SecureStorageUnavailableException] if
  /// the store is unavailable.
  Future<void> write(SecretRef ref, SecretValue value);

  /// Deletes the secret for [ref] (idempotent).
  Future<void> delete(SecretRef ref);

  /// Crypto-erases ALL secrets (used on device revocation/recovery). Best-effort
  /// even if the store is otherwise unavailable.
  Future<void> wipeAll();
}

/// Base for fail-closed secure-storage errors. Messages never include raw
/// secret material — only opaque [SecretRef]s.
sealed class SecureStorageException implements Exception {
  const SecureStorageException(this.message);

  /// Human-readable, secret-free description.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Platform secure storage is unavailable; persistent secure operations must
/// fail closed rather than fall back to plaintext.
final class SecureStorageUnavailableException extends SecureStorageException {
  const SecureStorageUnavailableException([
    super.message = 'Platform secure storage is unavailable',
  ]);
}

/// No secret is stored for the given reference.
final class SecretNotFoundException extends SecureStorageException {
  SecretNotFoundException(SecretRef ref) : super('No secret stored for $ref');
}

/// A secret already exists for the given reference. Explicit first-time
/// provisioning must NOT overwrite it; rotation/recovery is a separate,
/// explicit flow.
final class SecretAlreadyExistsException extends SecureStorageException {
  SecretAlreadyExistsException(SecretRef ref)
    : super('A secret already exists for $ref');
}

/// A stored secret could not be decrypted/decoded (tampering or platform
/// keystore loss); treated as fail-closed.
final class SecretCorruptedException extends SecureStorageException {
  SecretCorruptedException(SecretRef ref)
    : super('Stored secret for $ref is corrupted or undecryptable');
}

/// Data-at-rest encryption is unavailable on this platform/configuration;
/// persistent local storage must fail closed (no unencrypted on-disk fallback).
final class DataAtRestProtectionUnavailableException
    extends SecureStorageException {
  const DataAtRestProtectionUnavailableException([
    super.message = 'Data-at-rest encryption is unavailable on this platform',
  ]);
}
