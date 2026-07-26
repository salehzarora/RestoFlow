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
  /// version is ignored on load (start clean) rather than mis-parsed.
  static const int schemaVersion = 1;

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

  @override
  Future<void> persist(Map<String, PosDraftRecovery> recoveries) async {
    // Build + serialize FIRST so an unencodable record fails here, before the
    // durable store is touched (the old set stays on disk and still correct).
    final envelope = <String, Object?>{
      'version': schemaVersion,
      'recoveries': <String, Object?>{
        for (final e in recoveries.entries) e.key: e.value.toJson(),
      },
    };
    await _prefs.setString(_key, jsonEncode(envelope));
  }
}
