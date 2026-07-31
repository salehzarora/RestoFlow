import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_storage_health.dart';
import 'order_submission.dart';
import 'sync_cursor_store.dart' show PosPersistenceException;

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
  ///
  /// MONEY-DURABLE-STORES-003B: THROWS [PosPersistenceException] when the write
  /// does not stick. A queued order is the ONLY local record that an order was
  /// taken, so "it did not throw" is not good enough — the caller must be able
  /// to tell a stored order from a lost one and refuse to dispatch the latter.
  Future<void> persist(String scopeKey, List<OutboxEntry> entries);
}

/// A `shared_preferences`-backed [DurableOutboxStore]: one schema-versioned JSON
/// envelope `{version, entries[]}` PER SCOPE key. Web-durable (localStorage). The
/// full storage key is `<prefix>.<scopeKey>`, so each paired device's queue is
/// isolated (RF-114 scope binding): a re-paired-as-new device (new deviceId)
/// gets a fresh, empty queue and cannot pick up another device's pending orders.
class SharedPrefsOutboxStore
    implements DurableOutboxStore, PosDurableStoreHealth {
  SharedPrefsOutboxStore(this._prefs, {String keyPrefix = _defaultPrefix})
    : _prefix = keyPrefix;

  final SharedPreferences _prefs;
  final String _prefix;

  static const String _defaultPrefix = 'restoflow.pos.outbox.v1';

  /// Bump ONLY on an incompatible envelope/entry shape change; an unrecognised
  /// version is ignored on load (start clean) rather than mis-parsed.
  static const int schemaVersion = 1;

  bool _degraded = false;

  @override
  bool get isDegraded => _degraded;

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
        } catch (_) {
          // Drop a single corrupt/foreign entry; never crash the POS on start.
          //
          // MONEY-DURABLE-STORES-003B: this guard used to be `on FormatException`
          // only. `OutboxEntry.fromJson` reaches its fields through bare casts
          // (`json['id'] as String?`, `(json['attempt_count'] as num?)`), so a
          // wrongly-TYPED field raises TypeError, which escaped to the envelope
          // catch below and emptied the WHOLE queue — after which the next
          // `persist` wrote that emptiness back and every healthy queued order
          // was gone for good. One bad entry may cost one entry, never the till.
          // The entry is not lost either: `_quarantined` re-emits it verbatim.
        }
      }
      return entries;
    } catch (_) {
      // A corrupt localStorage value: start clean rather than fail to boot. The
      // bytes are NOT discarded — `persist` preserves them before overwriting.
      return <OutboxEntry>[];
    }
  }

  /// MONEY-DURABLE-STORES-003B: the raw entries this build cannot decode, read
  /// back from the CURRENT envelope.
  ///
  /// Deliberately re-read here rather than remembered from [load]: the caller
  /// replaces the whole queue on every write, so a guarantee that only holds
  /// when the caller happened to load first is not a guarantee. Mirrors
  /// `recent_orders_store._quarantined`.
  ///
  /// [keep] returns false for a raw entry the caller is rewriting, so a repaired
  /// entry replaces its broken shadow instead of doubling it.
  List<Object?> _quarantined(String scopeKey, bool Function(Object?) keep) {
    final raw = _prefs.getString(_keyFor(scopeKey));
    if (raw == null || raw.isEmpty) return const <Object?>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <Object?>[];
      if ((decoded['version'] as num?)?.toInt() != schemaVersion) {
        // A version this build does not understand is preserved WHOLE by
        // [_preserveUnreadableEnvelope]; re-shaping its entries into our
        // envelope would be a guess about a schema we do not know.
        return const <Object?>[];
      }
      final list = decoded['entries'];
      if (list is! List) return const <Object?>[];
      final out = <Object?>[];
      for (final e in list) {
        if (e is Map) {
          try {
            OutboxEntry.fromJson(e.cast<String, Object?>());
            continue; // readable — the caller owns it
          } catch (_) {
            // unreadable — falls through and is kept VERBATIM
          }
        }
        if (keep(e)) out.add(e);
      }
      return out;
    } catch (_) {
      return const <Object?>[];
    }
  }

  /// The operation identity of a RAW stored entry, read as plain strings. Used
  /// ONLY to recognise an entry the caller is rewriting — never to price it,
  /// submit it, or decide what it means.
  static Set<String> _identityOf(Object? entry) {
    if (entry is! Map) return const <String>{};
    final out = <String>{};
    final id = entry['id'];
    if (id is String && id.trim().isNotEmpty) out.add('id:$id');
    final device = entry['device_id'];
    final op = entry['local_operation_id'];
    if (device is String && op is String && op.trim().isNotEmpty) {
      // The D-022 idempotency identity.
      out.add('op:$device/$op');
    }
    return out;
  }

  @override
  int unreadableRecordCount(String scopeKey) {
    final quarantined = _quarantined(scopeKey, (_) => true).length;
    var preserved = 0;
    for (var slot = 0; slot < _maxPreservedEnvelopes; slot++) {
      if ((_prefs.getString(_preservedKey(scopeKey, slot)) ?? '').isNotEmpty) {
        preserved++;
      }
    }
    return quarantined + preserved;
  }

  /// Sidecar keys holding envelopes this build could not interpret at all.
  static const int _maxPreservedEnvelopes = 5;

  String _preservedKey(String scopeKey, int slot) => slot == 0
      ? '${_keyFor(scopeKey)}.unreadable'
      : '${_keyFor(scopeKey)}.unreadable.${slot + 1}';

  /// Copies an envelope this build cannot interpret to a sidecar key BEFORE the
  /// primary key is overwritten.
  ///
  /// The bytes are the only remaining evidence of what was queued — possibly
  /// real customer orders written by a newer build, or a value damaged in a way
  /// a later build could repair. Overwriting them silently was a destructive
  /// migration performed without anyone deciding to.
  ///
  /// Fails CLOSED: if the copy cannot be made, [persist] throws rather than
  /// destroying the original. That refuses new local writes on a till whose
  /// storage is already both corrupted and full — the alternative is deleting a
  /// customer's order to make room, which is not ours to choose.
  Future<void> _preserveUnreadableEnvelope(String scopeKey) async {
    final raw = _prefs.getString(_keyFor(scopeKey));
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map &&
          (decoded['version'] as num?)?.toInt() == schemaVersion &&
          decoded['entries'] is List) {
        return; // interpretable; per-entry quarantine covers it
      }
    } catch (_) {
      // not decodable at all — preserve it
    }
    for (var slot = 0; slot < _maxPreservedEnvelopes; slot++) {
      final key = _preservedKey(scopeKey, slot);
      final existing = _prefs.getString(key);
      if (existing == raw) return; // already preserved (idempotent)
      if (existing != null && existing.isNotEmpty) continue;
      if (await _prefs.setString(key, raw)) return;
      _degraded = true;
      throw const PosPersistenceException(
        'an unreadable order-outbox envelope could not be set aside, so it was '
        'not overwritten',
      );
    }
    _degraded = true;
    throw const PosPersistenceException(
      'too many unreadable order-outbox envelopes are already being held; '
      'refusing to overwrite another',
    );
  }

  @override
  Future<void> persist(String scopeKey, List<OutboxEntry> entries) async {
    // BUILD + SERIALIZE FIRST, so an unencodable entry fails here — before the
    // durable store is touched and while the old set is still correct on disk.
    //
    // Entries this build cannot decode are re-emitted VERBATIM ahead of the
    // caller's set: a record we cannot read is not a record we are entitled to
    // destroy. They are dropped only when the caller is writing the SAME
    // operation identity, so a repaired entry replaces its broken shadow rather
    // than doubling it. Quarantined raws are never decoded and never pushed —
    // they only occupy storage until a build that understands them arrives.
    await _preserveUnreadableEnvelope(scopeKey);
    final rewritten = <String>{
      for (final e in entries) ..._identityOf(e.toJson()),
    };
    final envelope = <String, Object?>{
      'version': schemaVersion,
      'entries': [
        ..._quarantined(
          scopeKey,
          (e) => _identityOf(e).intersection(rewritten).isEmpty,
        ),
        for (final e in entries) e.toJson(),
      ],
    };
    final encoded = jsonEncode(envelope);

    // MONEY-DURABLE-STORES-003B: setString returns Future<bool> and can report
    // FALSE WITHOUT THROWING (a full disk; a browser refusing or quota-limiting
    // localStorage). The previous build discarded that value, so a failed write
    // looked exactly like a successful one: `enqueue` returned the entry and the
    // caller pushed the order to the server. The kitchen then cooks an order the
    // till has no durable record of — it vanishes on the next restart, and no
    // retry, reprint or reconciliation can find it again.
    final ok = await _prefs.setString(_keyFor(scopeKey), encoded);
    if (!ok) {
      _degraded = true;
      throw const PosPersistenceException(
        'the order outbox could not be persisted',
      );
    }
  }
}
