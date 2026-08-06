/// POS-OFFLINE-OPERATIONS-002 (C6) — SECURE, BOUNDED persistence of the staff
/// PIN session, so a till that loses connectivity (or restarts while offline)
/// can keep operating under the SAME server-minted session instead of dying at
/// a PIN screen no offline server can answer.
///
/// SECURITY REQUIREMENT (D-006 / D-011) — what is stored, exactly and only:
/// the server-issued PIN session id, the operator's employee-profile id +
/// display name, the pairing scope ids (organization / restaurant / branch /
/// device / device-session), the server expiry when one is ever exposed, and
/// the last moment the session was PROVEN live online. NEVER the PIN, never a
/// PIN hash, never an enrollment code, never an anon/service key, never a JWT.
/// The record lives in NATIVE SECURE STORAGE (`flutter_secure_storage`, the
/// same Keystore-backed plugin family as the device-session token); web has no
/// Keystore, so it FAILS CLOSED — no browser storage of any kind is used.
///
/// The offline trust window is HARD-BOUNDED: a restored session is valid
/// strictly until `min(serverExpiry ?? +inf, lastOnlineVerify + 8h)`, where
/// `lastOnlineVerify` only ever advances on a REAL authenticated round-trip —
/// never on restart, never on a connectivity flag.
library;

import 'dart:convert' show json;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'sync_cursor_store.dart' show PosSyncScope;

/// The maximum time a session may keep operating OFFLINE past its last proven
/// online verification (C6). Mirrors the server's own 8-hour
/// `pin_sessions.expires_at` window (RF-051), so the client never extends
/// trust beyond what the server would have granted anyway.
const Duration kPosOfflinePinSessionMaxAge = Duration(hours: 8);

/// The storage key for one scope's persisted PIN session. [PosSyncScope.key]
/// is already storage-safe; the sanitizer is re-applied so this key is
/// provably safe on its own terms (the operational-snapshot idiom).
String posPinSessionStorageKey(PosSyncScope scope) {
  final safe = scope.key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return 'restoflow.pos.pin_session.v1.$safe';
}

/// One persisted PIN session — see the library doc for the exact field
/// contract and the security boundary.
class PosStoredPinSession {
  const PosStoredPinSession({
    required this.sessionId,
    required this.employeeProfileId,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.deviceId,
    required this.deviceSessionId,
    required this.lastOnlineVerify,
    this.displayName,
    this.serverExpiry,
  });

  /// Bump ONLY on an incompatible shape change; an unrecognised version is
  /// refused on read (fail closed), never guessed at.
  static const int schemaVersion = 1;

  /// The server-issued PIN session id (`start_pin_session`'s bare uuid).
  final String sessionId;

  /// The signed-in operator (identity id + display text only).
  final String employeeProfileId;
  final String? displayName;

  /// The pairing scope the session was established under. A restore is only
  /// ever offered for EXACTLY this scope — [deviceSessionId] is the pairing
  /// identity itself, so a re-paired till (new device session) can never
  /// resurrect the old pairing's session.
  final String organizationId;
  final String restaurantId;
  final String branchId;
  final String deviceId;
  final String deviceSessionId;

  /// The server-side expiry, when the establish result ever exposes one
  /// (`start_pin_session` returns a bare uuid today, so this is null and the
  /// 8-hour offline window is the binding bound).
  final DateTime? serverExpiry;

  /// The last moment this session was PROVEN live by a real authenticated
  /// server round-trip. Advanced ONLY by such proof.
  final DateTime lastOnlineVerify;

  /// The hard end of offline trust:
  /// `min(serverExpiry ?? +inf, lastOnlineVerify + 8h)`.
  DateTime get offlineValidUntil {
    final byVerify = lastOnlineVerify.add(kPosOfflinePinSessionMaxAge);
    final byServer = serverExpiry;
    return (byServer != null && byServer.isBefore(byVerify))
        ? byServer
        : byVerify;
  }

  /// Whether an offline restore is still permitted at [now] (strictly before
  /// the window's end — the boundary instant itself is expired).
  bool isValidAt(DateTime now) => now.isBefore(offlineValidUntil);

  /// A copy with only the online-verification anchor advanced.
  PosStoredPinSession withOnlineVerify(DateTime verifiedAt) =>
      PosStoredPinSession(
        sessionId: sessionId,
        employeeProfileId: employeeProfileId,
        organizationId: organizationId,
        restaurantId: restaurantId,
        branchId: branchId,
        deviceId: deviceId,
        deviceSessionId: deviceSessionId,
        lastOnlineVerify: verifiedAt.toUtc(),
        displayName: displayName,
        serverExpiry: serverExpiry,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'v': schemaVersion,
    'session_id': sessionId,
    'employee_profile_id': employeeProfileId,
    if (displayName != null) 'display_name': displayName,
    'organization_id': organizationId,
    'restaurant_id': restaurantId,
    'branch_id': branchId,
    'device_id': deviceId,
    'device_session_id': deviceSessionId,
    if (serverExpiry != null)
      'server_expiry': serverExpiry!.toUtc().toIso8601String(),
    'last_online_verify': lastOnlineVerify.toUtc().toIso8601String(),
  };

  /// Strict parse — ANY malformation returns null (fail closed; the store then
  /// treats the record as absent). `restaurant_id` may legitimately be `''`
  /// (an unset restaurant scope keys as `''` too, the snapshot-store rule).
  static PosStoredPinSession? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    if (raw['v'] != schemaVersion) return null;
    String? id(Object? v) {
      if (v is! String) return null;
      final trimmed = v.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final sessionId = id(raw['session_id']);
    final employeeProfileId = id(raw['employee_profile_id']);
    final organizationId = id(raw['organization_id']);
    final branchId = id(raw['branch_id']);
    final deviceId = id(raw['device_id']);
    final deviceSessionId = id(raw['device_session_id']);
    final lastOnlineVerify = DateTime.tryParse(
      '${raw['last_online_verify'] ?? ''}',
    );
    if (sessionId == null ||
        employeeProfileId == null ||
        organizationId == null ||
        branchId == null ||
        deviceId == null ||
        deviceSessionId == null ||
        lastOnlineVerify == null) {
      return null;
    }
    final rawServerExpiry = raw['server_expiry'];
    final serverExpiry = rawServerExpiry == null
        ? null
        : DateTime.tryParse('$rawServerExpiry');
    if (rawServerExpiry != null && serverExpiry == null) return null;
    final displayName = raw['display_name'];
    return PosStoredPinSession(
      sessionId: sessionId,
      employeeProfileId: employeeProfileId,
      organizationId: organizationId,
      restaurantId: raw['restaurant_id'] is String
          ? raw['restaurant_id']! as String
          : '',
      branchId: branchId,
      deviceId: deviceId,
      deviceSessionId: deviceSessionId,
      lastOnlineVerify: lastOnlineVerify.toUtc(),
      displayName: displayName is String && displayName.trim().isNotEmpty
          ? displayName.trim()
          : null,
      serverExpiry: serverExpiry?.toUtc(),
    );
  }
}

/// Reads/writes/clears ONE scope's persisted PIN session in secure storage.
///
/// Every method contains its own platform failures: a broken Keystore read is
/// an ABSENT record (fail closed — no restore), a broken write leaves the
/// previous record (the session simply is not restorable later; the live
/// in-memory session is untouched), and web is a hard no-op in all directions.
class PosSecureSessionStore {
  PosSecureSessionStore({FlutterSecureStorage? storage, bool? isWeb})
    : _storage = storage ?? const FlutterSecureStorage(),
      _isWeb = isWeb ?? kIsWeb;

  final FlutterSecureStorage _storage;
  final bool _isWeb;

  /// Loads [scope]'s record, or null when absent/malformed/foreign-scope.
  ///
  /// The key already partitions scopes; the embedded ids are ADDITIONALLY
  /// verified so a copied value can never restore under another scope (the
  /// operational-snapshot rule). A mismatched or malformed record is deleted —
  /// unlike the operational snapshot there is nothing to diagnose in a session
  /// handle, and a session record that cannot be trusted must not linger in
  /// secure storage.
  Future<PosStoredPinSession?> read(PosSyncScope scope) async {
    if (_isWeb) return null;
    final String? raw;
    try {
      raw = await _storage.read(key: posPinSessionStorageKey(scope));
    } catch (_) {
      return null;
    }
    if (raw == null || raw.isEmpty) return null;
    Object? decoded;
    try {
      decoded = json.decode(raw);
    } catch (_) {
      decoded = null;
    }
    final record = PosStoredPinSession.tryFromJson(decoded);
    if (record == null ||
        record.organizationId != scope.organizationId ||
        record.restaurantId != scope.restaurantId ||
        record.branchId != scope.branchId ||
        record.deviceId != scope.deviceId) {
      try {
        await _storage.delete(key: posPinSessionStorageKey(scope));
      } catch (_) {
        // Best effort — an unreadable record already restores nothing.
      }
      return null;
    }
    return record;
  }

  /// Persists [record] under [scope]. Refuses (throws [ArgumentError]) when
  /// the record's embedded scope does not name [scope] — key and payload stay
  /// provably in agreement forever, the snapshot-store rule.
  Future<void> save(PosSyncScope scope, PosStoredPinSession record) async {
    if (_isWeb) return;
    if (record.organizationId != scope.organizationId ||
        record.restaurantId != scope.restaurantId ||
        record.branchId != scope.branchId ||
        record.deviceId != scope.deviceId) {
      throw ArgumentError(
        'stored PIN session scope does not match the storage scope',
      );
    }
    // Serialize FIRST (build-then-swap): an unencodable record fails before
    // the secure store is touched.
    final payload = json.encode(record.toJson());
    try {
      await _storage.write(key: posPinSessionStorageKey(scope), value: payload);
    } catch (_) {
      // Contained: persistence is an availability enhancement — the LIVE
      // session is authoritative and unaffected; the till simply cannot
      // restore offline later. Never a throw into the sign-in path.
    }
  }

  /// Removes [scope]'s record (explicit logout / unpair / server refusal).
  Future<void> clear(PosSyncScope scope) async {
    if (_isWeb) return;
    try {
      await _storage.delete(key: posPinSessionStorageKey(scope));
    } catch (_) {
      // Best effort; an expired-window record restores nothing anyway.
    }
  }
}

/// The secure session persistence seam (root service — no autoDispose).
/// Tests override it, or mock the `flutter_secure_storage` channel.
final posSecureSessionStoreProvider = Provider<PosSecureSessionStore>(
  (ref) => PosSecureSessionStore(),
);
