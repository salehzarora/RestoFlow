// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F: test support for the POS card flow.
//
// [CardServerFake] is ONE scripted fake of the three server surfaces the flow
// touches, written from the verified contracts (execution packet §4):
//   * the `pos-card-charge` Edge (`start` / `status` / `release`), whose 200 and
//     non-200 answers pass through the REAL 001C `classifyCardChargeAnswer`, so
//     the POS sees exactly what the production transport would hand it;
//   * the provider-leg `sync_push` of the 001D ledger (identity-first gate,
//     canonical payload, refusals, the D-054 Resume guard,
//     `resume_authority_required`, the pre-ledger TEST refusal, idempotent
//     replay);
//   * the PIN-session probe `pin_session_capabilities` (role + branch features).
// It counts provider commits, lookups and releases so tests can prove that
// recording and Resume never reach the provider. No network: [NoNetworkGuard]
// refuses any HttpClient a test (or the code under test) would create.
import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, HttpOverrides, SecurityContext;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/online_order_inbox.dart'
    show onlineOrderInboxSecretStoreProvider;
import 'package:restoflow_pos/src/data/provider_card_attempt.dart'
    show ProviderCardAttempt, ProviderCardMode, ProviderCardStartOutcome;
import 'package:restoflow_pos/src/data/provider_card_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/state/order_sync_controller.dart'
    show posSyncClockProvider;
import 'package:restoflow_pos/src/state/pos_session.dart'
    show
        posAuthTransportProvider,
        posSignedInEmployeeProfileIdProvider,
        posSyncSessionProvider;
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart'
    show posSyncScopeProvider;
import 'package:restoflow_pos/src/state/provider_card_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Synthetic identities (no real value anywhere)
// ---------------------------------------------------------------------------

const String kCardDevice = 'd0d0d0d0-0000-4000-8000-000000000001';
const String kCardPin = 'a1a1a1a1-0000-4000-8000-000000000001';
const String kCardPin2 = 'a1a1a1a1-0000-4000-8000-000000000002';
const String kCardOrder = '0a0a0a0a-0000-4000-8000-000000000001';
const String kCardOrder2 = '0a0a0a0a-0000-4000-8000-000000000002';
const String kCardToken = 'synthetic-device-proof';
const PosSyncScope kCardScope = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: kCardDevice,
);
const SyncSession kCardSession = SyncSession(
  pinSessionId: kCardPin,
  deviceId: kCardDevice,
);
final DateTime kCardNow = DateTime.utc(2026, 10, 30, 12);

/// The n-th synthetic lowercase UUID v4.
String cardV4(int n) {
  final s = n.toString().padLeft(7, '0');
  final t = n.toString().padLeft(12, '0');
  return 'c$s-0000-4000-8000-$t';
}

/// A deterministic id source that counts its calls.
class CountingCardIds implements ClientIdGenerator {
  CountingCardIds([int start = 1]) : _next = start;
  int _next;
  int calls = 0;

  @override
  String newId() {
    calls++;
    return cardV4(_next++);
  }
}

/// A clock a test can move.
class CardClock {
  CardClock([DateTime? start]) : now = start ?? kCardNow;
  DateTime now;
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

// ---------------------------------------------------------------------------
// Stored journals (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F-JOURNAL-RECOVERY-
// CORRECTIONS-001: the admission bound and envelope uniqueness)
// ---------------------------------------------------------------------------

/// The n-th synthetic server order (a canonical lowercase UUID v4), distinct
/// from [kCardOrder] and [kCardOrder2].
String cardOrderN(int n) =>
    '0b0b0b0b-0000-4000-8000-${n.toString().padLeft(12, '0')}';

/// A never-sent attempt of this till for [order], identity [cardV4] of [n].
ProviderCardAttempt cardStoredAttempt(
  int n, {
  required String order,
  ProviderCardMode mode = ProviderCardMode.live,
  int amount = 1200,
}) => ProviderCardAttempt.create(
  attemptId: cardV4(n),
  organizationId: kCardScope.organizationId,
  restaurantId: kCardScope.restaurantId,
  branchId: kCardScope.branchId,
  deviceId: kCardScope.deviceId,
  orderId: order,
  orderNumber: '#B$n',
  mode: mode,
  amountMinor: amount,
  currencyCode: 'ILS',
  expectedRevision: mode == ProviderCardMode.live ? 7 : null,
  employeeProfileId: 'emp-cashier',
  now: kCardNow,
);

/// [a] after a `start` that may have executed and was never answered:
/// "result not confirmed" — open, never set aside, never pruned.
ProviderCardAttempt cardInDoubt(ProviderCardAttempt a) {
  final at = kCardNow.toUtc().toIso8601String();
  return a.copyWith(
    startMayHaveExecuted: true,
    startLastSentAt: at,
    startOutcome: ProviderCardStartOutcome.uncertain,
    updatedAt: at,
  );
}

/// The journal envelope of [attempts], exactly as the store writes it.
String cardJournalEnvelope(Iterable<ProviderCardAttempt> attempts) =>
    jsonEncode(<String, Object?>{
      'version': 1,
      'attempts': <Object?>[for (final a in attempts) a.toJson()],
    });

// ---------------------------------------------------------------------------
// The network guard
// ---------------------------------------------------------------------------

class _NoNetworkOverrides extends HttpOverrides {
  int attempts = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('001F tests: network access is not allowed');
  }
}

/// Refuses every HttpClient for the rest of the test and fails it if one was
/// asked for.
void installNoNetworkGuard() {
  final previous = HttpOverrides.current;
  final guard = _NoNetworkOverrides();
  HttpOverrides.global = guard;
  addTearDown(() {
    HttpOverrides.global = previous;
    expect(guard.attempts, 0, reason: 'unexpected network access');
  });
}

// ---------------------------------------------------------------------------
// The server fake
// ---------------------------------------------------------------------------

/// One provider attempt as the fake ledger holds it.
class FakeCardAttempt {
  FakeCardAttempt({
    required this.id,
    required this.mode,
    required this.amountMinor,
    required this.currencyCode,
    required this.orderId,
    required this.expectedRevision,
  });

  final String id;
  final String mode;
  final int amountMinor;
  final String currencyCode;
  final String? orderId;
  final Object? expectedRevision;
  String state = 'sent';
  String? resolution;
  bool chargeMayExist = false;
  String? anomalyCode;
  bool freed = false;
  String? refusalCode;

  /// When the latest refusal report was stored, and when the last authorized
  /// Resume reopened the row (the ledger's freshness order).
  int? reportedAt;
  int? lastResumeAt;
  int resumeCount = 0;
  int autoPolls = 0;
  bool contextLost = false;
  String? paymentId;
}

/// One provider-leg `sync_operations` row.
class FakeLegRow {
  FakeLegRow(this.op);
  Map<String, dynamic> op;
  String status = 'in_flight';
  int rejectedAt = 0;
  Map<String, Object?> result = const <String, Object?>{};
  bool reopened = false;
}

/// The scripted server (packet §4). Every knob is public on purpose.
class CardServerFake
    implements SyncRpcTransport, AuthenticatedCardChargeTransport {
  CardServerFake({
    this.terminalMode = 'live',
    this.terminalEnabled = true,
    this.role = 'cashier',
    this.orderTotal = 1200,
    this.currencyCode = 'ILS',
  });

  // ---- posture probe ----
  String? terminalMode;
  bool terminalEnabled;
  String role;
  bool capabilitiesThrow = false;
  int capabilitiesCalls = 0;

  /// A gate the next posture probe waits on (to hold a read in flight).
  Completer<void>? capabilitiesHold;

  /// PIN sessions the Edge's context proof refuses: revoked (401
  /// `invalid_session`: an inactive membership or employee) or outside the
  /// four roles (200 `permission_denied`).
  final Set<String> revokedPins = <String>{};
  final Set<String> deniedPins = <String>{};

  int _seq = 0;
  String? _lastPushPin;

  // ---- the order the LIVE attempts charge ----
  int orderTotal;
  String currencyCode;
  int orderRevision = 7;

  // ---- Edge ----
  final Map<String, FakeCardAttempt> attempts = <String, FakeCardAttempt>{};
  final List<Map<String, dynamic>> edgeBodies = <Map<String, dynamic>>[];
  final List<String> edgeBytes = <String>[];
  int providerCommits = 0;
  int providerLookups = 0;
  int providerReleases = 0;
  bool startsDisabled = false;
  bool releaseConfirms = true;
  bool includeReturnCode = true;
  int autoPollCap = 90;

  /// The next Edge exchanges answer with these instead of executing (FIFO):
  /// a [CardChargeTransportFailure], or an `(httpStatus, body)` record that is
  /// classified by the real 001C classifier.
  final List<Object> edgeScript = <Object>[];

  /// A state the next lookup of an attempt moves it to.
  final Map<String, String> nextLookupState = <String, String>{};

  /// Called with each Edge body before the fake answers (e.g. to read the
  /// journal at the moment of the handoff).
  FutureOr<void> Function(Map<String, dynamic> body)? onEdge;

  /// A gate the next Edge exchange waits on (to hold a request in flight).
  Completer<void>? holdEdge;

  // ---- sync_push ----
  final Map<String, FakeLegRow> legRows = <String, FakeLegRow>{};
  final List<Map<String, dynamic>> pushedOps = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> pushCalls = <Map<String, dynamic>>[];
  int paymentsCreated = 0;

  /// The next leg dispatches fail like this (FIFO): `transient`, `drop`
  /// (committed, reply lost), `lost` (reply lost, nothing committed),
  /// `raise42501` (whole call raised), `single`.
  final List<String> legFaults = <String>[];

  /// The next leg dispatch is refused like this: `precondition_failed`,
  /// `revoked_employee`, `permission_denied`, `revoked_device`,
  /// `provider_recording_refused`, `amount_mismatch`, `card_context_lost`,
  /// `generic`.
  String? nextLegRefusal;

  /// Called with each `sync_push` call before the fake answers.
  FutureOr<void> Function(Map<String, dynamic> params)? onPush;

  String get _ts => '2026-10-30T12:00:00Z';

  int edgeCount(String action) =>
      edgeBodies.where((b) => b['action'] == action).length;

  // ---- AuthenticatedCardChargeTransport ---------------------------------

  @override
  Future<CardChargeTransportResult> sendCardCharge(
    Map<String, dynamic> body, {
    bool Function()? isCurrent,
  }) async {
    if (isCurrent != null && !isCurrent()) {
      return const CardChargeTransportFailure.notSent(
        CardChargeFailureReason.deviceSessionUnverified,
      );
    }
    final bytes = jsonEncode(body);
    edgeBytes.add(bytes);
    final copy = jsonDecode(bytes) as Map<String, dynamic>;
    edgeBodies.add(copy);
    final hook = onEdge;
    if (hook != null) await hook(copy);
    final hold = holdEdge;
    if (hold != null) {
      holdEdge = null;
      await hold.future;
    }
    // The Edge's context proof comes first (handler.mjs, card_attempt_context).
    final pin = copy['pin_session_id'];
    if (revokedPins.contains(pin)) {
      return classifyCardChargeAnswer(401, <String, Object?>{
        'ok': false,
        'error': 'invalid_session',
      }, attemptId: copy['attempt_id'] as String?);
    }
    if (deniedPins.contains(pin)) {
      return classifyCardChargeAnswer(200, <String, Object?>{
        'ok': false,
        'error': 'permission_denied',
        'server_ts': _ts,
      }, attemptId: copy['attempt_id'] as String?);
    }
    if (edgeScript.isNotEmpty) {
      final next = edgeScript.removeAt(0);
      if (next is CardChargeTransportResult) return next;
      final (status, answer) = next as (int, Object?);
      return classifyCardChargeAnswer(
        status,
        answer,
        attemptId: copy['attempt_id'] as String?,
      );
    }
    final (status, answer) = _edge(copy);
    return classifyCardChargeAnswer(
      status,
      answer,
      attemptId: copy['attempt_id'] as String?,
    );
  }

  (int, Object?) _edge(Map<String, dynamic> b) {
    final id = b['attempt_id'] as String;
    switch (b['action']) {
      case 'start':
        if (startsDisabled) {
          return (
            200,
            <String, Object?>{'ok': false, 'error': 'card_payments_disabled'},
          );
        }
        final existing = attempts[id];
        if (existing != null) {
          final same =
              existing.mode == b['mode'] &&
              existing.amountMinor == b['amount_minor'] &&
              existing.currencyCode == b['currency_code'];
          if (!same) {
            return (
              200,
              <String, Object?>{
                'ok': false,
                'error': 'conflict',
                'attempt_id': id,
                'attempt_state': existing.state,
                'server_ts': _ts,
              },
            );
          }
          return (200, envelope(existing));
        }
        if (b['mode'] == 'live') {
          final busy = attempts.values.any(
            (a) =>
                a.orderId == b['order_id'] &&
                a.mode == 'live' &&
                a.resolution == null &&
                !a.freed &&
                a.state != 'declined' &&
                a.paymentId == null,
          );
          if (busy) {
            return (
              200,
              <String, Object?>{
                'ok': false,
                'error': 'payment_in_progress',
                'server_ts': _ts,
              },
            );
          }
        }
        final a = FakeCardAttempt(
          id: id,
          mode: b['mode'] as String,
          amountMinor: b['amount_minor'] as int,
          currencyCode: b['currency_code'] as String,
          orderId: b['order_id'] as String?,
          expectedRevision: b['expected_revision'],
        );
        attempts[id] = a;
        providerCommits++;
        return (200, envelope(a));
      case 'status':
        final a = attempts[id];
        if (a == null) {
          return (
            200,
            <String, Object?>{'ok': false, 'error': 'attempt_not_found'},
          );
        }
        if (a.resolution != null) return (200, envelope(a));
        if (a.state == 'approved') {
          if (b['recording_refused'] == true) return (200, _markRefused(a));
          return (200, envelope(a));
        }
        if (a.state == 'declined') return (200, envelope(a));
        if (b['source'] == 'auto' &&
            role == 'cashier' &&
            a.autoPolls >= autoPollCap) {
          return (
            200,
            <String, Object?>{
              'ok': false,
              'error': 'poll_limit',
              'attempt_id': id,
              'attempt_state': a.state,
            },
          );
        }
        providerLookups++;
        if (b['source'] == 'auto') a.autoPolls++;
        final next = nextLookupState.remove(id);
        if (next != null) a.state = next;
        return (200, envelope(a));
      case 'release':
        final a = attempts[id];
        if (a == null) {
          return (
            200,
            <String, Object?>{'ok': false, 'error': 'attempt_not_found'},
          );
        }
        if ((a.state == 'sent' || a.state == 'unknown') &&
            a.resolution == null) {
          providerReleases++;
          if (releaseConfirms) {
            a.state = 'released';
          } else {
            a.refusalCode = 'release_failed';
          }
        }
        return (200, envelope(a));
      default:
        return (
          400,
          <String, Object?>{'ok': false, 'error': 'invalid_request'},
        );
    }
  }

  static const Set<String> _recoverable = <String>{
    'precondition_failed',
    'revoked_employee',
    'permission_denied',
  };

  Map<String, Object?> _markRefused(FakeCardAttempt a) {
    final row = legRows[a.id];
    if (row == null || (row.status != 'rejected' && row.status != 'conflict')) {
      return <String, Object?>{
        'ok': false,
        'error': 'precondition_failed',
        'detail': 'no_recording_attempt',
        'attempt_id': a.id,
        'attempt_state': a.state,
        'server_ts': _ts,
      };
    }
    // The token comes from the stored row, never from the hint (SQL
    // card_attempt_mark_recording_result).
    final r = row.result;
    final error = r['error'];
    final detail = r['detail'];
    a.refusalCode = row.status == 'conflict'
        ? 'conflict'
        : switch (error) {
            'rejected' when detail == 'precondition_failed' =>
              'precondition_failed',
            'rejected' when detail == 'revoked_employee' => 'revoked_employee',
            'rejected' when detail == 'revoked_device' => 'revoked_device',
            'permission_denied' => 'permission_denied',
            'provider_recording_refused' => 'provider_recording_refused',
            'amount_mismatch' => 'amount_mismatch',
            'card_context_lost' => 'card_context_lost',
            _ => 'nonrecoverable_refusal',
          };
    a.reportedAt = ++_seq;
    return envelope(a);
  }

  /// The latest report is fresh: stored after the row's latest refusal and
  /// after the last authorized Resume (the ledger's `refusal_not_recorded`
  /// rule); a reopened row is unreported.
  bool _reportFresh(FakeCardAttempt a) {
    final row = legRows[a.id];
    final at = a.reportedAt;
    if (row == null || at == null) return false;
    if (row.status != 'rejected' && row.status != 'conflict') return false;
    return at > row.rejectedAt && at > (a.lastResumeAt ?? 0);
  }

  /// Another device's authorized Resume of [id] reopened the row, its leg was
  /// refused again and that refusal was reported: the count moved on.
  void simulateOtherResume(String id) {
    final a = attempts[id]!;
    final row = legRows[id]!;
    a.resumeCount++;
    a.lastResumeAt = ++_seq;
    row.rejectedAt = ++_seq;
    a.reportedAt = ++_seq;
  }

  /// The closed §4.55.4 envelope of [a] (the fake's `card_attempt_derive`).
  Map<String, Object?> envelope(FakeCardAttempt a) {
    final test = a.mode == 'test';
    final recorded = a.paymentId != null;
    final fresh = _reportFresh(a);
    final reportedRecoverable = fresh && _recoverable.contains(a.refusalCode);
    final orphan =
        a.state == 'approved' &&
        !recorded &&
        fresh &&
        (!_recoverable.contains(a.refusalCode) || a.resumeCount >= 3);
    final String classification;
    if (test) {
      classification = 'test_${a.state}';
    } else if (a.resolution != null) {
      classification = 'resolved';
    } else if (a.state == 'sent') {
      classification = 'in_progress';
    } else if ((a.state == 'unknown' || a.state == 'released') &&
        a.chargeMayExist) {
      classification = 'provider_anomaly';
    } else if ((a.state == 'unknown' || a.state == 'released') && a.freed) {
      classification = 'freed';
    } else if (a.state == 'unknown' || a.state == 'released') {
      classification = 'in_progress';
    } else if (a.state == 'declined') {
      classification = 'declined';
    } else if (recorded) {
      classification = 'recorded';
    } else if (orphan) {
      classification = 'orphan_approved';
    } else {
      classification = 'approved_unrecorded';
    }
    final withRecovery =
        classification == 'approved_unrecorded' ||
        classification == 'orphan_approved';
    return <String, Object?>{
      'ok': true,
      'attempt_id': a.id,
      'state': a.state,
      'classification': classification,
      if (includeReturnCode) 'provider_return_code': 0,
      if (a.refusalCode != null) 'refusal_code': a.refusalCode,
      if (classification == 'provider_anomaly')
        'anomaly_code': a.anomalyCode ?? 'out_of_contract',
      if (a.resolution != null) 'resolution': a.resolution,
      'recorded': !test && recorded,
      if (withRecovery) ...<String, Object?>{
        'recoverable':
            reportedRecoverable && a.resumeCount < 3 && !a.contextLost,
        'resume_count': a.resumeCount,
      },
      if (!test && recorded) 'payment_id': a.paymentId,
      'amount_minor': a.amountMinor,
      'currency_code': a.currencyCode,
      'server_ts': _ts,
    };
  }

  // ---- scripted provider facts ---------------------------------------------

  void approve(String id) => attempts[id]!.state = 'approved';
  void decline(String id) => attempts[id]!.state = 'declined';

  // ---- SyncRpcTransport ----------------------------------------------------

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    switch (function) {
      case 'pin_session_capabilities':
        capabilitiesCalls++;
        final hold = capabilitiesHold;
        if (hold != null) {
          capabilitiesHold = null;
          await hold.future;
        }
        if (capabilitiesThrow) {
          throw const SyncTransportException(
            SyncTransportErrorKind.transient,
            code: '503',
          );
        }
        return <String, Object?>{
          'ok': true,
          'entity': 'pin_session',
          'role': role,
          'capabilities': <String, Object?>{
            'apply_discount': true,
            'apply_full_comp': false,
          },
          'branch_features': <String, Object?>{
            'order_edit_enabled': false,
            'order_edit_finished_food_manager_only': false,
            if (terminalMode != null) 'card_terminal_enabled': terminalEnabled,
            if (terminalMode != null) 'card_terminal_mode': terminalMode,
          },
        };
      case 'sync_push':
        return _syncPush(params);
      default:
        throw StateError('CardServerFake does not serve $function');
    }
  }

  Map<String, Object?> _reply(List<Map<String, Object?>> results) =>
      <String, Object?>{'ok': true, 'results': results, 'server_ts': _ts};

  Future<Object?> _syncPush(Map<String, dynamic> params) async {
    final copy = jsonDecode(jsonEncode(params)) as Map<String, dynamic>;
    pushCalls.add(copy);
    _lastPushPin = copy['p_pin_session_id'] as String?;
    final hook = onPush;
    if (hook != null) await hook(copy);
    final ops = (copy['p_operations'] as List).cast<Map<String, dynamic>>();
    if (legFaults.isNotEmpty && legFaults.first == 'raise42501') {
      legFaults.removeAt(0);
      throw const SyncTransportException(
        SyncTransportErrorKind.server,
        code: '42501',
        message: 'sync_push: permission denied (active support session)',
      );
    }
    if (ops.length > 1 ||
        (legFaults.isNotEmpty && legFaults.first == 'single')) {
      if (legFaults.isNotEmpty && legFaults.first == 'single') {
        legFaults.removeAt(0);
      }
      return _reply(<Map<String, Object?>>[
        for (final o in ops)
          <String, Object?>{
            'local_operation_id': o['local_operation_id'],
            'operation_type': o['operation_type'],
            'ok': false,
            'error': 'single_operation_required',
            'retryable': true,
            'status': 'pending',
            'idempotency_replay': false,
          },
      ]);
    }
    final op = ops.single;
    pushedOps.add(op);
    final id = op['local_operation_id'] as String;
    final a = attempts[id];
    if (a == null) throw StateError('not a provider leg: $id');
    Map<String, Object?> head(String status, {bool replay = false}) =>
        <String, Object?>{
          'local_operation_id': id,
          'operation_type': op['operation_type'],
          'status': status,
          'idempotency_replay': replay,
        };
    final payload = op['payload'] as Map<String, dynamic>;
    if (a.mode == 'test') {
      return _reply(<Map<String, Object?>>[
        <String, Object?>{
          ...head('rejected'),
          'ok': false,
          'error': 'test_attempt_not_recordable',
          'server_ts': _ts,
          'order_id': payload['order_id'],
        },
      ]);
    }
    final resume = op['recording_resume'];
    var row = legRows[id];
    if (row != null) {
      if (jsonEncode(row.op['payload']) != jsonEncode(payload)) {
        return _reply(<Map<String, Object?>>[
          <String, Object?>{
            ...head('conflict'),
            'ok': false,
            'error': 'conflict',
            'detail':
                'idempotency key already used for a different operation/payload',
          },
        ]);
      }
      if (row.status == 'applied') {
        return _reply(<Map<String, Object?>>[
          <String, Object?>{...row.result, ...head('applied', replay: true)},
        ]);
      }
      if (row.status == 'rejected') {
        if (resume == null) {
          return _reply(<Map<String, Object?>>[
            <String, Object?>{...row.result, ...head('rejected', replay: true)},
          ]);
        }
        final denied = _resumeDenied(a, row, op, resume as int);
        if (denied != null) {
          return _reply(<Map<String, Object?>>[
            <String, Object?>{
              ...row.result,
              ...head('rejected', replay: true),
              'resume_denied': denied,
            },
          ]);
        }
        a.resumeCount++;
        a.lastResumeAt = ++_seq;
        row.reopened = true;
        row.status = 'in_flight';
      } else if (row.status == 'pending' && row.reopened) {
        if (role == 'cashier') {
          return _reply(<Map<String, Object?>>[
            <String, Object?>{
              'local_operation_id': id,
              'operation_type': op['operation_type'],
              'ok': false,
              'error': 'resume_authority_required',
              'retryable': true,
              'status': 'pending',
              'idempotency_replay': false,
            },
          ]);
        }
      }
    } else {
      row = FakeLegRow(op);
      legRows[id] = row;
    }
    // Dispatch.
    final fault = legFaults.isEmpty ? null : legFaults.removeAt(0);
    if (fault == 'lost') {
      // The reply is lost BEFORE anything committed: the row stays undecided.
      row.status = 'pending';
      throw const SyncTransportException(
        SyncTransportErrorKind.transient,
        code: '504',
      );
    }
    if (fault == 'transient') {
      row.status = 'pending';
      return _reply(<Map<String, Object?>>[
        <String, Object?>{
          'local_operation_id': id,
          'operation_type': op['operation_type'],
          'ok': false,
          'error': 'transient_failure',
          'retryable': true,
          'status': 'pending',
          'idempotency_replay': false,
        },
      ]);
    }
    // record_payment applies a present revision (RP L290-293): a stale one is
    // the memoized 40001 conflict. The canonical leg carries none.
    if (payload.containsKey('expected_revision') &&
        payload['expected_revision'] != orderRevision) {
      row.status = 'conflict';
      row.rejectedAt = ++_seq;
      row.result = <String, Object?>{
        'ok': false,
        'error': 'conflict',
        'sqlstate': '40001',
      };
      return _reply(<Map<String, Object?>>[
        <String, Object?>{...row.result, ...head('conflict')},
      ]);
    }
    final refusal = _guard(a, payload) ?? _takeLegRefusal();
    if (refusal != null) {
      row.status = 'rejected';
      row.rejectedAt = ++_seq;
      row.result = refusal;
      return _reply(<Map<String, Object?>>[
        <String, Object?>{...refusal, ...head('rejected')},
      ]);
    }
    paymentsCreated++;
    a.paymentId =
        'f0f0f0f0-0000-4000-8000-${paymentsCreated.toString().padLeft(12, '0')}';
    row.status = 'applied';
    row.result = <String, Object?>{
      'ok': true,
      'payment_id': a.paymentId,
      'order_id': a.orderId,
      'method': 'card',
      'receipt_number': 'R-$paymentsCreated',
      'change_due_minor': 0,
      'shift_id': 'shift-1',
      'cash_drawer_session_id': 'drawer-1',
      'payment_revision': 1,
      'order_revision': orderRevision,
      'auto_completed': false,
      'order_status': 'served',
      'server_ts': _ts,
    };
    if (fault == 'drop') {
      throw const SyncTransportException(
        SyncTransportErrorKind.transient,
        code: '504',
      );
    }
    return _reply(<Map<String, Object?>>[
      <String, Object?>{...row.result, ...head('applied')},
    ]);
  }

  Map<String, Object?>? _guard(
    FakeCardAttempt a,
    Map<String, dynamic> payload,
  ) {
    Map<String, Object?> guard(String error, [String? detail]) =>
        <String, Object?>{
          'ok': false,
          'error': error,
          'detail': ?detail,
          'server_ts': _ts,
          'order_id': payload['order_id'],
        };
    if (a.resolution != null) {
      return guard('provider_recording_refused', 'attempt_resolved');
    }
    if (a.state != 'approved') {
      return guard('provider_recording_refused', 'attempt_not_approved');
    }
    if (payload['order_id'] != a.orderId) {
      return guard('provider_recording_refused', 'order_mismatch');
    }
    if (payload['tender_type'] != 'card') {
      return guard('provider_recording_refused', 'tender_mismatch');
    }
    if (orderTotal != a.amountMinor || currencyCode != a.currencyCode) {
      return guard('amount_mismatch');
    }
    if (a.contextLost) return guard('card_context_lost');
    return null;
  }

  Map<String, Object?>? _takeLegRefusal() {
    final kind = nextLegRefusal;
    if (kind == null) return null;
    nextLegRefusal = null;
    // The refusal is about the pushing session's actor: the Edge's context
    // proof then refuses that session too (an inactive membership: 401; a
    // role outside the four: permission_denied).
    final pin = _lastPushPin;
    if (pin != null && kind == 'revoked_employee') revokedPins.add(pin);
    if (pin != null && kind == 'permission_denied') deniedPins.add(pin);
    return switch (kind) {
      'precondition_failed' || 'revoked_employee' => <String, Object?>{
        'ok': false,
        'error': 'rejected',
        'sqlstate': 'P0001',
        'detail': kind,
      },
      'generic' => <String, Object?>{
        'ok': false,
        'error': 'rejected',
        'sqlstate': 'P0001',
        'detail': null,
      },
      'permission_denied' => <String, Object?>{
        'ok': false,
        'error': 'permission_denied',
        'order_id': kCardOrder,
        'server_ts': _ts,
      },
      'revoked_device' => <String, Object?>{
        'ok': false,
        'error': 'rejected',
        'detail': 'revoked_device',
      },
      _ => throw StateError('unknown leg refusal $kind'),
    };
  }

  String? _resumeDenied(
    FakeCardAttempt a,
    FakeLegRow row,
    Map<String, dynamic> op,
    int resume,
  ) {
    if (role == 'cashier') return 'not_manager';
    if (op['target_id'] != row.op['target_id'] ||
        op['client_created_at'] != row.op['client_created_at']) {
      return 'operation_mismatch';
    }
    if (a.resumeCount >= 3) return 'resume_limit';
    if (a.resumeCount != resume) return 'resume_stale';
    if (!_reportFresh(a)) return 'refusal_not_recorded';
    if (!_recoverable.contains(a.refusalCode)) return 'not_recoverable';
    return null;
  }
}

// ---------------------------------------------------------------------------
// The container
// ---------------------------------------------------------------------------

/// Fresh mock preferences.
Future<SharedPreferences> freshCardPrefs([
  Map<String, Object> initial = const <String, Object>{},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  return SharedPreferences.getInstance();
}

/// The PIN session the card container runs under; a test signs another person
/// in by setting it (the controller rebuilds, as on a real sign-in).
final cardSessionProvider = StateProvider<SyncSession?>((ref) => kCardSession);

/// The real journal with test hooks: refuse the next [failUpdates] updates,
/// hold the next [holdLoad], or hold the return of the next update that writes
/// a recording leg ([holdLegWrite]; the write itself is durable by then).
class HookedCardStore implements ProviderCardStore {
  HookedCardStore(this.inner);
  final ProviderCardStore inner;
  int failUpdates = 0;
  Completer<void>? holdLoad;
  Completer<void>? holdLegWrite;
  int loads = 0;

  @override
  Future<ProviderCardLoad> load(PosSyncScope scope) async {
    loads++;
    final hold = holdLoad;
    if (hold != null) {
      holdLoad = null;
      await hold.future;
    }
    return inner.load(scope);
  }

  @override
  Future<ProviderCardCreate> createIfAbsent(
    PosSyncScope scope, {
    required String identityKey,
    required ProviderCardMode mode,
    required ProviderCardAttempt Function() mint,
  }) => inner.createIfAbsent(
    scope,
    identityKey: identityKey,
    mode: mode,
    mint: mint,
  );

  @override
  Future<ProviderCardAttempt> update(
    PosSyncScope scope,
    String attemptId,
    ProviderCardAttempt Function(ProviderCardAttempt current) transform,
  ) async {
    if (failUpdates > 0) {
      failUpdates--;
      throw StateError('storage refused');
    }
    var legWrite = false;
    final written = await inner.update(scope, attemptId, (c) {
      final next = transform(c);
      if (c.recording == null && next.recording != null) legWrite = true;
      return next;
    });
    final hold = holdLegWrite;
    if (legWrite && hold != null) {
      holdLegWrite = null;
      await hold.future;
    }
    return written;
  }
}

/// A real-mode container wired to [server] (packet §11); [transport], when
/// given, stands in for it as the RPC transport (a till that also serves the
/// ordinary tenders). The monotonic clock follows [clock] unless [monotonic]
/// is given (a test that steps the wall clock on its own).
ProviderContainer cardContainer({
  required CardServerFake server,
  required SharedPreferences prefs,
  SyncRpcTransport? transport,
  ClientIdGenerator? ids,
  CardClock? clock,
  Duration Function()? monotonic,
  ProviderCardStore? store,
  ProviderCardPollPolicy? policy,
  String? employee = 'emp-cashier',
  DeviceSessionSecretStore? secretStore,
  List<Override> extra = const <Override>[],
}) {
  final secrets = secretStore ?? InMemoryDeviceSessionSecretStore();
  if (secretStore == null) {
    unawaited(
      secrets.write(
        const DeviceSessionCredential(
          deviceId: kCardDevice,
          sessionToken: kCardToken,
        ),
      ),
    );
  }
  final k = clock ?? CardClock();
  final c = ProviderContainer(
    overrides: <Override>[
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport ?? server),
      posSyncSessionProvider.overrideWith(
        (ref) => ref.watch(cardSessionProvider),
      ),
      posSyncScopeProvider.overrideWithValue(kCardScope),
      onlineOrderInboxSecretStoreProvider.overrideWithValue(secrets),
      providerCardStoreProvider.overrideWithValue(
        store ?? SharedPrefsProviderCardStore(prefs: () async => prefs),
      ),
      clientIdGeneratorProvider.overrideWithValue(ids ?? CountingCardIds()),
      posSyncClockProvider.overrideWithValue(k.call),
      providerCardMonotonicProvider.overrideWithValue(
        monotonic ?? () => k.now.difference(kCardNow),
      ),
      if (policy != null)
        providerCardPollPolicyProvider.overrideWithValue(policy),
      ...extra,
    ],
  );
  addTearDown(c.dispose);
  c.read(posSignedInEmployeeProfileIdProvider.notifier).set(employee);
  return c;
}
