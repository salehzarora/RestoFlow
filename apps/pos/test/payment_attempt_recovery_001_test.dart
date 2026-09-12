// PAYMENT-ATTEMPT-RECOVERY-001 (BCA-MONEY-001) — the regression matrix over the
// DURABLE attempt seam: store, repository classifier, controller outcomes.
//
// Companion files:
//   * payment_attempt_recovery_001_red_test.dart — the baseline-RED cases
//     (R1, R2, R5, R7, R11) that fail on dc56065e without any new API;
//   * payment_attempt_recovery_001_sheet_test.dart — the cashier-facing sheet
//     (R14 effect windows, R16 surfaces, AR/HE/EN wording).
//
// Every server answer comes from the contract-faithful stateful fake in
// support/payment_attempt_server_fake.dart (a FAKE of the final SQL contract,
// read from source — not a database). The store under test is the REAL
// SharedPrefsPaymentAttemptStore over mock-initialised SharedPreferences; a
// "process restart" is a NEW store instance + NEW ProviderContainer over the
// SAME preferences (the house convention), and one case additionally reopens
// the adapter over a byte-copied backing store.
//
// Synthetic ids, amounts and sessions only. No network, no printer, no drawer.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession, SyncTransportErrorKind, SyncTransportException;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/order_identity.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_attempt.dart';
import 'package:restoflow_pos/src/data/payment_attempt_store.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
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

import 'support/failing_prefs.dart';
import 'support/payment_attempt_server_fake.dart';

class _CountingIds implements ClientIdGenerator {
  _CountingIds(this._prefix);
  final String _prefix;
  int calls = 0;

  @override
  String newId() => '$_prefix-id-${++calls}';
}

/// A SharedPreferences double whose `setString` HOLDS until released — the
/// "persistence in progress" window of R4 — and can also be scripted to fail
/// AFTER N successful writes (R9: the acceptance save fails).
class _ScriptedPrefs implements SharedPreferences {
  _ScriptedPrefs(this._inner);
  final SharedPreferences _inner;

  Completer<void>? hold;
  int failAfterWrites = -1;
  int writes = 0;

  /// R3b: the write LANDS and then the adapter reports failure anyway.
  bool landThenReportFalse = false;

  @override
  Future<bool> setString(String key, String value) async {
    final h = hold;
    if (h != null) await h.future;
    writes++;
    if (failAfterWrites >= 0 && writes > failAfterWrites) return false;
    final ok = await _inner.setString(key, value);
    if (landThenReportFalse) return false;
    return ok;
  }

  @override
  String? getString(String key) => _inner.getString(key);

  @override
  Future<bool> remove(String key) => _inner.remove(key);

  @override
  bool containsKey(String key) => _inner.containsKey(key);

  @override
  Set<String> getKeys() => _inner.getKeys();

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused: ${invocation.memberName}');
}

/// PDR-001: an INDEPENDENT view of what actually reached storage, for the one
/// test that needs the landed-then-failed recovery to be provable.
/// An INDEPENDENT view of what actually reached the underlying preferences.
///
/// S1-R3: after an unverified write the writing adapter's cache is no longer
/// evidence, so a probe that asks "what is really on disk" must read through
/// the independent seam, exactly as the product does.
class _PrefsBackingReader implements PaymentAttemptBackingReader {
  const _PrefsBackingReader(this.prefs);
  final SharedPreferences prefs;

  @override
  Future<String?> readRaw(String physicalKey) async => prefs.getString(
    physicalKey.startsWith(kLegacySharedPreferencesKeyPrefix)
        ? physicalKey.substring(kLegacySharedPreferencesKeyPrefix.length)
        : physicalKey,
  );
}

SharedPrefsPaymentAttemptStore _durableView(SharedPreferences prefs) =>
    SharedPrefsPaymentAttemptStore(
      prefs,
      backingReader: _PrefsBackingReader(prefs),
    );

class _MapBackingReader implements PaymentAttemptBackingReader {
  _MapBackingReader(this._prefs);
  final SharedPreferences _prefs;

  @override
  Future<String?> readRaw(String physicalKey) async {
    final logical = physicalKey.startsWith(kLegacySharedPreferencesKeyPrefix)
        ? physicalKey.substring(kLegacySharedPreferencesKeyPrefix.length)
        : physicalKey;
    return _prefs.getString(logical);
  }
}

const _scopeA = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-A',
  deviceId: 'device-A',
);
const _scopeB = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-A',
  deviceId: 'device-B',
);

final _pinnedNow = DateTime.utc(2026, 9, 8, 12);

PosOrderSnapshot _snapshot({
  String orderId = 'order-1',
  String code = '#A1',
  int revision = 3,
  int total = 4000,
  PosSettlement settlement = PosSettlement.unpaid,
}) => PosOrderSnapshot(
  orderId: orderId,
  orderCode: code,
  revision: revision,
  status: 'submitted',
  settlement: settlement,
  subtotalMinor: total,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: total,
  createdAt: _pinnedNow.subtract(const Duration(hours: 1)),
  updatedAt: _pinnedNow.subtract(const Duration(minutes: 50)),
  syncAt: _pinnedNow.subtract(const Duration(minutes: 50)),
  orderType: 'takeaway',
  currencyCode: 'ILS',
);

/// One REAL-mode till process: the real repository + controller + store.
class _Till {
  _Till({
    required this.container,
    required this.ids,
    required this.store,
    required this.snapshots,
  });

  final ProviderContainer container;
  final _CountingIds ids;
  final PaymentAttemptStore store;
  final DemoOrderSnapshotRepository snapshots;

  PaymentController get payments =>
      container.read(paymentControllerProvider.notifier);
  PaymentState get state => container.read(paymentControllerProvider);

  Future<PaymentAttemptOutcome> submit({
    String orderId = 'order-1',
    String orderNumber = '#A1',
    int amountMinor = 4000,
    int tenderedMinor = 5000,
    String currencyCode = 'ILS',
    PaymentMethod method = PaymentMethod.cash,
    int? expectedRevision = 3,
  }) => payments.submitAttempt(
    identity: PosOrderIdentity.server(orderId),
    orderId: orderId,
    orderNumber: orderNumber,
    amountMinor: amountMinor,
    tenderedMinor: tenderedMinor,
    currencyCode: currencyCode,
    method: method,
    expectedRevision: expectedRevision,
  );

  Future<PaymentAttemptOutcome> resume([String orderId = 'order-1']) =>
      payments.resumeAttempt(PosOrderIdentity.server(orderId));

  Future<PaymentAttemptStatusCheck> check([String orderId = 'order-1']) =>
      payments.checkStatus(PosOrderIdentity.server(orderId));
}

_Till _till({
  required PaymentAttemptServerFake server,
  PosSyncScope scope = _scopeA,
  required PaymentAttemptStore store,
  _CountingIds? ids,
  String employee = 'emp-1',
  String pinSession = 'pin-A',
  DemoOrderSnapshotRepository? snapshots,
}) {
  final counting = ids ?? _CountingIds(scope.deviceId);
  final snaps = snapshots ?? DemoOrderSnapshotRepository(seed: [_snapshot()]);
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(server),
      posSyncSessionProvider.overrideWithValue(
        SyncSession(pinSessionId: pinSession, deviceId: scope.deviceId),
      ),
      posSyncScopeProvider.overrideWithValue(scope),
      clientIdGeneratorProvider.overrideWithValue(counting),
      paymentAttemptStoreProvider.overrideWithValue(store),
      posRecentOrdersStoreProvider.overrideWithValue(
        InMemoryRecentOrdersStore(),
      ),
      orderSnapshotRepositoryProvider.overrideWithValue(snaps),
      posSyncPollIntervalProvider.overrideWithValue(null),
      posSyncClockProvider.overrideWithValue(() => _pinnedNow),
    ],
  );
  addTearDown(container.dispose);
  container.read(posSignedInEmployeeProfileIdProvider.notifier).set(employee);
  return _Till(
    container: container,
    ids: counting,
    store: store,
    snapshots: snaps,
  );
}

PaymentAttemptServerFake _server({
  Iterable<String> shifts = const {'device-A'},
  int total = 4000,
}) => PaymentAttemptServerFake(
  orders: [
    FakeServerOrder(orderId: 'order-1', grandTotalMinor: total, revision: 3),
    FakeServerOrder(orderId: 'order-2', grandTotalMinor: 2500, revision: 1),
  ],
  devicesWithOpenShift: shifts,
);

Future<SharedPreferences> _freshPrefs() async {
  SharedPreferences.setMockInitialValues(const {});
  return SharedPreferences.getInstance();
}

/// A byte-copy reopen of the backing store: what is on disk, and NOTHING else,
/// comes back through a brand-new adapter instance.
Future<SharedPreferences> _reopenBacking(SharedPreferences prefs) async {
  final copy = <String, Object>{
    for (final k in prefs.getKeys()) k: prefs.getString(k)!,
  };
  SharedPreferences.setMockInitialValues(copy);
  return SharedPreferences.getInstance();
}

Future<void> _settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.microtask(() {});
  }
}

PaymentAttempt _attemptFixture({
  String op = 'op-x',
  String orderId = 'order-1',
  PosSyncScope scope = _scopeA,
  String? employee = 'emp-1',
}) => PaymentAttempt.mint(
  ids: FixedClientIdGenerator([op, '$op-target']),
  now: _pinnedNow,
  orderId: orderId,
  orderNumber: '#A1',
  amountMinor: 4000,
  tenderedMinor: 5000,
  currencyCode: 'ILS',
  method: PaymentMethod.cash,
  expectedRevision: 3,
  organizationId: scope.organizationId,
  restaurantId: scope.restaurantId,
  branchId: scope.branchId,
  deviceId: scope.deviceId,
  employeeProfileId: employee,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // S1-R3 / F001: the physical-key trust boundary is deliberately isolate-wide
  // and impossible to clear at runtime, so each test starts from a clean one.
  setUp(resetPaymentAttemptKeyGuardsForTest);

  // =========================================================================
  group('R2 restart / reopen reuses every immutable field', () {
    test(
      'R2a a NEW store + NEW controller over the SAME preferences hydrates the '
      'pending attempt and resumes it under the SAME identity (no new ids)',
      () async {
        final prefs = await _freshPrefs();
        final server = _server();
        final p1 = _till(
          server: server,
          store: SharedPrefsPaymentAttemptStore(prefs),
        );
        server.faultNext(ServerFault.dropResponseAfterCommit);
        final first = await p1.submit();
        expect(first, isA<PaymentAttemptUnconfirmed>());
        final sentOp = server.paymentOpsSeen.single;
        p1.container.dispose();

        // "Restart": nothing survives but the preferences.
        final p2 = _till(
          server: server,
          store: SharedPrefsPaymentAttemptStore(prefs),
        );
        await p2.payments.ensureHydrated();
        final pending = p2.state.pendingAttemptFor(
          PosOrderIdentity.server('order-1'),
        );
        expect(pending, isNotNull, reason: 'the attempt survived the restart');
        expect(pending!.localOperationId, sentOp['local_operation_id']);
        expect(pending.targetId, sentOp['target_id']);
        expect(pending.clientCreatedAt, sentOp['client_created_at']);
        expect(jsonEncode(pending.toSyncOperation()), jsonEncode(sentOp));

        final resumed = await p2.resume();
        expect(resumed, isA<PaymentAttemptAccepted>());
        final acc = resumed as PaymentAttemptAccepted;
        expect(acc.replay, isTrue);
        expect(acc.payment.paymentId, 'srv-pay-1');
        expect(p2.ids.calls, 0, reason: 'a resume NEVER mints');
        expect(server.paymentOpIdsFrom('device-A'), hasLength(1));
        expect(jsonEncode(server.paymentOpsSeen[1]), jsonEncode(sentOp));
        expect(server.completedPaymentsFor('order-1'), 1);
        expect(server.executions, 1);
        expect(server.replays, 1);
      },
    );

    test(
      'R2b the REAL adapter reopened over a byte-copied backing store yields '
      'the same record and the same resume',
      () async {
        final prefs = await _freshPrefs();
        final server = _server();
        final p1 = _till(
          server: server,
          store: SharedPrefsPaymentAttemptStore(prefs),
        );
        server.faultNext(ServerFault.gatewayTimeoutAfterCommit);
        expect(await p1.submit(), isA<PaymentAttemptUnconfirmed>());
        final sentOp = server.paymentOpsSeen.single;
        p1.container.dispose();

        final reopened = await _reopenBacking(prefs);
        final p2 = _till(
          server: server,
          store: SharedPrefsPaymentAttemptStore(reopened),
        );
        final resumed = await p2.resume();
        expect(resumed, isA<PaymentAttemptAccepted>());
        expect(jsonEncode(server.paymentOpsSeen[1]), jsonEncode(sentOp));
        expect(server.completedPaymentsFor('order-1'), 1);
      },
    );

    test('R2c an accepted attempt hydrates as PAID after a restart and a '
        'further submit sends nothing and mints nothing', () async {
      final prefs = await _freshPrefs();
      final server = _server();
      final p1 = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );
      expect(await p1.submit(), isA<PaymentAttemptAccepted>());
      p1.container.dispose();

      final p2 = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );
      await p2.payments.ensureHydrated();
      expect(
        p2.state.paymentFor(PosOrderIdentity.server('order-1'))?.paymentId,
        'srv-pay-1',
      );
      // R14: hydration is NOT a payment edge. A payment that merely appeared
      // from the durable store must never arm an automatic receipt/drawer.
      expect(
        p2.state.effectsArmedFor(PosOrderIdentity.server('order-1')),
        isFalse,
      );
      final again = await p2.submit();
      expect(again, isA<PaymentAttemptAccepted>());
      expect((again as PaymentAttemptAccepted).automaticEffectsArmed, isFalse);
      expect(p2.ids.calls, 0);
      expect(server.paymentOpsSeen, hasLength(1));
    });
  });

  // =========================================================================
  group('R3 persist BEFORE send', () {
    test('R3a/S1-F001 a refused durable write sends NOTHING, and the SAME '
        'adapter stays contained afterwards', () async {
      // CHANGED IN S1-R2. This used to assert that simply flipping the double
      // back to healthy let the next Confirm succeed. Codex S1-F001 showed why
      // that is unsafe: the failed write left an optimistic value in the
      // adapter's own cache, so a later call could adopt a record that never
      // reached storage and transmit a payment whose identity was never
      // established. The adapter is now untrusted for that key, and recovery
      // needs genuinely independent evidence — see R3a2.
      final prefs = await _freshPrefs();
      final failing = FailingPrefs(prefs)..failWrites = true;
      final server = _server();
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(failing),
      );
      final blocked = await till.submit();
      expect(blocked, isA<PaymentAttemptSaveBlocked>());
      expect(server.attemptedPushes, isEmpty, reason: 'zero network sends');
      expect(failing.writeAttempts, greaterThan(0));

      failing.failWrites = false;
      final after = await till.submit();
      expect(
        after,
        isNot(isA<PaymentAttemptAccepted>()),
        reason: 'the poisoned adapter can never authorise a send again',
      );
      expect(server.attemptedPushes, isEmpty);
    });

    test('R3a2/S1-F001 POSITIVE CONTROL: a genuinely independent reader lets '
        'the same scope recover and send exactly once', () async {
      final prefs = await _freshPrefs();
      final failing = FailingPrefs(prefs)..failWrites = true;
      final server = _server();
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(
          failing,
          backingReader: _MapBackingReader(prefs),
        ),
      );
      expect(await till.submit(), isA<PaymentAttemptSaveBlocked>());
      expect(server.attemptedPushes, isEmpty);

      // The platform recovers; reads now come from the independent view.
      failing.failWrites = false;
      final ok = await till.submit();
      expect(ok, isA<PaymentAttemptAccepted>());
      expect(server.paymentOpsSeen, hasLength(1));
      expect(server.completedPaymentsFor('order-1'), 1);
    });

    test('R3b/PDR-001 a write that LANDED but reported failure is recovered '
        'ONLY when an independent backing read proves it', () async {
      // CHANGED IN S1. This accepted a landed-then-failed write on the
      // strength of a re-read through the SAME adapter. Codex PDR-001 showed
      // that read returns the adapter's own optimistic cache, so it proves
      // nothing. The recovery still exists; it now requires evidence.
      final prefs = await _freshPrefs();
      final scripted = _ScriptedPrefs(prefs)..landThenReportFalse = true;
      final server = _server();
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(
          scripted,
          backingReader: _MapBackingReader(prefs),
        ),
      );
      final outcome = await till.submit();
      expect(outcome, isA<PaymentAttemptAccepted>());
      expect(server.paymentOpsSeen, hasLength(1));
      final load = await SharedPrefsPaymentAttemptStore(prefs).load(_scopeA);
      expect(load.attempts, hasLength(1));
      expect(load.quarantined, isEmpty);
    });

    test('R3b2/PDR-001 the same landed-then-failed write with NO independent '
        'reader fails closed: nothing is sent', () async {
      final prefs = await _freshPrefs();
      final scripted = _ScriptedPrefs(prefs)..landThenReportFalse = true;
      final server = _server();
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(scripted),
      );
      expect(await till.submit(), isA<PaymentAttemptSaveBlocked>());
      expect(server.attemptedPushes, isEmpty);
    });

    test('R3c no session / no scope: nothing minted, nothing sent', () async {
      final prefs = await _freshPrefs();
      final server = _server();
      final ids = _CountingIds('a');
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posAuthTransportProvider.overrideWithValue(server),
          posSyncSessionProvider.overrideWithValue(null),
          posSyncScopeProvider.overrideWithValue(null),
          clientIdGeneratorProvider.overrideWithValue(ids),
          paymentAttemptStoreProvider.overrideWithValue(
            SharedPrefsPaymentAttemptStore(prefs),
          ),
        ],
      );
      addTearDown(container.dispose);
      final outcome = await container
          .read(paymentControllerProvider.notifier)
          .submitAttempt(
            identity: PosOrderIdentity.server('order-1'),
            orderId: 'order-1',
            orderNumber: '#A1',
            amountMinor: 4000,
            tenderedMinor: 5000,
            currencyCode: 'ILS',
          );
      expect(outcome, isA<PaymentAttemptSaveBlocked>());
      expect(ids.calls, 0);
      expect(server.attemptedPushes, isEmpty);
    });
  });

  // =========================================================================
  group('R4 frozen inputs while persistence is held', () {
    test(
      'R4a a second submit with DIFFERENT tender during the held save cannot '
      'slip past the guard; the sent attempt carries the FIRST decision only',
      () async {
        final prefs = await _freshPrefs();
        final scripted = _ScriptedPrefs(prefs)..hold = Completer<void>();
        final server = _server();
        final till = _till(
          server: server,
          store: SharedPrefsPaymentAttemptStore(scripted),
        );
        final first = till.submit(); // cash 5000, held at the durable write
        await _settle();
        expect(server.attemptedPushes, isEmpty, reason: 'still persisting');

        final second = await till.submit(
          method: PaymentMethod.card,
          tenderedMinor: 4000,
        );
        expect(second, isA<PaymentAttemptBusy>());
        expect(server.attemptedPushes, isEmpty);

        scripted.hold!.complete();
        final outcome = await first;
        expect(outcome, isA<PaymentAttemptAccepted>());
        final op = server.paymentOpsSeen.single;
        expect(op['payload']['tender_type'], 'cash');
        expect(op['payload']['amount_tendered_minor'], 5000);
        expect(server.paymentOpsSeen, hasLength(1));
      },
    );

    test('R4b a DIFFERENT decision against an unresolved attempt is refused '
        'without a send; the SAME decision resumes it', () async {
      final prefs = await _freshPrefs();
      final server = _server();
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );
      server.faultNext(ServerFault.dropResponseAfterCommit);
      expect(await till.submit(), isA<PaymentAttemptUnconfirmed>());

      final changed = await till.submit(
        method: PaymentMethod.card,
        tenderedMinor: 4000,
      );
      expect(changed, isA<PaymentAttemptUnresolved>());
      expect(server.paymentOpsSeen, hasLength(1));
      expect(till.ids.calls, 2);

      // A refreshed revision is NOT a new decision.
      final same = await till.submit(expectedRevision: 4);
      expect(same, isA<PaymentAttemptAccepted>());
      expect(server.paymentOpsSeen, hasLength(2));
      expect(
        server.paymentOpsSeen[1]['payload']['expected_revision'],
        3,
        reason: 'the FROZEN payload is re-sent, byte for byte',
      );
    });
  });

  // =========================================================================
  group('R5 late response / applied replay', () {
    test('R5a a HELD response completes the original send; a resume in the '
        'meantime is busy and sends nothing; one settlement', () async {
      final prefs = await _freshPrefs();
      final server = _server();
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );
      server.faultNext(ServerFault.holdResponseAfterCommit);
      final inFlight = till.submit();
      await _settle();
      expect(server.isHolding, isTrue);
      expect(await till.resume(), isA<PaymentAttemptBusy>());
      expect(await till.check(), isA<PaymentAttemptStatusStillPending>());
      expect(server.pushes, hasLength(1));
      server.releaseHeld();
      final outcome = await inFlight;
      expect(outcome, isA<PaymentAttemptAccepted>());
      expect((outcome as PaymentAttemptAccepted).automaticEffectsArmed, isTrue);
      expect(server.completedPaymentsFor('order-1'), 1);
    });
  });

  // =========================================================================
  group(
    'R6 refusals, replays of refusals, malformed results — never success',
    () {
      PaymentAttempt a() => _attemptFixture();

      // S1/PDR-002: the final `sync_push` stamps `operation_type` on EVERY
      // per-op result, so the fixtures state it too. A validator is only as
      // honest as the shape it is fed.
      // CHANGED IN S1-R3: `sync_push` stamps `idempotency_replay` on EVERY
      // result it emits — false when it decided now, true when it replayed a
      // stored terminal row (20260905090001_..._002.sql:402-405, 798-800,
      // 848-853, 861-872). The default is therefore part of the source shape,
      // and any case that wants it absent or wrongly typed overrides it.
      Map<String, dynamic> env(Map<String, dynamic> op) => <String, dynamic>{
        'ok': true,
        // CHANGED IN S1-R5: the final `sync_push` stamps its own `server_ts` on
        // the one envelope it returns (20260905090001_..._002.sql:876). This is
        // the OUTER stamp; the inner row carries its own below.
        'server_ts': '2026-09-08T12:00:01.000Z',
        'results': <dynamic>[
          <String, dynamic>{
            'local_operation_id': 'op-x',
            'operation_type': 'payment.create',
            'idempotency_replay': false,
            // CHANGED IN S1-R4: the complete tracked applied tuple. A case
            // that wants one of these absent overrides it.
            'shift_id': 'shift-1',
            'cash_drawer_session_id': 'drawer-1',
            'payment_revision': 1,
            'order_revision': 8,
            'auto_completed': false,
            'server_ts': '2026-09-08T12:00:01.000Z',
            ...op,
          },
        ],
      };

      test('envelope classifier matrix (source-faithful tokens)', () {
        final cases = <String, (Object?, Object)>{
          'rejected generic (memoized)': (
            env({
              'status': 'rejected',
              'ok': false,
              'error': 'rejected',
              'sqlstate': '42501',
              'detail': null,
            }),
            isA<PaymentSendRefused>()
                .having((r) => r.code, 'code', PaymentRefusalCode.generic)
                .having((r) => r.memoized, 'memoized', isTrue),
          ),
          'order_not_chargeable': (
            env({
              'status': 'rejected',
              'ok': false,
              'error': 'order_not_chargeable',
              // CHANGED IN S1-R4: `record_payment` RETURNS this refusal and
              // always names the order it refused
              // (20260716090000_..._contracts.sql:187-188, :256-258), so the
              // binding is part of the tuple rather than optional.
              'order_id': 'order-1',
            }),
            isA<PaymentSendRefused>().having(
              (r) => r.code,
              'code',
              PaymentRefusalCode.notChargeable,
            ),
          ),
          'permission_denied': (
            env({
              'status': 'rejected',
              'ok': false,
              'error': 'permission_denied',
              // CHANGED IN S1-R4: `record_payment` RETURNS this refusal and
              // always names the order it refused
              // (20260716090000_..._contracts.sql:187-188, :256-258), so the
              // binding is part of the tuple rather than optional.
              'order_id': 'order-1',
            }),
            isA<PaymentSendRefused>().having(
              (r) => r.code,
              'code',
              PaymentRefusalCode.permissionDenied,
            ),
          ),
          'precondition_failed (no shift)': (
            env({
              'status': 'rejected',
              'ok': false,
              'error': 'rejected',
              'sqlstate': '42501',
              'detail': 'precondition_failed',
            }),
            isA<PaymentSendRefused>().having(
              (r) => r.code,
              'code',
              PaymentRefusalCode.shiftRequired,
            ),
          ),
          'revoked_employee': (
            env({
              'status': 'rejected',
              'ok': false,
              'error': 'rejected',
              'sqlstate': '42501',
              'detail': 'revoked_employee',
            }),
            isA<PaymentSendRefused>().having(
              (r) => r.code,
              'code',
              PaymentRefusalCode.revokedEmployee,
            ),
          ),
          'revision conflict 40001': (
            env({
              'status': 'conflict',
              'ok': false,
              'error': 'conflict',
              'sqlstate': '40001',
            }),
            isA<PaymentSendRefused>().having(
              (r) => r.code,
              'code',
              PaymentRefusalCode.revisionConflict,
            ),
          ),
          'idempotency collision (different payload under our key)': (
            env({
              'status': 'conflict',
              'ok': false,
              'error': 'conflict',
              'detail':
                  'idempotency key already used for a different operation/payload',
            }),
            isA<PaymentSendUnconfirmed>().having(
              (u) => u.reason,
              'reason',
              PaymentUnconfirmedReason.identityCollision,
            ),
          ),
          'replayed rejection is still a rejection': (
            env({
              'status': 'rejected',
              'ok': false,
              'error': 'rejected',
              'sqlstate': '42501',
              'detail': null,
              'idempotency_replay': true,
            }),
            isA<PaymentSendRefused>(),
          ),
          'malformed: not a map': ('nope', isA<PaymentSendUnconfirmed>()),
          'malformed: no results': (
            <String, dynamic>{'ok': true},
            isA<PaymentSendUnconfirmed>().having(
              (u) => u.reason,
              'reason',
              PaymentUnconfirmedReason.malformedResponse,
            ),
          ),
          'mismatched: result for another op': (
            <String, dynamic>{
              // S1-F002: a faithful envelope states its own outer ok, so this
              // case isolates the identity mismatch rather than tripping the
              // new outer-envelope rule first.
              // CHANGED IN S1-R5: and its own outer `server_ts`, for exactly
              // the same reason.
              'ok': true,
              'server_ts': '2026-09-08T12:00:01.000Z',
              'results': <dynamic>[
                <String, dynamic>{
                  'local_operation_id': 'someone',
                  'operation_type': 'payment.create',
                  'status': 'applied',
                  'ok': true,
                  'payment_id': 'p',
                  'order_id': 'order-1',
                  'method': 'cash',
                  'receipt_number': 'r',
                  'change_due_minor': 0,
                },
              ],
            },
            isA<PaymentSendUnconfirmed>().having(
              (u) => u.reason,
              'reason',
              PaymentUnconfirmedReason.mismatchedResult,
            ),
          ),
          'applied without payment_id': (
            env({
              'status': 'applied',
              'ok': true,
              'receipt_number': 'R-1',
              'change_due_minor': 1000,
            }),
            isA<PaymentSendUnconfirmed>().having(
              (u) => u.reason,
              'reason',
              PaymentUnconfirmedReason.appliedUnparseable,
            ),
          ),
          'applied with float change': (
            env({
              'status': 'applied',
              'ok': true,
              'payment_id': 'p',
              'receipt_number': 'R-1',
              'change_due_minor': 10.0,
            }),
            isA<PaymentSendUnconfirmed>(),
          ),
          'applied contradicted by ok:false': (
            env({
              'status': 'applied',
              'ok': false,
              'payment_id': 'p',
              'receipt_number': 'R-1',
              'change_due_minor': 0,
            }),
            isA<PaymentSendUnconfirmed>(),
          ),
          'pending (dependency_not_ready) is not applied': (
            env({
              'status': 'pending',
              'ok': false,
              'error': 'dependency_not_ready',
            }),
            isA<PaymentSendNotApplied>(),
          ),
          'applied + replay flag is accepted with replay=true': (
            env({
              'status': 'applied',
              'ok': true,
              'payment_id': 'srv-1',
              'order_id': 'order-1',
              'receipt_number': 'R-1',
              'change_due_minor': 1000,
              'method': 'cash',
              'idempotency_replay': true,
            }),
            isA<PaymentSendAccepted>()
                .having((s) => s.resolution.replay, 'replay', isTrue)
                .having((s) => s.resolution.paymentId, 'paymentId', 'srv-1'),
          ),
        };
        cases.forEach((name, c) {
          expect(
            RealPaymentRepository.classifyEnvelope(c.$1, a()),
            c.$2,
            reason: name,
          );
        });
      });

      test('transport classifier matrix (what each failure PROVES)', () {
        const auth = SyncTransportException(
          SyncTransportErrorKind.auth,
          code: '42501',
          message:
              'sync_push: PIN session is not valid (inactive/ended/expired)',
        );
        const raised = SyncTransportException(
          SyncTransportErrorKind.server,
          code: '42501',
          message: 'sync_push: p_operations must be a JSON array',
        );
        const shift = SyncTransportException(
          SyncTransportErrorKind.server,
          code: '42501',
          message: 'record_payment: no open shift (precondition_failed)',
        );
        const pgrst = SyncTransportException(
          SyncTransportErrorKind.server,
          code: 'PGRST202',
          message: 'function not found',
        );
        const egress = SyncTransportException(
          SyncTransportErrorKind.server,
          code: '402',
          message: 'exceed_egress_quota',
        );
        const badGateway = SyncTransportException(
          SyncTransportErrorKind.server,
          code: '502',
          message: 'bad gateway',
        );
        const throttled = SyncTransportException(
          SyncTransportErrorKind.transient,
          code: '429',
        );
        const timeout = SyncTransportException(
          SyncTransportErrorKind.transient,
          message: 'TimeoutException',
        );
        const unknown = SyncTransportException(SyncTransportErrorKind.unknown);
        const noCode = SyncTransportException(SyncTransportErrorKind.server);

        final c = RealPaymentRepository.classifyTransportFailure;
        expect(c(auth), isA<PaymentSendAuthRequired>());
        expect(c(raised), isA<PaymentSendNotApplied>());
        expect(
          c(shift),
          isA<PaymentSendRefused>()
              .having((r) => r.code, 'code', PaymentRefusalCode.shiftRequired)
              .having((r) => r.memoized, 'memoized', isFalse),
        );
        expect(c(pgrst), isA<PaymentSendNotApplied>());
        expect(c(egress), isA<PaymentSendNotApplied>());
        expect(c(badGateway), isA<PaymentSendUnconfirmed>());
        expect(c(throttled), isA<PaymentSendUnconfirmed>());
        expect(c(timeout), isA<PaymentSendUnconfirmed>());
        expect(c(unknown), isA<PaymentSendUnconfirmed>());
        expect(c(noCode), isA<PaymentSendUnconfirmed>());
      });

      test(
        'R6b a memoized refusal replays as a refusal on every same-key send; '
        'it is never re-executed and never becomes success',
        () async {
          final server = _server(shifts: const {}); // no open shift on device-A
          final repo = RealPaymentRepository(
            server,
            const SyncSession(pinSessionId: 'pin-A', deviceId: 'device-A'),
            _CountingIds('a'),
          );
          final attempt = a();
          final first = await repo.sendAttempt(attempt);
          expect(
            first,
            isA<PaymentSendRefused>().having(
              (r) => r.code,
              'code',
              PaymentRefusalCode.shiftRequired,
            ),
          );
          server.shiftOpenDevices.add('device-A'); // the cashier opens a shift
          final again = await repo.sendAttempt(attempt);
          expect(again, isA<PaymentSendRefused>(), reason: 'cached rejection');
          expect(server.executions, 1);
          expect(server.replays, 1);
          expect(server.completedPaymentsFor('order-1'), 0);
        },
      );

      test(
        'R6c wrong device: another till\'s attempt is never transmitted',
        () async {
          final server = _server();
          final repo = RealPaymentRepository(
            server,
            const SyncSession(pinSessionId: 'pin-A', deviceId: 'device-A'),
            _CountingIds('a'),
          );
          final foreign = _attemptFixture(scope: _scopeB);
          expect(await repo.sendAttempt(foreign), isA<PaymentSendNotApplied>());
          expect(
            await repo.lookupAttemptStatus(foreign),
            isA<PaymentAttemptStatusUnavailable>(),
          );
          expect(server.attemptedPushes, isEmpty);
        },
      );

      test(
        'R6d controller: typed refusals resolve the attempt and never merge a '
        'payment',
        () async {
          final prefs = await _freshPrefs();
          final server = _server(
            total: 0,
          ); // zero-total -> order_not_chargeable
          final till = _till(
            server: server,
            store: SharedPrefsPaymentAttemptStore(prefs),
            snapshots: DemoOrderSnapshotRepository(
              seed: [
                _snapshot(total: 0, settlement: PosSettlement.notChargeable),
              ],
            ),
          );
          final o = await till.submit(amountMinor: 0, tenderedMinor: 0);
          expect(
            o,
            isA<PaymentAttemptRefused>().having(
              (r) => r.code,
              'code',
              PaymentRefusalCode.notChargeable,
            ),
          );
          expect(till.state.payments, isEmpty);
          final stored = await till.store.load(_scopeA);
          expect(stored.attempts.single.phase, PaymentAttemptPhase.refused);
          expect(
            stored.attempts.single.refusal,
            PaymentRefusalCode.notChargeable,
          );
        },
      );
    },
  );

  // =========================================================================
  group('R7 two tills', () {
    test(
      'the unconfirmed till resumes its OWN key, learns the order was '
      'settled ELSEWHERE, records no payment and keeps the linkage',
      () async {
        final prefsA = await _freshPrefs();
        final server = _server(shifts: const {'device-A', 'device-B'});
        final tillA = _till(
          server: server,
          store: SharedPrefsPaymentAttemptStore(prefsA),
        );
        // B is a different device; its store is irrelevant here but must not be
        // A's (a different scope key on the same prefs would also do).
        final tillB = _till(
          server: server,
          scope: _scopeB,
          store: SharedPrefsPaymentAttemptStore(prefsA),
          pinSession: 'pin-B',
        );

        server.faultNext(ServerFault.failBeforeExecute);
        expect(await tillA.submit(), isA<PaymentAttemptUnconfirmed>());
        expect(await tillB.submit(), isA<PaymentAttemptAccepted>());
        tillA.snapshots.upsert(_snapshot(settlement: PosSettlement.paid));

        final a2 = await tillA.resume();
        // CHANGED IN S1 (PDR-006). This asserted `settledElsewhere`, which the
        // client inferred from "the order is paid". A paid order names no
        // operation, so A's attempt records what the server said about IT.
        expect(a2, isA<PaymentAttemptRefused>());
        expect(tillA.state.payments, isEmpty, reason: 'not our payment');
        expect(tillA.ids.calls, 2);
        expect(server.orders['order-1']!.paidByDevice, 'device-B');
        expect(server.completedPaymentsFor('order-1'), 1);
        final stored = await tillA.store.load(_scopeA);
        expect(stored.attempts.single.phase, PaymentAttemptPhase.refused);
        // A later submit for the (now settled) order is a NEW decision that the
        // server refuses again — and it is LINKED to the old record.
        final a3 = await tillA.submit();
        expect(a3, isA<PaymentAttemptRefused>());
        final after = await tillA.store.load(_scopeA);
        expect(after.attempts, hasLength(2));
        expect(
          after.attempts.last.supersedes,
          stored.attempts.single.localOperationId,
        );
      },
    );

    test('check status: no ledger row + order PAID elsewhere resolves '
        'settled-elsewhere WITHOUT sending anything', () async {
      final prefs = await _freshPrefs();
      final server = _server(shifts: const {'device-A', 'device-B'});
      final tillA = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );
      server.faultNext(ServerFault.failBeforeExecute);
      expect(await tillA.submit(), isA<PaymentAttemptUnconfirmed>());
      // B pays through the server directly.
      final tillB = _till(
        server: server,
        scope: _scopeB,
        store: SharedPrefsPaymentAttemptStore(prefs),
        pinSession: 'pin-B',
      );
      expect(await tillB.submit(), isA<PaymentAttemptAccepted>());
      tillA.snapshots.upsert(_snapshot(settlement: PosSettlement.paid));

      final pushesBefore = server.attemptedPushes.length;
      final check = await tillA.check();
      // CHANGED IN S1 (PDR-006). A missing ledger row plus a paid order used
      // to resolve this exact attempt. Absence is not attribution: it stays
      // pending and keeps blocking a replacement identity.
      expect(check, isA<PaymentAttemptStatusStillPending>());
      expect(
        server.attemptedPushes,
        hasLength(pushesBefore),
        reason: 'a status check executes nothing',
      );
    });
  });

  // =========================================================================
  group('R8 same-device concurrent writers', () {
    test('two controllers over ONE store instance: exactly one record is '
        'created, the other adopts it; one key on the server', () async {
      final prefs = await _freshPrefs();
      final server = _server();
      final store = SharedPrefsPaymentAttemptStore(prefs);
      final c1 = _till(server: server, store: store, ids: _CountingIds('c1'));
      final c2 = _till(server: server, store: store, ids: _CountingIds('c2'));
      server.faultNext(ServerFault.holdResponseAfterCommit);
      final f1 = c1.submit();
      final f2 = c2.submit();
      await _settle();
      server.releaseHeld();
      final r1 = await f1;
      final r2 = await f2;
      expect(r1, isA<PaymentAttemptAccepted>());
      expect(r2, isA<PaymentAttemptAccepted>());
      expect(server.paymentOpIdsFrom('device-A'), hasLength(1));
      expect(server.completedPaymentsFor('order-1'), 1);
      final stored = await store.load(_scopeA);
      expect(stored.attempts, hasLength(1));
      // Effects are armed for exactly ONE of the two writers.
      final armed = [r1, r2]
          .whereType<PaymentAttemptAccepted>()
          .where((r) => r.automaticEffectsArmed)
          .length;
      expect(armed, 1);
    });

    test(
      'two store instances over the SAME preferences (two tabs, '
      'sequential): the second adopts the first\'s pending attempt',
      () async {
        final prefs = await _freshPrefs();
        final server = _server();
        final tab1 = _till(
          server: server,
          store: SharedPrefsPaymentAttemptStore(prefs),
          ids: _CountingIds('t1'),
        );
        server.faultNext(ServerFault.dropResponseAfterCommit);
        expect(await tab1.submit(), isA<PaymentAttemptUnconfirmed>());
        final tab2 = _till(
          server: server,
          store: SharedPrefsPaymentAttemptStore(prefs),
          ids: _CountingIds('t2'),
        );
        final r = await tab2.submit();
        expect(r, isA<PaymentAttemptAccepted>());
        expect(tab2.ids.calls, 0);
        expect(server.paymentOpIdsFrom('device-A'), hasLength(1));
      },
    );

    test(
      'two INDEPENDENT backing stores (the web two-tab bound): each mints its '
      'own attempt, the SERVER refuses the second, and the loser is settled '
      'elsewhere with no second charge and no automatic effects',
      () async {
        final server = _server();
        // Two tabs of one origin: two adapter instances, each answering reads
        // from its own cache — modelled as two separate backing stores.
        final tab1 = _till(
          server: server,
          store: SharedPrefsPaymentAttemptStore(await _freshPrefs()),
          ids: _CountingIds('t1'),
        );
        final tab2 = _till(
          server: server,
          store: SharedPrefsPaymentAttemptStore(await _freshPrefs()),
          ids: _CountingIds('t2'),
        );
        final first = await tab1.submit();
        expect(first, isA<PaymentAttemptAccepted>());
        expect((first as PaymentAttemptAccepted).automaticEffectsArmed, isTrue);
        tab2.snapshots.upsert(_snapshot(settlement: PosSettlement.paid));

        final second = await tab2.submit();
        // CHANGED IN S1 (PDR-006): the server refused tab 2's attempt; the
        // order being paid is order-level information, not an attribution.
        expect(second, isA<PaymentAttemptRefused>());
        expect(server.completedPaymentsFor('order-1'), 1);
        expect(tab2.state.payments, isEmpty);
        expect(
          tab2.state.effectsArmedFor(PosOrderIdentity.server('order-1')),
          isFalse,
        );
      },
    );

    test(
      'store: createIfAbsent is atomic per instance under a burst',
      () async {
        final prefs = await _freshPrefs();
        final store = SharedPrefsPaymentAttemptStore(prefs);
        final claims = await Future.wait([
          for (var i = 0; i < 5; i++)
            store.createIfAbsent(_scopeA, _attemptFixture(op: 'op-$i')),
        ]);
        expect(claims.where((c) => c.created).length, 1);
        expect(
          claims.map((c) => c.attempt.localOperationId).toSet(),
          hasLength(1),
        );
        expect((await store.load(_scopeA)).attempts, hasLength(1));
      },
    );
  });

  // =========================================================================
  group('R9 accepted, then the local resolution save fails', () {
    test('the payment stands, effects are NOT armed, no second tender is '
        'offered, and a restart resolves it as a replay', () async {
      final prefs = await _freshPrefs();
      final scripted = _ScriptedPrefs(prefs)..failAfterWrites = 1;
      final server = _server();
      final p1 = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(scripted),
      );
      final o = await p1.submit();
      expect(o, isA<PaymentAttemptAccepted>());
      final acc = o as PaymentAttemptAccepted;
      expect(acc.localSaveFailed, isTrue);
      expect(acc.automaticEffectsArmed, isFalse);
      expect(acc.payment.paymentId, 'srv-pay-1');
      expect(
        p1.state.paymentFor(PosOrderIdentity.server('order-1')),
        isNotNull,
        reason: 'server truth is kept in memory',
      );
      // On disk the record is still pending.
      final onDisk = await _durableView(prefs).load(_scopeA);
      expect(onDisk.attempts.single.phase, PaymentAttemptPhase.pending);
      // A second confirm in this process: accepted from memory, nothing sent.
      expect(await p1.submit(), isA<PaymentAttemptAccepted>());
      expect(server.paymentOpsSeen, hasLength(1));
      p1.container.dispose();

      // Restart: pending -> resume -> replay -> accepted; the reservation is
      // written for the first time NOW, so effects arm exactly once overall.
      // CHANGED IN S1-R3: a RESTART is modelled as what it actually is — a new
      // Dart isolate. The physical-key trust boundary is isolate-scoped and
      // deliberately cannot be cleared at runtime by a new wrapper, a new
      // store or a disposer, so a test that means "the app was restarted" has
      // to say so. Everything before this line still runs under the
      // containment the failed acceptance installed.
      resetPaymentAttemptKeyGuardsForTest();
      final p2 = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );
      final r = await p2.resume();
      expect(r, isA<PaymentAttemptAccepted>());
      expect((r as PaymentAttemptAccepted).automaticEffectsArmed, isTrue);
      expect(r.replay, isTrue);
      expect(server.executions, 1);
      expect(server.completedPaymentsFor('order-1'), 1);
    });
  });

  // =========================================================================
  group('R10 credentials, actors and scope', () {
    test('an auth-class refusal keeps the attempt pending; the SAME actor with '
        'a fresh session resumes the SAME key', () async {
      final prefs = await _freshPrefs();
      final server = _server()..invalidPinSessions.add('pin-A');
      final p1 = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );
      final o = await p1.submit();
      expect(o, isA<PaymentAttemptAuthRequired>());
      final stored = await p1.store.load(_scopeA);
      expect(
        stored.attempts.single.lastOutcome,
        PaymentAttemptLastOutcome.authRequired,
      );
      p1.container.dispose();

      final p2 = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
        pinSession: 'pin-A2',
      );
      final r = await p2.resume();
      expect(r, isA<PaymentAttemptAccepted>());
      expect(server.paymentOpIdsFrom('device-A'), hasLength(1));
      expect(server.pushes.last.pinSessionId, 'pin-A2');
    });

    test('ANOTHER cashier cannot resume the attempt (nothing sent) but may '
        'check its status read-only', () async {
      final prefs = await _freshPrefs();
      final server = _server();
      final p1 = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );
      server.faultNext(ServerFault.dropResponseAfterCommit);
      expect(await p1.submit(), isA<PaymentAttemptUnconfirmed>());
      p1.container.dispose();

      final p2 = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
        employee: 'emp-2',
        pinSession: 'pin-A2',
      );
      expect(await p2.resume(), isA<PaymentAttemptOtherActor>());
      expect(await p2.submit(), isA<PaymentAttemptOtherActor>());
      expect(
        server.paymentOpsSeen,
        hasLength(1),
        reason: 'no cross-actor send',
      );

      final check = await p2.check();
      expect(check, isA<PaymentAttemptStatusResolved>());
      expect(
        (check as PaymentAttemptStatusResolved).outcome,
        isA<PaymentAttemptAccepted>(),
      );
      expect(server.paymentOpsSeen, hasLength(1), reason: 'read-only');
    });

    test('a scope switch hides the other scope\'s records and destroys '
        'nothing', () async {
      final prefs = await _freshPrefs();
      final server = _server(shifts: const {'device-A', 'device-B'});
      final a = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );
      server.faultNext(ServerFault.dropResponseAfterCommit);
      expect(await a.submit(), isA<PaymentAttemptUnconfirmed>());
      a.container.dispose();

      final b = _till(
        server: server,
        scope: _scopeB,
        store: SharedPrefsPaymentAttemptStore(prefs),
        pinSession: 'pin-B',
      );
      await b.payments.ensureHydrated();
      expect(
        b.state.pendingAttemptFor(PosOrderIdentity.server('order-1')),
        isNull,
      );
      expect(
        (await SharedPrefsPaymentAttemptStore(prefs).load(_scopeA)).attempts,
        hasLength(1),
        reason: 'the other scope\'s record survives untouched',
      );
    });

    test('a late acceptance after the session changed is persisted but not '
        'merged into the new session\'s state', () async {
      final prefs = await _freshPrefs();
      final server = _server();
      final sessionProvider = StateProvider<SyncSession?>(
        (_) => const SyncSession(pinSessionId: 'pin-A', deviceId: 'device-A'),
      );
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posAuthTransportProvider.overrideWithValue(server),
          posSyncSessionProvider.overrideWith(
            (ref) => ref.watch(sessionProvider),
          ),
          posSyncScopeProvider.overrideWithValue(_scopeA),
          clientIdGeneratorProvider.overrideWithValue(_CountingIds('a')),
          paymentAttemptStoreProvider.overrideWithValue(
            SharedPrefsPaymentAttemptStore(prefs),
          ),
          posRecentOrdersStoreProvider.overrideWithValue(
            InMemoryRecentOrdersStore(),
          ),
          orderSnapshotRepositoryProvider.overrideWithValue(
            DemoOrderSnapshotRepository(seed: [_snapshot()]),
          ),
          posSyncPollIntervalProvider.overrideWithValue(null),
          posSyncClockProvider.overrideWithValue(() => _pinnedNow),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(posSignedInEmployeeProfileIdProvider.notifier)
          .set('emp-1');
      final payments = container.read(paymentControllerProvider.notifier);
      server.faultNext(ServerFault.holdResponseAfterCommit);
      final inFlight = payments.submitAttempt(
        identity: PosOrderIdentity.server('order-1'),
        orderId: 'order-1',
        orderNumber: '#A1',
        amountMinor: 4000,
        tenderedMinor: 5000,
        currencyCode: 'ILS',
        // PDR-003: a real attempt now requires an authoritative revision.
        expectedRevision: 3,
      );
      await _settle();
      // The cashier signs out / another signs in while the reply is held.
      container.read(sessionProvider.notifier).state = const SyncSession(
        pinSessionId: 'pin-A2',
        deviceId: 'device-A',
      );
      await _settle();
      server.releaseHeld();
      final o = await inFlight;
      expect(o, isA<PaymentAttemptAccepted>());
      expect(
        container
            .read(paymentControllerProvider)
            .paymentFor(PosOrderIdentity.server('order-1')),
        isNull,
        reason: 'a late callback never mutates the new session\'s state',
      );
      expect(
        (o as PaymentAttemptAccepted).automaticEffectsArmed,
        isFalse,
        reason:
            'the automatic receipt/drawer never fire in a world this payment '
            'was not taken in',
      );
      expect(
        container
            .read(paymentControllerProvider)
            .effectsArmedFor(PosOrderIdentity.server('order-1')),
        isFalse,
      );
      final onDisk = await SharedPrefsPaymentAttemptStore(prefs).load(_scopeA);
      expect(
        onDisk.attempts.single.phase,
        PaymentAttemptPhase.accepted,
        reason: 'the server truth is still durable',
      );
    });
  });

  // =========================================================================
  group('R11 read-only status check', () {
    test('no ledger row + order still unpaid = STILL PENDING, no fresh key, '
        'nothing sent', () async {
      final prefs = await _freshPrefs();
      final server = _server();
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );
      server.faultNext(ServerFault.failBeforeExecute);
      expect(await till.submit(), isA<PaymentAttemptUnconfirmed>());
      final before = server.attemptedPushes.length;
      final check = await till.check();
      expect(check, isA<PaymentAttemptStatusStillPending>());
      expect(server.attemptedPushes, hasLength(before));
      expect(till.ids.calls, 2);
      expect(
        till.state.pendingAttemptFor(PosOrderIdentity.server('order-1')),
        isNotNull,
      );
    });

    test('ledger row APPLIED resolves the attempt from the read alone (no '
        'execution, effects armed once)', () async {
      final prefs = await _freshPrefs();
      final server = _server();
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );
      server.faultNext(ServerFault.dropResponseAfterCommit);
      expect(await till.submit(), isA<PaymentAttemptUnconfirmed>());
      final check = await till.check();
      expect(check, isA<PaymentAttemptStatusResolved>());
      final outcome = (check as PaymentAttemptStatusResolved).outcome;
      expect(outcome, isA<PaymentAttemptAccepted>());
      // CHANGED IN S1 (PDR-005). Check Status used to arm the automatic
      // receipt and drawer. A query is not a payment edge: the attempt is
      // resolved, the one-time effect claim is spent so nothing can fire it
      // later, and the manual reprint remains the cashier's route to paper.
      expect(
        (outcome as PaymentAttemptAccepted).automaticEffectsArmed,
        isFalse,
      );
      expect(server.paymentOpsSeen, hasLength(1), reason: 'no re-push');
      expect(server.replays, 0);
      // A later resume is a no-op acceptance: no effects again, nothing sent.
      final again = await till.submit();
      expect((again as PaymentAttemptAccepted).automaticEffectsArmed, isFalse);
      expect(server.paymentOpsSeen, hasLength(1));
    });

    test(
      'ledger row REJECTED resolves the attempt as refused from the read',
      () async {
        final prefs = await _freshPrefs();
        final server = _server(shifts: const {});
        final till = _till(
          server: server,
          store: SharedPrefsPaymentAttemptStore(prefs),
        );
        server.faultNext(ServerFault.dropResponseAfterCommit);
        expect(await till.submit(), isA<PaymentAttemptUnconfirmed>());
        final check = await till.check();
        final outcome = (check as PaymentAttemptStatusResolved).outcome;
        expect(
          outcome,
          isA<PaymentAttemptRefused>().having(
            (r) => r.code,
            'code',
            PaymentRefusalCode.shiftRequired,
          ),
        );
      },
    );

    test(
      'a NON-terminal ledger row is STILL PENDING, never a refusal',
      () async {
        final server = _server()..ledgerStatusOverride = 'in_flight';
        final repo = RealPaymentRepository(
          server,
          const SyncSession(pinSessionId: 'pin-A', deviceId: 'device-A'),
          _CountingIds('a'),
        );
        final attempt = _attemptFixture();
        server.faultNext(ServerFault.dropResponseAfterCommit);
        await repo.sendAttempt(attempt);
        expect(
          await repo.lookupAttemptStatus(attempt),
          isA<PaymentAttemptStatusInProgress>(),
        );
      },
    );

    test('the lookup is bounded and read-only: a scan that exceeds the page '
        'cap answers UNAVAILABLE (the attempt stays pending)', () async {
      final server = _server()..ledgerNoise = 5000;
      final repo = RealPaymentRepository(
        server,
        const SyncSession(pinSessionId: 'pin-A', deviceId: 'device-A'),
        _CountingIds('a'),
      );
      final attempt = _attemptFixture();
      expect(
        await repo.lookupAttemptStatus(attempt),
        isA<PaymentAttemptStatusUnavailable>(),
      );
      expect(server.pushes, isEmpty);
    });
  });

  // =========================================================================
  group('R12 definitive refusal, then a corrected attempt', () {
    test('after a memoized precondition refusal and a shift opened, the next '
        'confirm is a NEW linked attempt; the old record is kept', () async {
      final prefs = await _freshPrefs();
      final server = _server(shifts: const {});
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );
      final first = await till.submit();
      expect(
        first,
        isA<PaymentAttemptRefused>().having(
          (r) => r.code,
          'code',
          PaymentRefusalCode.shiftRequired,
        ),
      );
      server.shiftOpenDevices.add('device-A');
      final second = await till.submit();
      expect(second, isA<PaymentAttemptAccepted>());
      expect(server.paymentOpIdsFrom('device-A'), hasLength(2));
      expect(till.ids.calls, 4);
      final stored = await till.store.load(_scopeA);
      expect(stored.attempts, hasLength(2));
      expect(stored.attempts[0].phase, PaymentAttemptPhase.refused);
      expect(
        stored.attempts[1].supersedes,
        stored.attempts[0].localOperationId,
      );
      expect(server.completedPaymentsFor('order-1'), 1);
    });
  });

  // =========================================================================
  group('R13 quarantine', () {
    String key() => paymentAttemptsStorageKey(_scopeA.key);

    test('a corrupt record for the order blocks a NEW attempt for that order '
        'only; the bytes survive a write for another order', () async {
      final prefs = await _freshPrefs();
      final garbage = <String, Object?>{
        'version': 1,
        'attempts': [
          {'order_id': 'order-1', 'local_operation_id': 'op-old', 'phase': 42},
        ],
      };
      await prefs.setString(key(), jsonEncode(garbage));
      final server = _server();
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );
      expect(await till.submit(), isA<PaymentAttemptQuarantined>());
      expect(server.attemptedPushes, isEmpty);
      // Another order is unaffected.
      final other = await till.submit(
        orderId: 'order-2',
        orderNumber: '#A2',
        amountMinor: 2500,
        tenderedMinor: 2500,
        expectedRevision: 1,
      );
      expect(other, isA<PaymentAttemptAccepted>());
      final raw = jsonDecode(prefs.getString(key())!) as Map;
      final entries = raw['attempts'] as List;
      expect(entries, hasLength(2));
      expect(
        entries.first,
        (garbage['attempts'] as List).first as Map,
        reason: 'the unreadable record is re-emitted verbatim',
      );
    });

    test('an unknown envelope version blocks every new attempt and is never '
        'overwritten', () async {
      final prefs = await _freshPrefs();
      final bytes = jsonEncode({'version': 99, 'attempts': []});
      await prefs.setString(key(), bytes);
      final server = _server();
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );
      expect(await till.submit(), isA<PaymentAttemptQuarantined>());
      expect(server.attemptedPushes, isEmpty);
      expect(prefs.getString(key()), bytes);
      final store = till.store as SharedPrefsPaymentAttemptStore;
      expect(store.unreadableRecordCount(_scopeA.key), 1);
    });

    test('a record bound to ANOTHER scope under this key is quarantined for '
        'its own order and never acted on', () async {
      final prefs = await _freshPrefs();
      final foreign = _attemptFixture(scope: _scopeB, op: 'op-foreign');
      await prefs.setString(
        key(),
        jsonEncode({
          'version': 1,
          'attempts': [foreign.toJson()],
        }),
      );
      final server = _server();
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );
      expect(await till.submit(), isA<PaymentAttemptQuarantined>());
      expect(server.attemptedPushes, isEmpty);
      final other = await till.submit(
        orderId: 'order-2',
        orderNumber: '#A2',
        amountMinor: 2500,
        tenderedMinor: 2500,
        expectedRevision: 1,
      );
      expect(other, isA<PaymentAttemptAccepted>());
    });

    test('strict decode: a non-allowlisted field or a secret-shaped key is '
        'unreadable, never merged', () {
      final ok = _attemptFixture().toJson();
      expect(PaymentAttempt.fromJson(ok).localOperationId, 'op-x');
      final withSecret = {...ok, 'pin_session_id': 'bearer-xyz'};
      expect(() => PaymentAttempt.fromJson(withSecret), throwsFormatException);
      expect(
        () => PaymentAttempt.fromJson({...ok, 'amount_minor': 12.5}),
        throwsFormatException,
      );
      expect(
        () => PaymentAttempt.fromJson({...ok, 'phase': 'paid'}),
        throwsFormatException,
      );
    });
  });

  // =========================================================================
  group('R15 normal flows keep integer money, tenders and revisions', () {
    test(
      'cash / card / bit / external send the RF-117 payload shape',
      () async {
        for (final method in PaymentMethod.values) {
          final prefs = await _freshPrefs();
          final server = _server();
          final till = _till(
            server: server,
            store: SharedPrefsPaymentAttemptStore(prefs),
          );
          final o = await till.submit(method: method, tenderedMinor: 5000);
          expect(o, isA<PaymentAttemptAccepted>(), reason: method.wire);
          final payload = server.paymentOpsSeen.single['payload'] as Map;
          expect(payload['tender_type'], method.wire);
          expect(payload['amount_tendered_minor'], isA<int>());
          expect(payload['amount_tendered_minor'], method.isCash ? 5000 : 4000);
          expect(payload['expected_revision'], 3);
          expect(payload.containsKey('amount_minor'), isFalse);
          expect(payload.containsKey('change_minor'), isFalse);
          final p = (o as PaymentAttemptAccepted).payment;
          expect(p.changeMinor, method.isCash ? 1000 : 0);
          expect(p.method, method);
          expect(p.currencyCode, 'ILS');
          till.container.dispose();
        }
      },
    );

    test(
      'a zero-decimal currency passes through as integer minor units',
      () async {
        final prefs = await _freshPrefs();
        final server = PaymentAttemptServerFake(
          orders: [
            FakeServerOrder(
              orderId: 'order-1',
              grandTotalMinor: 480,
              revision: 3,
            ),
          ],
          devicesWithOpenShift: const {'device-A'},
        );
        final till = _till(
          server: server,
          store: SharedPrefsPaymentAttemptStore(prefs),
          snapshots: DemoOrderSnapshotRepository(seed: [_snapshot(total: 480)]),
        );
        final o = await till.submit(
          amountMinor: 480,
          tenderedMinor: 1000,
          currencyCode: 'JPY',
        );
        expect(o, isA<PaymentAttemptAccepted>());
        expect((o as PaymentAttemptAccepted).payment.changeMinor, 520);
        final stored = (await till.store.load(_scopeA)).attempts.single;
        expect(stored.currencyCode, 'JPY');
        expect(stored.amountTenderedMinor, 1000);
      },
    );

    test('the durable record is allowlisted: identifiers and integer money '
        'only, no session capability', () async {
      final prefs = await _freshPrefs();
      final server = _server();
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );
      await till.submit();
      final raw = prefs.getString(paymentAttemptsStorageKey(_scopeA.key))!;
      expect(raw, isNot(contains('pin-A')));
      expect(raw, isNot(contains('pin_session')));
      final record =
          ((jsonDecode(raw) as Map)['attempts'] as List).single as Map;
      expect(
        record.keys.toSet().difference(PaymentAttempt.allowedKeys),
        isEmpty,
      );
      expect(record['employee_profile_id'], 'emp-1');
      expect(record['device_id'], 'device-A');
    });
  });

  // =========================================================================
  group('legacy path (demo store / hand-written repositories)', () {
    test('a repository without the attempt seam keeps its historical '
        'semantics and touches no durable store', () async {
      final prefs = await _freshPrefs();
      final failing = FailingPrefs(prefs)..failWrites = true;
      final container = ProviderContainer(
        overrides: [
          paymentRepositoryProvider.overrideWithValue(DemoPaymentStore()),
          paymentAttemptStoreProvider.overrideWithValue(
            SharedPrefsPaymentAttemptStore(failing),
          ),
        ],
      );
      addTearDown(container.dispose);
      final o = await container
          .read(paymentControllerProvider.notifier)
          .submitAttempt(
            identity: PosOrderIdentity.server('order-1'),
            orderId: 'order-1',
            orderNumber: '#A1',
            amountMinor: 4000,
            tenderedMinor: 5000,
            currencyCode: 'ILS',
          );
      expect(o, isA<PaymentAttemptAccepted>());
      expect(failing.writeAttempts, 0);
    });
  });
}
