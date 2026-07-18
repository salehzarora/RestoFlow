import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

import '../state/pos_session.dart';

/// PSC-001A — the typed client of `public.pos_ready_feed` (the PSC-001C
/// durable derived ready feed).
///
/// STRICT FAIL-CLOSED parse: a malformed envelope, row, or cursor throws —
/// the notification store must never learn a guessed identity, a coerced
/// work-unit type, or a cursor it cannot trust. The keyset cursor is an
/// OPAQUE server tuple: `ready_at` is round-tripped as the VERBATIM server
/// string (never re-formatted through a client DateTime, which could shift
/// precision and skip/duplicate rows on the tuple comparison).
class PosReadyCursor {
  const PosReadyCursor({
    required this.readyAt,
    required this.workUnitType,
    required this.id,
  });

  /// The server's `ready_at` string, VERBATIM (precision-preserving).
  final String readyAt;
  final String workUnitType;
  final String id;

  Map<String, Object?> toJson() => {
    'ready_at': readyAt,
    'work_unit_type': workUnitType,
    'id': id,
  };

  /// Fail-closed: all three fields present and well-formed, or null.
  static PosReadyCursor? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final readyAt = raw['ready_at'];
    final type = raw['work_unit_type'];
    final id = raw['id'];
    if (readyAt is! String ||
        readyAt.isEmpty ||
        DateTime.tryParse(readyAt) == null ||
        !kReadyWorkUnitTypes.contains(type) ||
        id is! String ||
        !kUuidPattern.hasMatch(id)) {
      return null;
    }
    return PosReadyCursor(
      readyAt: readyAt,
      workUnitType: type as String,
      id: id,
    );
  }
}

/// The closed work-unit-type vocabulary of the shipped feed.
const Set<String> kReadyWorkUnitTypes = {'initial_order', 'service_round'};

/// Canonical UUID shape — identities are real server rows, never fabricated.
final RegExp kUuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
  r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// One ready work unit as the feed reported it (safe fields only — no money,
/// no items, no payloads).
class PosReadyFeedRow {
  const PosReadyFeedRow({
    required this.workUnitType,
    required this.workUnitId,
    required this.orderId,
    required this.orderCode,
    required this.readyAt,
    required this.workUnitStatus,
    required this.parentOrderStatus,
    required this.revision,
    this.roundNumber,
    this.orderType,
    this.tableLabel,
  });

  final String workUnitType;
  final String workUnitId;
  final String orderId;
  final String orderCode;

  /// Null for the initial order; the round number (>= 2) for an addition.
  final int? roundNumber;
  final String? orderType;
  final String? tableLabel;

  /// The server's `ready_at` VERBATIM — the cursor-fidelity source.
  final String readyAt;
  final String workUnitStatus;
  final String parentOrderStatus;
  final int revision;

  /// The dedup identity — NEVER the order id alone (one order legitimately
  /// yields an initial unit plus Round 2, Round 3, ...).
  String get identityKey => '$workUnitType|$workUnitId';

  DateTime get readyAtTime => DateTime.parse(readyAt);

  /// Fail-closed: every required field present, typed, and in-vocabulary.
  static PosReadyFeedRow? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['work_unit_type'];
    final workUnitId = raw['work_unit_id'];
    final orderId = raw['order_id'];
    final orderCode = raw['order_code'];
    final roundNumber = raw['round_number'];
    final readyAt = raw['ready_at'];
    final workUnitStatus = raw['work_unit_status'];
    final parentStatus = raw['parent_order_status'];
    final revision = raw['revision'];
    if (!kReadyWorkUnitTypes.contains(type) ||
        workUnitId is! String ||
        !kUuidPattern.hasMatch(workUnitId) ||
        orderId is! String ||
        !kUuidPattern.hasMatch(orderId) ||
        orderCode is! String ||
        orderCode.isEmpty ||
        readyAt is! String ||
        readyAt.isEmpty ||
        DateTime.tryParse(readyAt) == null ||
        workUnitStatus is! String ||
        workUnitStatus.isEmpty ||
        parentStatus is! String ||
        parentStatus.isEmpty ||
        revision is! int ||
        revision < 1) {
      return null;
    }
    // An addition names its round (>= 2); the initial unit never does.
    if (type == 'service_round') {
      if (roundNumber is! int || roundNumber < 2) return null;
    } else if (roundNumber != null) {
      return null;
    }
    return PosReadyFeedRow(
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
    );
  }
}

/// One validated feed page.
class PosReadyFeedPage {
  const PosReadyFeedPage({
    required this.rows,
    required this.hasMore,
    required this.serverTs,
    this.nextCursor,
  });

  final List<PosReadyFeedRow> rows;
  final bool hasMore;

  /// The server's `server_ts` VERBATIM (the bootstrap baseline stamp).
  final String serverTs;
  final PosReadyCursor? nextCursor;
}

/// Why a feed read failed — the fail-closed taxonomy.
enum PosReadyFeedFailure {
  /// No usable session/device context, or the server refused the identity
  /// (`invalid_session` / `invalid_device_type` / `permission_denied`) —
  /// polling must STOP and defer to the existing reauth/scope-drop flow.
  session,

  /// The network/transport failed — retryable; the poll is the probe.
  transport,

  /// The server payload failed validation — nothing may be trusted or stored.
  malformed,

  /// The server refused the REQUEST shape (`invalid_cursor`/`invalid_limit`).
  /// Never silently restart with a null cursor — surface the degraded state.
  rejected,
}

class PosReadyFeedException implements Exception {
  const PosReadyFeedException(this.failure, [this.detail]);
  final PosReadyFeedFailure failure;
  final String? detail;
  @override
  String toString() => 'PosReadyFeedException(${failure.name}, $detail)';
}

abstract class ReadyFeedRepository {
  /// Fetches one feed page. [cursor] is all-three-or-none by construction.
  Future<PosReadyFeedPage> fetch({PosReadyCursor? cursor, int limit = 100});
}

/// The real read over `public.pos_ready_feed` (anon key + PIN/device session,
/// D-011 — the same authenticated transport every POS read rides).
class RealReadyFeedRepository implements ReadyFeedRepository {
  const RealReadyFeedRepository(this._transport, this._session);

  final SyncRpcTransport? _transport;
  final SyncSession? _session;

  @override
  Future<PosReadyFeedPage> fetch({
    PosReadyCursor? cursor,
    int limit = 100,
  }) async {
    final transport = _transport;
    final session = _session;
    if (transport == null || session == null) {
      throw const PosReadyFeedException(
        PosReadyFeedFailure.session,
        'no authenticated PIN session on a paired device',
      );
    }
    final Object? raw;
    try {
      raw = await transport.invoke('pos_ready_feed', <String, dynamic>{
        'p_pin_session_id': session.pinSessionId,
        'p_device_id': session.deviceId,
        'p_since_ready_at': cursor?.readyAt,
        'p_since_type': cursor?.workUnitType,
        'p_since_id': cursor?.id,
        'p_limit': limit,
      });
    } on SyncTransportException catch (e) {
      throw PosReadyFeedException(
        PosReadyFeedFailure.transport,
        e.code ?? e.kind.name,
      );
    }
    if (raw is! Map) {
      throw const PosReadyFeedException(PosReadyFeedFailure.malformed);
    }
    if (raw['ok'] != true) {
      final error = raw['error'];
      throw PosReadyFeedException(switch (error) {
        'invalid_cursor' || 'invalid_limit' => PosReadyFeedFailure.rejected,
        _ => PosReadyFeedFailure.session,
      }, error is String ? error : null);
    }
    final serverTs = raw['server_ts'];
    if (serverTs is! String || DateTime.tryParse(serverTs) == null) {
      throw const PosReadyFeedException(PosReadyFeedFailure.malformed);
    }
    final readyRaw = raw['ready'];
    final hasMore = raw['has_more'];
    if (readyRaw is! List || hasMore is! bool) {
      throw const PosReadyFeedException(PosReadyFeedFailure.malformed);
    }
    final rows = <PosReadyFeedRow>[];
    for (final e in readyRaw) {
      final row = PosReadyFeedRow.fromJson(e);
      // ATOMIC page: one malformed row rejects the page — a half-parsed page
      // would advance the cursor past rows that were never stored.
      if (row == null) {
        throw const PosReadyFeedException(PosReadyFeedFailure.malformed);
      }
      rows.add(row);
    }
    final nextCursorRaw = raw['next_cursor'];
    PosReadyCursor? nextCursor;
    if (nextCursorRaw != null) {
      nextCursor = PosReadyCursor.fromJson(nextCursorRaw);
      // A PARTIAL cursor is refused, never coerced (all-three-or-none).
      if (nextCursor == null) {
        throw const PosReadyFeedException(PosReadyFeedFailure.malformed);
      }
    }
    // A page that claims more but names no continuation cannot be followed.
    if (hasMore && nextCursor == null) {
      throw const PosReadyFeedException(PosReadyFeedFailure.malformed);
    }
    return PosReadyFeedPage(
      rows: rows,
      hasMore: hasMore,
      serverTs: serverTs,
      nextCursor: nextCursor,
    );
  }
}

/// Demo mode has no server feed; the bell simply shows its honest empty state
/// (the controller never polls in demo mode — this is the fail-closed floor).
class UnavailableReadyFeedRepository implements ReadyFeedRepository {
  const UnavailableReadyFeedRepository();
  @override
  Future<PosReadyFeedPage> fetch({PosReadyCursor? cursor, int limit = 100}) =>
      throw const PosReadyFeedException(
        PosReadyFeedFailure.session,
        'ready feed is unavailable in demo mode',
      );
}

final readyFeedRepositoryProvider = Provider<ReadyFeedRepository>((ref) {
  final cfg = ref.watch(runtimeConfigProvider);
  if (cfg.isDemoMode) return const UnavailableReadyFeedRepository();
  return RealReadyFeedRepository(
    ref.watch(posAuthTransportProvider),
    ref.watch(posSyncSessionProvider),
  );
});
