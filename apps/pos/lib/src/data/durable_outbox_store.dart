import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'order_submission.dart';

/// Durable persistence for the POS order outbox (RF-114): queued/failed order
/// submissions survive a browser refresh, tab close/reopen, and app restart.
///
/// A SWAPPABLE seam. This build persists to `shared_preferences` (localStorage
/// on Flutter web — durable per browser origin; a file on native), which the POS
/// already depends on for other prefs. The canonical durable store per DECISION
/// D-010 is the `data_local` Drift `OutboxOperations` table, but there is no
/// Drift-on-web setup in this repo yet, so shared_preferences is the simple,
/// demo-safe, web-durable interim store; Drift remains the native/hardware-pilot
/// target (see the completion roadmap).
abstract class DurableOutboxStore {
  /// Loads the persisted entries for [scopeKey] (a stable per-device/scope key,
  /// RF-114). Never throws — a corrupt/foreign value yields an empty list so the
  /// POS starts clean instead of crashing. Orders queued under a DIFFERENT scope
  /// key are not returned, so an order queued on one device is never loaded
  /// under a different device/session.
  Future<List<OutboxEntry>> load(String scopeKey);

  /// Replaces the persisted set for [scopeKey] with [entries] (integer minor
  /// money only; no secrets, no service-role key — see [OutboxEntry]).
  Future<void> persist(String scopeKey, List<OutboxEntry> entries);
}

/// A `shared_preferences`-backed [DurableOutboxStore]: one schema-versioned JSON
/// envelope `{version, entries[]}` PER SCOPE key. Web-durable (localStorage). The
/// full storage key is `<prefix>.<scopeKey>`, so each paired device's queue is
/// isolated (RF-114 scope binding): a re-paired-as-new device (new deviceId)
/// gets a fresh, empty queue and cannot pick up another device's pending orders.
class SharedPrefsOutboxStore implements DurableOutboxStore {
  SharedPrefsOutboxStore(this._prefs, {String keyPrefix = _defaultPrefix})
    : _prefix = keyPrefix;

  final SharedPreferences _prefs;
  final String _prefix;

  static const String _defaultPrefix = 'restoflow.pos.outbox.v1';

  /// Bump ONLY on an incompatible envelope/entry shape change; an unrecognised
  /// version is ignored on load (start clean) rather than mis-parsed.
  static const int schemaVersion = 1;

  String _keyFor(String scopeKey) {
    // Keep only key-safe chars so a scope value can never break the key space.
    final safe = scopeKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '$_prefix.$safe';
  }

  @override
  Future<List<OutboxEntry>> load(String scopeKey) async {
    final raw = _prefs.getString(_keyFor(scopeKey));
    if (raw == null || raw.isEmpty) return <OutboxEntry>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <OutboxEntry>[];
      final version = (decoded['version'] as num?)?.toInt();
      if (version != schemaVersion) return <OutboxEntry>[];
      final list = decoded['entries'];
      if (list is! List) return <OutboxEntry>[];
      final entries = <OutboxEntry>[];
      for (final e in list) {
        if (e is! Map) continue;
        try {
          entries.add(OutboxEntry.fromJson(e.cast<String, Object?>()));
        } on FormatException {
          // Drop a single corrupt/foreign entry; never crash the POS on start.
        }
      }
      return entries;
    } catch (_) {
      // A corrupt localStorage value: start clean rather than fail to boot.
      return <OutboxEntry>[];
    }
  }

  @override
  Future<void> persist(String scopeKey, List<OutboxEntry> entries) async {
    final envelope = <String, Object?>{
      'version': schemaVersion,
      'entries': [for (final e in entries) e.toJson()],
    };
    await _prefs.setString(_keyFor(scopeKey), jsonEncode(envelope));
  }
}
