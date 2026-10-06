/// POS-CASH-DRAWER-MANUAL-OPEN-001 — the server seam of the MANUAL ("no-sale")
/// cash-drawer open, plus the durable journal that carries an open's audit record
/// to the server when the till was offline at the moment it opened.
///
/// Two server calls, both over the shared public-schema [SyncRpcTransport] +
/// [SyncSession] (anon key + PIN/device session — never the `app` schema, never
/// a service-role key):
///
///  * `public.pos_verify_drawer_pin` — unlocks the drawer button for the CURRENT
///    PIN session by re-proving the signed-in employee's OWN PIN. The PIN (or a
///    hash of it) never lives on the device (D-006), so the unlock needs the
///    server; it shares the sign-in lockout (5 attempts / 15 minutes).
///  * `public.sync_push` with ONE `cash_drawer.no_sale_open` operation — records
///    who opened which till's drawer (D-013). The server owns idempotency
///    (D-022: device + local_operation_id), so re-sending a journaled record after
///    a timeout can never write a second audit row.
///
/// Every result the UI sees is a closed, safe enum — never raw backend text.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The operation type the server's `sync_operations` CHECK and `app.sync_push`
/// allowlists accept for a manual drawer open.
const String kNoSaleOperationType = 'cash_drawer.no_sale_open';

/// How long an online push may take before the till treats the open as an
/// OFFLINE one (journal first, then pulse). A slow network must not make the
/// cashier wait for the drawer.
const Duration kNoSalePushTimeout = Duration(seconds: 4);

/// The outcome of one unlock attempt.
enum DrawerUnlockResult {
  /// The PIN matched and the actor may open the drawer.
  unlocked,

  /// The PIN did not match (the shared attempt counter advanced).
  wrongPin,

  /// Too many wrong PINs on this device — the shared sign-in lockout is active.
  pinLocked,

  /// The actor does not hold the open_cash_drawer permission.
  permissionDenied,

  /// The PIN session is no longer valid (expired / ended / revoked device).
  sessionInvalid,

  /// No server could be reached — the first unlock needs a connection.
  offline,

  /// Any other non-success (malformed envelope, unexpected error token).
  unavailable,
}

/// [DrawerUnlockResult] plus, on success, the server PIN-session expiry that
/// bounds how long OFFLINE opens may still be recorded under this session.
class DrawerUnlockOutcome {
  const DrawerUnlockOutcome(this.result, {this.sessionExpiresAt});

  final DrawerUnlockResult result;
  final DateTime? sessionExpiresAt;
}

/// The outcome of pushing ONE no-sale record.
enum NoSalePushResult {
  /// The server recorded the open (also a replay of an already-recorded one).
  recorded,

  /// The server refused: the actor lacks the permission (or the device is not
  /// a POS till). The refusal itself is audited server-side.
  denied,

  /// The PIN session the record belongs to is dead — it can never be recorded
  /// under its original actor.
  sessionInvalid,

  /// Transport failure / timeout — the authoritative outcome is unknown.
  offline,

  /// Any other non-applied result or a malformed envelope.
  rejected,
}

/// One manual drawer open, as journaled on the device until the server has it.
///
/// It carries its OWN [pinSessionId]: a record queued by cashier A while offline
/// must be attributed to A even if B is signed in when the connection returns.
class NoSaleRecord {
  const NoSaleRecord({
    required this.localOperationId,
    required this.pinSessionId,
    required this.deviceId,
    required this.occurredAt,
  });

  final String localOperationId;
  final String pinSessionId;
  final String deviceId;

  /// The device clock at the moment of the open (display only; the server's
  /// audit `occurred_at` stays server time).
  final DateTime occurredAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': localOperationId,
    'pin_session_id': pinSessionId,
    'device_id': deviceId,
    'at': occurredAt.toUtc().toIso8601String(),
  };

  static NoSaleRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final pin = raw['pin_session_id'];
    final device = raw['device_id'];
    final at = raw['at'];
    if (id is! String || id.isEmpty) return null;
    if (pin is! String || pin.isEmpty) return null;
    if (device is! String || device.isEmpty) return null;
    final parsed = at is String ? DateTime.tryParse(at) : null;
    if (parsed == null) return null;
    return NoSaleRecord(
      localOperationId: id,
      pinSessionId: pin,
      deviceId: device,
      occurredAt: parsed,
    );
  }

  /// The exact `sync_push` envelope. Built from the record alone, so a re-send
  /// is byte-identical (same local_operation_id + payload => same fingerprint).
  Map<String, dynamic> toOperation() => <String, dynamic>{
    'local_operation_id': localOperationId,
    'operation_type': kNoSaleOperationType,
    'target_entity': 'cash_drawer',
    'payload': <String, dynamic>{
      'client_occurred_at': occurredAt.toUtc().toIso8601String(),
    },
  };
}

/// The server seam.
abstract class CashDrawerManualRepository {
  /// Verifies the signed-in employee's own [pin] for the current session.
  Future<DrawerUnlockOutcome> verifyPin(String pin);

  /// Records [record] through `sync_push` under the record's own session.
  Future<NoSalePushResult> pushNoSale(NoSaleRecord record);
}

/// REAL implementation over the shared transport.
class RealCashDrawerManualRepository implements CashDrawerManualRepository {
  const RealCashDrawerManualRepository(
    this._transport,
    this._session, {
    this.pushTimeout = kNoSalePushTimeout,
  });

  final SyncRpcTransport? _transport;
  final SyncSession? _session;
  final Duration pushTimeout;

  @override
  Future<DrawerUnlockOutcome> verifyPin(String pin) async {
    final transport = _transport;
    final session = _session;
    if (transport == null || session == null) {
      return const DrawerUnlockOutcome(DrawerUnlockResult.sessionInvalid);
    }
    final Object? raw;
    try {
      raw = await transport.invoke('pos_verify_drawer_pin', <String, dynamic>{
        'p_pin_session_id': session.pinSessionId,
        'p_device_id': session.deviceId,
        'p_pin': pin,
      });
    } on SyncTransportException catch (e) {
      // A transient/network failure is "offline"; a missing RPC (an older
      // server), an auth or a server error is honestly "unavailable" — never
      // an unlock.
      return DrawerUnlockOutcome(
        e.kind == SyncTransportErrorKind.transient
            ? DrawerUnlockResult.offline
            : DrawerUnlockResult.unavailable,
      );
    } catch (_) {
      return const DrawerUnlockOutcome(DrawerUnlockResult.offline);
    }
    if (raw is! Map) {
      return const DrawerUnlockOutcome(DrawerUnlockResult.unavailable);
    }
    if (raw['ok'] == true) {
      final expires = raw['session_expires_at'];
      return DrawerUnlockOutcome(
        DrawerUnlockResult.unlocked,
        sessionExpiresAt: expires is String ? DateTime.tryParse(expires) : null,
      );
    }
    return DrawerUnlockOutcome(switch (raw['error']) {
      'invalid_pin' => DrawerUnlockResult.wrongPin,
      'pin_locked' => DrawerUnlockResult.pinLocked,
      'permission_denied' => DrawerUnlockResult.permissionDenied,
      'invalid_device_type' => DrawerUnlockResult.permissionDenied,
      'invalid_session' => DrawerUnlockResult.sessionInvalid,
      _ => DrawerUnlockResult.unavailable,
    });
  }

  @override
  Future<NoSalePushResult> pushNoSale(NoSaleRecord record) async {
    final transport = _transport;
    if (transport == null) return NoSalePushResult.offline;
    final Object? raw;
    try {
      raw = await transport
          .invoke('sync_push', <String, dynamic>{
            'p_pin_session_id': record.pinSessionId,
            'p_device_id': record.deviceId,
            'p_operations': <dynamic>[record.toOperation()],
          })
          .timeout(pushTimeout);
    } on TimeoutException {
      return NoSalePushResult.offline;
    } on SyncTransportException catch (e) {
      return switch (e.kind) {
        // The whole batch was refused for the session itself (expired / ended
        // PIN session, revoked device binding): this record can never land.
        SyncTransportErrorKind.auth => NoSalePushResult.sessionInvalid,
        SyncTransportErrorKind.transient => NoSalePushResult.offline,
        _ => NoSalePushResult.offline,
      };
    } catch (_) {
      return NoSalePushResult.offline;
    }
    return parseNoSalePush(raw, record.localOperationId);
  }

  /// Maps one `sync_push` envelope to the record's result.
  static NoSalePushResult parseNoSalePush(Object? raw, String localOpId) {
    if (raw is! Map) return NoSalePushResult.rejected;
    final results = raw['results'];
    if (results is! List) return NoSalePushResult.rejected;
    for (final r in results) {
      if (r is! Map || r['local_operation_id'] != localOpId) continue;
      if (r['status'] == 'applied' && r['ok'] != false) {
        return NoSalePushResult.recorded;
      }
      final error = r['error'];
      if (error == 'permission_denied' || error == 'invalid_device_type') {
        return NoSalePushResult.denied;
      }
      if (r['detail'] == 'revoked_employee') return NoSalePushResult.denied;
      return NoSalePushResult.rejected;
    }
    return NoSalePushResult.rejected;
  }
}

/// DEMO: the drawer is a hardware cash control, so demo mode never unlocks it
/// (the button is hidden in demo anyway).
class DemoCashDrawerManualRepository implements CashDrawerManualRepository {
  const DemoCashDrawerManualRepository();

  @override
  Future<DrawerUnlockOutcome> verifyPin(String pin) async =>
      const DrawerUnlockOutcome(DrawerUnlockResult.unavailable);

  @override
  Future<NoSalePushResult> pushNoSale(NoSaleRecord record) async =>
      NoSalePushResult.rejected;
}

/// The SharedPreferences key of the per-device no-sale journal.
String posNoSaleJournalStorageKey(String deviceId) {
  final safe = deviceId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return 'restoflow.pos.cash_drawer_no_sale_journal.v1.$safe';
}

const int kPosNoSaleJournalSchemaVersion = 1;

/// A bound so the envelope can never grow without limit. 500 unsent manual
/// opens on one till is far beyond any real offline window (the offline open is
/// itself bounded by the PIN-session expiry).
const int kPosNoSaleJournalLimit = 500;

/// The durable, serialized journal of manual opens whose audit record has not
/// reached the server yet. The house shared_preferences JSON-envelope pattern
/// (see `PosCashDrawerClaimStore`): every write swaps one whole versioned value,
/// writes are serialized through one chain, and an unreadable envelope is never
/// overwritten (evidence is kept; that till simply opens nothing offline).
class CashDrawerNoSaleJournal {
  CashDrawerNoSaleJournal({Future<SharedPreferences> Function()? prefs})
    : _resolvePrefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _resolvePrefs;
  Future<void> _serial = Future<void>.value();

  Future<T> _run<T>(Future<T> Function() body, T onError) {
    final run = _serial.then((_) => body());
    _serial = run.then((_) {}, onError: (_) {});
    return run.then((v) => v, onError: (_) => onError);
  }

  /// Appends [record]. Returns false when it could not be persisted — the caller
  /// must then NOT pulse the drawer offline (an unrecorded open is exactly what
  /// the audit exists to prevent).
  Future<bool> append(String deviceId, NoSaleRecord record) => _run(() async {
    final prefs = await _resolvePrefs();
    final key = posNoSaleJournalStorageKey(deviceId);
    final current = _decode(prefs.getString(key));
    if (current == null) return false;
    if (current.any((r) => r.localOperationId == record.localOperationId)) {
      return true;
    }
    final next = <NoSaleRecord>[...current, record];
    if (next.length > kPosNoSaleJournalLimit) return false;
    return prefs.setString(key, _encode(next));
  }, false);

  /// The pending records, oldest first (empty when none or unreadable).
  Future<List<NoSaleRecord>> pending(String deviceId) => _run(() async {
    final prefs = await _resolvePrefs();
    return _decode(prefs.getString(posNoSaleJournalStorageKey(deviceId))) ??
        const <NoSaleRecord>[];
  }, const <NoSaleRecord>[]);

  /// Removes the record [localOperationId] (it reached a final server verdict).
  Future<void> remove(String deviceId, String localOperationId) =>
      _run(() async {
        final prefs = await _resolvePrefs();
        final key = posNoSaleJournalStorageKey(deviceId);
        final current = _decode(prefs.getString(key));
        if (current == null) return;
        final next = [
          for (final r in current)
            if (r.localOperationId != localOperationId) r,
        ];
        if (next.length == current.length) return;
        if (next.isEmpty) {
          await prefs.remove(key);
        } else {
          await prefs.setString(key, _encode(next));
        }
      }, null);

  static String _encode(List<NoSaleRecord> records) =>
      jsonEncode(<String, Object?>{
        'v': kPosNoSaleJournalSchemaVersion,
        'records': [for (final r in records) r.toJson()],
      });

  /// Null means UNREADABLE (never treated as empty, never overwritten).
  static List<NoSaleRecord>? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return <NoSaleRecord>[];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map ||
        (decoded['v'] as num?)?.toInt() != kPosNoSaleJournalSchemaVersion ||
        decoded['records'] is! List) {
      return null;
    }
    final out = <NoSaleRecord>[];
    for (final r in decoded['records'] as List) {
      final parsed = NoSaleRecord.fromJson(r);
      if (parsed != null) out.add(parsed);
    }
    return out;
  }
}

final posCashDrawerNoSaleJournalProvider = Provider<CashDrawerNoSaleJournal>(
  (ref) => CashDrawerNoSaleJournal(),
);
