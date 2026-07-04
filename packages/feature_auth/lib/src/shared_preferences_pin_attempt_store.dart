import 'dart:convert';

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A `shared_preferences`-backed [PinAttemptStore] (RF-118): the client PIN
/// attempt/lockout counter survives a browser refresh / app restart, so a
/// too-many-attempts cooldown is not trivially cleared by reloading the tab.
///
/// Web-durable (localStorage per origin); a file on native. Mirrors the RF-114
/// [SharedPrefsOutboxStore] pattern: one schema-versioned JSON value per scope,
/// key `<prefix>.<scopeKey>`. SECURITY: stores ONLY a failure count + a lockout
/// timestamp — NEVER a PIN, verifier, or token (the raw device token lives in
/// flutter_secure_storage). A corrupt/foreign value loads as
/// [PinAttemptState.empty] (never throws) so sign-in can never be bricked.
class SharedPreferencesPinAttemptStore implements PinAttemptStore {
  SharedPreferencesPinAttemptStore(
    this._prefs, {
    String keyPrefix = _defaultPrefix,
  }) : _prefix = keyPrefix;

  final SharedPreferences _prefs;
  final String _prefix;

  static const String _defaultPrefix = 'restoflow.pin_attempts.v1';

  String _keyFor(String scopeKey) {
    final safe = scopeKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '$_prefix.$safe';
  }

  @override
  Future<PinAttemptState> load(String scopeKey) async {
    final raw = _prefs.getString(_keyFor(scopeKey));
    if (raw == null || raw.isEmpty) return PinAttemptState.empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return PinAttemptState.empty;
      return PinAttemptState.fromJson(decoded.cast<String, Object?>());
    } catch (_) {
      return PinAttemptState.empty;
    }
  }

  @override
  Future<void> persist(String scopeKey, PinAttemptState state) async {
    await _prefs.setString(_keyFor(scopeKey), jsonEncode(state.toJson()));
  }

  @override
  Future<void> clear(String scopeKey) async {
    await _prefs.remove(_keyFor(scopeKey));
  }
}
