import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_storage_health.dart';
import 'order_edit_diff.dart' show OrderEditAttemptSummary;
import 'order_edit_read_model.dart' show PosKitchenChannel;
import 'order_edit_response.dart'
    show
        OrderEditApplied,
        OrderEditAppliedChange,
        OrderEditKitchenDispatch,
        kOrderEditChangeKinds;
import 'order_edit_slip.dart' show OrderEditSlipItem;
import 'sync_cursor_store.dart' show PosPersistenceException;

/// ORDER-EDIT-001E — the durable SENT-ORDER-EDIT JOURNAL (design §7.1 point 7,
/// API_CONTRACT §4.45.5), the Add-items journal's pattern
/// (`addition_journal_store.dart`) for `order.edit`.
///
/// THE INVARIANT. One durable identity and one byte-identical frozen payload
/// survive from before the first dispatch until authoritative reconciliation
/// proves the server's final state. `app.edit_order` keys its idempotency on
/// (organization, device, `local_operation_id`) and answers a repeat with the
/// SAME stored envelope — the same `order_edit_id` and `edit_number` — but only
/// under the same identity AND the same payload: `sync_push` fingerprints
/// `md5(op_type | payload | target_id)`, so a payload rebuilt from the cart is
/// refused as a CONFLICT, never replayed. Stored verbatim, re-sent verbatim.
///
/// A record exists only while the edit's outcome is open. A refused (or
/// rejected) edit provably changed nothing, so its record is REMOVED rather
/// than kept in a terminal phase; an applied edit's record is removed once the
/// authoritative detail proves it.
enum OrderEditJournalPhase {
  /// Written BEFORE the dispatch and confirmed. A crash from here on means the
  /// outcome is UNKNOWN — emphatically not "not applied".
  dispatching,

  /// The transport failed or the answer proved nothing. Only a replay of the
  /// same identity can tell.
  transportUncertain,

  /// The server said APPLIED; the authoritative refresh has not yet proven it.
  /// Never dispatched again — only the refresh may be retried.
  awaitingAuthoritativeRefresh,

  /// The identity exists server-side under another order or payload. Never
  /// resolvable by retrying: a person must settle it.
  conflict,
}

/// One durable edit attempt — immutable evidence captured at freeze time.
///
/// Nothing is re-derived from the live cart or menu. The payload carries the
/// expected totals (integer minor units, D-007); the [summary] is money-free.
class OrderEditJournalRecord {
  const OrderEditJournalRecord({
    required this.localOperationId,
    required this.orderId,
    required this.orderCode,
    required this.clientCreatedAt,
    required this.generation,
    required this.payload,
    required this.summary,
    this.phase = OrderEditJournalPhase.dispatching,
    this.attemptCount = 0,
    this.employeeProfileId,
    this.lastErrorCode,
    this.applied,
    this.slipWas,
  });

  /// The D-022 idempotency identity AND this record's key — one per attempt,
  /// reused by every retry and every replay.
  final String localOperationId;

  /// The order being edited — never retargetable. Equals the payload's
  /// `order_id`, which `sync_push` requires to equal the op's `target_id`.
  final String orderId;
  final String orderCode;

  /// When the attempt was frozen, in UTC — the op's `client_created_at`.
  final DateTime clientCreatedAt;

  /// The cart-lock generation the attempt owned, persisted because the owner
  /// token compares it and the counter restarts at 0 after a restart.
  final int generation;

  /// THE FROZEN `order.edit` PAYLOAD, exactly as dispatched. Re-sent verbatim
  /// — never rebuilt.
  final Map<String, Object?> payload;

  /// A money-free description of the attempt (counts and the remake dishes the
  /// result toast reports, decision D8).
  final OrderEditAttemptSummary summary;

  final OrderEditJournalPhase phase;
  final int attemptCount;

  /// The worker who froze the attempt — DIAGNOSTIC only (decision D12): the
  /// journal is device-scoped and any operator may resolve it, exactly like the
  /// Add-items journal. An uncertain edit replayed under another worker is
  /// attributed to that worker unless the server had already applied it
  /// (RISK R-007).
  final String? employeeProfileId;

  /// A SAFE classification code — never raw backend text.
  final String? lastErrorCode;

  /// The server's applied facts, once it said APPLIED. Required in
  /// [OrderEditJournalPhase.awaitingAuthoritativeRefresh]: the reconcile
  /// verifies against them. Carries the paper dispatch for ORDER-EDIT-001F.
  final OrderEditApplied? applied;

  /// ORDER-EDIT-001F (decision D2): the money-free kitchen projections of the
  /// lines the payload names, FROZEN from the entry baseline on a PAPER edit,
  /// keyed by lower-case `order_item_id` — so a cart-free replay after a
  /// restart can still hand-build the full change slip. Null on a KDS edit and
  /// on a record written before 001F (its slip then stays unbuilt; the spool
  /// backup covers it). Slip evidence only: an unreadable value decodes as
  /// null and NEVER costs the record its identity.
  final Map<String, OrderEditSlipItem>? slipWas;

  bool get isConflict => phase == OrderEditJournalPhase.conflict;

  bool get awaitingRefresh =>
      phase == OrderEditJournalPhase.awaitingAuthoritativeRefresh;

  OrderEditJournalRecord copyWith({
    OrderEditJournalPhase? phase,
    int? attemptCount,
    String? lastErrorCode,
    OrderEditApplied? applied,
    bool clearError = false,
  }) => OrderEditJournalRecord(
    localOperationId: localOperationId,
    orderId: orderId,
    orderCode: orderCode,
    clientCreatedAt: clientCreatedAt,
    generation: generation,
    payload: payload,
    summary: summary,
    phase: phase ?? this.phase,
    attemptCount: attemptCount ?? this.attemptCount,
    employeeProfileId: employeeProfileId,
    lastErrorCode: clearError ? null : (lastErrorCode ?? this.lastErrorCode),
    applied: applied ?? this.applied,
    slipWas: slipWas,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'local_operation_id': localOperationId,
    'order_id': orderId,
    'order_code': orderCode,
    'client_created_at': clientCreatedAt.toUtc().toIso8601String(),
    'generation': generation,
    'payload': payload,
    'summary': summary.toJson(),
    'phase': phase.name,
    'attempt_count': attemptCount,
    'employee_profile_id': employeeProfileId,
    'last_error_code': lastErrorCode,
    'applied': applied == null ? null : _appliedToJson(applied!),
    // ORDER-EDIT-001F: written only when present, so a KDS edit's record is
    // byte-identical to its 001E form.
    if (slipWas != null)
      'slip_was': <Object?>[
        for (final e in slipWas!.entries)
          <String, Object?>{'order_item_id': e.key, 'item': e.value.toJson()},
      ],
  };

  /// STRICT decoding (the 003A/003B house style): a record this build cannot
  /// interpret exactly throws [FormatException], so the store quarantines it
  /// VERBATIM rather than replay a half-understood money operation.
  factory OrderEditJournalRecord.fromJson(Map<String, Object?> json) {
    String requireString(String key) {
      final raw = json[key];
      if (raw is String && raw.trim().isNotEmpty) return raw;
      throw FormatException(
        'order edit journal: $key is not a non-blank string '
        '(${raw == null ? 'absent/null' : raw.runtimeType})',
      );
    }

    int requireInt(String key) {
      final raw = json[key];
      if (raw is int) return raw;
      throw FormatException(
        'order edit journal: $key is not an integer '
        '(${raw == null ? 'absent/null' : raw.runtimeType})',
      );
    }

    String? optionalString(String key) {
      final raw = json[key];
      if (raw == null || raw is String) return raw as String?;
      throw FormatException('order edit journal: $key is not a string');
    }

    final orderId = requireString('order_id');
    final rawPayload = json['payload'];
    if (rawPayload is! Map) {
      throw const FormatException(
        'order edit journal: payload is not an object',
      );
    }
    final payload = rawPayload.cast<String, Object?>();
    // The payload must still be the edit of THIS order, with changes and the
    // mandatory expected totals — anything else could only be refused, or
    // worse, applied to the wrong order.
    if (payload['order_id'] != orderId) {
      throw const FormatException(
        'order edit journal: payload.order_id does not match the record',
      );
    }
    final changes = payload['changes'];
    if (changes is! List || changes.isEmpty) {
      throw const FormatException('order edit journal: payload has no changes');
    }
    if (payload['expected'] is! Map) {
      throw const FormatException(
        'order edit journal: payload has no expected totals',
      );
    }
    final createdRaw = json['client_created_at'];
    final created = createdRaw is String ? DateTime.tryParse(createdRaw) : null;
    if (created == null) {
      throw const FormatException(
        'order edit journal: client_created_at is not a parseable timestamp',
      );
    }
    final phaseWire = json['phase'];
    final phase = OrderEditJournalPhase.values
        .where((p) => p.name == phaseWire)
        .firstOrNull;
    if (phase == null) {
      throw FormatException('order edit journal: unknown phase $phaseWire');
    }
    final appliedRaw = json['applied'];
    final applied = appliedRaw == null ? null : _appliedFromJson(appliedRaw);
    if (phase == OrderEditJournalPhase.awaitingAuthoritativeRefresh &&
        applied == null) {
      throw const FormatException(
        'order edit journal: an applied record carries no applied facts',
      );
    }
    final attemptCount = requireInt('attempt_count');
    final generation = requireInt('generation');
    if (attemptCount < 0 || generation < 0) {
      throw const FormatException('order edit journal: negative counter');
    }

    return OrderEditJournalRecord(
      localOperationId: requireString('local_operation_id'),
      orderId: orderId,
      orderCode: requireString('order_code'),
      clientCreatedAt: created,
      generation: generation,
      payload: payload,
      summary: OrderEditAttemptSummary.fromJson(json['summary']),
      phase: phase,
      attemptCount: attemptCount,
      employeeProfileId: optionalString('employee_profile_id'),
      lastErrorCode: optionalString('last_error_code'),
      applied: applied,
      slipWas: _slipWasFromJson(json['slip_was']),
    );
  }
}

/// ORDER-EDIT-001F: TOLERANT on purpose — the frozen "was" lines are slip
/// evidence, not part of the money operation, so anything this build cannot
/// read exactly yields null (an unbuilt slip) rather than quarantining a
/// record whose identity may be live on the server.
Map<String, OrderEditSlipItem>? _slipWasFromJson(Object? raw) {
  if (raw is! List) return null;
  final out = <String, OrderEditSlipItem>{};
  try {
    for (final e in raw) {
      if (e is! Map) return null;
      final id = e['order_item_id'];
      if (id is! String || id.isEmpty || e.length != 2) return null;
      out[id.toLowerCase()] = OrderEditSlipItem.fromJson(e['item']);
    }
  } catch (_) {
    return null;
  }
  return out;
}

Map<String, Object?> _appliedToJson(OrderEditApplied a) => <String, Object?>{
  'order_edit_id': a.orderEditId,
  'edit_number': a.editNumber,
  'revision': a.revision,
  'kitchen_channel': a.kitchenChannel.name,
  'kitchen_ack_required': a.kitchenAckRequired,
  'new_round_id': a.newRoundId,
  'new_round_number': a.newRoundNumber,
  'remake_change_count': a.remakeChangeCount,
  'kitchen_dispatch': a.kitchenDispatch == null
      ? null
      : <String, Object?>{
          'id': a.kitchenDispatch!.id,
          'claim_expires_at': a.kitchenDispatch!.claimExpiresAt
              ?.toUtc()
              .toIso8601String(),
        },
  'order_status': a.orderStatus,
  'auto_completed': a.autoCompleted,
  // ORDER-EDIT-001F: the envelope changes the hand-built slip zips with the
  // payload. Written only when present (a KDS edit keeps its 001E bytes).
  if (a.changes.isNotEmpty)
    'changes': <Object?>[
      for (final c in a.changes)
        <String, Object?>{
          'kind': c.kind,
          'order_item_id': c.orderItemId,
          'new_order_item_ids': c.newOrderItemIds,
        },
    ],
};

/// ORDER-EDIT-001F: TOLERANT, like `slip_was` — the changes only feed the
/// change slip, so an unreadable list reads as empty (an unbuilt slip) and
/// never quarantines the applied record the reconcile depends on.
List<OrderEditAppliedChange> _appliedChangesFromJson(Object? raw) {
  if (raw is! List) return const <OrderEditAppliedChange>[];
  final out = <OrderEditAppliedChange>[];
  for (final c in raw) {
    if (c is! Map) return const <OrderEditAppliedChange>[];
    final kind = c['kind'];
    final id = c['order_item_id'];
    final ids = c['new_order_item_ids'];
    if (kind is! String ||
        !kOrderEditChangeKinds.contains(kind) ||
        (id != null && (id is! String || id.isEmpty)) ||
        (kind == 'add') != (id == null) ||
        ids is! List ||
        ids.any((n) => n is! String || n.isEmpty)) {
      return const <OrderEditAppliedChange>[];
    }
    out.add(
      OrderEditAppliedChange(
        kind: kind,
        orderItemId: id as String?,
        newOrderItemIds: List<String>.unmodifiable(ids.cast<String>()),
      ),
    );
  }
  return List<OrderEditAppliedChange>.unmodifiable(out);
}

/// STRICT: the facts the reconcile verifies against must be exact.
OrderEditApplied _appliedFromJson(Object? raw) {
  if (raw is! Map) {
    throw const FormatException('order edit journal: applied is not an object');
  }
  final editId = raw['order_edit_id'];
  final editNumber = raw['edit_number'];
  final revision = raw['revision'];
  final channel = PosKitchenChannel.fromWire(raw['kitchen_channel']);
  final ack = raw['kitchen_ack_required'];
  final remakes = raw['remake_change_count'];
  final roundId = raw['new_round_id'];
  final roundNumber = raw['new_round_number'];
  final status = raw['order_status'];
  final auto = raw['auto_completed'];
  if (editId is! String ||
      editId.trim().isEmpty ||
      editNumber is! int ||
      editNumber < 1 ||
      revision is! int ||
      channel == null ||
      ack is! bool ||
      remakes is! int ||
      remakes < 0 ||
      (roundId != null && roundId is! String) ||
      (roundNumber != null && roundNumber is! int) ||
      (status != null && status is! String) ||
      auto is! bool) {
    throw const FormatException('order edit journal: applied is malformed');
  }
  final dispatchRaw = raw['kitchen_dispatch'];
  OrderEditKitchenDispatch? dispatch;
  if (dispatchRaw != null) {
    if (dispatchRaw is! Map) {
      throw const FormatException(
        'order edit journal: kitchen_dispatch is not an object',
      );
    }
    final id = dispatchRaw['id'];
    final expiresRaw = dispatchRaw['claim_expires_at'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException(
        'order edit journal: kitchen_dispatch has no id',
      );
    }
    if (expiresRaw != null && expiresRaw is! String) {
      throw const FormatException(
        'order edit journal: kitchen_dispatch expiry is not a timestamp',
      );
    }
    dispatch = OrderEditKitchenDispatch(
      id: id,
      claimExpiresAt: expiresRaw == null
          ? null
          : DateTime.tryParse(expiresRaw as String),
    );
  }
  return OrderEditApplied(
    orderEditId: editId,
    editNumber: editNumber,
    revision: revision,
    kitchenChannel: channel,
    kitchenAckRequired: ack,
    newRoundId: roundId as String?,
    newRoundNumber: roundNumber as int?,
    remakeChangeCount: remakes,
    kitchenDispatch: dispatch,
    orderStatus: status as String?,
    autoCompleted: auto,
    changes: _appliedChangesFromJson(raw['changes']),
  );
}

/// Durable persistence for unresolved sent-order edits.
abstract class OrderEditJournalStore {
  /// Every readable record, keyed by `local_operation_id`. Never throws — an
  /// unreadable record is quarantined, not surfaced, and never dispatched.
  Future<Map<String, OrderEditJournalRecord>> load(String scopeKey);

  /// Replaces the persisted set for [scopeKey].
  ///
  /// THROWS [PosPersistenceException] when the write does not stick. An edit
  /// that could not be journalled must not be dispatched: without the record
  /// there is nothing to replay under, so a later retry would mint a new
  /// identity for an edit the server may already have applied.
  Future<void> persist(
    String scopeKey,
    Map<String, OrderEditJournalRecord> records,
  );
}

/// A `shared_preferences`-backed journal: one schema-versioned envelope
/// `{version, records:{localOperationId:{…}}}` PER DEVICE scope, so one device
/// never replays another's edit.
class SharedPrefsOrderEditJournalStore
    implements OrderEditJournalStore, PosDurableStoreHealth {
  SharedPrefsOrderEditJournalStore(this._prefs, {String keyPrefix = _prefix})
    : _keyPrefix = keyPrefix;

  final SharedPreferences _prefs;
  final String _keyPrefix;

  static const String _prefix = 'restoflow.pos.order_edit_journal.v1';

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
  Future<Map<String, OrderEditJournalRecord>> load(String scopeKey) async {
    final raw = _prefs.getString(_keyFor(scopeKey));
    if (raw == null || raw.isEmpty) {
      // ABSENT IS A VALID EMPTY JOURNAL — a till that never edited an order.
      return <String, OrderEditJournalRecord>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, OrderEditJournalRecord>{};
      if ((decoded['version'] as num?)?.toInt() != schemaVersion) {
        return <String, OrderEditJournalRecord>{};
      }
      final records = decoded['records'];
      if (records is! Map) return <String, OrderEditJournalRecord>{};
      final out = <String, OrderEditJournalRecord>{};
      for (final e in records.entries) {
        final v = e.value;
        if (v is! Map) continue;
        try {
          out[e.key.toString()] = OrderEditJournalRecord.fromJson(
            v.cast<String, Object?>(),
          );
        } catch (_) {
          // Broad by design (003B): a wrongly-TYPED value raises TypeError, not
          // FormatException, and letting it escape would empty the WHOLE
          // journal. One damaged record costs one record; `_quarantined`
          // preserves it.
        }
      }
      return out;
    } catch (_) {
      // An envelope this build cannot interpret at all. Its bytes are set
      // aside by `persist` before anything overwrites them.
      return <String, OrderEditJournalRecord>{};
    }
  }

  /// The raw records this build cannot decode, re-read from the CURRENT
  /// envelope on every write — not remembered from [load].
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
            OrderEditJournalRecord.fromJson(v.cast<String, Object?>());
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

  /// Copies an envelope this build cannot interpret to a sidecar key BEFORE
  /// the primary is overwritten. Fails CLOSED: when the copy cannot be made,
  /// [persist] throws rather than destroy evidence of an edit that may be live
  /// on the server.
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
        'an unreadable order edit journal could not be set aside, so it was '
        'not overwritten',
      );
    }
    _degraded = true;
    throw const PosPersistenceException(
      'too many unreadable order edit journals are already being held; '
      'refusing to overwrite another',
    );
  }

  @override
  Future<void> persist(
    String scopeKey,
    Map<String, OrderEditJournalRecord> records,
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
        'the order edit journal could not be persisted',
      );
    }
  }
}

/// An in-memory journal (tests). Session-only and honest about it.
class InMemoryOrderEditJournalStore implements OrderEditJournalStore {
  final Map<String, Map<String, OrderEditJournalRecord>> _data = {};

  @override
  Future<Map<String, OrderEditJournalRecord>> load(String scopeKey) async =>
      Map<String, OrderEditJournalRecord>.of(
        _data[scopeKey] ?? const <String, OrderEditJournalRecord>{},
      );

  @override
  Future<void> persist(
    String scopeKey,
    Map<String, OrderEditJournalRecord> records,
  ) async {
    _data[scopeKey] = Map<String, OrderEditJournalRecord>.of(records);
  }
}

/// The durable edit journal. Null by default (demo mode / tests, where edit
/// mode is never offered); `main.dart` overrides it for the real app.
final orderEditJournalStoreProvider = Provider<OrderEditJournalStore?>(
  (_) => null,
);
