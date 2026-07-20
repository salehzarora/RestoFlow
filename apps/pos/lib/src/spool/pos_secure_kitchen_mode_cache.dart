import 'dart:convert' show json;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:restoflow_core/restoflow_core.dart';

import 'pos_kitchen_spool_platform.dart';

/// KITCHEN-MODE-001C2B — the INTEGRITY-PROTECTED kitchen-mode cache.
///
/// The mode is not secret, but its integrity controls operational routing —
/// so the record lives in NATIVE SECURE STORAGE (the same Keystore-backed
/// plugin family as the kitchen-spool key), never ordinary SharedPreferences
/// and never any browser storage. Web fails closed. A malformed/corrupted
/// record, a scope-tuple mismatch, or a session-fingerprint change all
/// invalidate the cache (fail closed to UNKNOWN — never a silent kds).
///
/// Freshness: fresh <= 10 minutes; stale <= 2 hours (usable only to REFUSE
/// work / trigger revalidation); hard-expired > 2 hours = unknown.
final class KitchenModeCacheRecord {
  const KitchenModeCacheRecord({
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.deviceId,
    required this.sessionFingerprint,
    required this.mode,
    this.modeRevision,
    required this.verifiedAt,
  });

  static const int schemaVersion = 1;

  final String organizationId;
  final String restaurantId;
  final String branchId;
  final String deviceId;

  /// A DETERMINISTIC digest of the device-session token (never the token).
  final String sessionFingerprint;

  /// `kds` or `printer_only`.
  final String mode;

  /// LOCKED D1: null until 001C3 exposes a trusted revision — and while
  /// null, printer-only importing stays disabled.
  final int? modeRevision;

  final DateTime verifiedAt;
}

enum KitchenModeCacheFreshness { fresh, stale, expired }

KitchenModeCacheFreshness kitchenModeCacheFreshness(
  KitchenModeCacheRecord record,
  DateTime now,
) {
  final age = now.difference(record.verifiedAt);
  if (age <= const Duration(minutes: 10)) {
    return KitchenModeCacheFreshness.fresh;
  }
  if (age <= const Duration(hours: 2)) return KitchenModeCacheFreshness.stale;
  return KitchenModeCacheFreshness.expired;
}

final class PosSecureKitchenModeCache {
  PosSecureKitchenModeCache({
    FlutterSecureStorage? storage,
    PosKitchenSpoolPlatform platform = const PosKitchenSpoolPlatform(),
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _platform = platform;

  /// Lives under the kitchen-spool namespace so the kitchen-scoped wipe
  /// covers it.
  static const String storageKey = 'restoflow.pos.kitchen_spool.mode_cache.v1';

  final FlutterSecureStorage _storage;
  final PosKitchenSpoolPlatform _platform;

  Future<void> write(KitchenModeCacheRecord record) async {
    if (!_platform.supportsSecureSpool) {
      throw const SecureStorageUnavailableException();
    }
    await _storage.write(
      key: storageKey,
      value: json.encode({
        'v': KitchenModeCacheRecord.schemaVersion,
        'organization_id': record.organizationId,
        'restaurant_id': record.restaurantId,
        'branch_id': record.branchId,
        'device_id': record.deviceId,
        'session_fingerprint': record.sessionFingerprint,
        'mode': record.mode,
        'mode_revision': record.modeRevision,
        'verified_at': record.verifiedAt.toUtc().toIso8601String(),
      }),
    );
  }

  /// Reads the record ONLY when it matches the caller's current scope tuple
  /// and session fingerprint; every mismatch or malformation invalidates
  /// (deletes) the record and returns null (= UNKNOWN, fail closed).
  Future<KitchenModeCacheRecord?> read({
    required String organizationId,
    required String restaurantId,
    required String branchId,
    required String deviceId,
    required String sessionFingerprint,
  }) async {
    if (!_platform.supportsSecureSpool) return null;
    final String? raw;
    try {
      raw = await _storage.read(key: storageKey);
    } on Exception {
      return null;
    }
    if (raw == null) return null;
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) throw const FormatException();
      final map = decoded.map((k, v) => MapEntry(k.toString(), v));
      if (map['v'] != KitchenModeCacheRecord.schemaVersion) {
        throw const FormatException();
      }
      final record = KitchenModeCacheRecord(
        organizationId: map['organization_id'] as String,
        restaurantId: map['restaurant_id'] as String,
        branchId: map['branch_id'] as String,
        deviceId: map['device_id'] as String,
        sessionFingerprint: map['session_fingerprint'] as String,
        mode: map['mode'] as String,
        modeRevision: map['mode_revision'] as int?,
        verifiedAt: DateTime.parse(map['verified_at'] as String),
      );
      if (record.mode != 'kds' && record.mode != 'printer_only') {
        throw const FormatException();
      }
      final tupleMatches =
          record.organizationId == organizationId &&
          record.restaurantId == restaurantId &&
          record.branchId == branchId &&
          record.deviceId == deviceId &&
          record.sessionFingerprint == sessionFingerprint;
      if (!tupleMatches) {
        await _storage.delete(key: storageKey);
        return null;
      }
      return record;
    } on Object {
      // Malformed/corrupted: invalidate and report UNKNOWN.
      try {
        await _storage.delete(key: storageKey);
      } on Exception {
        // Best effort.
      }
      return null;
    }
  }

  Future<void> invalidate() async {
    if (!_platform.supportsSecureSpool) return;
    try {
      await _storage.delete(key: storageKey);
    } on Exception {
      // Best effort.
    }
  }
}
