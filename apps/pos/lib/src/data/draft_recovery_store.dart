import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../state/draft_recovery_controller.dart' show PosDraftRecovery;

/// MENU-ORDER-001 (Codex #8/#9): persistence for the POS draft-recovery map so a
/// permanently-rejected order's recovery — its draft (products, quantities,
/// modifiers, notes AND the Dashboard menu ranks), order type, table, and
/// customer name — survives a browser refresh / app restart. Mirrors the RF-114
/// durable-outbox seam.
///
/// A SWAPPABLE seam: the default is in-memory (demo mode / tests — session only);
/// the real app overrides it with a [SharedPrefsDraftRecoveryStore]. Access to a
/// restored draft is STILL gated by its [PosRecoveryBinding] (scope + PIN
/// session), so a different operator never sees another's draft, name, or notes.
abstract class PosDraftRecoveryStore {
  /// Loads the persisted recovery map (keyed by outbox entry id). Never throws —
  /// a corrupt/foreign value yields an empty map so the POS starts clean.
  Future<Map<String, PosDraftRecovery>> load();

  /// Replaces the persisted recovery map with [recoveries].
  Future<void> persist(Map<String, PosDraftRecovery> recoveries);
}

/// An in-memory [PosDraftRecoveryStore] (demo mode / tests). Session-only: the
/// data lives on the singleton provider instance, so it survives controller
/// rebuilds within a session but not an app restart.
class InMemoryDraftRecoveryStore implements PosDraftRecoveryStore {
  Map<String, PosDraftRecovery> _data = <String, PosDraftRecovery>{};

  @override
  Future<Map<String, PosDraftRecovery>> load() async =>
      Map<String, PosDraftRecovery>.of(_data);

  @override
  Future<void> persist(Map<String, PosDraftRecovery> recoveries) async {
    _data = Map<String, PosDraftRecovery>.of(recoveries);
  }
}

/// A `shared_preferences`-backed [PosDraftRecoveryStore]: one schema-versioned
/// JSON envelope `{version, recoveries:{outboxEntryId:{...}}}`. Web-durable
/// (localStorage). Each installed app / paired device has its OWN
/// shared_preferences, and every stored record carries its scope binding, so a
/// restored draft is still access-gated to its own scope + PIN session.
class SharedPrefsDraftRecoveryStore implements PosDraftRecoveryStore {
  SharedPrefsDraftRecoveryStore(this._prefs, {String key = _defaultKey})
    : _key = key;

  final SharedPreferences _prefs;
  final String _key;

  static const String _defaultKey = 'restoflow.pos.draft_recovery.v1';

  /// Bump ONLY on an incompatible envelope/record shape change; an unrecognised
  /// version is ignored on load (start clean) rather than mis-parsed. v2
  /// (MENU-ORDER-001 Codex #1): ownership moved from the ephemeral pinSessionId to
  /// the stable worker id (employee_profile_id) + the stable cart lineId is now
  /// persisted — so a v1 record (pin-session-keyed, unattributable to the stable
  /// worker) is intentionally dropped on load rather than silently mis-owned.
  static const int schemaVersion = 2;

  @override
  Future<Map<String, PosDraftRecovery>> load() async {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <String, PosDraftRecovery>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, PosDraftRecovery>{};
      final version = (decoded['version'] as num?)?.toInt();
      if (version != schemaVersion) return <String, PosDraftRecovery>{};
      final map = decoded['recoveries'];
      if (map is! Map) return <String, PosDraftRecovery>{};
      final out = <String, PosDraftRecovery>{};
      for (final entry in map.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        try {
          out[entry.key.toString()] = PosDraftRecovery.fromJson(
            value.cast<String, Object?>(),
          );
        } catch (_) {
          // Drop a single corrupt/foreign record; never crash the POS on start.
        }
      }
      return out;
    } catch (_) {
      return <String, PosDraftRecovery>{};
    }
  }

  /// MONEY-LOCAL-DECODE-INTEGRITY-002B (Codex Blocker 6): the raw records this
  /// build cannot decode, read back from the CURRENT envelope.
  ///
  /// Deliberately re-read here rather than remembered from [load]: a guarantee
  /// that only holds when the caller happens to have loaded first is not a
  /// guarantee. The controller replaces the whole map on every write, so
  /// preservation has to live where it cannot be bypassed.
  Map<String, Object?> _quarantined() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, Object?>{};
      if ((decoded['version'] as num?)?.toInt() != schemaVersion) {
        // A version this build does not understand is already left untouched
        // by `load`, and this store only ever writes its OWN version — so
        // there is nothing here we could carry forward without mis-shaping it.
        return const <String, Object?>{};
      }
      final map = decoded['recoveries'];
      if (map is! Map) return const <String, Object?>{};
      final out = <String, Object?>{};
      for (final entry in map.entries) {
        final value = entry.value;
        if (value is Map) {
          try {
            PosDraftRecovery.fromJson(value.cast<String, Object?>());
            continue; // readable — the caller owns it
          } catch (_) {
            // unreadable — falls through and is kept VERBATIM
          }
        }
        out[entry.key.toString()] = value;
      }
      return out;
    } catch (_) {
      return const <String, Object?>{};
    }
  }

  @override
  Future<void> persist(Map<String, PosDraftRecovery> recoveries) async {
    // Build + serialize FIRST so an unencodable record fails here, before the
    // durable store is touched (the old set stays on disk and still correct).
    //
    // A record we cannot read is NOT a record we are entitled to destroy, so
    // the quarantined raw entries are re-emitted byte-for-byte. A readable
    // record under the same key REPLACES its quarantined shadow — the caller's
    // set is written last and wins — so a key never ends up duplicated and a
    // repaired record never stays hidden behind the broken one.
    final envelope = <String, Object?>{
      'version': schemaVersion,
      'recoveries': <String, Object?>{
        ..._quarantined(),
        for (final e in recoveries.entries) e.key: e.value.toJson(),
      },
    };
    await _prefs.setString(_key, jsonEncode(envelope));
  }
}
