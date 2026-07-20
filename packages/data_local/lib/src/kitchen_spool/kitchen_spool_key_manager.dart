/// KITCHEN-MODE-001C2A — the kitchen-spool key manager over the generic
/// [SecureKeyStore] contract.
///
/// One random 256-bit AES key per app installation / device data set, held
/// exclusively by platform secure storage (Android Keystore-backed on the
/// POS). The key NEVER touches SharedPreferences, Drift, logs, or source
/// code. All operations are explicit — nothing here runs automatically at
/// startup, database open never provisions or reads a key, and there is no
/// silent replacement path (regenerating while unresolved encrypted rows
/// exist would strand them; that orchestration is a later, explicit,
/// operator-facing phase).
library;

import 'dart:convert' show base64Url;
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:restoflow_core/restoflow_core.dart';

import 'kitchen_spool_cipher.dart';

/// Explicit, fail-closed key lifecycle for the kitchen spool.
final class KitchenSpoolKeyManager {
  KitchenSpoolKeyManager(this._store, {Random? random})
    : _random = random ?? Random.secure();

  /// Fixed, versioned reference for the v1 kitchen-spool AES key. A future
  /// algorithm/format change mints a NEW versioned ref; it never silently
  /// rewrites this one.
  static final SecretRef keyRef = SecretRef('ref:kitchen-spool-aes-key-v1');

  static const int _keyLengthBytes = 32;

  final SecureKeyStore _store;
  final Random _random;

  /// CLEANUP 6: the process-local provisioning serialization chain — each
  /// provision waits for the previous one; failures never poison the chain.
  Future<void> _provisionQueue = Future<void>.value();

  /// Whether platform secure storage is usable (fail-closed signal).
  Future<bool> isAvailable() => _store.isAvailable();

  /// Reads the existing key, or `null` when none has been provisioned.
  ///
  /// Throws [SecureStorageUnavailableException] when the platform store is
  /// unusable and [SecretCorruptedException] when a stored value exists but
  /// is not a valid base64url-encoded 32-byte key.
  Future<SecretValue?> readKey() async {
    final stored = await _store.read(keyRef);
    if (stored == null) return null;
    _requireValidKey(stored);
    return stored;
  }

  /// Explicitly provisions a NEW key. Refuses to overwrite: if any key
  /// already exists (even a corrupted one) this throws
  /// [SecretAlreadyExistsException] — replacing a key is a destructive
  /// operation that must go through [deleteKeyDangerously] deliberately.
  ///
  /// CLEANUP 6 — PROCESS-LOCAL PROVISIONING SINGLE-FLIGHT: concurrent
  /// `provisionKey()` calls on this manager are SERIALIZED (each waits for
  /// the previous to finish before its own read-then-write), so a
  /// read-then-write race can never store two different keys and strand
  /// ciphertext under a replaced one — exactly one concurrent call
  /// provisions; the rest observe the stored key and get the existing
  /// already-exists outcome. This is honestly a PROCESS-LOCAL guarantee (per
  /// manager/store instance); flutter_secure_storage offers no cross-process
  /// atomic compare-and-set and none is claimed. Production provisioning
  /// must flow through this manager (the raw adapter `write()` remains
  /// refuse-overwrite as defence in depth).
  Future<void> provisionKey() {
    final task = _provisionQueue.then((_) => _provisionOnce());
    // The queue itself must never carry a failure into the NEXT caller.
    _provisionQueue = task.then((_) {}, onError: (Object _) {});
    return task;
  }

  Future<void> _provisionOnce() async {
    final existing = await _readRawTolerantOfCorruption();
    if (existing != null) {
      throw SecretAlreadyExistsException(keyRef);
    }
    final bytes = Uint8List(_keyLengthBytes);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    final encoded = base64Url.encode(bytes).replaceAll('=', '');
    await _store.write(keyRef, SecretValue(encoded));
  }

  /// EXPLICIT destructive path (crypto-erase of the spool): deletes the key,
  /// making every existing encrypted blob permanently undecryptable. Callers
  /// own the orchestration (checking for unresolved rows first); nothing in
  /// this phase calls it from production code.
  Future<void> deleteKeyDangerously() => _store.delete(keyRef);

  /// Reports the store/key state without throwing, for capability surfaces:
  /// `available` (usable + key readable or absent), `missing`, `corrupted`,
  /// or `unavailable`.
  Future<KitchenSpoolKeyState> inspectState() async {
    if (!await _store.isAvailable()) {
      return KitchenSpoolKeyState.unavailable;
    }
    try {
      final stored = await _store.read(keyRef);
      if (stored == null) return KitchenSpoolKeyState.missing;
      _requireValidKey(stored);
      return KitchenSpoolKeyState.present;
    } on SecretCorruptedException {
      return KitchenSpoolKeyState.corrupted;
    } on SecureStorageUnavailableException {
      return KitchenSpoolKeyState.unavailable;
    }
  }

  /// Reads whatever is stored, mapping corruption to "exists" so that
  /// [provisionKey] can refuse to overwrite even a corrupted value.
  Future<SecretValue?> _readRawTolerantOfCorruption() async {
    try {
      return await _store.read(keyRef);
    } on SecretCorruptedException {
      // A corrupted value still occupies the slot: never overwrite silently.
      return SecretValue('corrupted-placeholder');
    }
  }

  static void _requireValidKey(SecretValue value) {
    final Uint8List bytes;
    try {
      bytes = decodeKitchenSpoolKey(value);
    } on FormatException {
      throw SecretCorruptedException(keyRef);
    }
    if (bytes.length != _keyLengthBytes) {
      throw SecretCorruptedException(keyRef);
    }
  }
}

/// Non-throwing key/store state for capability reporting.
enum KitchenSpoolKeyState { present, missing, corrupted, unavailable }
