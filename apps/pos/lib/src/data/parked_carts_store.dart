/// PARKED-CARTS-001 — durable, SCOPE-PARTITIONED parked (held) carts.
///
/// A parked cart is an ordinary UNSENT POS cart the cashier set aside to serve
/// somebody else first. It is a LOCAL DRAFT and nothing more: parking creates no
/// server order, no sync operation, no kitchen work, no print, no payment and no
/// table claim. A parked cart becomes a real order only when it is restored and
/// the cashier later uses the ordinary Submit flow.
///
/// It is keyed by the FULL operational scope (organization, restaurant, branch,
/// device) exactly like the pull cursor: a till moved to another branch, or
/// re-paired as another device, must not inherit somebody else's held orders.
/// Demo and real mode resolve to different scopes, so they can never share a
/// namespace either. Nothing here is synchronized to another device or to
/// Supabase.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:shared_preferences/shared_preferences.dart';

import '../state/cart_controller.dart' show CartDraftSnapshot;
import 'demo_tables.dart' show DemoTable;
import 'sync_cursor_store.dart' show PosPersistenceException, PosSyncScope;

/// The storage key for one scope's parked carts.
///
/// [PosSyncScope.key] is already preferences-safe; the sanitizer is re-applied
/// here so this key is provably safe on its own terms rather than by trusting a
/// caller. Two different scopes can never collide onto one key.
String parkedCartsStorageKey(PosSyncScope scope) {
  final safe = scope.key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return 'restoflow.pos.parked_carts.v1.$safe';
}

/// One parked cart: everything needed to rebuild the cashier's draft EXACTLY.
///
/// Deliberately absent: any stored total. A total that is stored rather than
/// derived can disagree with the very lines it claims to summarize, and the
/// lines are the truth (D-007 integer minor units throughout). Also absent:
/// discounts — the pre-submit cart does not own them — and any rendered display
/// string used as authoritative line data.
class ParkedCart {
  const ParkedCart({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.orderType,
    required this.draft,
    this.label,
    this.table,
    this.customerName,
    this.customerPhone,
    this.scopeKey,
    this.employeeProfileId,
  });

  /// Bump ONLY on an incompatible envelope/record shape change. An unrecognised
  /// version is REFUSED on load rather than mis-parsed.
  static const int schemaVersion = 1;

  /// Stable local identity, allocated from the store's persisted sequence
  /// (`park-<n>`). Never a list position, never reused after a delete.
  final String id;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// The cashier-visible label. v1 has no rename editor; the controller defaults
  /// it to the customer name when there is one, else the UI falls back to the
  /// parked-at time. Null is normal.
  final String? label;

  final OrderType orderType;

  /// The dine-in table's IDENTITY + display snapshot (id/label/seats/area) — not
  /// its status. Occupancy is re-derived from the LIVE tables on restore, because
  /// a serialized "available" is a claim about the past, not the present.
  final DemoTable? table;

  final String? customerName;
  final String? customerPhone;

  /// The cart itself: per-line menu item id, name/price snapshots, quantity,
  /// modifiers (ids, name snapshots, price delta, quantity, kitchen meat), item
  /// note, menu display ordering and the per-line prep components.
  final CartDraftSnapshot draft;

  /// PROVENANCE, not an access lock. Access is scope-gated: any currently
  /// authorized cashier on the same device and branch may restore a parked cart
  /// (a held order belongs to the till, not to whoever keyed it — the next shift
  /// must be able to serve that customer). Mirrors the recovery binding's stable
  /// fields so the origin stays attributable.
  final String? scopeKey;
  final String? employeeProfileId;

  /// Physical item count (sum of line quantities) — derived.
  int get itemCount =>
      draft.lines.fold(0, (count, line) => count + line.quantity);

  /// The cart subtotal in integer minor units, DERIVED with the same RF-052
  /// formula the cart and the server use: `Σ(qty × unit + Σ(delta × mod qty))`.
  /// Never read from storage.
  int get subtotalMinor => draft.lines.fold(0, (sum, line) {
    final mods = line.modifiers.fold<int>(
      0,
      (m, mod) => m + mod.totalDeltaMinor,
    );
    return sum + line.basePriceMinor * line.quantity + mods;
  });

  String get currencyCode => draft.currencyCode;

  bool get isEmpty => draft.lines.isEmpty;

  ParkedCart copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? label,
    OrderType? orderType,
    DemoTable? table,
    String? customerName,
    String? customerPhone,
    CartDraftSnapshot? draft,
    String? scopeKey,
    String? employeeProfileId,
  }) => ParkedCart(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    label: label ?? this.label,
    orderType: orderType ?? this.orderType,
    table: table ?? this.table,
    customerName: customerName ?? this.customerName,
    customerPhone: customerPhone ?? this.customerPhone,
    draft: draft ?? this.draft,
    scopeKey: scopeKey ?? this.scopeKey,
    employeeProfileId: employeeProfileId ?? this.employeeProfileId,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'order_type': orderType == OrderType.dineIn ? 'dine_in' : 'takeaway',
    if (label != null) 'label': label,
    if (table != null) 'table': table!.toJson(),
    if (customerName != null) 'customer_name': customerName,
    if (customerPhone != null) 'customer_phone': customerPhone,
    if (scopeKey != null) 'scope_key': scopeKey,
    if (employeeProfileId != null) 'employee_profile_id': employeeProfileId,
    'draft': draft.toJson(),
  };

  /// Decodes ONE record. Optional fields are tolerated (an older or partial
  /// record must never crash the till on start), but a record with no usable
  /// IDENTITY or no draft is unusable — it throws rather than being silently
  /// given a fabricated id, which would make it undeletable and unattributable.
  static ParkedCart fromJson(Map<String, Object?> json) {
    final id = (json['id'] ?? '').toString();
    if (id.isEmpty) {
      throw const FormatException('parked cart record has no id');
    }
    final rawDraft = json['draft'];
    if (rawDraft is! Map) {
      throw const FormatException('parked cart record has no draft');
    }
    final rawTable = json['table'];
    String? nonEmpty(Object? v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return ParkedCart(
      id: id,
      createdAt: _parseTime(json['created_at']),
      updatedAt: _parseTime(json['updated_at']),
      label: nonEmpty(json['label']),
      orderType: json['order_type'] == 'dine_in'
          ? OrderType.dineIn
          : OrderType.takeaway,
      table: rawTable is Map
          ? DemoTable.fromJson(rawTable.cast<String, Object?>())
          : null,
      customerName: nonEmpty(json['customer_name']),
      customerPhone: nonEmpty(json['customer_phone']),
      scopeKey: nonEmpty(json['scope_key']),
      employeeProfileId: nonEmpty(json['employee_profile_id']),
      draft: CartDraftSnapshot.fromJson(rawDraft.cast<String, Object?>()),
    );
  }

  static DateTime _parseTime(Object? raw) =>
      DateTime.tryParse('${raw ?? ''}')?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

/// The decoded contents of one scope's parked-cart envelope.
class ParkedCartsSnapshot {
  const ParkedCartsSnapshot({
    required this.seq,
    required this.carts,
    this.unreadable = const <Object?>[],
  });

  /// The persisted monotonic id sequence. It only ever moves FORWARD, so a
  /// deleted id is never handed out again.
  final int seq;

  /// Readable records, ordered updatedAt-descending with a deterministic
  /// tie-break.
  final List<ParkedCart> carts;

  /// Records this build could not decode, kept VERBATIM. They are surfaced as a
  /// count rather than deleted: a record we cannot read is not a record we are
  /// entitled to destroy, and a later legitimate write re-emits them untouched.
  final List<Object?> unreadable;
}

/// The stored envelope could not be trusted (unparseable, or a version this
/// build does not understand). FAIL CLOSED: the caller surfaces the failure
/// instead of rendering "no parked orders", which would invite the cashier to
/// re-key an order that is actually still on disk.
class ParkedCartsLoadException implements Exception {
  const ParkedCartsLoadException(this.message);

  final String message;

  @override
  String toString() => 'ParkedCartsLoadException: $message';
}

/// Reads/writes the parked carts of ONE scope. Every mutation persists BEFORE it
/// returns, so a caller may only publish state it knows is durable.
abstract class ParkedCartsStore {
  /// Loads [scope]'s parked carts. Throws [ParkedCartsLoadException] when the
  /// envelope itself cannot be trusted.
  Future<ParkedCartsSnapshot> load(PosSyncScope scope);

  /// Allocates the next stable id, builds the record with it, and persists the
  /// whole envelope. Id allocation and the write are ONE step, so an id can
  /// never be consumed by a record that failed to store.
  ///
  /// Throws [PosPersistenceException] when the write does not stick.
  Future<ParkedCart> add(
    PosSyncScope scope,
    ParkedCart Function(String id) build,
  );

  /// Replaces the record with [cart]'s id. No-op when it is gone.
  Future<void> update(PosSyncScope scope, ParkedCart cart);

  /// Deletes by STABLE id (never by list position). No-op when it is gone.
  Future<void> remove(PosSyncScope scope, String id);
}

/// updatedAt DESCENDING, then id descending as the deterministic tie-break, so
/// two carts parked in the same instant keep a stable, reproducible order.
List<ParkedCart> _ordered(Iterable<ParkedCart> carts) {
  final out = carts.toList(growable: false);
  out.sort((a, b) {
    final byTime = b.updatedAt.compareTo(a.updatedAt);
    if (byTime != 0) return byTime;
    return b.id.compareTo(a.id);
  });
  return out;
}

/// In-memory store (tests / a build with no durable prefs). Session-only.
class InMemoryParkedCartsStore implements ParkedCartsStore {
  final Map<String, List<ParkedCart>> _byScope = <String, List<ParkedCart>>{};
  final Map<String, int> _seqByScope = <String, int>{};

  @override
  Future<ParkedCartsSnapshot> load(PosSyncScope scope) async =>
      ParkedCartsSnapshot(
        seq: _seqByScope[scope.key] ?? 0,
        carts: _ordered(_byScope[scope.key] ?? const <ParkedCart>[]),
      );

  @override
  Future<ParkedCart> add(
    PosSyncScope scope,
    ParkedCart Function(String id) build,
  ) async {
    final next = (_seqByScope[scope.key] ?? 0) + 1;
    final cart = build('park-$next');
    _seqByScope[scope.key] = next;
    (_byScope[scope.key] ??= <ParkedCart>[]).add(cart);
    return cart;
  }

  @override
  Future<void> update(PosSyncScope scope, ParkedCart cart) async {
    final list = _byScope[scope.key];
    if (list == null) return;
    final at = list.indexWhere((c) => c.id == cart.id);
    if (at >= 0) list[at] = cart;
  }

  @override
  Future<void> remove(PosSyncScope scope, String id) async {
    _byScope[scope.key]?.removeWhere((c) => c.id == id);
  }
}

/// `shared_preferences`-backed store — ONE schema-versioned envelope per scope:
/// `{"version":1,"seq":<monotonic int>,"carts":[...]}`.
class SharedPrefsParkedCartsStore implements ParkedCartsStore {
  SharedPrefsParkedCartsStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<ParkedCartsSnapshot> load(PosSyncScope scope) async {
    final raw = _prefs.getString(parkedCartsStorageKey(scope));
    if (raw == null || raw.isEmpty) {
      return const ParkedCartsSnapshot(seq: 0, carts: <ParkedCart>[]);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const ParkedCartsLoadException('parked carts could not be decoded');
    }
    if (decoded is! Map) {
      throw const ParkedCartsLoadException(
        'parked carts envelope is malformed',
      );
    }
    final version = (decoded['version'] as num?)?.toInt();
    if (version != ParkedCart.schemaVersion) {
      // FAIL CLOSED. Silently returning an empty list would tell the cashier
      // there is nothing parked while their order is still sitting on disk.
      throw ParkedCartsLoadException(
        'unsupported parked carts version: $version',
      );
    }
    final rawCarts = decoded['carts'];
    if (rawCarts is! List) {
      throw const ParkedCartsLoadException('parked carts list is malformed');
    }
    final carts = <ParkedCart>[];
    final unreadable = <Object?>[];
    for (final entry in rawCarts) {
      if (entry is! Map) {
        unreadable.add(entry);
        continue;
      }
      try {
        carts.add(ParkedCart.fromJson(entry.cast<String, Object?>()));
      } catch (_) {
        // One bad record must not hide the good ones — and must not be deleted.
        unreadable.add(entry);
      }
    }
    return ParkedCartsSnapshot(
      seq: (decoded['seq'] as num?)?.toInt() ?? 0,
      carts: _ordered(carts),
      unreadable: unreadable,
    );
  }

  @override
  Future<ParkedCart> add(
    PosSyncScope scope,
    ParkedCart Function(String id) build,
  ) async {
    final current = await load(scope);
    final next = current.seq + 1;
    final cart = build('park-$next');
    await _write(
      scope,
      seq: next,
      carts: [...current.carts, cart],
      from: current,
    );
    return cart;
  }

  @override
  Future<void> update(PosSyncScope scope, ParkedCart cart) async {
    final current = await load(scope);
    if (!current.carts.any((c) => c.id == cart.id)) return;
    await _write(
      scope,
      seq: current.seq,
      carts: [
        for (final c in current.carts)
          if (c.id == cart.id) cart else c,
      ],
      from: current,
    );
  }

  @override
  Future<void> remove(PosSyncScope scope, String id) async {
    final current = await load(scope);
    if (!current.carts.any((c) => c.id == id)) return;
    await _write(
      scope,
      seq: current.seq,
      carts: [
        for (final c in current.carts)
          if (c.id != id) c,
      ],
      from: current,
    );
  }

  /// Serializes FIRST (an unencodable record fails before the durable store is
  /// touched, leaving the old set intact), then writes and VERIFIES.
  ///
  /// `setString` returns `Future<bool>` and can report FALSE without throwing —
  /// a full disk, a browser refusing localStorage. Treating that as success is
  /// how a cashier's cart is cleared for a draft that was never stored.
  Future<void> _write(
    PosSyncScope scope, {
    required int seq,
    required List<ParkedCart> carts,
    required ParkedCartsSnapshot from,
  }) async {
    final payload = jsonEncode(<String, Object?>{
      'version': ParkedCart.schemaVersion,
      'seq': seq,
      'carts': <Object?>[
        for (final c in carts) c.toJson(),
        // Records this build could not read are carried through untouched.
        ...from.unreadable,
      ],
    });
    final ok = await _prefs.setString(parkedCartsStorageKey(scope), payload);
    if (!ok) {
      throw const PosPersistenceException('parked cart could not be persisted');
    }
  }
}

/// The parked-cart persistence seam.
///
/// Default: in-memory (tests / demo — session only). The real app overrides it
/// in `main.dart` with a [SharedPrefsParkedCartsStore] so a held order survives
/// a restart, a force-stop and a logout. Kept a singleton so the in-memory data
/// survives controller rebuilds within a session.
final parkedCartsStoreProvider = Provider<ParkedCartsStore>(
  (ref) => InMemoryParkedCartsStore(),
);
