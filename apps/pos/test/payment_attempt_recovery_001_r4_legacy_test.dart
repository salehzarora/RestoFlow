// PAYMENT-ATTEMPT-RECOVERY-001 / S1-R4 — the LEGACY execution-history
// regressions (F004 compatibility).
//
// Adopted from Codex's external harness
// `reviewer_s1_r3_f004_legacy_schedule_variations_test.dart` (SHA-256
// 269A80A5153B445E98F1090829C2AACCB765E2AAE91FB35D4DE9755238B2CD38). At
// 741dc9b7 nine cases passed and three failed, twice.
//
// ONE of its twelve cases is NOT adopted, and the reason is recorded where it
// stood — see the note below. Every other assertion is unchanged.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show
        SyncRpcTransport,
        SyncSession,
        SyncTransportErrorKind,
        SyncTransportException;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/order_identity.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_attempt.dart';
import 'package:restoflow_pos/src/data/payment_attempt_store.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart'
    show
        posAuthTransportProvider,
        posSignedInEmployeeProfileIdProvider,
        posSyncSessionProvider;
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/payment_attempt_server_fake.dart';

const _scope = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-A',
  deviceId: 'device-A',
);

final _now = DateTime.utc(2026, 9, 9, 8);

class _CountingIds implements ClientIdGenerator {
  int calls = 0;

  @override
  String newId() => 'reviewer-id-${++calls}';
}

PosOrderSnapshot _snapshot() => PosOrderSnapshot(
  orderId: 'order-1',
  orderCode: '#A1',
  revision: 3,
  status: 'submitted',
  settlement: PosSettlement.unpaid,
  subtotalMinor: 4000,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 4000,
  createdAt: _now.subtract(const Duration(hours: 1)),
  updatedAt: _now.subtract(const Duration(minutes: 50)),
  syncAt: _now.subtract(const Duration(minutes: 50)),
  orderType: 'takeaway',
  currencyCode: 'ILS',
);

PaymentAttemptServerFake _server({required bool shiftOpen}) =>
    PaymentAttemptServerFake(
      orders: <FakeServerOrder>[
        FakeServerOrder(orderId: 'order-1', grandTotalMinor: 4000, revision: 3),
      ],
      devicesWithOpenShift: shiftOpen ? const <String>{'device-A'} : const {},
    );

class _SecondPushPreconditionTransport implements SyncRpcTransport {
  _SecondPushPreconditionTransport(this.delegate);

  final PaymentAttemptServerFake delegate;
  final List<Map<String, dynamic>> paymentOps = <Map<String, dynamic>>[];
  int paymentPushes = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'sync_push') {
      final raw = params['p_operations'];
      if (raw is List) {
        for (final entry in raw) {
          if (entry is Map && entry['operation_type'] == 'payment.create') {
            paymentOps.add(
              jsonDecode(jsonEncode(entry)) as Map<String, dynamic>,
            );
            paymentPushes++;
            if (paymentPushes == 2) {
              throw const SyncTransportException(
                SyncTransportErrorKind.server,
                code: '42501',
                message: 'record_payment: no open shift (precondition_failed)',
              );
            }
          }
        }
      }
    }
    return delegate.invoke(function, params);
  }
}

/// S1-R3 / F004 (adopted from the Codex history probe): the first push reaches the server but loses its
/// reply, the second is denied by the auth preamble, and the third is refused
/// before the operation ledger. The third answer cannot erase the uncertainty
/// created by the first invocation.
class _ThirdPushPreconditionTransport implements SyncRpcTransport {
  _ThirdPushPreconditionTransport(this.delegate);

  final PaymentAttemptServerFake delegate;
  final List<Map<String, dynamic>> paymentOps = <Map<String, dynamic>>[];
  int paymentPushes = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'sync_push') {
      final raw = params['p_operations'];
      if (raw is List) {
        for (final entry in raw) {
          if (entry is Map && entry['operation_type'] == 'payment.create') {
            paymentOps.add(
              jsonDecode(jsonEncode(entry)) as Map<String, dynamic>,
            );
            paymentPushes++;
            if (paymentPushes == 3) {
              throw const SyncTransportException(
                SyncTransportErrorKind.server,
                code: '42501',
                message: 'record_payment: no open shift (precondition_failed)',
              );
            }
          }
        }
      }
    }
    return delegate.invoke(function, params);
  }
}

class _FourthPushPreconditionTransport implements SyncRpcTransport {
  _FourthPushPreconditionTransport(this.delegate);

  final PaymentAttemptServerFake delegate;
  final List<Map<String, dynamic>> paymentOps = <Map<String, dynamic>>[];
  int paymentPushes = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'sync_push') {
      final raw = params['p_operations'];
      if (raw is List) {
        for (final entry in raw) {
          if (entry is Map && entry['operation_type'] == 'payment.create') {
            paymentOps.add(
              jsonDecode(jsonEncode(entry)) as Map<String, dynamic>,
            );
            paymentPushes++;
            if (paymentPushes == 2) {
              throw const SyncTransportException(
                SyncTransportErrorKind.server,
                code: 'P0001',
                message: 'synthetic rolled-back SQLSTATE',
              );
            }
            if (paymentPushes == 4) {
              throw const SyncTransportException(
                SyncTransportErrorKind.server,
                code: '42501',
                message: 'record_payment: no open shift (precondition_failed)',
              );
            }
          }
        }
      }
    }
    return delegate.invoke(function, params);
  }
}

PaymentAttempt _sentAttempt({int? revision = 3}) => PaymentAttempt.mint(
  ids: FixedClientIdGenerator(const <String>['legacy-op', 'legacy-target']),
  now: _now,
  orderId: 'order-1',
  orderNumber: '#A1',
  amountMinor: 4000,
  tenderedMinor: 5000,
  currencyCode: 'ILS',
  method: PaymentMethod.cash,
  expectedRevision: revision,
  organizationId: _scope.organizationId,
  restaurantId: _scope.restaurantId,
  branchId: _scope.branchId,
  deviceId: _scope.deviceId,
  employeeProfileId: 'emp-1',
).markSent(_now.toIso8601String());

class _Till {
  const _Till({
    required this.container,
    required this.ids,
    required this.store,
  });

  final ProviderContainer container;
  final _CountingIds ids;
  final SharedPrefsPaymentAttemptStore store;

  PaymentController get payments =>
      container.read(paymentControllerProvider.notifier);

  Future<PaymentAttemptOutcome> submit() => payments.submitAttempt(
    identity: PosOrderIdentity.server('order-1'),
    orderId: 'order-1',
    orderNumber: '#A1',
    amountMinor: 4000,
    tenderedMinor: 5000,
    currencyCode: 'ILS',
    expectedRevision: 3,
  );

  Future<PaymentAttemptOutcome> resume() =>
      payments.resumeAttempt(PosOrderIdentity.server('order-1'));
}

/// Builds a till. Passing [store] and [ids] REBUILDS the whole controller
/// stack over the same durable store and the same identity generator, which is
/// exactly what a provider rebuild leaves behind.
Future<_Till> _till(
  SyncRpcTransport transport, {
  SharedPrefsPaymentAttemptStore? existingStore,
  _CountingIds? existingIds,
}) async {
  SharedPrefsPaymentAttemptStore store;
  if (existingStore == null) {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    store = SharedPrefsPaymentAttemptStore(
      await SharedPreferences.getInstance(),
    );
  } else {
    store = existingStore;
  }
  final ids = existingIds ?? _CountingIds();
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport),
      posSyncSessionProvider.overrideWithValue(
        const SyncSession(pinSessionId: 'pin-A', deviceId: 'device-A'),
      ),
      posSyncScopeProvider.overrideWithValue(_scope),
      clientIdGeneratorProvider.overrideWithValue(ids),
      paymentAttemptStoreProvider.overrideWithValue(store),
      posRecentOrdersStoreProvider.overrideWithValue(
        InMemoryRecentOrdersStore(),
      ),
      orderSnapshotRepositoryProvider.overrideWithValue(
        DemoOrderSnapshotRepository(seed: <PosOrderSnapshot>[_snapshot()]),
      ),
      posSyncPollIntervalProvider.overrideWithValue(null),
      posSyncClockProvider.overrideWithValue(() => _now),
    ],
  );
  addTearDown(container.dispose);
  container.read(posSignedInEmployeeProfileIdProvider.notifier).set('emp-1');
  return _Till(container: container, ids: ids, store: store);
}

Map<String, dynamic> _paymentOp(RecordedPush push) =>
    push.ops.singleWhere((op) => op['operation_type'] == 'payment.create');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // S1-R4: the physical-key boundary and the in-process disclosure register are
  // both isolate-wide by design, so each test starts from a clean one.
  setUp(resetPaymentAttemptKeyGuardsForTest);
  setUp(resetPaymentDisclosuresForTest);

  // S1-R3 / F001: the physical-key trust boundary is deliberately isolate-wide
  // and impossible to clear at runtime, so each test starts from a clean one.
  setUp(resetPaymentAttemptKeyGuardsForTest);

  test(
    'REVIEWER-B2-001 ambiguous send then auth preamble denial stays pending and reuses key',
    () async {
      final server = _server(shiftOpen: true)
        ..faultNext(ServerFault.dropResponseAfterCommit);
      final till = await _till(server);

      final first = await till.submit();
      final afterFirst = await till.store.load(_scope);
      server.invalidPinSessions.add('pin-A');
      final second = await till.resume();
      final afterAuth = await till.store.load(_scope);
      server.invalidPinSessions.remove('pin-A');
      final third = await till.resume();
      final afterRecovery = await till.store.load(_scope);
      final ops = server.attemptedPushes.map(_paymentOp).toList();

      expect(
        <String, Object?>{
          'first': first.runtimeType.toString(),
          'phaseAfterFirst': afterFirst.attempts.single.phase.wire,
          'second': second.runtimeType.toString(),
          'phaseAfterAuth': afterAuth.attempts.single.phase.wire,
          'lastAfterAuth': afterAuth.attempts.single.lastOutcome.wire,
          'third': third.runtimeType.toString(),
          'phaseAfterRecovery': afterRecovery.attempts.single.phase.wire,
          'ids': till.ids.calls,
          'distinctOps': ops
              .map((op) => op['local_operation_id'])
              .toSet()
              .length,
          'distinctTargets': ops.map((op) => op['target_id']).toSet().length,
          'executions': server.executions,
          'replays': server.replays,
          'payments': server.completedPaymentsFor('order-1'),
        },
        <String, Object?>{
          'first': 'PaymentAttemptUnconfirmed',
          'phaseAfterFirst': 'pending',
          'second': 'PaymentAttemptAuthRequired',
          'phaseAfterAuth': 'pending',
          'lastAfterAuth': 'auth_required',
          'third': 'PaymentAttemptAccepted',
          'phaseAfterRecovery': 'accepted',
          'ids': 2,
          'distinctOps': 1,
          'distinctTargets': 1,
          'executions': 1,
          'replays': 1,
          'payments': 1,
        },
      );
    },
  );

  test(
    'REVIEWER-B2-002 ambiguous send then nonmemoized precondition stays pending and cannot mint',
    () async {
      final server = _server(shiftOpen: true)
        ..faultNext(ServerFault.dropResponseAfterCommit);
      final transport = _SecondPushPreconditionTransport(server);
      final till = await _till(transport);

      final first = await till.submit();
      final second = await till.resume();
      final afterPrecondition = await till.store.load(_scope);
      final idsAfterPrecondition = till.ids.calls;
      final third = await till.submit();
      final afterRetry = await till.store.load(_scope);
      final opIds = transport.paymentOps
          .map((op) => op['local_operation_id'])
          .toSet();
      final targetIds = transport.paymentOps
          .map((op) => op['target_id'])
          .toSet();

      expect(
        <String, Object?>{
          'first': first.runtimeType.toString(),
          'secondWasAccepted': second is PaymentAttemptAccepted,
          'phaseAfterPrecondition': afterPrecondition.attempts.first.phase.wire,
          'idsAfterPrecondition': idsAfterPrecondition,
          'third': third.runtimeType.toString(),
          'finalAttemptCount': afterRetry.attempts.length,
          'finalPhase': afterRetry.attempts.last.phase.wire,
          'idsFinal': till.ids.calls,
          'distinctOps': opIds.length,
          'distinctTargets': targetIds.length,
          'executions': server.executions,
          'replays': server.replays,
          'payments': server.completedPaymentsFor('order-1'),
        },
        <String, Object?>{
          'first': 'PaymentAttemptUnconfirmed',
          'secondWasAccepted': false,
          'phaseAfterPrecondition': 'pending',
          'idsAfterPrecondition': 2,
          'third': 'PaymentAttemptAccepted',
          'finalAttemptCount': 1,
          'finalPhase': 'accepted',
          'idsFinal': 2,
          'distinctOps': 1,
          'distinctTargets': 1,
          'executions': 1,
          'replays': 1,
          'payments': 1,
        },
      );
    },
  );

  test(
    'REVIEWER-B2-003 memoized ledger refusal is terminal and permits linked correction control',
    () async {
      final server = _server(shiftOpen: false);
      final till = await _till(server);

      final first = await till.submit();
      final afterRefusal = await till.store.load(_scope);
      server.shiftOpenDevices.add('device-A');
      final second = await till.submit();
      final afterCorrection = await till.store.load(_scope);
      final ops = server.paymentOpsSeen;

      expect(
        <String, Object?>{
          'first': first.runtimeType.toString(),
          'firstPhase': afterRefusal.attempts.single.phase.wire,
          'firstMemoized': afterRefusal.attempts.single.refusalMemoized,
          'second': second.runtimeType.toString(),
          'attemptCount': afterCorrection.attempts.length,
          'linked':
              afterCorrection.attempts.last.supersedes ==
              afterCorrection.attempts.first.localOperationId,
          'ids': till.ids.calls,
          'distinctOps': ops
              .map((op) => op['local_operation_id'])
              .toSet()
              .length,
          'payments': server.completedPaymentsFor('order-1'),
        },
        <String, Object?>{
          'first': 'PaymentAttemptRefused',
          'firstPhase': 'refused',
          'firstMemoized': true,
          'second': 'PaymentAttemptAccepted',
          'attemptCount': 2,
          'linked': true,
          'ids': 4,
          'distinctOps': 2,
          'payments': 1,
        },
      );
    },
  );

  // =========================================================================
  // S1-R2 / F004 — the same three sequences, with the controller REBUILT over
  // the same durable store before the retry. A rebuilt controller holds no
  // in-memory memory of the ambiguity, so everything it decides comes from the
  // stored record; these are the runs that would expose a fix that only lives
  // in controller state.
  // =========================================================================
  // S1-R3 — the chained-history probe, adopted UNCHANGED in substance from
  // Codex's external harness `reviewer_f004_history_test.dart`. At 5159338a it
  // failed twice: the intervening auth denial overwrote the single
  // `last_outcome` enum, so the following non-memoized refusal terminalised an
  // attempt whose money may already have moved, and the next Confirm minted a
  // replacement identity. Nothing in its assertions was altered.
  test(
    'REVIEWER-R2-F004-HISTORY ambiguity survives intervening auth before a nonmemoized refusal',
    () async {
      final server = _server(shiftOpen: true)
        ..faultNext(ServerFault.dropResponseAfterCommit);
      final transport = _ThirdPushPreconditionTransport(server);
      final till = await _till(transport);

      final first = await till.submit();
      server.invalidPinSessions.add('pin-A');
      final second = await till.resume();
      server.invalidPinSessions.remove('pin-A');
      final third = await till.resume();
      final afterThird = await till.store.load(_scope);
      final idsAfterThird = till.ids.calls;
      final fourth = await till.submit();
      final afterRecovery = await till.store.load(_scope);

      expect(
        <String, Object?>{
          'first': first.runtimeType.toString(),
          'second': second.runtimeType.toString(),
          'third': third.runtimeType.toString(),
          'phaseAfterThird': afterThird.attempts.single.phase.wire,
          'idsAfterThird': idsAfterThird,
          'fourth': fourth.runtimeType.toString(),
          'attemptCount': afterRecovery.attempts.length,
          'finalPhase': afterRecovery.attempts.last.phase.wire,
          'idsFinal': till.ids.calls,
          'distinctOps': transport.paymentOps
              .map((op) => op['local_operation_id'])
              .toSet()
              .length,
          'distinctTargets': transport.paymentOps
              .map((op) => op['target_id'])
              .toSet()
              .length,
          'executions': server.executions,
          'payments': server.completedPaymentsFor('order-1'),
        },
        <String, Object?>{
          'first': 'PaymentAttemptUnconfirmed',
          'second': 'PaymentAttemptAuthRequired',
          'third': 'PaymentAttemptUnconfirmed',
          'phaseAfterThird': 'pending',
          'idsAfterThird': 2,
          'fourth': 'PaymentAttemptAccepted',
          'attemptCount': 1,
          'finalPhase': 'accepted',
          'idsFinal': 2,
          'distinctOps': 1,
          'distinctTargets': 1,
          'executions': 1,
          'payments': 1,
        },
        reason:
            'an auth denial proves only that invocation rolled back; it cannot '
            'erase the earlier lost-reply ambiguity or let a later transient '
            'refusal retire the original payment identity',
      );
    },
  );

  test(
    'S1R2-F004a REVIEWER-B2-001 across a controller rebuild: the auth-denied '
    'attempt resumes under the SAME key and pays exactly once',
    () async {
      final server = _server(shiftOpen: true)
        ..faultNext(ServerFault.dropResponseAfterCommit);
      final till = await _till(server);

      final first = await till.submit();
      server.invalidPinSessions.add('pin-A');
      final second = await till.resume();

      // The provider graph is thrown away and rebuilt over the same store.
      final rebuilt = await _till(
        server,
        existingStore: till.store,
        existingIds: till.ids,
      );
      server.invalidPinSessions.remove('pin-A');
      final third = await rebuilt.resume();
      final stored = await rebuilt.store.load(_scope);
      final ops = server.attemptedPushes.map(_paymentOp).toList();

      expect(
        <String, Object?>{
          'first': first.runtimeType.toString(),
          'second': second.runtimeType.toString(),
          'third': third.runtimeType.toString(),
          'attempts': stored.attempts.length,
          'phase': stored.attempts.single.phase.wire,
          'ids': rebuilt.ids.calls,
          'distinctOps': ops
              .map((op) => op['local_operation_id'])
              .toSet()
              .length,
          'distinctTargets': ops.map((op) => op['target_id']).toSet().length,
          'executions': server.executions,
          'payments': server.completedPaymentsFor('order-1'),
        },
        <String, Object?>{
          'first': 'PaymentAttemptUnconfirmed',
          'second': 'PaymentAttemptAuthRequired',
          'third': 'PaymentAttemptAccepted',
          'attempts': 1,
          'phase': 'accepted',
          'ids': 2,
          'distinctOps': 1,
          'distinctTargets': 1,
          'executions': 1,
          'payments': 1,
        },
      );
    },
  );

  test('S1R2-F004b REVIEWER-B2-002 across a controller rebuild: a TRANSIENT '
      'precondition refusal is never remembered as a settlement', () async {
    final server = _server(shiftOpen: true)
      ..faultNext(ServerFault.dropResponseAfterCommit);
    final transport = _SecondPushPreconditionTransport(server);
    final till = await _till(transport);

    final first = await till.submit();
    final second = await till.resume();
    final afterRefusal = await till.store.load(_scope);

    final rebuilt = await _till(
      transport,
      existingStore: till.store,
      existingIds: till.ids,
    );
    final third = await rebuilt.resume();
    final stored = await rebuilt.store.load(_scope);
    final opIds = transport.paymentOps
        .map((op) => op['local_operation_id'])
        .toSet();

    expect(
      <String, Object?>{
        'first': first.runtimeType.toString(),
        'secondWasAccepted': second is PaymentAttemptAccepted,
        'secondWasRefused': second is PaymentAttemptRefused,
        'phaseAfterRefusal': afterRefusal.attempts.single.phase.wire,
        'memoAfterRefusal': afterRefusal.attempts.single.refusalMemoized,
        'third': third.runtimeType.toString(),
        'attempts': stored.attempts.length,
        'phase': stored.attempts.single.phase.wire,
        'ids': rebuilt.ids.calls,
        'distinctOps': opIds.length,
        'executions': server.executions,
        'payments': server.completedPaymentsFor('order-1'),
      },
      <String, Object?>{
        'first': 'PaymentAttemptUnconfirmed',
        'secondWasAccepted': false,
        'secondWasRefused': false,
        'phaseAfterRefusal': 'pending',
        'memoAfterRefusal': false,
        'third': 'PaymentAttemptAccepted',
        'attempts': 1,
        'phase': 'accepted',
        'ids': 2,
        'distinctOps': 1,
        'executions': 1,
        'payments': 1,
      },
    );
  });

  test(
    'S1R2-F004c REVIEWER-B2-003 across a controller rebuild: a MEMOIZED '
    'refusal is still terminal and still takes the linked correction',
    () async {
      final server = _server(shiftOpen: false);
      final till = await _till(server);

      final first = await till.submit();
      final afterRefusal = await till.store.load(_scope);

      final rebuilt = await _till(
        server,
        existingStore: till.store,
        existingIds: till.ids,
      );
      server.shiftOpenDevices.add('device-A');
      final second = await rebuilt.submit();
      final stored = await rebuilt.store.load(_scope);

      expect(
        <String, Object?>{
          'first': first.runtimeType.toString(),
          'firstPhase': afterRefusal.attempts.single.phase.wire,
          'firstMemoized': afterRefusal.attempts.single.refusalMemoized,
          'second': second.runtimeType.toString(),
          'attempts': stored.attempts.length,
          'linked':
              stored.attempts.last.supersedes ==
              stored.attempts.first.localOperationId,
          'payments': server.completedPaymentsFor('order-1'),
        },
        <String, Object?>{
          'first': 'PaymentAttemptRefused',
          'firstPhase': 'refused',
          'firstMemoized': true,
          'second': 'PaymentAttemptAccepted',
          'attempts': 2,
          'linked': true,
          'payments': 1,
        },
      );
    },
  );

  test('CODEX-F004-LEGACY-001 missing/null flag derives conservatively from '
      'sent_at and the monotonic fact survives later diagnostics', () {
    for (final mode in const <String>['missing', 'null']) {
      final raw = _sentAttempt().toJson();
      if (mode == 'missing') {
        raw.remove('may_have_executed');
      } else {
        raw['may_have_executed'] = null;
      }
      final decoded = PaymentAttempt.fromJson(raw);
      expect(decoded.mayHaveExecuted, isTrue, reason: mode);
      for (final outcome in PaymentAttemptLastOutcome.values) {
        expect(
          decoded.withLastOutcome(outcome).mayHaveExecuted,
          isTrue,
          reason: '$mode/${outcome.wire}',
        );
      }
    }

    final legacyNullRevision = _sentAttempt(revision: null).toJson()
      ..remove('may_have_executed');
    final decodedNullRevision = PaymentAttempt.fromJson(legacyNullRevision);
    expect(decodedNullRevision.expectedRevision, isNull);
    expect(decodedNullRevision.mayHaveExecuted, isTrue);

    final wrongType = _sentAttempt().toJson()..['may_have_executed'] = 'true';
    expect(
      () => PaymentAttempt.fromJson(wrongType),
      throwsA(isA<FormatException>()),
    );
  });

  test('CODEX-F004-SCHEDULE-001 ambiguity survives alternating not-applied and '
      'auth diagnostics plus rebuilds', () async {
    final server = _server(shiftOpen: true)
      ..faultNext(ServerFault.dropResponseAfterCommit);
    final transport = _FourthPushPreconditionTransport(server);
    final firstTill = await _till(transport);

    final first = await firstTill.submit();
    final secondTill = await _till(
      transport,
      existingStore: firstTill.store,
      existingIds: firstTill.ids,
    );
    final second = await secondTill.resume();

    server.invalidPinSessions.add('pin-A');
    final thirdTill = await _till(
      transport,
      existingStore: firstTill.store,
      existingIds: firstTill.ids,
    );
    final third = await thirdTill.resume();
    server.invalidPinSessions.remove('pin-A');

    final fourthTill = await _till(
      transport,
      existingStore: firstTill.store,
      existingIds: firstTill.ids,
    );
    final fourth = await fourthTill.resume();
    final stored = await firstTill.store.load(_scope);

    expect(
      <String, Object?>{
        'first': first.runtimeType.toString(),
        'second': second.runtimeType.toString(),
        'third': third.runtimeType.toString(),
        'fourth': fourth.runtimeType.toString(),
        'phase': stored.attempts.single.phase.wire,
        'last': stored.attempts.single.lastOutcome.wire,
        'mayHaveExecuted': stored.attempts.single.mayHaveExecuted,
        'ids': fourthTill.ids.calls,
        'distinctOps': transport.paymentOps
            .map((op) => op['local_operation_id'])
            .toSet()
            .length,
        'distinctTargets': transport.paymentOps
            .map((op) => op['target_id'])
            .toSet()
            .length,
        'executions': server.executions,
        'payments': server.completedPaymentsFor('order-1'),
      },
      <String, Object?>{
        'first': 'PaymentAttemptUnconfirmed',
        'second': 'PaymentAttemptNotApplied',
        'third': 'PaymentAttemptAuthRequired',
        'fourth': 'PaymentAttemptUnconfirmed',
        'phase': 'pending',
        'last': 'auth_required',
        'mayHaveExecuted': true,
        'ids': 2,
        'distinctOps': 1,
        'distinctTargets': 1,
        'executions': 1,
        'payments': 1,
      },
    );
  });

  test('CODEX-F004-LEGACY-002 false may_have_executed plus sent_at must be '
      'quarantined as contradictory evidence', () {
    final contradictory = _sentAttempt().toJson()
      ..['may_have_executed'] = false;
    expect(
      () => PaymentAttempt.fromJson(contradictory),
      throwsA(isA<FormatException>()),
      reason:
          'sent_at proves dispatch may have started; an explicit false flag '
          'must not downgrade that history',
    );
  });

  // NOT ADOPTED — CODEX-F004-LEGACY-003.
  //
  // This case and `CODEX-F004-LEGACY-002` describe the SAME stored record:
  // `_sentAttempt().toJson()..['may_have_executed'] = false`, i.e. an explicit
  // false flag beside a non-null `sent_at`. LEGACY-002 requires
  // `PaymentAttempt.fromJson` to throw for it, and the independent F002/F003
  // matrix requires the STORE to report it as `(0 attempts, 1 quarantine)`.
  // LEGACY-003 instead requires the same record to load as a resumable pending
  // attempt, be pushed once, and keep its original operation id — which is only
  // possible if it is NOT quarantined.
  //
  // The two cannot both hold. This build takes the quarantine reading, which
  // satisfies LEGACY-002, LEGACY-004 and all four F003 codec cases, and which
  // the governing brief states directly: an explicitly contradictory record
  // must not be silently repaired into authority, and a decode failure may not
  // produce a resend or a new identity. A conservative read-only interpretation
  // is reserved for RECOGNISED legacy forms — a record MISSING the field, which
  // `CODEX-F004-LEGACY-004` covers and which this build derives conservatively.
  //
  // The consequence is stated rather than hidden: a record in this exact
  // contradictory shape is blocked for the cashier and needs manager recovery,
  // instead of being re-pushed under its old identity.

  test('CODEX-F004-LEGACY-004 missing flag with terminal or explicitly '
      'ambiguous history must quarantine or derive true', () {
    bool isConservative(Map<String, Object?> raw) {
      try {
        return PaymentAttempt.fromJson(raw).mayHaveExecuted;
      } on FormatException {
        return true;
      }
    }

    Map<String, Object?> withoutMarkerAndSentAt(PaymentAttempt attempt) =>
        attempt.toJson()
          ..remove('may_have_executed')
          ..['sent_at'] = null;

    final accepted = _sentAttempt().accepted(
      const PaymentAttemptResolution(
        paymentId: 'pay-1',
        receiptNumber: 'R-1',
        changeDueMinor: 1000,
        method: PaymentMethod.cash,
        replay: false,
        orderStatus: 'submitted',
      ),
      at: _now.toIso8601String(),
      reserveEffects: true,
    );
    final refused = _sentAttempt().refused(
      PaymentRefusalCode.shiftRequired,
      at: _now.toIso8601String(),
      memoized: true,
    );
    final ambiguous = _sentAttempt().withLastOutcome(
      PaymentAttemptLastOutcome.unconfirmed,
    );

    expect(
      <String, bool>{
        'accepted': isConservative(withoutMarkerAndSentAt(accepted)),
        'refused': isConservative(withoutMarkerAndSentAt(refused)),
        'unconfirmed': isConservative(withoutMarkerAndSentAt(ambiguous)),
      },
      <String, bool>{'accepted': true, 'refused': true, 'unconfirmed': true},
      reason:
          'missing new metadata is not proof that older terminal or explicit '
          'ambiguity history never executed',
    );
  });
}
