import 'dart:convert';

import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenPrepComponent;
import 'package:shared_preferences/shared_preferences.dart';

import '../state/cart_controller.dart' show CartLineView, SelectedModifier;
import 'local_storage_health.dart';
import 'sync_cursor_store.dart' show PosPersistenceException;

/// MONEY-DURABLE-ADDITIONS-003C — the durable Add-items AMENDMENT JOURNAL.
///
/// WHY A DEDICATED STORE. The generic order outbox carries `order.submit` and
/// nothing else: its op builder emits one shape, and an amendment needs state
/// the outbox has no room for — the target order's ownership, the workflow
/// phase, the frozen cart lines the kitchen ticket is rendered from, the
/// expected monetary delta, the applied round identity, and the cart-lock
/// owner token. Bending the outbox around that would make BOTH contracts
/// vaguer; the operations are genuinely different.
///
/// THE INVARIANT. One durable identity and one byte-identical frozen payload
/// survive from before the first dispatch until authoritative reconciliation
/// proves the server's final state. `app.add_order_items` keys its idempotency
/// on `(organization, device, local_operation_id)` and returns the SAME
/// `round_id`/`round_number` for a repeat — but only if we come back under the
/// same identity, with the same payload. The server fingerprint is
/// `md5(op_type || '|' || payload::text || '|' || target_id::text)`, so a
/// payload rebuilt from the live cart or menu is refused as a CONFLICT rather
/// than replayed. That is fail-safe, and useless for recovery. Hence: stored
/// verbatim, re-sent verbatim.
enum PosAdditionJournalPhase {
  /// Durably stored, nothing dispatched yet. A crash here means the operation
  /// provably never reached the server.
  prepared,

  /// Handed to the transport. A crash here means the outcome is UNKNOWN — which
  /// is emphatically not the same as "not applied".
  dispatching,

  /// The transport failed or timed out. The server may or may not own the
  /// operation; only a replay can tell us.
  transportUncertain,

  /// The server said APPLIED and named the round, but the authoritative detail
  /// refresh has not yet proven it. The operation must never be dispatched
  /// again; only the refresh may be retried.
  awaitingAuthoritativeRefresh,

  /// The server refused it permanently (a typed business rejection). Terminal
  /// for the operation: no retry, no print.
  rejected,

  /// The same identity came back with a different payload fingerprint. Never a
  /// second round — and never resolvable by retrying, so it needs a human.
  conflict,
}

/// One durable amendment attempt.
///
/// Everything here is immutable evidence captured at freeze time. Nothing is
/// re-derived from the live cart, the live menu, or current catalogue prices —
/// that is the whole point. Money is integer minor units (D-007).
class PosAdditionJournalRecord {
  const PosAdditionJournalRecord({
    required this.localOperationId,
    required this.orderId,
    required this.orderCode,
    required this.orderTypeWire,
    required this.generation,
    required this.itemsJson,
    required this.lines,
    required this.prepByItemId,
    required this.expectedDeltaMinor,
    required this.currencyCode,
    required this.clientCreatedAt,
    this.phase = PosAdditionJournalPhase.prepared,
    this.tableLabel,
    this.customerName,
    this.customerPhone,
    this.attemptCount = 0,
    this.lastErrorCode,
    this.appliedRoundId,
    this.appliedRoundNumber,
  });

  /// The D-022 idempotency identity AND this record's key. One per attempt,
  /// reused by every retry and every replay.
  final String localOperationId;

  /// The parent order being extended — never retargetable.
  final String orderId;

  /// The parent's own identity/type/table, frozen so a restored attempt can
  /// rebuild the kitchen ticket without re-reading the authoritative detail.
  final String orderCode;
  final String orderTypeWire;
  final String? tableLabel;
  final String? customerName;
  final String? customerPhone;

  /// The cart-lock generation this attempt owned. Persisted because
  /// `CartLockOwner` compares all three fields, so reconstructing the token
  /// after a restart needs it (the counter itself restarts at 0).
  final int generation;

  /// THE FROZEN WIRE PAYLOAD, byte-identical to what was dispatched. Re-sent
  /// verbatim — never rebuilt.
  final List<Map<String, Object?>> itemsJson;

  /// The SAME cart lines [itemsJson] was serialized from, kept for the kitchen
  /// ticket (money-free) and for showing the cashier what is unresolved.
  final List<CartLineView> lines;

  /// The ORDER-TIME (D-008) per-item prep snapshot used for both the wire
  /// payload and the printed ticket.
  final Map<String, List<KitchenPrepComponent>> prepByItemId;

  /// What this amendment is expected to add to the bill, in minor units:
  /// `Σ qty × (base + Σ(delta × modifierQty))` computed ONCE at freeze time
  /// (MONEY-PRICING-FORMULA-002A) and never recomputed.
  final int expectedDeltaMinor;
  final String currencyCode;

  final DateTime clientCreatedAt;
  final PosAdditionJournalPhase phase;
  final int attemptCount;

  /// A SAFE classification only — an error code, never raw backend text and
  /// never a stack trace.
  final String? lastErrorCode;

  /// The server's applied round, once known. Both are needed: the id scopes the
  /// exactly-once print claim, the number is what the kitchen reads.
  final String? appliedRoundId;
  final int? appliedRoundNumber;

  /// Whether this attempt was handed to the transport. A `prepared` record
  /// provably never reached the server, which is the ONLY state in which
  /// abandoning the identity is safe.
  bool get wasDispatched => phase != PosAdditionJournalPhase.prepared;

  /// Whether the operation still needs the server's verdict.
  ///
  /// `conflict` is EXCLUDED here on purpose: the server has spoken (the identity
  /// exists under a different payload), so there is nothing left to ask it. It
  /// is still ACTIONABLE — see [needsAttention].
  bool get isUnresolved =>
      phase != PosAdditionJournalPhase.rejected &&
      phase != PosAdditionJournalPhase.conflict;

  /// MONEY-CODEX-FINAL-CORRECTIONS-004 (F4): whether this record still requires
  /// operator or automatic resolution and must therefore survive a restart, keep
  /// its order blocked, and be counted by the cutover.
  ///
  /// Broader than [isUnresolved] by exactly one phase — `conflict` — which the
  /// previous build dropped on restart. A conflict is the one state that CANNOT
  /// resolve itself: it needs a person, so silently forgetting it was the worst
  /// possible default. Only a definitive `rejected` is finished.
  bool get needsAttention => phase != PosAdditionJournalPhase.rejected;

  /// Whether this record is blocked awaiting a person rather than a retry.
  bool get isConflict => phase == PosAdditionJournalPhase.conflict;

  PosAdditionJournalRecord copyWith({
    PosAdditionJournalPhase? phase,
    int? attemptCount,
    String? lastErrorCode,
    String? appliedRoundId,
    int? appliedRoundNumber,
    bool clearError = false,
  }) => PosAdditionJournalRecord(
    localOperationId: localOperationId,
    orderId: orderId,
    orderCode: orderCode,
    orderTypeWire: orderTypeWire,
    generation: generation,
    itemsJson: itemsJson,
    lines: lines,
    prepByItemId: prepByItemId,
    expectedDeltaMinor: expectedDeltaMinor,
    currencyCode: currencyCode,
    clientCreatedAt: clientCreatedAt,
    phase: phase ?? this.phase,
    tableLabel: tableLabel,
    customerName: customerName,
    customerPhone: customerPhone,
    attemptCount: attemptCount ?? this.attemptCount,
    lastErrorCode: clearError ? null : (lastErrorCode ?? this.lastErrorCode),
    appliedRoundId: appliedRoundId ?? this.appliedRoundId,
    appliedRoundNumber: appliedRoundNumber ?? this.appliedRoundNumber,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'local_operation_id': localOperationId,
    'order_id': orderId,
    'order_code': orderCode,
    'order_type_wire': orderTypeWire,
    'generation': generation,
    'items_json': itemsJson,
    'lines': [for (final l in lines) _lineToJson(l)],
    'prep_by_item_id': <String, Object?>{
      for (final e in prepByItemId.entries)
        e.key: [for (final p in e.value) p.toJson()],
    },
    'expected_delta_minor': expectedDeltaMinor,
    'currency_code': currencyCode,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'phase': phase.name,
    'table_label': tableLabel,
    'customer_name': customerName,
    'customer_phone': customerPhone,
    'attempt_count': attemptCount,
    'last_error_code': lastErrorCode,
    'applied_round_id': appliedRoundId,
    'applied_round_number': appliedRoundNumber,
  };

  /// STRICT decoding, in the 003A/003B house style: a record this build cannot
  /// interpret exactly throws [FormatException] so the store can quarantine it
  /// VERBATIM rather than dispatch a half-understood money operation. Every
  /// money field must be a real integer — a tolerant `?? 0` here would send a
  /// silently-zeroed amendment.
  factory PosAdditionJournalRecord.fromJson(Map<String, Object?> json) {
    String requireString(String key) {
      final raw = json[key];
      if (raw is String && raw.trim().isNotEmpty) return raw;
      throw FormatException(
        'addition journal: $key is not a non-blank string '
        '(${raw == null ? 'absent/null' : raw.runtimeType})',
      );
    }

    int requireInt(String key) {
      final raw = json[key];
      if (raw is int) return raw;
      throw FormatException(
        'addition journal: $key is not an integer '
        '(${raw == null ? 'absent/null' : raw.runtimeType})',
      );
    }

    final rawItems = json['items_json'];
    if (rawItems is! List) {
      throw const FormatException('addition journal: items_json is not a list');
    }
    if (rawItems.isEmpty) {
      throw const FormatException('addition journal: items_json is empty');
    }
    final rawLines = json['lines'];
    if (rawLines is! List) {
      throw const FormatException('addition journal: lines is not a list');
    }
    final createdRaw = json['client_created_at'];
    final created = createdRaw is String ? DateTime.tryParse(createdRaw) : null;
    if (created == null) {
      throw FormatException(
        'addition journal: client_created_at is not a parseable timestamp '
        '(${createdRaw == null ? 'absent/null' : createdRaw.runtimeType})',
      );
    }
    final phaseWire = json['phase'];
    final phase = PosAdditionJournalPhase.values
        .where((p) => p.name == phaseWire)
        .firstOrNull;
    if (phase == null) {
      throw FormatException('addition journal: unknown phase $phaseWire');
    }

    final prep = <String, List<KitchenPrepComponent>>{};
    final rawPrep = json['prep_by_item_id'];
    if (rawPrep is Map) {
      for (final e in rawPrep.entries) {
        final v = e.value;
        if (v is! List) continue;
        final parsed = <KitchenPrepComponent>[
          for (final p in v)
            if (KitchenPrepComponent.tryFromJson(p) case final c?) c,
        ];
        if (parsed.isNotEmpty) prep[e.key.toString()] = parsed;
      }
    }

    final roundNumberRaw = json['applied_round_number'];
    if (roundNumberRaw != null && roundNumberRaw is! int) {
      throw FormatException(
        'addition journal: applied_round_number is not an integer '
        '(${roundNumberRaw.runtimeType})',
      );
    }

    return PosAdditionJournalRecord(
      localOperationId: requireString('local_operation_id'),
      orderId: requireString('order_id'),
      orderCode: requireString('order_code'),
      orderTypeWire: (json['order_type_wire'] ?? '').toString(),
      generation: requireInt('generation'),
      itemsJson: [
        for (final i in rawItems)
          if (i is Map)
            i.cast<String, Object?>()
          else
            throw const FormatException(
              'addition journal: an items_json entry is not an object',
            ),
      ],
      lines: [for (final l in rawLines) _lineFromJson(l)],
      prepByItemId: prep,
      expectedDeltaMinor: requireInt('expected_delta_minor'),
      currencyCode: requireString('currency_code'),
      clientCreatedAt: created,
      phase: phase,
      tableLabel: json['table_label'] as String?,
      customerName: json['customer_name'] as String?,
      customerPhone: json['customer_phone'] as String?,
      attemptCount: requireInt('attempt_count'),
      lastErrorCode: json['last_error_code'] as String?,
      appliedRoundId: json['applied_round_id'] as String?,
      appliedRoundNumber: roundNumberRaw as int?,
    );
  }
}

Map<String, Object?> _lineToJson(CartLineView l) => <String, Object?>{
  'line_id': l.lineId,
  'menu_item_id': l.menuItemId,
  'name': l.name,
  'quantity': l.quantity,
  'unit_price_minor': l.unitPriceMinor,
  'line_total_minor': l.lineTotalMinor,
  'currency_code': l.currencyCode,
  'note': l.note,
  'category_display_order': l.categoryDisplayOrder,
  'item_display_order': l.itemDisplayOrder,
  'modifiers': [for (final m in l.modifiers) m.toJson()],
};

CartLineView _lineFromJson(Object? raw) {
  if (raw is! Map) {
    throw const FormatException('addition journal: a line is not an object');
  }
  final json = raw.cast<String, Object?>();
  String requireString(String key) {
    final v = json[key];
    if (v is String && v.trim().isNotEmpty) return v;
    throw FormatException(
      'addition journal line: $key is not a non-blank string '
      '(${v == null ? 'absent/null' : v.runtimeType})',
    );
  }

  int requireInt(String key) {
    final v = json[key];
    if (v is int) return v;
    throw FormatException(
      'addition journal line: $key is not an integer '
      '(${v == null ? 'absent/null' : v.runtimeType})',
    );
  }

  final mods = json['modifiers'];
  return CartLineView(
    lineId: requireString('line_id'),
    menuItemId: requireString('menu_item_id'),
    name: (json['name'] ?? '').toString(),
    quantity: requireInt('quantity'),
    unitPriceMinor: requireInt('unit_price_minor'),
    lineTotalMinor: requireInt('line_total_minor'),
    currencyCode: requireString('currency_code'),
    note: json['note'] as String?,
    categoryDisplayOrder: requireInt('category_display_order'),
    itemDisplayOrder: requireInt('item_display_order'),
    // SelectedModifier.fromJson is the 002C/003A STRICT decoder: it refuses a
    // blank option id and a wrongly-typed display name, so a damaged modifier
    // quarantines the record instead of silently dropping a paid surcharge.
    modifiers: [
      if (mods is List)
        for (final m in mods)
          if (m is Map)
            SelectedModifier.fromJson(m.cast<String, Object?>())
          else
            throw const FormatException(
              'addition journal line: a modifier is not an object',
            ),
    ],
  );
}

/// Durable persistence for unresolved Add-items amendments.
abstract class PosAdditionJournalStore {
  /// Every readable record, keyed by `local_operation_id`. Never throws — an
  /// unreadable record is quarantined, not surfaced, and never dispatched.
  Future<Map<String, PosAdditionJournalRecord>> load(String scopeKey);

  /// Replaces the persisted set for [scopeKey].
  ///
  /// THROWS [PosPersistenceException] when the write does not stick (003B). An
  /// amendment that could not be journalled must not be dispatched: without the
  /// record there is nothing to replay under, so a later retry would mint a new
  /// identity and the server would build a second round.
  Future<void> persist(
    String scopeKey,
    Map<String, PosAdditionJournalRecord> records,
  );
}

/// A `shared_preferences`-backed journal: one schema-versioned envelope
/// `{version, records:{localOperationId:{…}}}` PER DEVICE scope, mirroring the
/// RF-114 outbox binding so one device never replays another's amendment.
class SharedPrefsAdditionJournalStore
    implements PosAdditionJournalStore, PosDurableStoreHealth {
  SharedPrefsAdditionJournalStore(this._prefs, {String keyPrefix = _prefix})
    : _keyPrefix = keyPrefix;

  final SharedPreferences _prefs;
  final String _keyPrefix;

  static const String _prefix = 'restoflow.pos.addition_journal.v1';

  /// Bump ONLY on an incompatible envelope/record shape change.
  static const int schemaVersion = 1;

  static const int _maxPreservedEnvelopes = 5;

  bool _degraded = false;

  @override
  bool get isDegraded => _degraded;

  String _keyFor(String scopeKey) {
    final safe = scopeKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty ? _keyPrefix : '$_keyPrefix.$safe';
  }

  String _preservedKey(String scopeKey, int slot) => slot == 0
      ? '${_keyFor(scopeKey)}.unreadable'
      : '${_keyFor(scopeKey)}.unreadable.${slot + 1}';

  @override
  Future<Map<String, PosAdditionJournalRecord>> load(String scopeKey) async {
    final raw = _prefs.getString(_keyFor(scopeKey));
    if (raw == null || raw.isEmpty) {
      // ABSENT IS A VALID EMPTY JOURNAL — a till that has never amended an
      // order. Distinct from a malformed envelope, which is preserved below.
      return <String, PosAdditionJournalRecord>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, PosAdditionJournalRecord>{};
      if ((decoded['version'] as num?)?.toInt() != schemaVersion) {
        return <String, PosAdditionJournalRecord>{};
      }
      final records = decoded['records'];
      if (records is! Map) return <String, PosAdditionJournalRecord>{};
      final out = <String, PosAdditionJournalRecord>{};
      for (final e in records.entries) {
        final v = e.value;
        if (v is! Map) continue;
        try {
          out[e.key.toString()] = PosAdditionJournalRecord.fromJson(
            v.cast<String, Object?>(),
          );
        } catch (_) {
          // Broad by design (003B): the decoders reach fields through casts, so
          // a wrongly-TYPED value raises TypeError rather than FormatException,
          // and letting that escape would empty the WHOLE journal. One damaged
          // record costs one record; it is preserved by `_quarantined`.
        }
      }
      return out;
    } catch (_) {
      // An envelope this build cannot interpret at all. The bytes are NOT
      // discarded — `persist` sets them aside before overwriting.
      return <String, PosAdditionJournalRecord>{};
    }
  }

  /// The raw records this build cannot decode, re-read from the CURRENT
  /// envelope on every write — not remembered from [load], because a guarantee
  /// that only holds when the caller happened to load first is not a guarantee.
  Map<String, Object?> _quarantined(String scopeKey, Set<String> rewritten) {
    final raw = _prefs.getString(_keyFor(scopeKey));
    if (raw == null || raw.isEmpty) return const <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, Object?>{};
      if ((decoded['version'] as num?)?.toInt() != schemaVersion) {
        return const <String, Object?>{};
      }
      final records = decoded['records'];
      if (records is! Map) return const <String, Object?>{};
      final out = <String, Object?>{};
      for (final e in records.entries) {
        final key = e.key.toString();
        if (rewritten.contains(key)) continue; // repaired: caller's wins
        final v = e.value;
        if (v is Map) {
          try {
            PosAdditionJournalRecord.fromJson(v.cast<String, Object?>());
            continue; // readable — the caller owns it
          } catch (_) {
            // unreadable — kept VERBATIM
          }
        }
        out[key] = v;
      }
      return out;
    } catch (_) {
      return const <String, Object?>{};
    }
  }

  @override
  int unreadableRecordCount(String scopeKey) {
    var preserved = 0;
    for (var slot = 0; slot < _maxPreservedEnvelopes; slot++) {
      if ((_prefs.getString(_preservedKey(scopeKey, slot)) ?? '').isNotEmpty) {
        preserved++;
      }
    }
    return _quarantined(scopeKey, const <String>{}).length + preserved;
  }

  /// Copies an envelope this build cannot interpret to a sidecar key BEFORE the
  /// primary is overwritten. Fails CLOSED: if the copy cannot be made, [persist]
  /// throws rather than destroying evidence of an amendment that may be live on
  /// the server.
  Future<void> _preserveUnreadableEnvelope(String scopeKey) async {
    final raw = _prefs.getString(_keyFor(scopeKey));
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map &&
          (decoded['version'] as num?)?.toInt() == schemaVersion &&
          decoded['records'] is Map) {
        return; // interpretable; per-record quarantine covers it
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
        'an unreadable addition journal could not be set aside, so it was not '
        'overwritten',
      );
    }
    _degraded = true;
    throw const PosPersistenceException(
      'too many unreadable addition journals are already being held; refusing '
      'to overwrite another',
    );
  }

  @override
  Future<void> persist(
    String scopeKey,
    Map<String, PosAdditionJournalRecord> records,
  ) async {
    await _preserveUnreadableEnvelope(scopeKey);
    // BUILD + SERIALIZE FIRST, so an unencodable record fails here, before the
    // durable store is touched and while the old set is still correct on disk.
    final encoded = jsonEncode(<String, Object?>{
      'version': schemaVersion,
      'records': <String, Object?>{
        ..._quarantined(scopeKey, records.keys.toSet()),
        for (final e in records.entries) e.key: e.value.toJson(),
      },
    });
    final ok = await _prefs.setString(_keyFor(scopeKey), encoded);
    if (!ok) {
      _degraded = true;
      throw const PosPersistenceException(
        'the addition journal could not be persisted',
      );
    }
  }
}

/// An in-memory journal (demo mode / tests). Session-only and honest about it.
class InMemoryAdditionJournalStore implements PosAdditionJournalStore {
  final Map<String, Map<String, PosAdditionJournalRecord>> _data = {};

  @override
  Future<Map<String, PosAdditionJournalRecord>> load(String scopeKey) async =>
      Map<String, PosAdditionJournalRecord>.of(
        _data[scopeKey] ?? const <String, PosAdditionJournalRecord>{},
      );

  @override
  Future<void> persist(
    String scopeKey,
    Map<String, PosAdditionJournalRecord> records,
  ) async {
    _data[scopeKey] = Map<String, PosAdditionJournalRecord>.of(records);
  }
}
