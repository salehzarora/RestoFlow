import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:restoflow_core/restoflow_core.dart';

import 'pos_kitchen_spool_platform.dart';

/// KITCHEN-MODE-001C2A — the POS's Android-Keystore-backed [SecureKeyStore]
/// for the kitchen-spool AES key.
///
/// Native Android: values live in `flutter_secure_storage` (the same plugin
/// family, default options and Keystore-backed at-rest protection as the
/// authenticated device-session store in `feature_auth`). Web: FAILS CLOSED —
/// `isAvailable()` is false and every read/write throws
/// [SecureStorageUnavailableException]; no shared-preferences or browser
/// storage fallback of any kind exists, and web printer-only support is not
/// claimed.
///
/// Redaction contract: no secret value ever appears in exception text or
/// `toString`; only [SecretRef]s (non-secret) are named. Keys are namespaced
/// under a kitchen-spool prefix so [wipeAll] can crypto-erase the kitchen
/// secrets WITHOUT touching the device-session credentials (no auth->kitchen
/// coupling in either direction).
final class FlutterSecureKitchenSpoolKeyStore implements SecureKeyStore {
  FlutterSecureKitchenSpoolKeyStore({
    FlutterSecureStorage? storage,
    PosKitchenSpoolPlatform platform = const PosKitchenSpoolPlatform(),
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _platform = platform;

  /// Storage-key namespace; every kitchen-spool secret lives under it.
  static const String keyPrefix = 'restoflow.pos.kitchen_spool.';

  final FlutterSecureStorage _storage;
  final PosKitchenSpoolPlatform _platform;

  String _storageKey(SecretRef ref) => '$keyPrefix${ref.value}';

  @override
  Future<bool> isAvailable() async => _platform.supportsSecureSpool;

  @override
  Future<SecretValue?> read(SecretRef ref) async {
    await _requireAvailable();
    final String? raw;
    try {
      raw = await _storage.read(key: _storageKey(ref));
    } on Exception {
      // Platform-channel/Keystore failure: the store is unusable, which is
      // DISTINCT from a corrupted value. Never include plugin details that
      // could carry values.
      throw const SecureStorageUnavailableException();
    }
    if (raw == null) return null;
    if (raw.trim().isEmpty) {
      // A present-but-empty value can never be a real secret we wrote:
      // corrupted, not missing.
      throw SecretCorruptedException(ref);
    }
    return SecretValue(raw);
  }

  @override
  Future<void> write(SecretRef ref, SecretValue value) async {
    await _requireAvailable();
    // Refuse overwrite: replacing a kitchen-spool key silently would strand
    // every existing encrypted row. Deletion is a separate, explicit,
    // destructive path.
    final String? existing;
    try {
      existing = await _storage.read(key: _storageKey(ref));
    } on Exception {
      throw const SecureStorageUnavailableException();
    }
    if (existing != null) {
      throw SecretAlreadyExistsException(ref);
    }
    try {
      await _storage.write(
        key: _storageKey(ref),
        value: value.revealForStorageBoundary(),
      );
    } on Exception {
      throw const SecureStorageUnavailableException();
    }
  }

  @override
  Future<void> delete(SecretRef ref) async {
    await _requireAvailable();
    try {
      await _storage.delete(key: _storageKey(ref));
    } on Exception {
      throw const SecureStorageUnavailableException();
    }
  }

  @override
  Future<void> wipeAll() async {
    // Best-effort crypto-erase of KITCHEN-SPOOL secrets only (never the
    // device-session credentials); swallows platform failures by contract.
    try {
      final all = await _storage.readAll();
      for (final key in all.keys) {
        if (key.startsWith(keyPrefix)) {
          await _storage.delete(key: key);
        }
      }
    } on Exception {
      // Best-effort by contract.
    }
  }

  Future<void> _requireAvailable() async {
    if (!await isAvailable()) {
      throw const SecureStorageUnavailableException();
    }
  }
}
