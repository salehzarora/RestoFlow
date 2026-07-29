import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'printer_config.dart';

/// WIFI-PRINTER-PROFILE-LISTS-001 — the saved Wi-Fi/Ethernet printer profiles.
///
/// Each device keeps its OWN list of saved network printers per printer slot.
/// Profiles are local application configuration: they live in
/// `shared_preferences` under a fully device- and slot-scoped key, never in
/// Supabase, and they never move between devices, apps or slots.
///
/// This layer stores CONFIGURATION ONLY. Connected/disconnected status, sockets,
/// native handles, stream state and transient errors are runtime concerns and
/// are deliberately absent from the model and from storage.

/// One saved network printer, identified by a STABLE id (never a list index).
class NetworkPrinterProfile {
  const NetworkPrinterProfile({
    required this.id,
    required this.name,
    required this.config,
  });

  /// Stable local identity. Survives rename, host/port edits and reordering.
  final String id;

  /// The user-visible profile name ("Kitchen printer").
  final String name;

  /// The endpoint + printer options (host, port, media profile).
  final NetworkPrinterConfig config;

  NetworkPrinterProfile copyWith({
    String? name,
    NetworkPrinterConfig? config,
  }) => NetworkPrinterProfile(
    id: id,
    name: name ?? this.name,
    config: config ?? this.config,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'config': config.toJson(),
  };

  /// Tolerant decode — a malformed entry is dropped, never crashes the till.
  static NetworkPrinterProfile? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}'.trim();
    if (id.isEmpty) return null;
    final config = NetworkPrinterConfig.fromJson(switch (raw['config']) {
      final Map<String, dynamic> m => m,
      final Map m => m.map((k, v) => MapEntry('$k', v)),
      _ => const <String, dynamic>{},
    });
    if (config == null) return null;
    return NetworkPrinterProfile(
      id: id,
      name: '${raw['name'] ?? ''}',
      config: config,
    );
  }

  /// The dedup identity of a saved endpoint: normalized host + port. Two
  /// profiles that resolve to the SAME printer on the same slot are one
  /// logical profile, however they were typed.
  static String endpointKeyOf(NetworkPrinterConfig config) =>
      '${config.host.trim().toLowerCase()}:${config.port}';

  String get endpointKey => endpointKeyOf(config);
}

/// True when [config] is safe to persist as a profile. Mirrors the existing
/// single-config rule: a non-blank host and a real TCP port. 9100 is the
/// DEFAULT port, never the only valid one.
bool isValidNetworkProfileConfig(NetworkPrinterConfig config) =>
    config.host.trim().isNotEmpty && config.port > 0 && config.port <= 65535;

/// The prefs-backed profile repository for ONE device + ONE printer slot.
///
/// Every key is supplied by the caller already fully scoped, so the POS (whose
/// namespace comes from `PosPrinterScope`) and the KDS (whose namespace comes
/// from the native printer store) can share this class without either one
/// being able to read the other's profiles.
class NetworkPrinterProfileStore {
  NetworkPrinterProfileStore({
    required this.prefs,
    required this.listKey,
    required this.activeKey,
    required this.legacyConfigKey,
  });

  final SharedPreferences prefs;

  /// Where the profile LIST lives, e.g.
  /// `restoflow.printer.network_profiles.pos.<slot><deviceSegment>`.
  final String listKey;

  /// Where the ACTIVE profile id lives for this slot.
  final String activeKey;

  /// The EXISTING single-config key for this slot — read for the one-time
  /// migration and then left alone. Never erased here: losing a working
  /// printer to a half-finished migration is worse than a stale duplicate key.
  final String legacyConfigKey;

  /// Every saved profile for this device + slot, in stable stored order.
  ///
  /// On the first read for a scope that has no list yet, the EXISTING single
  /// configuration is migrated into one active profile. Reading never rewrites
  /// persisted ordering.
  Future<List<NetworkPrinterProfile>> list() async {
    final stored = _read();
    if (stored.isNotEmpty) return stored;
    final migrated = await _migrateLegacy();
    return migrated;
  }

  Future<NetworkPrinterProfile?> get(String id) async {
    for (final p in await list()) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Adds a profile, or returns the EXISTING one when the normalized endpoint
  /// already exists on this slot (never a silent duplicate). Returns null when
  /// [config] is invalid — nothing is stored in that case.
  Future<NetworkPrinterProfile?> add({
    required String name,
    required NetworkPrinterConfig config,
  }) async {
    if (!isValidNetworkProfileConfig(config)) return null;
    final normalized = _normalize(config);
    final current = await list();
    final key = NetworkPrinterProfile.endpointKeyOf(normalized);
    for (final existing in current) {
      if (existing.endpointKey == key) return existing;
    }
    final profile = NetworkPrinterProfile(
      id: await _newId(current),
      name: name.trim(),
      config: normalized,
    );
    await _write([...current, profile]);
    return profile;
  }

  /// Updates a profile IN PLACE, preserving its id. Returns false (changing
  /// nothing) when the profile is unknown, the new config is invalid, or the
  /// edit would collide with another saved endpoint on this slot.
  Future<bool> update(NetworkPrinterProfile profile) async {
    if (!isValidNetworkProfileConfig(profile.config)) return false;
    final current = await list();
    final index = current.indexWhere((p) => p.id == profile.id);
    if (index < 0) return false;
    final normalized = profile.copyWith(config: _normalize(profile.config));
    for (var i = 0; i < current.length; i++) {
      if (i != index && current[i].endpointKey == normalized.endpointKey) {
        return false;
      }
    }
    final next = [...current]..[index] = normalized;
    await _write(next);
    return true;
  }

  /// Removes a profile. Removing the ACTIVE profile clears the selection so the
  /// slot is honestly unconfigured — an unrelated profile is NEVER promoted.
  Future<void> remove(String id) async {
    final current = await list();
    final next = [
      for (final p in current)
        if (p.id != id) p,
    ];
    if (next.length == current.length) return;
    await _write(next);
    if (prefs.getString(activeKey) == id) {
      await prefs.remove(activeKey);
    }
  }

  /// The active profile id for this slot, or null when unconfigured. A stale
  /// pointer to a deleted profile reads as null.
  Future<String?> activeProfileId() async {
    final id = prefs.getString(activeKey);
    if (id == null || id.isEmpty) return null;
    for (final p in await list()) {
      if (p.id == id) return id;
    }
    return null;
  }

  /// The active profile, or null.
  Future<NetworkPrinterProfile?> activeProfile() async {
    final id = await activeProfileId();
    return id == null ? null : get(id);
  }

  /// Selects [id] for this slot (null clears it). Selecting an unknown id is a
  /// no-op rather than a silent wrong selection.
  Future<void> setActiveProfileId(String? id) async {
    if (id == null) {
      await prefs.remove(activeKey);
      return;
    }
    final known = await get(id);
    if (known == null) return;
    await prefs.setString(activeKey, id);
  }

  // --- internals -----------------------------------------------------------

  List<NetworkPrinterProfile> _read() {
    final raw = prefs.getString(listKey);
    if (raw == null || raw.isEmpty) return const <NetworkPrinterProfile>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <NetworkPrinterProfile>[];
      return [
        for (final e in decoded)
          if (NetworkPrinterProfile.tryFromJson(e) case final p?) p,
      ];
    } catch (_) {
      // Corrupt storage degrades to "no profiles" — never a crash on startup.
      return const <NetworkPrinterProfile>[];
    }
  }

  Future<void> _write(List<NetworkPrinterProfile> profiles) async {
    await prefs.setString(
      listKey,
      jsonEncode([for (final p in profiles) p.toJson()]),
    );
  }

  /// One-time, idempotent adoption of the EXISTING single configuration.
  ///
  /// Runs only when no list exists yet. The legacy value is preserved, and a
  /// re-run finds the list non-empty and does nothing — so no duplicate can be
  /// created however many times a provider is rebuilt.
  Future<List<NetworkPrinterProfile>> _migrateLegacy() async {
    final raw = prefs.getString(legacyConfigKey);
    if (raw == null || raw.isEmpty) return const <NetworkPrinterProfile>[];
    NetworkPrinterConfig? legacy;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        legacy = NetworkPrinterConfig.fromJson(
          decoded.map((k, v) => MapEntry('$k', v)),
        );
      }
    } catch (_) {
      legacy = null;
    }
    if (legacy == null || !isValidNetworkProfileConfig(legacy)) {
      return const <NetworkPrinterProfile>[];
    }
    final profile = NetworkPrinterProfile(
      id: await _newId(const <NetworkPrinterProfile>[]),
      // Keep the saved label when there is one; the caller supplies a localized
      // default otherwise (never a hardcoded user-facing string here).
      name: (legacy.name ?? '').trim(),
      config: _normalize(legacy),
    );
    await _write([profile]);
    // Verify the write landed before treating the migration as done.
    if (_read().isEmpty) return const <NetworkPrinterProfile>[];
    await prefs.setString(activeKey, profile.id);
    return [profile];
  }

  /// Trims the host so a stored profile is already normalized on disk.
  NetworkPrinterConfig _normalize(NetworkPrinterConfig config) =>
      config.copyWith(host: config.host.trim());

  /// The key holding this slot's monotonic id counter.
  String get _seqKey => '$listKey.seq';

  /// A stable id from a MONOTONIC per-slot counter that never decreases.
  ///
  /// Deriving the id from the list length or the current maximum would REUSE an
  /// id after a deletion (delete `p2` from `[p1, p2]`, add again, and the new
  /// profile is `p2`), so a dialog or a caller holding the old id would silently
  /// edit or select a DIFFERENT printer. The counter is persisted next to the
  /// list and is still collision-checked against it.
  Future<String> _newId(List<NetworkPrinterProfile> current) async {
    final taken = {for (final p in current) p.id};
    var n = (prefs.getInt(_seqKey) ?? current.length) + 1;
    while (taken.contains('p$n')) {
      n++;
    }
    await prefs.setInt(_seqKey, n);
    return 'p$n';
  }
}
