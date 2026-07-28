import 'dart:convert';

import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'customer_phone.dart';
import 'durable_outbox_store.dart';
import 'order_submission.dart';

/// Thrown when an order submission cannot be built or enqueued.
class OrderSubmissionException implements Exception {
  const OrderSubmissionException(this.message);
  final String message;
  @override
  String toString() => 'OrderSubmissionException: $message';
}

/// The client OUTBOX seam (RF-115). Each method maps 1:1 to the production
/// outbox + push engine:
///  * [enqueue]      → `LocalDatabase.enqueueOperation` (an `OutboxOperations`
///                     row keyed by `(deviceId, localOperationId)`, DECISION D-022).
///  * [recentEntries]→ a query of the most recent outbox rows for the UI.
///  * [push]         → the RF-056 push engine calling `app.submit_order` (RF-052).
///  * [retry]        → re-queue a failed (rejected/dead) entry for another push.
///
/// Implemented here ONLY by the in-memory [DemoOutboxStore]; the real
/// `data_local`-backed implementation lands with the device/PIN-session auth
/// bridge. Nothing here contacts a backend.
abstract class OutboxRepository {
  /// Enqueues [entry] (idempotent on `(deviceId, localOperationId)`), returning
  /// the stored entry — `pending`/`created` until pushed.
  Future<OutboxEntry> enqueue(OutboxEntry entry);

  /// The outbox entries, most recent first.
  Future<List<OutboxEntry>> recentEntries();

  /// Attempts to deliver the entry. DEMO ONLY — simulates the push outcome; it
  /// does NOT contact a backend.
  Future<OutboxEntry> push(String entryId);

  /// Re-queues a failed entry back to `pending` so it can be pushed again.
  Future<OutboxEntry> retry(String entryId);

  /// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 2): the customer phone from the
  /// DURABLE `order.submit` operation identified by [key] — persisted BEFORE the
  /// network push, so it is available for the encrypted kitchen spool even when
  /// the server dispatch is imported before the order reaches recent-orders.
  ///
  /// FULLY SCOPED (Codex HIGH): a match requires the op's organization, restaurant,
  /// branch, AND device to equal the caller's live scope, the op type to be
  /// `order.submit`, and the order identity (`targetId` + payload `order_id`, plus
  /// `local_operation_id` when the key carries it) to match — never a loose
  /// single-field or cross-restaurant/branch/device match, never a "first order id"
  /// guess. The recovered phone is passed through the ONE shared
  /// [normalizeCustomerPhone] validator, so a malformed durable value (e.g. one
  /// containing letters) can never enter the encrypted spool or a printed ticket.
  /// Returns the normalized phone for exactly one authoritative match, else null
  /// (ambiguity resolves to null safely; never a throw, never a logged phone).
  Future<String?> findOrderSubmitCustomerPhone(OrderSubmitPhoneLookupKey key);
}

/// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 2, Codex HIGH): the fully-scoped,
/// authoritative identity of the durable `order.submit` op whose phone may seed
/// the encrypted kitchen spool. The scope fields come from the LIVE imported
/// dispatch/job context (never mutable global state); [localOperationId] is set
/// only when the contract carries it (the pulled dispatch does not).
class OrderSubmitPhoneLookupKey {
  const OrderSubmitPhoneLookupKey({
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.deviceId,
    required this.orderId,
    this.localOperationId,
  });

  final String organizationId;
  final String restaurantId;
  final String branchId;
  final String deviceId;
  final String orderId;
  final String? localOperationId;
}

/// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 2, Codex HIGH): read the customer
/// phone from the durable `order.submit` outbox entry that EXACTLY matches [key].
/// Shared, side-effect-free, and defensive. Matching is all-of:
///   * `operation_type == 'order.submit'`
///   * organization / restaurant / branch / device all equal the key's scope
///   * `targetId == key.orderId` AND payload `order_id == key.orderId`
///   * `local_operation_id == key.localOperationId` when the key carries one
/// The matched op's phone is passed through [normalizeCustomerPhone] (the ONE
/// shared validator), so a blank / non-string / letters / control / short / long
/// value yields null. More than one exact match (ambiguity) resolves to null.
String? customerPhoneFromOrderSubmitEntries(
  Iterable<OutboxEntry> entries,
  OrderSubmitPhoneLookupKey key,
) {
  String? found;
  var matches = 0;
  for (final e in entries) {
    if (e.operationType != 'order.submit') continue;
    if (e.organizationId != key.organizationId) continue;
    if (e.restaurantId != key.restaurantId) continue;
    if (e.branchId != key.branchId) continue;
    if (e.deviceId != key.deviceId) continue;
    if (e.targetId != key.orderId) continue;
    if (key.localOperationId != null &&
        e.localOperationId != key.localOperationId) {
      continue;
    }
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(e.payloadJson);
      if (decoded is! Map<String, dynamic>) continue;
      body = decoded;
    } on FormatException {
      continue;
    }
    // The payload's OWN order identity must also match (defence beyond targetId).
    if (body['order_id'] != key.orderId) continue;
    // VALIDATE through the shared normalizer — an invalid durable phone is null,
    // never a raw value that could reach the encrypted spool / printed ticket.
    final raw = body['customer_phone'];
    matches++;
    found = normalizeCustomerPhone(raw is String ? raw : null);
  }
  // Exactly one authoritative match may supply a phone; ambiguity -> null.
  return matches == 1 ? found : null;
}

/// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 4): the CANONICAL identity payload
/// for an operation — the subset the server hashes into the idempotency
/// fingerprint. `customer_phone` is DATA ONLY on an `order.submit`: it rides the
/// transport payload for persistence but is EXCLUDED from the operation IDENTITY,
/// so re-sending the same `(device, local_operation_id)` op with only a different
/// phone is an idempotent replay (the first stored phone is kept), never a
/// conflict. Every other field, and every other operation type, is unchanged.
/// Mirrors `app.sync_push`'s `v_payload - 'customer_phone'` rule; this is the ONE
/// place the client expresses it (no inline key removal scattered elsewhere).
Map<String, dynamic> canonicalOperationIdentityPayload(
  String operationType,
  Map<String, dynamic> payload,
) {
  if (operationType != 'order.submit') return payload;
  if (!payload.containsKey('customer_phone')) return payload;
  return <String, dynamic>{
    for (final entry in payload.entries)
      if (entry.key != 'customer_phone') entry.key: entry.value,
  };
}

/// A stable identity KEY for local duplicate detection — the client mirror of the
/// server fingerprint's INPUT. (It is NOT claimed to be byte-identical to the
/// server md5; the server remains authoritative.) Two `order.submit` ops that
/// differ ONLY in `customer_phone` produce the SAME key; a change to any other
/// field, or any non-`order.submit` op, produces a different key. The transport
/// payload (which still carries the phone) is unaffected.
String operationIdentityKey(
  String operationType,
  Map<String, dynamic> payload,
) {
  final identity = canonicalOperationIdentityPayload(operationType, payload);
  final sortedKeys = identity.keys.toList()..sort();
  return '$operationType|'
      '${jsonEncode(<String, dynamic>{for (final k in sortedKeys) k: identity[k]})}';
}

/// In-memory, clearly-labelled DEMO outbox (RF-115). Holds enqueued order
/// submissions and simulates the sync lifecycle (pending → in-flight →
/// applied / rejected). NO backend, NO persistence — the order body is the real
/// `submit_order`-shaped JSON, but it is never sent anywhere.
class DemoOutboxStore implements OutboxRepository {
  DemoOutboxStore({
    Future<void> Function(Duration)? delay,
    this.pushDelay = const Duration(milliseconds: 600),
    this.enqueueFails = false,
  }) : _delay = delay ?? Future<void>.delayed;

  final Future<void> Function(Duration) _delay;
  final Duration pushDelay;

  /// When true, [enqueue] throws — used to exercise the "enqueue failed, keep
  /// the cart" path. (No real backend can fail here.)
  final bool enqueueFails;

  /// When true, the NEXT [push] simulates a transient delivery failure, then
  /// resets. Lets a demo/test show the failed → retry → synced lifecycle.
  bool nextPushFails = false;

  final List<OutboxEntry> _entries = <OutboxEntry>[];

  @override
  Future<OutboxEntry> enqueue(OutboxEntry entry) async {
    if (enqueueFails) {
      throw const OrderSubmissionException('demo enqueue failed');
    }
    // Idempotency: at most one row per (deviceId, localOperationId) — mirrors the
    // production UNIQUE constraint (DECISION D-022). A duplicate returns the
    // already-stored entry instead of adding a second.
    for (final e in _entries) {
      if (e.deviceId == entry.deviceId &&
          e.localOperationId == entry.localOperationId) {
        return e;
      }
    }
    _entries.add(entry);
    return entry;
  }

  @override
  Future<List<OutboxEntry>> recentEntries() async =>
      List.unmodifiable(_entries.reversed);

  @override
  Future<OutboxEntry> push(String entryId) async {
    final idx = _indexOf(entryId);
    await _delay(pushDelay);
    final current = _entries[idx];
    final fail = nextPushFails;
    nextPushFails = false;
    final updated = fail
        ? current.copyWith(
            syncState: OutboxSyncState.rejected,
            attemptCount: current.attemptCount + 1,
            lastErrorCode: 'demo_transient',
          )
        : current.copyWith(
            syncState: OutboxSyncState.applied,
            attemptCount: current.attemptCount + 1,
            clearError: true,
          );
    _entries[idx] = updated;
    return updated;
  }

  @override
  Future<OutboxEntry> retry(String entryId) async {
    final idx = _indexOf(entryId);
    final current = _entries[idx];
    if (!current.syncState.isFailed) return current;
    final updated = current.copyWith(
      syncState: OutboxSyncState.pending,
      clearError: true,
    );
    _entries[idx] = updated;
    return updated;
  }

  @override
  Future<String?> findOrderSubmitCustomerPhone(
    OrderSubmitPhoneLookupKey key,
  ) async => customerPhoneFromOrderSubmitEntries(_entries, key);

  int _indexOf(String entryId) {
    for (var i = 0; i < _entries.length; i++) {
      if (_entries[i].id == entryId) return i;
    }
    throw OrderSubmissionException('unknown outbox entry: $entryId');
  }
}

/// REAL client outbox repository (M7 / RF-129). Selected by
/// `runtimeConfigProvider` in real mode. It delivers each queued order via the
/// RF-126 `public.sync_push` wrapper (an `order.submit` op dispatched server-side
/// to `app.submit_order`, RF-052), reusing the shared public-schema
/// [SyncRpcTransport] (anon key + the signed-in JWT; never the `app` schema,
/// never a service-role key).
///
/// FAIL-CLOSED: `public.sync_push` requires a valid PIN session on a paired,
/// active device ([SyncSession] = `pinSessionId` + `deviceId`). Until the
/// PIN/device sign-in flow establishes one, [_session] (and/or [_transport]) is
/// null and EVERY method throws [OrderSubmissionException] - no order is queued
/// or sent, so there is no false "live" submit.
///
/// SCOPE: this holds queued entries in memory; durable local persistence
/// (`data_local` Drift `OutboxOperations`, D-022) is a separate step. The
/// `order.submit` op payload carries NO org/restaurant/branch/device - the
/// server derives tenant scope from the session - so no demo tenant value is
/// ever transmitted; the idempotency identity is the session device + the
/// entry's `local_operation_id` (D-022). Money stays integer minor units (D-007;
/// values are passed through verbatim from the captured snapshot - no float).
class RealOutboxRepository implements OutboxRepository {
  RealOutboxRepository(
    this._transport,
    this._session, {
    DurableOutboxStore? store,
  }) : _store = store;

  /// The shared public-schema RPC transport, or null when real mode was selected
  /// but the Supabase config was missing/invalid (fail-closed).
  final SyncRpcTransport? _transport;

  /// The authenticated PIN/device session, or null until the sign-in flow wires
  /// one (fail-closed: no session => no real submit).
  final SyncSession? _session;

  /// RF-114: the durable store the queue is loaded from + persisted to (survives
  /// refresh/restart). Null => in-memory only (existing tests / no store wired).
  final DurableOutboxStore? _store;

  /// Queued entries, LAZILY loaded from [_store] on first access (RF-114). Null
  /// until loaded so a fresh repo picks up orders queued before a refresh/restart.
  List<OutboxEntry>? _entries;

  /// RF-114 scope binding: the durable queue is keyed by THIS session's device
  /// id, so a re-paired-as-new device (a different deviceId) never loads or
  /// submits another device's queued orders. Only reached after [_ensureReady].
  String get _scopeKey => _session!.deviceId;

  /// Loads the durable queue once (per repo instance). Cheap no-op thereafter.
  Future<void> _ensureLoaded() async {
    final store = _store;
    _entries ??= store == null ? <OutboxEntry>[] : await store.load(_scopeKey);
  }

  /// Writes the current queue back to the durable store (no-op when in-memory).
  Future<void> _persist() async {
    final store = _store;
    if (store != null) {
      await store.persist(_scopeKey, _entries ?? const <OutboxEntry>[]);
    }
  }

  bool get _ready => _transport != null && _session != null;

  void _ensureReady() {
    if (!_ready) {
      throw const OrderSubmissionException(
        'real outbox unavailable: an authenticated PIN session on a paired, '
        'active device is required (sign-in flow not wired yet) - failing '
        'closed, no order is submitted.',
      );
    }
  }

  @override
  Future<OutboxEntry> enqueue(OutboxEntry entry) async {
    _ensureReady();
    await _ensureLoaded();
    final entries = _entries!;
    // Idempotency: at most one row per (deviceId, localOperationId) - mirrors the
    // server transport identity (DECISION D-022). A duplicate returns the stored
    // entry instead of adding a second.
    for (final e in entries) {
      if (e.deviceId == entry.deviceId &&
          e.localOperationId == entry.localOperationId) {
        return e;
      }
    }
    entries.add(entry);
    await _persist();
    return entry;
  }

  @override
  Future<List<OutboxEntry>> recentEntries() async {
    _ensureReady();
    await _ensureLoaded();
    return List.unmodifiable(_entries!.reversed);
  }

  @override
  Future<OutboxEntry> push(String entryId) async {
    _ensureReady();
    await _ensureLoaded();
    final transport = _transport!;
    final session = _session!;
    final idx = _indexOf(entryId);
    final entry = _entries![idx];

    // RF-114 scope guard (defence in depth beyond the per-device store key): an
    // order queued for a DIFFERENT device MUST NOT be submitted under this
    // session (e.g. it survived an unpair/re-pair as a new device). Mark it
    // `conflict` so the UI surfaces "attention needed" — never silently sent to
    // the wrong device/branch, never faked as synced, never deleted here.
    if (entry.deviceId != session.deviceId) {
      final stale = entry.copyWith(
        syncState: OutboxSyncState.conflict,
        attemptCount: entry.attemptCount + 1,
        lastErrorCode: 'device_scope_mismatch',
      );
      _entries![idx] = stale;
      await _persist();
      return stale;
    }

    OutboxEntry updated;
    try {
      final raw = await transport.invoke('sync_push', <String, dynamic>{
        'p_pin_session_id': session.pinSessionId,
        'p_device_id': session.deviceId,
        'p_operations': <dynamic>[_buildOrderSubmitOp(entry)],
      });
      updated = _applyPushResult(entry, raw);
    } on SyncTransportException catch (e) {
      // A whole-batch failure (e.g. 42501 - revoked device / expired PIN
      // session) marks the entry rejected so the cashier sees failed -> retry.
      // Carry only the error code, never raw backend text.
      updated = entry.copyWith(
        syncState: OutboxSyncState.rejected,
        attemptCount: entry.attemptCount + 1,
        lastErrorCode: e.code ?? e.kind.name,
      );
    }
    _entries![idx] = updated;
    await _persist();
    return updated;
  }

  @override
  Future<OutboxEntry> retry(String entryId) async {
    _ensureReady();
    await _ensureLoaded();
    final idx = _indexOf(entryId);
    final current = _entries![idx];
    if (!current.syncState.isFailed) return current;
    final updated = current.copyWith(
      syncState: OutboxSyncState.pending,
      clearError: true,
    );
    _entries![idx] = updated;
    await _persist();
    return updated;
  }

  @override
  Future<String?> findOrderSubmitCustomerPhone(
    OrderSubmitPhoneLookupKey key,
  ) async {
    // Best-effort READ (never the fail-closed submit guard): a not-yet-signed-in
    // repo simply has no durable op to read, so return null rather than throw.
    if (!_ready) return null;
    await _ensureLoaded();
    // The queue is loaded per THIS session's device; the shared matcher
    // additionally enforces the FULL org/restaurant/branch/device + order identity
    // scope, so a re-paired-device / cross-tenant / cross-branch op cannot match.
    return customerPhoneFromOrderSubmitEntries(_entries!, key);
  }

  int _indexOf(String entryId) {
    final entries = _entries!;
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].id == entryId) return i;
    }
    throw OrderSubmissionException('unknown outbox entry: $entryId');
  }

  /// Builds one `public.sync_push` operation envelope for an `order.submit`.
  ///
  /// The op `payload` is the server-accepted subset of the captured order body
  /// (order_id + type/table/currency/notes + integer-minor totals + order_items);
  /// it deliberately omits org/restaurant/branch/device/station, which the server
  /// derives from the session. Money fields are passed through verbatim - all
  /// integer minor units, no float introduced.
  Map<String, dynamic> _buildOrderSubmitOp(OutboxEntry entry) {
    final body = jsonDecode(entry.payloadJson) as Map<String, dynamic>;
    final payload = <String, dynamic>{
      'order_id': body['order_id'],
      'order_type': body['order_type'],
      'table_id': body['table_id'],
      'currency_code': body['currency_code'],
      'notes': body['notes'],
      // ORDER-CUSTOMER-001: forward the OPTIONAL customer display name so the
      // server can stamp it on the order. Added ONLY when present so a
      // null-customer op keeps the EXACT pre-feature wire shape — the server
      // idempotency fingerprint is md5(op_type || payload::text), so emitting a
      // `customer_name: null` key would change the fingerprint of existing
      // null-customer orders and break their idempotent replay across an upgrade.
      if (body['customer_name'] != null) 'customer_name': body['customer_name'],
      // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: forward the OPTIONAL customer phone
      // ONLY when present, keeping a phone-less op's EXACT pre-feature wire shape.
      // Finding 4: the phone is DATA ONLY — the server EXCLUDES customer_phone
      // from the order.submit idempotency fingerprint (see
      // canonicalOperationIdentityPayload), so re-sending the same op with only a
      // different phone replays idempotently (the first stored phone is kept)
      // rather than conflicting. The client's own dedupe is the D-022
      // (device, local_operation_id) identity — already phone-independent.
      if (body['customer_phone'] != null)
        'customer_phone': body['customer_phone'],
      'order_items': body['order_items'],
      'subtotal_minor': body['subtotal_minor'],
      'discount_total_minor': body['discount_total_minor'],
      'tax_total_minor': body['tax_total_minor'],
      'grand_total_minor': body['grand_total_minor'],
      // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: forward dispatch_mode ONLY for a
      // direct_print order (a VERIFIED printer_only branch). A kds order omits the
      // key entirely, keeping the exact pre-feature op shape + idempotency
      // fingerprint (the server defaults a missing dispatch_mode to 'kds').
      if (body['dispatch_mode'] == 'direct_print')
        'dispatch_mode': body['dispatch_mode'],
    };
    return <String, dynamic>{
      'local_operation_id': entry.localOperationId,
      'operation_type': entry.operationType, // 'order.submit'
      'target_entity': entry.targetEntity, // 'order'
      'target_id': entry.targetId,
      'client_created_at': entry.clientCreatedAt.toIso8601String(),
      'payload': payload,
    };
  }

  /// Applies the `public.sync_push` envelope result to [entry], FAIL-CLOSED.
  ///
  /// The entry becomes [OutboxSyncState.applied] / `rejected` / `conflict` / etc.
  /// ONLY when the matched per-op result carries a KNOWN status. Anything we
  /// cannot positively parse - a malformed envelope, a missing/empty `results`,
  /// no result matching this op's `local_operation_id`, a missing/unknown status,
  /// or an `applied` status contradicted by `ok: false` - is treated as
  /// `rejected` with a short diagnostic code (never silently applied, and never
  /// the raw backend JSON). A replayed op (`idempotency_replay`) reflects its
  /// stored status like any other; no duplicate is created.
  OutboxEntry _applyPushResult(OutboxEntry entry, Object? raw) {
    OutboxEntry rejected(String code) => entry.copyWith(
      syncState: OutboxSyncState.rejected,
      attemptCount: entry.attemptCount + 1,
      lastErrorCode: code,
    );

    if (raw is! Map) return rejected('malformed_response');
    final results = raw['results'];
    if (results is! List) return rejected('missing_results');
    if (results.isEmpty) return rejected('empty_results');

    Map<String, dynamic>? opResult;
    for (final r in results) {
      if (r is Map && r['local_operation_id'] == entry.localOperationId) {
        opResult = r.cast<String, dynamic>();
        break;
      }
    }
    if (opResult == null) return rejected('no_matching_operation');

    final statusWire = opResult['status'];
    if (statusWire is! String) return rejected('missing_status');
    final state = _stateFromWire(statusWire);
    if (state == null) return rejected('unknown_status');
    // An `applied` status contradicted by an explicit `ok: false` is not trusted.
    if (state == OutboxSyncState.applied && opResult['ok'] == false) {
      return rejected('applied_not_ok');
    }

    final errorCode = opResult['error'];
    // RESTAURANT-OPERATIONS-V1-001: for the ONE refusal a cashier must act on
    // line-by-line, keep the blocked-item names the server echoed back (from
    // OUR OWN payload snapshots — safe display text, never raw backend JSON).
    String? errorDetail;
    if (errorCode == 'item_unavailable' && opResult['items'] is List) {
      final names = <String>[
        for (final it in opResult['items'] as List)
          if (it is Map &&
              it['name'] is String &&
              (it['name'] as String).trim().isNotEmpty)
            (it['name'] as String).trim(),
      ];
      if (names.isNotEmpty) errorDetail = names.join(', ');
    }
    return entry.copyWith(
      syncState: state,
      attemptCount: entry.attemptCount + 1,
      lastErrorCode: errorCode is String ? errorCode : null,
      lastErrorDetail: errorDetail,
      clearError: errorCode is! String,
    );
  }

  OutboxSyncState? _stateFromWire(String? wire) {
    if (wire == null) return null;
    for (final state in OutboxSyncState.values) {
      if (state.wire == wire) return state;
    }
    return null;
  }
}
