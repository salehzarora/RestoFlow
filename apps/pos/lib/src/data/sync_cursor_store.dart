/// POS-OPERATIONS-SYNC-001 — durable, SCOPE-PARTITIONED pull cursor.
///
/// The cursor says "I have seen everything up to here". That claim is only true
/// WITHIN one branch on one device: replaying branch A's cursor against branch B
/// would skip B's entire history and silently present an empty, confident,
/// completely wrong board. So the cursor is keyed by the full operational scope and
/// is NEVER shared across one.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'order_snapshot.dart';

/// The operational scope a cached snapshot set and its cursor belong to.
///
/// The POS learns org/restaurant/branch from its paired DeviceContext and the
/// device id from its session. All four are part of the key: a re-pair as a
/// different device, or a device moved to another branch, must start clean rather
/// than inherit someone else's view.
class PosSyncScope {
  const PosSyncScope({
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.deviceId,
  });

  final String organizationId;
  final String restaurantId;
  final String branchId;
  final String deviceId;

  /// A stable, filesystem/preferences-safe key. Every component is present, so two
  /// different scopes can never collide onto one key.
  String get key {
    final raw = '$organizationId.$restaurantId.$branchId.$deviceId';
    return raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  @override
  bool operator ==(Object other) =>
      other is PosSyncScope &&
      other.organizationId == organizationId &&
      other.restaurantId == restaurantId &&
      other.branchId == branchId &&
      other.deviceId == deviceId;

  @override
  int get hashCode =>
      Object.hash(organizationId, restaurantId, branchId, deviceId);
}

/// Reads/writes the incremental pull cursor for one scope.
abstract class PosSyncCursorStore {
  Future<PosSyncCursor?> load(PosSyncScope scope);

  /// Persists [cursor] for [scope].
  ///
  /// CALL THIS ONLY AFTER the page it came from has been fully validated AND the
  /// reconciled snapshot set has been persisted. The cursor only ever moves
  /// FORWARD, so advancing it past data we failed to apply loses that data
  /// permanently — the server will never offer it again.
  ///
  /// THROWS [PosPersistenceException] when the write does not stick. It must not
  /// return quietly: a caller that believes the cursor advanced when it did not will
  /// happily skip the very rows it failed to save.
  Future<void> save(PosSyncScope scope, PosSyncCursor cursor);

  /// Forgets the cursor for [scope] (used when a scope's cache is invalidated).
  /// Never touches another scope, and never touches queued operations.
  Future<void> clear(PosSyncScope scope);
}

/// In-memory cursor store (demo mode / tests).
class InMemorySyncCursorStore implements PosSyncCursorStore {
  final Map<String, PosSyncCursor> _byScope = <String, PosSyncCursor>{};

  @override
  Future<PosSyncCursor?> load(PosSyncScope scope) async => _byScope[scope.key];

  @override
  Future<void> save(PosSyncScope scope, PosSyncCursor cursor) async {
    _byScope[scope.key] = cursor;
  }

  @override
  Future<void> clear(PosSyncScope scope) async {
    _byScope.remove(scope.key);
  }
}

/// `shared_preferences`-backed cursor store — one key per scope.
class SharedPrefsSyncCursorStore implements PosSyncCursorStore {
  SharedPrefsSyncCursorStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _prefix = 'restoflow.pos.sync_cursor.v1';

  String _keyFor(PosSyncScope scope) => '$_prefix.${scope.key}';

  @override
  Future<PosSyncCursor?> load(PosSyncScope scope) async {
    final raw = _prefs.getString(_keyFor(scope));
    if (raw == null || raw.isEmpty) return null;
    try {
      // A malformed stored cursor reads as NULL, which restarts from the window
      // start — safe (it re-delivers, and reconciliation is idempotent) and
      // strictly better than resuming from a position we cannot trust.
      return PosSyncCursor.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(PosSyncScope scope, PosSyncCursor cursor) async {
    // setString returns Future<bool> and can report FALSE WITHOUT THROWING — a full
    // disk, a browser refusing localStorage. Ignoring that return value is how a
    // cursor "advances" in memory, is lost on restart, and quietly re-delivers or
    // skips a page. `false` is a failure, and it is reported as one.
    final ok = await _prefs.setString(
      _keyFor(scope),
      jsonEncode(cursor.toJson()),
    );
    if (!ok) {
      throw const PosPersistenceException('sync cursor could not be persisted');
    }
  }

  @override
  Future<void> clear(PosSyncScope scope) =>
      _prefs.remove(_keyFor(scope)).then((_) {});
}

/// A durable write did not stick.
///
/// `SharedPreferences.setString` returns `Future<bool>`: it can report **false**
/// without throwing. Silently treating that as success is how the POS ends up with a
/// cursor that has moved past rows it never actually stored — rows the server will
/// never offer again, because as far as it is concerned we already have them.
class PosPersistenceException implements Exception {
  const PosPersistenceException(this.message);

  final String message;

  @override
  String toString() => 'PosPersistenceException: $message';
}
