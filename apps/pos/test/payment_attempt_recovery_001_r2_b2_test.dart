// PAYMENT-ATTEMPT-RECOVERY-001 / S1-R2 — the B2 transient-refusal probes.
//
// Adopted verbatim in substance from the external Codex delta review that
// raised S1-F004: after a TRANSIENT refusal of a re-send (a precondition
// failure on the second push), the controller answered the cashier from a
// memoized refusal instead of the ambiguity the attempt still carried, so an
// attempt whose money may already have moved could be presented as settled.
//
// Every sequence here runs the REAL controller/repository/store over the
// contract-faithful server fake, so the identity, the ledger key and the
// re-send path are the production ones.
//
// S1-R2 adds the RECREATION variant of each sequence: the controller is
// rebuilt over the SAME durable store between the ambiguity and the retry, as
// a provider rebuild or a returning-to-foreground POS does. The
// FAILED-PERSISTENCE variants need a write-refusing preferences adapter and
// live with that adapter, in the `S1-R2/F004` group of
// `payment_attempt_recovery_001_s1_test.dart`.
//
// Synthetic ids, amounts and sessions only. No network, no printer, no drawer.
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
}
