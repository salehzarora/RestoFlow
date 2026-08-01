import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'recent_order.dart';
import 'sync_cursor_store.dart' show PosPersistenceException;

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
  ///
  /// THROWS [PosPersistenceException] when the write does not stick. Reporting
  /// success on a failed write is how the cashier's day disappears on restart while
  /// the sync cursor has already sailed past it.
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

  /// MONEY-LOCAL-DECODE-INTEGRITY-002B (Codex Blocker 6): the raw entries of
  /// [scopeKey]'s CURRENT envelope that this build cannot decode.
  ///
  /// Re-read here rather than remembered from [load], because the caller
  /// replaces the whole set on every write and a guarantee that depends on the
  /// caller having loaded first is not a guarantee.
  ///
  /// [keep] returns false for an entry whose order is also in the set being
  /// written — a repaired record must not sit behind its broken shadow.
  List<Object?> _quarantined(String scopeKey, bool Function(Object?) keep) {
    final raw = _prefs.getString(_keyFor(scopeKey));
    if (raw == null || raw.isEmpty) return const <Object?>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <Object?>[];
      if ((decoded['version'] as num?)?.toInt() != schemaVersion) {
        // Already ignored by `load`, and this store only writes its OWN
        // version — there is nothing here we could carry forward safely.
        return const <Object?>[];
      }
      final list = decoded['orders'];
      if (list is! List) return const <Object?>[];
      final out = <Object?>[];
      for (final e in list) {
        if (e is Map) {
          try {
            PosRecentOrder.fromJson(e.cast<String, Object?>());
            continue; // readable — the caller owns it
          } on FormatException {
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

  /// The cashier-visible code and the server id of a RAW stored entry, read as
  /// plain strings. Used ONLY to recognise a record the caller is rewriting —
  /// never to price it, and never to decide what it means.
  static Set<String> _identityOf(Object? entry) {
    if (entry is! Map) return const <String>{};
    final out = <String>{};
    void add(Object? container, String key, String prefix) {
      if (container is! Map) return;
      final v = container[key];
      if (v is String && v.trim().isNotEmpty) out.add('$prefix:$v');
    }

    add(entry['order'], 'order_number', 'number');
    add(entry['order'], 'order_id', 'id');
    add(entry['snapshot'], 'order_id', 'id');
    return out;
  }

  @override
  Future<void> persist(String scopeKey, List<PosRecentOrder> orders) async {
    // BUILD AND SERIALIZE FIRST. If any row cannot be encoded we fail here, before
    // touching the durable store — the old set is still on disk and still correct.
    //
    // Entries this build cannot decode are re-emitted VERBATIM ahead of the
    // caller's set: a record we cannot read is not a record we are entitled to
    // destroy. They are dropped only when the caller is writing the SAME order,
    // so a repaired record replaces its broken shadow instead of doubling it.
    final rewritten = <String>{
      for (final o in orders) ..._identityOf(o.toJson()),
    };
    final envelope = <String, Object?>{
      'version': schemaVersion,
      'orders': [
        ..._quarantined(
          scopeKey,
          (e) => _identityOf(e).intersection(rewritten).isEmpty,
        ),
        for (final o in orders) o.toJson(),
      ],
    };
    final encoded = jsonEncode(envelope);

    // setString returns Future<bool> and can report FALSE WITHOUT THROWING (a full
    // disk; a browser refusing localStorage). The previous build ignored that value,
    // so a failed write looked exactly like a successful one — and the caller went on
    // to advance the sync cursor past rows that were never stored. Those rows vanish
    // on restart and the server never offers them again, because as far as it is
    // concerned we already have them.
    final ok = await _prefs.setString(_keyFor(scopeKey), encoded);
    if (!ok) {
      throw const PosPersistenceException(
        'recent orders could not be persisted',
      );
    }
  }
}
