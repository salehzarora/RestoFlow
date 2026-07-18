import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ready_feed_repository.dart';
import 'sync_cursor_store.dart';

/// PSC-001A — the LOCAL persisted ready-notification state, one envelope per
/// operational scope (org/restaurant/branch/device — the exact
/// [PosSyncScope.key] convention every POS store uses).
///
/// The backend stores READINESS; this store owns everything per-device:
/// the durable feed cursor, discovered notification records, read/alerted
/// state, and the bootstrap marker. The whole envelope — cursor INCLUDED —
/// persists in ONE write, so the cursor structurally cannot advance past
/// records that were never stored.
///
/// SAFE FIELDS ONLY: identities, display context, timestamps, statuses,
/// local read state. Never a PIN, token, customer datum, payment, money
/// amount, raw RPC response, or item/modifier payload.
class PosReadyNotificationRecord {
  const PosReadyNotificationRecord({
    required this.workUnitType,
    required this.workUnitId,
    required this.orderId,
    required this.orderCode,
    required this.readyAt,
    required this.workUnitStatus,
    required this.parentOrderStatus,
    required this.revision,
    required this.discoveredAt,
    required this.read,
    required this.alerted,
    this.roundNumber,
    this.orderType,
    this.tableLabel,
  });

  final String workUnitType;
  final String workUnitId;
  final String orderId;
  final String orderCode;
  final int? roundNumber;
  final String? orderType;
  final String? tableLabel;

  /// The server's `ready_at`, VERBATIM (display parses it; ordering uses it).
  final String readyAt;
  final String workUnitStatus;
  final String parentOrderStatus;
  final int revision;

  /// When THIS device first discovered the row (local clock; display only).
  final String discoveredAt;

  /// STICKY local flags — an already-seen identity can never re-alert, and
  /// read state survives restarts.
  final bool read;
  final bool alerted;

  String get identityKey => '$workUnitType|$workUnitId';
  DateTime get readyAtTime => DateTime.parse(readyAt);
  bool get isServiceRound => workUnitType == 'service_round';

  PosReadyNotificationRecord copyWith({
    String? workUnitStatus,
    String? parentOrderStatus,
    int? revision,
    String? orderType,
    String? tableLabel,
    bool? read,
    bool? alerted,
  }) => PosReadyNotificationRecord(
    workUnitType: workUnitType,
    workUnitId: workUnitId,
    orderId: orderId,
    orderCode: orderCode,
    roundNumber: roundNumber,
    orderType: orderType ?? this.orderType,
    tableLabel: tableLabel ?? this.tableLabel,
    readyAt: readyAt,
    workUnitStatus: workUnitStatus ?? this.workUnitStatus,
    parentOrderStatus: parentOrderStatus ?? this.parentOrderStatus,
    revision: revision ?? this.revision,
    discoveredAt: discoveredAt,
    read: read ?? this.read,
    alerted: alerted ?? this.alerted,
  );

  Map<String, Object?> toJson() => {
    'work_unit_type': workUnitType,
    'work_unit_id': workUnitId,
    'order_id': orderId,
    'order_code': orderCode,
    'round_number': roundNumber,
    'order_type': orderType,
    'table_label': tableLabel,
    'ready_at': readyAt,
    'work_unit_status': workUnitStatus,
    'parent_order_status': parentOrderStatus,
    'revision': revision,
    'discovered_at': discoveredAt,
    'read': read,
    'alerted': alerted,
  };

  /// Fail-closed: a malformed record invalidates the envelope it rode in
  /// (the caller discards the whole envelope and re-bootstraps safely).
  static PosReadyNotificationRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['work_unit_type'];
    final workUnitId = raw['work_unit_id'];
    final orderId = raw['order_id'];
    final orderCode = raw['order_code'];
    final readyAt = raw['ready_at'];
    final workUnitStatus = raw['work_unit_status'];
    final parentStatus = raw['parent_order_status'];
    final revision = raw['revision'];
    final discoveredAt = raw['discovered_at'];
    final read = raw['read'];
    final alerted = raw['alerted'];
    if (!kReadyWorkUnitTypes.contains(type) ||
        workUnitId is! String ||
        orderId is! String ||
        orderCode is! String ||
        readyAt is! String ||
        DateTime.tryParse(readyAt) == null ||
        workUnitStatus is! String ||
        parentStatus is! String ||
        revision is! int ||
        discoveredAt is! String ||
        read is! bool ||
        alerted is! bool) {
      return null;
    }
    final roundNumber = raw['round_number'];
    return PosReadyNotificationRecord(
      workUnitType: type as String,
      workUnitId: workUnitId,
      orderId: orderId,
      orderCode: orderCode,
      roundNumber: roundNumber is int ? roundNumber : null,
      orderType: raw['order_type'] is String
          ? raw['order_type'] as String
          : null,
      tableLabel: raw['table_label'] is String
          ? raw['table_label'] as String
          : null,
      readyAt: readyAt,
      workUnitStatus: workUnitStatus,
      parentOrderStatus: parentStatus,
      revision: revision,
      discoveredAt: discoveredAt,
      read: read,
      alerted: alerted,
    );
  }
}

/// The per-scope persisted envelope.
///
/// `initialized` is the EXPLICIT bootstrap marker — a legitimate zero-row
/// bootstrap leaves `cursor` null while `initialized` is true, so cursor
/// presence is NEVER the first-run signal.
class PosReadyNotificationsEnvelope {
  const PosReadyNotificationsEnvelope({
    required this.initialized,
    required this.records,
    this.bootstrapServerTs,
    this.cursor,
  });

  final bool initialized;

  /// The `server_ts` of the FIRST successful bootstrap response — the
  /// baseline line: bootstrap rows at-or-before it are historical (read,
  /// no alert); rows after it became ready DURING bootstrap and alert.
  final String? bootstrapServerTs;
  final PosReadyCursor? cursor;
  final List<PosReadyNotificationRecord> records;

  static const PosReadyNotificationsEnvelope empty =
      PosReadyNotificationsEnvelope(initialized: false, records: []);

  Map<String, Object?> toJson() => {
    'version': SharedPrefsReadyNotificationsStore.schemaVersion,
    'initialized': initialized,
    'bootstrap_server_ts': bootstrapServerTs,
    'cursor': cursor?.toJson(),
    'records': [for (final r in records) r.toJson()],
  };
}

abstract class ReadyNotificationsStore {
  /// The envelope for [scope], or null when none/corrupt/wrong-version —
  /// null always means "start a fresh bootstrap", never "throw".
  Future<PosReadyNotificationsEnvelope?> load(PosSyncScope scope);

  /// Persists the WHOLE envelope (records + cursor + markers) in one write.
  /// THROWS [PosPersistenceException] when the write does not stick — a
  /// caller believing the cursor advanced when it did not would skip rows
  /// the server never offers again.
  Future<void> persist(PosSyncScope scope, PosReadyNotificationsEnvelope env);

  /// Forgets [scope]'s envelope only (used to recover from corruption).
  Future<void> clear(PosSyncScope scope);
}

/// In-memory store (demo mode / tests).
class InMemoryReadyNotificationsStore implements ReadyNotificationsStore {
  final Map<String, PosReadyNotificationsEnvelope> _byScope = {};

  @override
  Future<PosReadyNotificationsEnvelope?> load(PosSyncScope scope) async =>
      _byScope[scope.key];

  @override
  Future<void> persist(
    PosSyncScope scope,
    PosReadyNotificationsEnvelope env,
  ) async {
    _byScope[scope.key] = env;
  }

  @override
  Future<void> clear(PosSyncScope scope) async {
    _byScope.remove(scope.key);
  }
}

/// `shared_preferences`-backed store — one schema-versioned JSON envelope per
/// scope key (the exact recent-orders/cursor-store pattern).
class SharedPrefsReadyNotificationsStore implements ReadyNotificationsStore {
  SharedPrefsReadyNotificationsStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _prefix = 'restoflow.pos.ready_notifications.v1';
  static const int schemaVersion = 1;

  String _keyFor(PosSyncScope scope) => '$_prefix.${scope.key}';

  @override
  Future<PosReadyNotificationsEnvelope?> load(PosSyncScope scope) async {
    final raw = _prefs.getString(_keyFor(scope));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != schemaVersion) return null;
      final initialized = decoded['initialized'];
      if (initialized is! bool) return null;
      final bootstrapTs = decoded['bootstrap_server_ts'];
      final cursorRaw = decoded['cursor'];
      PosReadyCursor? cursor;
      if (cursorRaw != null) {
        cursor = PosReadyCursor.fromJson(cursorRaw);
        if (cursor == null) return null; // corrupt cursor = corrupt envelope
      }
      final recordsRaw = decoded['records'];
      if (recordsRaw is! List) return null;
      final records = <PosReadyNotificationRecord>[];
      for (final e in recordsRaw) {
        final record = PosReadyNotificationRecord.fromJson(e);
        // ATOMIC envelope: one corrupt record discards the whole envelope —
        // a fresh bootstrap (bounded by the server's 24h window) is strictly
        // safer than trusting a partially-readable local state.
        if (record == null) return null;
        records.add(record);
      }
      return PosReadyNotificationsEnvelope(
        initialized: initialized,
        bootstrapServerTs: bootstrapTs is String ? bootstrapTs : null,
        cursor: cursor,
        records: records,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> persist(
    PosSyncScope scope,
    PosReadyNotificationsEnvelope env,
  ) async {
    // setString can report FALSE without throwing (full disk, refused
    // localStorage). False is a failure and is reported as one — the caller
    // must not let its in-memory cursor outrun the durable envelope.
    final ok = await _prefs.setString(_keyFor(scope), jsonEncode(env.toJson()));
    if (!ok) {
      throw const PosPersistenceException(
        'ready notifications could not be persisted',
      );
    }
  }

  @override
  Future<void> clear(PosSyncScope scope) =>
      _prefs.remove(_keyFor(scope)).then((_) {});
}

/// Default in-memory (demo/tests); `main.dart` overrides with the
/// SharedPreferences store after preferences load.
final readyNotificationsStoreProvider = Provider<ReadyNotificationsStore>(
  (ref) => InMemoryReadyNotificationsStore(),
);
