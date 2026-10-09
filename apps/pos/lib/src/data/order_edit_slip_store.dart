import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show OrderChangeSlipView;
import 'package:shared_preferences/shared_preferences.dart';

import 'local_storage_health.dart';
import 'order_edit_slip.dart';
import 'sync_cursor_store.dart' show PosPersistenceException;

/// ORDER-EDIT-001F — the durable store of UNSENT paper change slips (design
/// §7.3 "durable backup"), patterned on the 001E edit journal
/// (`order_edit_journal_store.dart`): one schema-versioned SharedPreferences
/// envelope per device scope, STRICT decode, VERBATIM quarantine of anything
/// this build cannot read, and a typed [PosPersistenceException] when a write
/// does not stick.
///
/// A record exists only while its slip is NOT yet on paper: a slip that was
/// sent, handed over to the spool, superseded or retired is REMOVED, never
/// kept in a terminal state. "Unbuilt" (no [OrderEditSlipRecord.slip]) means
/// the till could not hand-build the slip — its banner still offers Print
/// again, which builds it from [OrderEditSlipRecord.was] and
/// [OrderEditSlipRecord.lines] plus a fresh detail.
///
/// MONEY-FREE (SECURITY T-003, D-007): every key avoids the money and the
/// hostile kitchen vocabulary, and no `_minor` key exists — the frozen
/// request payload (which carries the expected totals) is deliberately NOT
/// stored here; only its money-free slip lines are.
enum OrderEditSlipState {
  /// Recorded; the direct print has not been attempted (or is in flight).
  pending,

  /// The last direct attempt did not reach the printer.
  failed,
}

/// One unsent change slip, keyed by its `order_edit_id`.
class OrderEditSlipRecord {
  const OrderEditSlipRecord({
    required this.orderEditId,
    required this.orderId,
    required this.orderCode,
    required this.editNumber,
    required this.updatedAt,
    this.dispatchId,
    this.editCreatedAt,
    this.slip,
    this.was = const <String, OrderEditSlipItem>{},
    this.lines = const <OrderEditSlipLine>[],
    this.staffFirstName,
    this.state = OrderEditSlipState.pending,
    this.attempts = 0,
  });

  final String orderEditId;
  final String orderId;

  /// The order's display code, already prefixed with '#'.
  final String orderCode;

  /// "Change N".
  final int editNumber;

  /// The paper `order_edit` dispatch born claimed by this POS, or null when
  /// the envelope carried none (the slip then prints with no acknowledgement).
  final String? dispatchId;

  /// The edit's SERVER creation instant (`pos_order_detail.edits[]`), the
  /// ordering evidence of the local supersession sweep. Null until known.
  final DateTime? editCreatedAt;

  /// The hand-built slip; null while UNBUILT.
  final OrderChangeSlipView? slip;

  /// The frozen "was" projections (lower-case `order_item_id` keys) and the
  /// zipped slip lines — the inputs to build an unbuilt slip later.
  final Map<String, OrderEditSlipItem> was;
  final List<OrderEditSlipLine> lines;

  /// The acting worker's first name, as the slip prints it.
  final String? staffFirstName;

  final OrderEditSlipState state;

  /// Direct print attempts so far.
  final int attempts;
  final DateTime updatedAt;

  bool get isBuilt => slip != null;

  OrderEditSlipRecord copyWith({
    OrderChangeSlipView? slip,
    DateTime? editCreatedAt,
    OrderEditSlipState? state,
    int? attempts,
    DateTime? updatedAt,
  }) => OrderEditSlipRecord(
    orderEditId: orderEditId,
    orderId: orderId,
    orderCode: orderCode,
    editNumber: editNumber,
    dispatchId: dispatchId,
    editCreatedAt: editCreatedAt ?? this.editCreatedAt,
    slip: slip ?? this.slip,
    was: was,
    lines: lines,
    staffFirstName: staffFirstName,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'order_edit_id': orderEditId,
    'order_id': orderId,
    'order_code': orderCode,
    'edit_number': editNumber,
    if (dispatchId != null) 'dispatch_id': dispatchId,
    if (editCreatedAt != null)
      'edit_created_at': editCreatedAt!.toUtc().toIso8601String(),
    if (slip != null) 'slip': encodeOrderChangeSlipView(slip!),
    'was': <Object?>[
      for (final e in was.entries)
        <String, Object?>{'order_item_id': e.key, 'item': e.value.toJson()},
    ],
    'edit_lines': <Object?>[for (final l in lines) l.toJson()],
    if (staffFirstName != null) 'staff_first_name': staffFirstName,
    'state': state.name,
    'attempts': attempts,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  /// STRICT: anything this build did not write exactly — an unknown key, a
  /// wrong type, a slip of another order or number — throws
  /// [FormatException] naming the key (never a value), and the store
  /// quarantines the record VERBATIM.
  factory OrderEditSlipRecord.fromJson(Map<String, Object?> json) {
    const known = {
      'order_edit_id',
      'order_id',
      'order_code',
      'edit_number',
      'dispatch_id',
      'edit_created_at',
      'slip',
      'was',
      'edit_lines',
      'staff_first_name',
      'state',
      'attempts',
      'updated_at',
    };
    for (final key in json.keys) {
      if (!known.contains(key)) {
        throw FormatException('order edit slip record: unknown key $key');
      }
    }
    Never bad(String key) =>
        throw FormatException('order edit slip record: $key');
    String requireString(String key) {
      final v = json[key];
      return v is String && v.trim().isNotEmpty ? v : bad(key);
    }

    String? optionalString(String key) {
      final v = json[key];
      if (v == null) return null;
      return v is String && v.trim().isNotEmpty ? v : bad(key);
    }

    DateTime? optionalTime(String key) {
      final v = optionalString(key);
      if (v == null) return null;
      return DateTime.tryParse(v) ?? bad(key);
    }

    final orderCode = requireString('order_code');
    final editNumber = json['edit_number'];
    if (editNumber is! int || editNumber < 1) bad('edit_number');
    final attempts = json['attempts'];
    if (attempts is! int || attempts < 0) bad('attempts');
    final state = OrderEditSlipState.values
        .where((s) => s.name == json['state'])
        .firstOrNull;
    if (state == null) bad('state');
    final updatedAt = optionalTime('updated_at') ?? bad('updated_at');

    final slipRaw = json['slip'];
    final slip = slipRaw == null ? null : decodeOrderChangeSlipView(slipRaw);
    if (slip != null &&
        (slip.orderCode != orderCode || slip.editNumber != editNumber)) {
      bad('slip');
    }

    final wasRaw = json['was'];
    if (wasRaw is! List) bad('was');
    final was = <String, OrderEditSlipItem>{};
    for (final e in wasRaw) {
      if (e is! Map || e.length != 2) bad('was');
      final id = e['order_item_id'];
      if (id is! String || id.isEmpty) bad('was');
      was[id.toLowerCase()] = OrderEditSlipItem.fromJson(e['item']);
    }
    final linesRaw = json['edit_lines'];
    if (linesRaw is! List) bad('edit_lines');

    return OrderEditSlipRecord(
      orderEditId: requireString('order_edit_id'),
      orderId: requireString('order_id'),
      orderCode: orderCode,
      editNumber: editNumber,
      dispatchId: optionalString('dispatch_id'),
      editCreatedAt: optionalTime('edit_created_at'),
      slip: slip,
      was: was,
      lines: [for (final l in linesRaw) OrderEditSlipLine.fromJson(l)],
      staffFirstName: optionalString('staff_first_name'),
      state: state,
      attempts: attempts,
      updatedAt: updatedAt,
    );
  }
}

/// ORDER-EDIT-001F — evidence that THIS till put an edit's slip on paper
/// directly: the order, the (completed) dispatch and the edit's SERVER
/// creation instant. Its dispatch is completed by the direct print and never
/// reaches the spool, so without this the local supersession sweep could not
/// retire this till's own older kitchen jobs of the order. Money-free.
class OrderEditSlipEvidence {
  const OrderEditSlipEvidence({
    required this.orderId,
    required this.editCreatedAt,
    required this.recordedAt,
    this.dispatchId,
  });

  final String orderId;
  final String? dispatchId;
  final DateTime editCreatedAt;

  /// When this till recorded it — the TTL clock.
  final DateTime recordedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'order_id': orderId,
    if (dispatchId != null) 'dispatch_id': dispatchId,
    'edit_created_at': editCreatedAt.toUtc().toIso8601String(),
    'recorded_at': recordedAt.toUtc().toIso8601String(),
  };

  /// Null for anything this build did not write exactly.
  static OrderEditSlipEvidence? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final orderId = raw['order_id'];
    final dispatchId = raw['dispatch_id'];
    final created = raw['edit_created_at'];
    final recorded = raw['recorded_at'];
    if (orderId is! String ||
        orderId.isEmpty ||
        (dispatchId != null && (dispatchId is! String || dispatchId.isEmpty)) ||
        created is! String ||
        recorded is! String ||
        raw.keys.any(
          (k) => !const {
            'order_id',
            'dispatch_id',
            'edit_created_at',
            'recorded_at',
          }.contains(k),
        )) {
      return null;
    }
    final createdAt = DateTime.tryParse(created);
    final recordedAt = DateTime.tryParse(recorded);
    if (createdAt == null || recordedAt == null) return null;
    return OrderEditSlipEvidence(
      orderId: orderId,
      dispatchId: dispatchId as String?,
      editCreatedAt: createdAt,
      recordedAt: recordedAt,
    );
  }
}

/// How long direct-print evidence is kept, and at most how many entries.
const Duration kOrderEditSlipEvidenceTtl = Duration(hours: 72);
const int kOrderEditSlipEvidenceCap = 200;

/// Durable persistence for unsent change slips and direct-print evidence.
abstract class OrderEditSlipStore {
  /// Every readable unsent slip, keyed by `order_edit_id`. Never throws — an
  /// unreadable record is quarantined, not surfaced.
  Future<Map<String, OrderEditSlipRecord>> load(String scopeKey);

  /// Replaces the persisted set for [scopeKey]. THROWS
  /// [PosPersistenceException] when the write does not stick: a slip that
  /// could not be recorded must not be printed as if it were (claim before
  /// send).
  Future<void> persist(
    String scopeKey,
    Map<String, OrderEditSlipRecord> records,
  );

  /// The live direct-print evidence (younger than [kOrderEditSlipEvidenceTtl]
  /// at [now]), oldest first. Never throws.
  Future<List<OrderEditSlipEvidence>> loadEvidence(
    String scopeKey, {
    required DateTime now,
  });

  /// Appends [entry], dropping expired entries and keeping at most
  /// [kOrderEditSlipEvidenceCap] (the newest). THROWS
  /// [PosPersistenceException] when the write does not stick.
  Future<void> appendEvidence(
    String scopeKey,
    OrderEditSlipEvidence entry, {
    required DateTime now,
  });
}

List<OrderEditSlipEvidence> _liveEvidence(
  Iterable<OrderEditSlipEvidence> all,
  DateTime now,
) {
  final cutoff = now.toUtc().subtract(kOrderEditSlipEvidenceTtl);
  final live = [
    for (final e in all)
      if (e.recordedAt.toUtc().isAfter(cutoff)) e,
  ]..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
  return live.length <= kOrderEditSlipEvidenceCap
      ? live
      : live.sublist(live.length - kOrderEditSlipEvidenceCap);
}

/// A `shared_preferences`-backed slip store: one schema-versioned envelope
/// `{version, records:{orderEditId:{…}}}` PER DEVICE scope (one device never
/// prints another's slip) and a separate bounded evidence envelope
/// `{version, evidence:[…]}`.
class SharedPrefsOrderEditSlipStore
    implements OrderEditSlipStore, PosDurableStoreHealth {
  SharedPrefsOrderEditSlipStore(this._prefs, {String keyPrefix = _prefix})
    : _keyPrefix = keyPrefix;

  final SharedPreferences _prefs;
  final String _keyPrefix;

  static const String _prefix = 'restoflow.pos.order_edit_slips.v1';
  static const String _evidencePrefix =
      'restoflow.pos.order_edit_slip_evidence.v1';

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

  /// Its own prefix, so no scope key can ever name another scope's records.
  String _evidenceKey(String scopeKey) {
    final safe = scopeKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty ? _evidencePrefix : '$_evidencePrefix.$safe';
  }

  String _preservedKey(String scopeKey, int slot) => slot == 0
      ? '${_keyFor(scopeKey)}.unreadable'
      : '${_keyFor(scopeKey)}.unreadable.${slot + 1}';

  @override
  Future<Map<String, OrderEditSlipRecord>> load(String scopeKey) async {
    final raw = _prefs.getString(_keyFor(scopeKey));
    // ABSENT IS A VALID EMPTY STORE — a till that never printed a slip.
    if (raw == null || raw.isEmpty) return <String, OrderEditSlipRecord>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, OrderEditSlipRecord>{};
      if ((decoded['version'] as num?)?.toInt() != schemaVersion) {
        return <String, OrderEditSlipRecord>{};
      }
      final records = decoded['records'];
      if (records is! Map) return <String, OrderEditSlipRecord>{};
      final out = <String, OrderEditSlipRecord>{};
      for (final e in records.entries) {
        final v = e.value;
        if (v is! Map) continue;
        try {
          final record = OrderEditSlipRecord.fromJson(
            v.cast<String, Object?>(),
          );
          // The key IS the identity: a record filed under another edit's id
          // is not this build's write.
          if (record.orderEditId != e.key.toString()) continue;
          out[record.orderEditId] = record;
        } catch (_) {
          // Broad by design (the journal's rule): one damaged record costs
          // one record, and `_quarantined` preserves it verbatim.
        }
      }
      return out;
    } catch (_) {
      return <String, OrderEditSlipRecord>{};
    }
  }

  bool _readable(String key, Object? value) {
    if (value is! Map) return false;
    try {
      return OrderEditSlipRecord.fromJson(
            value.cast<String, Object?>(),
          ).orderEditId ==
          key;
    } catch (_) {
      return false;
    }
  }

  /// The raw records this build cannot decode, re-read from the CURRENT
  /// envelope on every write.
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
        if (_readable(key, e.value)) continue; // the caller owns it
        out[key] = e.value;
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
  /// the primary is overwritten; fails CLOSED when it cannot.
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
        'an unreadable change-slip store could not be set aside, so it was '
        'not overwritten',
      );
    }
    _degraded = true;
    throw const PosPersistenceException(
      'too many unreadable change-slip stores are already being held; '
      'refusing to overwrite another',
    );
  }

  @override
  Future<void> persist(
    String scopeKey,
    Map<String, OrderEditSlipRecord> records,
  ) async {
    await _preserveUnreadableEnvelope(scopeKey);
    // BUILD + SERIALIZE FIRST: an unencodable record fails here, before the
    // durable store is touched.
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
        'the change-slip store could not be persisted',
      );
    }
  }

  /// Evidence is ADVISORY and bounded (72 h, at most 200): an entry this
  /// build cannot read is dropped at the next write rather than quarantined —
  /// it can only make the local sweep KEEP a job, the pre-001F behaviour.
  List<OrderEditSlipEvidence> _readEvidence(String scopeKey) {
    final raw = _prefs.getString(_evidenceKey(scopeKey));
    if (raw == null || raw.isEmpty) return const <OrderEditSlipEvidence>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          (decoded['version'] as num?)?.toInt() != schemaVersion) {
        return const <OrderEditSlipEvidence>[];
      }
      final list = decoded['evidence'];
      if (list is! List) return const <OrderEditSlipEvidence>[];
      return [
        for (final e in list)
          if (OrderEditSlipEvidence.tryParse(e) case final ev?) ev,
      ];
    } catch (_) {
      return const <OrderEditSlipEvidence>[];
    }
  }

  @override
  Future<List<OrderEditSlipEvidence>> loadEvidence(
    String scopeKey, {
    required DateTime now,
  }) async => _liveEvidence(_readEvidence(scopeKey), now);

  @override
  Future<void> appendEvidence(
    String scopeKey,
    OrderEditSlipEvidence entry, {
    required DateTime now,
  }) async {
    final next = _liveEvidence([..._readEvidence(scopeKey), entry], now);
    final ok = await _prefs.setString(
      _evidenceKey(scopeKey),
      jsonEncode(<String, Object?>{
        'version': schemaVersion,
        'evidence': [for (final e in next) e.toJson()],
      }),
    );
    if (!ok) {
      _degraded = true;
      throw const PosPersistenceException(
        'the change-slip evidence could not be persisted',
      );
    }
  }
}

/// An in-memory slip store (tests). Session-only and honest about it.
class InMemoryOrderEditSlipStore implements OrderEditSlipStore {
  final Map<String, Map<String, OrderEditSlipRecord>> _data = {};
  final Map<String, List<OrderEditSlipEvidence>> _evidence = {};

  @override
  Future<Map<String, OrderEditSlipRecord>> load(String scopeKey) async =>
      Map<String, OrderEditSlipRecord>.of(
        _data[scopeKey] ?? const <String, OrderEditSlipRecord>{},
      );

  @override
  Future<void> persist(
    String scopeKey,
    Map<String, OrderEditSlipRecord> records,
  ) async {
    _data[scopeKey] = Map<String, OrderEditSlipRecord>.of(records);
  }

  @override
  Future<List<OrderEditSlipEvidence>> loadEvidence(
    String scopeKey, {
    required DateTime now,
  }) async => _liveEvidence(_evidence[scopeKey] ?? const [], now);

  @override
  Future<void> appendEvidence(
    String scopeKey,
    OrderEditSlipEvidence entry, {
    required DateTime now,
  }) async {
    _evidence[scopeKey] = _liveEvidence([...?_evidence[scopeKey], entry], now);
  }
}

/// The durable change-slip store. Null by default (demo mode / tests, where
/// no paper edit is ever printed); `main.dart` overrides it for the real app.
final orderEditSlipStoreProvider = Provider<OrderEditSlipStore?>((_) => null);
