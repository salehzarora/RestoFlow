import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'recent_order.dart';

/// POS-ORDERS-AND-PAYMENT-001: persistence for the POS recent/unpaid-orders
/// surface. Mirrors the RF-114 durable-outbox seam so the recent-orders list
/// (and each order's paid/unpaid state) survives a browser refresh / app restart
/// on real devices, giving the cashier a real "today + yesterday" window.
///
/// A SWAPPABLE seam: the default is in-memory (demo mode / tests — session only);
/// the real app overrides it with a [SharedPrefsRecentOrdersStore]. It never
/// stores secrets or service-role keys — only the same integer-minor order/
/// payment snapshots the POS already holds in memory + the durable outbox.
abstract class PosRecentOrdersStore {
  /// Loads the persisted recent orders for [scopeKey] (a stable per-device key).
  /// Never throws — a corrupt/foreign value yields an empty list so the POS
  /// starts clean instead of crashing.
  Future<List<PosRecentOrder>> load(String scopeKey);

  /// Replaces the persisted set for [scopeKey] with [orders].
  Future<void> persist(String scopeKey, List<PosRecentOrder> orders);
}

/// An in-memory [PosRecentOrdersStore] (demo mode / tests). Session-only: the
/// data lives on the singleton provider instance so it survives controller
/// rebuilds within a session, but not an app restart.
class InMemoryRecentOrdersStore implements PosRecentOrdersStore {
  final Map<String, List<PosRecentOrder>> _byScope =
      <String, List<PosRecentOrder>>{};

  @override
  Future<List<PosRecentOrder>> load(String scopeKey) async =>
      List<PosRecentOrder>.of(_byScope[scopeKey] ?? const <PosRecentOrder>[]);

  @override
  Future<void> persist(String scopeKey, List<PosRecentOrder> orders) async {
    _byScope[scopeKey] = List<PosRecentOrder>.of(orders);
  }
}

/// A `shared_preferences`-backed [PosRecentOrdersStore]: one schema-versioned
/// JSON envelope `{version, orders[]}` PER SCOPE key. Web-durable (localStorage).
/// The full storage key is `<prefix>.<scopeKey>`, so each paired device's list is
/// isolated — a re-paired-as-new device (new deviceId) gets a fresh, empty list
/// and never picks up another device's orders.
class SharedPrefsRecentOrdersStore implements PosRecentOrdersStore {
  SharedPrefsRecentOrdersStore(this._prefs, {String keyPrefix = _defaultPrefix})
    : _prefix = keyPrefix;

  final SharedPreferences _prefs;
  final String _prefix;

  static const String _defaultPrefix = 'restoflow.pos.recent_orders.v1';

  /// Bump ONLY on an incompatible envelope/entry shape change; an unrecognised
  /// version is ignored on load (start clean) rather than mis-parsed.
  static const int schemaVersion = 1;

  String _keyFor(String scopeKey) {
    final safe = scopeKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '$_prefix.$safe';
  }

  @override
  Future<List<PosRecentOrder>> load(String scopeKey) async {
    final raw = _prefs.getString(_keyFor(scopeKey));
    if (raw == null || raw.isEmpty) return <PosRecentOrder>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <PosRecentOrder>[];
      final version = (decoded['version'] as num?)?.toInt();
      if (version != schemaVersion) return <PosRecentOrder>[];
      final list = decoded['orders'];
      if (list is! List) return <PosRecentOrder>[];
      final orders = <PosRecentOrder>[];
      for (final e in list) {
        if (e is! Map) continue;
        try {
          orders.add(PosRecentOrder.fromJson(e.cast<String, Object?>()));
        } on FormatException {
          // Drop a single corrupt/foreign entry; never crash the POS on start.
        }
      }
      return orders;
    } catch (_) {
      return <PosRecentOrder>[];
    }
  }

  @override
  Future<void> persist(String scopeKey, List<PosRecentOrder> orders) async {
    final envelope = <String, Object?>{
      'version': schemaVersion,
      'orders': [for (final o in orders) o.toJson()],
    };
    await _prefs.setString(_keyFor(scopeKey), jsonEncode(envelope));
  }
}
