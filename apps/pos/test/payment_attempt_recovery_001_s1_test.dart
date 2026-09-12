// PAYMENT-ATTEMPT-RECOVERY-001 / S1 — the Codex-correction regressions.
//
// Every test in this file is written against seams that already exist at the
// reviewed commit dbfd4efa, so each one reaches the UNSAFE BEHAVIOUR there and
// fails for a semantic reason rather than a compile error. That is the RED
// evidence for S1; the same file must be GREEN after the corrections.
//
// Covered, one group per Codex finding:
//   PDR-001  a cache-only write must never pass the persist-before-send gate
//   PDR-002  one exact result, or unconfirmed (existing fields only)
//   PDR-003  a real attempt needs a non-null authoritative revision
//   PDR-005  Check Status / boot / hydration never arm an automatic effect
//   PDR-006  feed absence is not attribution
//   PDR-007  actor identity fails closed, including every null asymmetry
//   PDR-008  corrupt or unknown stored evidence is quarantined, never coerced
//
// S1-R2 additionally carries the reviewer probes that found S1-F001 and
// S1-F002 (`REVIEWER-CACHE-*`, `REVIEWER-RESP-*`, `REVIEWER-STATUS-*`). They
// arrived as an external Codex harness; they are kept here verbatim in
// substance so the same four defects cannot return unnoticed.
//
// D3 (immediate provisional-target proof) is NOT in S1 and is not asserted
// here. Cross-context ownership (PDR-004) and the per-effect model (PDR-005's
// remainder) are S3/S4 and are likewise absent.
//
// Synthetic ids, amounts and sessions only. No network, no printer, no drawer.
import 'dart:convert';

import 'package:flutter/foundation.dart';
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
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosPersistenceException, PosSyncScope;
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

// ---------------------------------------------------------------------------
// PDR-001 — the adapter double that models the REAL installed ordering.
//
// `shared_preferences-2.5.5/lib/src/shared_preferences_legacy.dart` `_setValue`
// assigns `_preferenceCache[key] = value` and only THEN returns the platform
// store future. So when the platform write fails, the adapter's own cache
// already holds the new value and `getString` serves it. Any durability check
// that reads back through the same adapter is therefore reading its own
// optimistic guess.
//
// The owner-authored `FailingPrefs` double returns false BEFORE delegating, so
// it can never produce this ordering. This double does: the cache is mutated
// first, the backing map is left untouched, and only then does the write fail.
// ---------------------------------------------------------------------------
class _CacheFirstPrefs implements SharedPreferences {
  _CacheFirstPrefs({this.throwInstead = false});

  /// What the adapter would serve from memory after an optimistic write.
  final Map<String, String> cache = <String, String>{};

  /// What actually reached durable storage.
  final Map<String, String> backing = <String, String>{};

  /// While true every write mutates [cache] and then fails.
  bool failWrites = false;

  /// Deterministic alternative to [failWrites]: every write from this
  /// 1-based ordinal onwards mutates [cache] and then fails. Used to let the
  /// attempt be created durably and fail only the LATER acceptance write.
  int failFromWrite = 0;

  /// Fail by throwing instead of returning false.
  final bool throwInstead;

  int writeAttempts = 0;

  /// Models the distinct positive-control ordering in which the backing write
  /// really lands, but the legacy adapter still reports failure to its caller.
  bool landBeforeFailure = false;

  @override
  Future<bool> setString(String key, String value) async {
    writeAttempts++;
    cache[key] = value; // the installed adapter's ordering
    if (failWrites || (failFromWrite > 0 && writeAttempts >= failFromWrite)) {
      if (landBeforeFailure) backing[key] = value;
      if (throwInstead) throw StateError('platform write failed');
      return false;
    }
    backing[key] = value;
    return true;
  }

  @override
  String? getString(String key) => cache[key];

  @override
  Future<bool> remove(String key) async {
    cache.remove(key);
    backing.remove(key);
    return true;
  }

  @override
  bool containsKey(String key) => cache.containsKey(key);

  @override
  Set<String> getKeys() => cache.keys.toSet();

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused: ${invocation.memberName}');
}

/// Independent raw reader over the fake's backing map. The production reader
/// receives the physical `flutter.` key, while the fake writer receives the
/// legacy API's logical key, so this test seam performs exactly that prefix
/// translation and never consults [_CacheFirstPrefs.cache].
class _MapBackingReader implements PaymentAttemptBackingReader {
  const _MapBackingReader(this.backing);
  final Map<String, String> backing;

  @override
  Future<String?> readRaw(String physicalKey) async {
    final logicalKey = physicalKey.startsWith(kLegacySharedPreferencesKeyPrefix)
        ? physicalKey.substring(kLegacySharedPreferencesKeyPrefix.length)
        : physicalKey;
    return backing[logicalKey];
  }
}

/// A SECOND scope on the same device family, used to prove that containing
/// one poisoned key does not disable the rest of the store.
const _scopeB = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-B',
  deviceId: 'device-A',
);

/// A scriptable stand-in for the independent backing read. [source] is the map
/// the bytes come from and [transform] is how the physical store differs from
/// what the writer believed it stored (stale, wrong, truncated, corrupt).
class _ScriptedBackingReader implements PaymentAttemptBackingReader {
  _ScriptedBackingReader(
    this.source, {
    this.transform,
    this.shouldThrow = false,
  });

  final Map<String, String> source;
  final String? Function(String? raw)? transform;
  final bool shouldThrow;
  int reads = 0;

  @override
  Future<String?> readRaw(String physicalKey) async {
    reads++;
    if (shouldThrow) throw StateError('backing store unavailable');
    final logicalKey = physicalKey.startsWith(kLegacySharedPreferencesKeyPrefix)
        ? physicalKey.substring(kLegacySharedPreferencesKeyPrefix.length)
        : physicalKey;
    final raw = source[logicalKey];
    final transformRaw = transform;
    return transformRaw == null ? raw : transformRaw(raw);
  }
}

class _SecondPushPreconditionTransport implements SyncRpcTransport {
  _SecondPushPreconditionTransport(this.delegate);

  final PaymentAttemptServerFake delegate;
  int paymentPushes = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'sync_push') {
      final raw = params['p_operations'];
      if (raw is List &&
          raw.any(
            (entry) =>
                entry is Map && entry['operation_type'] == 'payment.create',
          )) {
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
    return delegate.invoke(function, params);
  }
}

class _ScriptedTransport implements SyncRpcTransport {
  const _ScriptedTransport(this.response);
  final Object? response;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async =>
      response;
}

/// Answers each `sync_pull` with the next scripted page, so the bounded page
/// window can be walked for real instead of simulated.
class _PagedTransport implements SyncRpcTransport {
  _PagedTransport(this.pages);
  final List<Object?> pages;
  int calls = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    final page = calls < pages.length ? pages[calls] : pages.last;
    calls++;
    return page;
  }
}

/// A store view over ONLY what reached durable storage.
/// An INDEPENDENT view of the durable bytes.
///
/// S1-R3: a probe that reads the backing map is exactly the independent read
/// the store is allowed to believe, so it is given one. Handing it only a
/// backing-only adapter would make it look like a fresh writer wrapper, which
/// the corrected build deliberately no longer treats as evidence.
SharedPrefsPaymentAttemptStore _durableView(Map<String, String> backing) =>
    SharedPrefsPaymentAttemptStore(
      _BackingOnlyPrefs(backing),
      backingReader: _MapBackingReader(backing),
    );

class _BackingOnlyPrefs implements SharedPreferences {
  _BackingOnlyPrefs(this._backing);
  final Map<String, String> _backing;

  @override
  String? getString(String key) => _backing[key];

  @override
  Future<bool> setString(String key, String value) async {
    _backing[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _backing.remove(key);
    return true;
  }

  @override
  bool containsKey(String key) => _backing.containsKey(key);

  @override
  Set<String> getKeys() => _backing.keys.toSet();

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused: ${invocation.memberName}');
}

const _scopeA = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-A',
  deviceId: 'device-A',
);

final _pinnedNow = DateTime.utc(2026, 9, 8, 12);

PosOrderSnapshot _snapshot({PosSettlement settlement = PosSettlement.unpaid}) =>
    PosOrderSnapshot(
      orderId: 'order-1',
      orderCode: '#A1',
      revision: 3,
      status: 'submitted',
      settlement: settlement,
      subtotalMinor: 4000,
      discountTotalMinor: 0,
      taxTotalMinor: 0,
      grandTotalMinor: 4000,
      createdAt: _pinnedNow.subtract(const Duration(hours: 1)),
      updatedAt: _pinnedNow.subtract(const Duration(minutes: 50)),
      syncAt: _pinnedNow.subtract(const Duration(minutes: 50)),
      orderType: 'takeaway',
      currencyCode: 'ILS',
    );

class _CountingIds implements ClientIdGenerator {
  _CountingIds(this._prefix);
  final String _prefix;
  int calls = 0;

  @override
  String newId() => '$_prefix-id-${++calls}';
}

PaymentAttemptServerFake _server({
  Iterable<String> shifts = const {'device-A'},
}) => PaymentAttemptServerFake(
  orders: [
    FakeServerOrder(orderId: 'order-1', grandTotalMinor: 4000, revision: 3),
  ],
  devicesWithOpenShift: shifts,
);

class _Till {
  _Till(this.container, this.ids, this.snapshots);
  final ProviderContainer container;
  final _CountingIds ids;
  final DemoOrderSnapshotRepository snapshots;

  PaymentController get payments =>
      container.read(paymentControllerProvider.notifier);
  PaymentState get state => container.read(paymentControllerProvider);

  Future<PaymentAttemptOutcome> submit({
    int? expectedRevision = 3,
    int amountMinor = 4000,
    int tenderedMinor = 5000,
  }) => payments.submitAttempt(
    identity: PosOrderIdentity.server('order-1'),
    orderId: 'order-1',
    orderNumber: '#A1',
    amountMinor: amountMinor,
    tenderedMinor: tenderedMinor,
    currencyCode: 'ILS',
    expectedRevision: expectedRevision,
  );

  Future<PaymentAttemptOutcome> resume() =>
      payments.resumeAttempt(PosOrderIdentity.server('order-1'));

  Future<PaymentAttemptStatusCheck> check() =>
      payments.checkStatus(PosOrderIdentity.server('order-1'));
}

_Till _till({
  required PaymentAttemptServerFake server,
  required PaymentAttemptStore store,
  SyncRpcTransport? transport,
  String employee = 'emp-1',
  DemoOrderSnapshotRepository? snapshots,
}) {
  final ids = _CountingIds('a');
  final snaps = snapshots ?? DemoOrderSnapshotRepository(seed: [_snapshot()]);
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport ?? server),
      posSyncSessionProvider.overrideWithValue(
        const SyncSession(pinSessionId: 'pin-A', deviceId: 'device-A'),
      ),
      posSyncScopeProvider.overrideWithValue(_scopeA),
      clientIdGeneratorProvider.overrideWithValue(ids),
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
  return _Till(container, ids, snaps);
}

PaymentAttempt _attempt({
  String op = 'op-1',
  String? employee = 'emp-1',
  int? revision = 3,
}) => PaymentAttempt.mint(
  ids: FixedClientIdGenerator([op, '$op-target']),
  now: _pinnedNow,
  orderId: 'order-1',
  orderNumber: '#A1',
  amountMinor: 4000,
  tenderedMinor: 5000,
  currencyCode: 'ILS',
  method: PaymentMethod.cash,
  expectedRevision: revision,
  organizationId: _scopeA.organizationId,
  restaurantId: _scopeA.restaurantId,
  branchId: _scopeA.branchId,
  deviceId: _scopeA.deviceId,
  employeeProfileId: employee,
);

/// CHANGED IN S1-R5: the final `sync_push` stamps its own `server_ts` on the
/// one envelope it returns (20260905090001_..._002.sql:876), so an envelope
/// without it is not a reply that function produced.
Map<String, dynamic> _envelope(Map<String, dynamic> op) => <String, dynamic>{
  'ok': true,
  'results': <dynamic>[op],
  'server_ts': '2026-09-08T12:00:01.000Z',
};

/// A fully-formed APPLIED result for [op], as the final SQL contract returns it.
Map<String, dynamic> _applied({
  String op = 'op-1',
  String orderId = 'order-1',
  String method = 'cash',
}) => <String, dynamic>{
  'local_operation_id': op,
  'operation_type': 'payment.create',
  'status': 'applied',
  'ok': true,
  'payment_id': 'srv-pay-1',
  'order_id': orderId,
  'method': method,
  'receipt_number': 'R-1',
  'change_due_minor': 1000,
  'idempotency_replay': false,
  // CHANGED IN S1-R4: `app.record_payment` emits every one of these on a
  // real application (20260716090000_..._contracts.sql:400-411), so a
  // fixture without them blessed a shape the source never produces.
  'shift_id': 'shift-1',
  'cash_drawer_session_id': 'drawer-1',
  'payment_revision': 1,
  'order_revision': 8,
  'auto_completed': false,
  'server_ts': '2026-09-08T12:00:01.000Z',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // S1-R3 / F001: the physical-key trust boundary is deliberately isolate-wide
  // and impossible to clear at runtime, so each test starts from a clean one.
  setUp(resetPaymentAttemptKeyGuardsForTest);
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  // =========================================================================
  group('PDR-001 — a cache-only write never passes persist-before-send', () {
    test('S1-001a cache mutated then setString returns FALSE: zero sends, zero '
        'arming, and durable backing still has no record', () async {
      final prefs = _CacheFirstPrefs()..failWrites = true;
      final server = _server();
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );

      final outcome = await till.submit();

      expect(
        server.attemptedPushes,
        isEmpty,
        reason: 'a payment must never leave without a durable record',
      );
      expect(outcome, isA<PaymentAttemptSaveBlocked>());
      expect(
        prefs.cache.keys.where((k) => k.contains('payment_attempts')),
        isNotEmpty,
        reason: 'the adapter cache DID take the optimistic value',
      );
      expect(
        prefs.backing.keys.where((k) => k.contains('payment_attempts')),
        isEmpty,
        reason: 'but nothing reached durable storage',
      );
      final fresh = await _durableView(prefs.backing).load(_scopeA);
      expect(fresh.attempts, isEmpty);
    });

    test(
      'S1-001b cache mutated then setString THROWS: same guarantee',
      () async {
        final prefs = _CacheFirstPrefs(throwInstead: true)..failWrites = true;
        final server = _server();
        final till = _till(
          server: server,
          store: SharedPrefsPaymentAttemptStore(prefs),
        );

        final outcome = await till.submit();

        expect(server.attemptedPushes, isEmpty);
        expect(outcome, isA<PaymentAttemptSaveBlocked>());
        expect(
          await _durableView(
            prefs.backing,
          ).load(_scopeA).then((l) => l.attempts),
          isEmpty,
        );
      },
    );

    test('S1-001c the ACCEPTED resolution cannot be armed from a cache-only '
        'write: the payment stands, the automatic effects do not', () async {
      // The create (write 1) succeeds durably; the acceptance save
      // (write 2) is the one that fails, deterministically.
      final prefs = _CacheFirstPrefs()..failFromWrite = 2;
      final server = _server();
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );

      final outcome = await till.submit();

      expect(outcome, isA<PaymentAttemptAccepted>());
      final accepted = outcome as PaymentAttemptAccepted;
      expect(
        accepted.automaticEffectsArmed,
        isFalse,
        reason: 'an unverified reservation may never arm paper or a drawer',
      );
      expect(accepted.localSaveFailed, isTrue);
      expect(server.completedPaymentsFor('order-1'), 1);
    });

    test('S1-001d POSITIVE CONTROL: a write that genuinely reaches backing is '
        'accepted and the payment is sent exactly once', () async {
      final prefs = _CacheFirstPrefs();
      final server = _server();
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );

      final outcome = await till.submit();

      expect(outcome, isA<PaymentAttemptAccepted>());
      expect(server.paymentOpsSeen, hasLength(1));
      expect(
        prefs.backing.keys.where((k) => k.contains('payment_attempts')),
        isNotEmpty,
      );
    });

    test('S1-001e existing records stay readable and unchanged when a later '
        'write fails on the cache-first path', () async {
      final prefs = _CacheFirstPrefs();
      final store = SharedPrefsPaymentAttemptStore(prefs);
      final first = _attempt(op: 'op-old');
      await store.createIfAbsent(_scopeA, first);
      final durableBefore = Map<String, String>.from(prefs.backing);

      prefs.failWrites = true;
      await expectLater(
        store.update(
          _scopeA,
          first.withLastOutcome(PaymentAttemptLastOutcome.unconfirmed),
        ),
        throwsA(anything),
      );

      expect(
        prefs.backing,
        durableBefore,
        reason: 'durable bytes are untouched by a failed write',
      );
      final reread = await _durableView(prefs.backing).load(_scopeA);
      expect(reread.attempts.single.localOperationId, 'op-old');
    });
  });

  // =========================================================================
  group('PDR-002 — one exact result, or unconfirmed', () {
    final attempt = _attempt();

    test(
      'S1-002a two contradictory rows for our operation are unconfirmed',
      () {
        final raw = <String, dynamic>{
          'ok': true,
          // CHANGED IN S1-R5: the outer reply stamp, so this case keeps
          // isolating CARDINALITY.
          'server_ts': '2026-09-08T12:00:01.000Z',
          'results': <dynamic>[
            _applied(),
            <String, dynamic>{
              'local_operation_id': 'op-1',
              'operation_type': 'payment.create',
              'status': 'rejected',
              'ok': false,
              'error': 'rejected',
            },
          ],
        };
        expect(
          RealPaymentRepository.classifyEnvelope(raw, attempt),
          isA<PaymentSendUnconfirmed>(),
          reason: 'cardinality must be checked before the first row wins',
        );
      },
    );

    test('S1-002b a result for the wrong operation TYPE is unconfirmed', () {
      final raw = _envelope(_applied()..['operation_type'] = 'order.submit');
      expect(
        RealPaymentRepository.classifyEnvelope(raw, attempt),
        isA<PaymentSendUnconfirmed>(),
      );
    });

    test('S1-002c an applied result for the WRONG ORDER is unconfirmed', () {
      final raw = _envelope(_applied(orderId: 'order-999'));
      expect(
        RealPaymentRepository.classifyEnvelope(raw, attempt),
        isA<PaymentSendUnconfirmed>(),
        reason: 'never settle our attempt from another order\'s payment',
      );
    });

    test('S1-002d a WRONG tender method is unconfirmed, never coerced to the '
        'requested one', () {
      final raw = _envelope(_applied(method: 'card'));
      expect(
        RealPaymentRepository.classifyEnvelope(raw, attempt),
        isA<PaymentSendUnconfirmed>(),
      );
    });

    test('S1-002e a MISSING tender method on an applied result is '
        'unconfirmed', () {
      final row = _applied()..remove('method');
      expect(
        RealPaymentRepository.classifyEnvelope(_envelope(row), attempt),
        isA<PaymentSendUnconfirmed>(),
      );
    });

    test('S1-002f an UNKNOWN status word is unconfirmed, not a terminal '
        'refusal', () {
      final raw = _envelope(<String, dynamic>{
        'local_operation_id': 'op-1',
        'operation_type': 'payment.create',
        'status': 'in_flight',
        'ok': false,
      });
      expect(
        RealPaymentRepository.classifyEnvelope(raw, attempt),
        isA<PaymentSendUnconfirmed>(),
        reason: 'an undecided server row must never free a new key',
      );
    });

    test('S1-002g POSITIVE CONTROLS: a complete applied result and the known '
        'terminal refusals still classify exactly as before', () {
      expect(
        RealPaymentRepository.classifyEnvelope(_envelope(_applied()), attempt),
        isA<PaymentSendAccepted>(),
      );
      expect(
        RealPaymentRepository.classifyEnvelope(
          _envelope(<String, dynamic>{
            'local_operation_id': 'op-1',
            'operation_type': 'payment.create',
            'status': 'rejected',
            'ok': false,
            'error': 'rejected',
            'sqlstate': '42501',
            'detail': 'precondition_failed',
            // CHANGED IN S1-R3: `sync_push` stamps `idempotency_replay` on
            // EVERY result it emits (20260905090001_..._002.sql:848-853), so a
            // fixture without it was blessing a shape the source never
            // produces. The assertion is unchanged.
            'idempotency_replay': false,
          }),
          attempt,
        ),
        isA<PaymentSendRefused>().having(
          (r) => r.code,
          'code',
          PaymentRefusalCode.shiftRequired,
        ),
        reason: 'the no-open-shift refusal keeps its exact meaning',
      );
      expect(
        RealPaymentRepository.classifyEnvelope(
          _envelope(<String, dynamic>{
            'local_operation_id': 'op-1',
            'operation_type': 'payment.create',
            'status': 'rejected',
            'ok': false,
            'error': 'order_not_chargeable',
            'order_id': 'order-1',
            // CHANGED IN S1-R3: `record_payment` RETURNS this refusal with its
            // own replay flag (20260716090000_...sql:256-259) and sync_push
            // merges it through verbatim.
            'server_ts': '2026-09-08T12:00:01.000Z',
            'idempotency_replay': false,
          }),
          attempt,
        ),
        isA<PaymentSendRefused>().having(
          (r) => r.code,
          'code',
          PaymentRefusalCode.notChargeable,
        ),
      );
    });

    test('S1-002h a refusal shape is NOT required to carry applied-only '
        'payment or receipt fields', () {
      final raw = _envelope(<String, dynamic>{
        'local_operation_id': 'op-1',
        'operation_type': 'payment.create',
        'status': 'conflict',
        'ok': false,
        'error': 'conflict',
        'sqlstate': '40001',
        // CHANGED IN S1-R3: the exact revision-conflict tuple
        // (20260905090001_..._002.sql:790-800) carries the replay flag.
        'idempotency_replay': false,
      });
      expect(
        RealPaymentRepository.classifyEnvelope(raw, attempt),
        isA<PaymentSendRefused>().having(
          (r) => r.code,
          'code',
          PaymentRefusalCode.revisionConflict,
        ),
      );
    });
  });

  // =========================================================================
  group('PDR-003 — a real attempt needs an authoritative revision', () {
    test('S1-003a a null revision blocks BEFORE id allocation, persistence and '
        'any send', () async {
      final prefs = _CacheFirstPrefs();
      final server = _server();
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );

      final outcome = await till.submit(expectedRevision: null);

      // Asserted behaviourally so this file compiles unchanged against the
      // reviewed commit: nothing minted, nothing stored, nothing sent, and
      // certainly not an accepted payment.
      expect(server.attemptedPushes, isEmpty);
      expect(till.ids.calls, 0, reason: 'no identity may be minted');
      expect(
        prefs.backing.keys.where((k) => k.contains('payment_attempts')),
        isEmpty,
      );
      expect(outcome, isNot(isA<PaymentAttemptAccepted>()));
    });

    test('S1-003b a stored legacy attempt with no revision is passive-only '
        'and is never patched from a fresh order read', () async {
      final prefs = _CacheFirstPrefs();
      final store = SharedPrefsPaymentAttemptStore(prefs);
      final legacy = _attempt(op: 'op-legacy', revision: null);
      await store.createIfAbsent(_scopeA, legacy);
      final server = _server();
      final till = _till(server: server, store: store);

      final outcome = await till.resume();

      expect(server.attemptedPushes, isEmpty);
      expect(outcome, isNot(isA<PaymentAttemptAccepted>()));
      final stored = (await store.load(_scopeA)).attempts.single;
      expect(stored.expectedRevision, isNull, reason: 'bytes unchanged');
      expect(stored.localOperationId, 'op-legacy');
    });
  });

  // =========================================================================
  group('PDR-005 — passive resolution never arms an automatic effect', () {
    test('S1-005a Check Status resolving an APPLIED ledger row reports NO '
        'automatic effect arming', () async {
      final prefs = _CacheFirstPrefs();
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
      expect(
        (outcome as PaymentAttemptAccepted).automaticEffectsArmed,
        isFalse,
        reason: 'a status query is not a payment edge',
      );
      expect(
        till.state.effectsArmedFor(PosOrderIdentity.server('order-1')),
        isFalse,
      );
    });

    test('S1-005b a passive resolution cannot grant automatic eligibility to a '
        'LATER resume either', () async {
      final prefs = _CacheFirstPrefs();
      final server = _server();
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );
      server.faultNext(ServerFault.dropResponseAfterCommit);
      await till.submit();
      await till.check();

      final again = await till.submit();

      expect(again, isA<PaymentAttemptAccepted>());
      expect(
        (again as PaymentAttemptAccepted).automaticEffectsArmed,
        isFalse,
        reason: 'the effect edge was consumed passively and is spent',
      );
    });
  });

  // =========================================================================
  group('PDR-006 — absence is not attribution', () {
    test('S1-006a no ledger row plus a PAID order leaves the exact attempt '
        'unresolved and mints no replacement identity', () async {
      final prefs = _CacheFirstPrefs();
      final server = _server();
      final snapshots = DemoOrderSnapshotRepository(seed: [_snapshot()]);
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
        snapshots: snapshots,
      );
      // The request never arrived, so the ledger has no row for it.
      server.faultNext(ServerFault.failBeforeExecute);
      expect(await till.submit(), isA<PaymentAttemptUnconfirmed>());
      // Meanwhile the order reads as paid.
      snapshots.upsert(_snapshot(settlement: PosSettlement.paid));

      final check = await till.check();

      expect(
        check,
        isA<PaymentAttemptStatusStillPending>(),
        reason: 'a paid order cannot say WHICH attempt paid it',
      );
      final stored = (await _durableView(
        prefs.backing,
      ).load(_scopeA)).attempts.single;
      expect(stored.phase, PaymentAttemptPhase.pending);
      expect(till.ids.calls, 2, reason: 'no new identity');
    });

    test(
      'S1-006b a GENERIC refusal plus a paid order stays this attempt\'s own '
      'refusal, never another attempt\'s settlement',
      () async {
        final prefs = _CacheFirstPrefs();
        final server = _server();
        // Another till already settled the order, so `record_payment` answers
        // the generic "already has a completed payment" rejection.
        server.orders['order-1']!
          ..paymentId = 'srv-pay-other'
          ..paidByDevice = 'device-B';
        final snapshots = DemoOrderSnapshotRepository(
          seed: [_snapshot(settlement: PosSettlement.paid)],
        );
        final till = _till(
          server: server,
          store: SharedPrefsPaymentAttemptStore(prefs),
          snapshots: snapshots,
        );

        final outcome = await till.submit();

        expect(
          outcome,
          isA<PaymentAttemptRefused>(),
          reason:
              'the server refused THIS attempt; the order being paid is '
              'order-level information and identifies no operation',
        );
      },
    );
  });

  // =========================================================================
  group('PDR-007 — actor identity fails closed', () {
    Future<PaymentAttemptOutcome> resumeWith({
      String? stored,
      String? current,
    }) async {
      final prefs = _CacheFirstPrefs();
      final store = SharedPrefsPaymentAttemptStore(prefs);
      await store.createIfAbsent(_scopeA, _attempt(employee: stored));
      final server = _server();
      final till = _till(server: server, store: store, employee: current ?? '');
      final outcome = await till.resume();
      expect(
        server.attemptedPushes,
        isEmpty,
        reason: 'no resend under an unproven actor',
      );
      return outcome;
    }

    // Each asserts the load-bearing property BEHAVIOURALLY — nothing was
    // re-sent and no payment was produced — so this file compiles unchanged
    // against the reviewed commit and fails there for the right reason. The
    // precise refusal wording differs per case (no identifiable cashier vs a
    // different cashier) and is exercised through the sheet suite.
    test('S1-007a stored actor present, current actor absent', () async {
      expect(
        await resumeWith(stored: 'emp-1', current: null),
        isNot(isA<PaymentAttemptAccepted>()),
      );
    });

    test('S1-007b stored actor absent, current actor present', () async {
      expect(
        await resumeWith(stored: null, current: 'emp-1'),
        isNot(isA<PaymentAttemptAccepted>()),
      );
    });

    test('S1-007c both absent', () async {
      expect(
        await resumeWith(stored: null, current: null),
        isNot(isA<PaymentAttemptAccepted>()),
      );
    });

    test('S1-007d whitespace-only stored actor is not an identity', () async {
      expect(
        await resumeWith(stored: '   ', current: 'emp-1'),
        isNot(isA<PaymentAttemptAccepted>()),
      );
    });

    test(
      'S1-007e POSITIVE CONTROL: the SAME employee resumes normally',
      () async {
        final prefs = _CacheFirstPrefs();
        final store = SharedPrefsPaymentAttemptStore(prefs);
        await store.createIfAbsent(_scopeA, _attempt(employee: 'emp-1'));
        final server = _server();
        final till = _till(server: server, store: store, employee: 'emp-1');

        final outcome = await till.resume();

        expect(outcome, isA<PaymentAttemptAccepted>());
        expect(server.paymentOpsSeen, hasLength(1));
      },
    );

    test('S1-007f a blocked actor never erases the record, so the original '
        'cashier can still recover it', () async {
      final prefs = _CacheFirstPrefs();
      final store = SharedPrefsPaymentAttemptStore(prefs);
      await store.createIfAbsent(_scopeA, _attempt(employee: 'emp-1'));
      final server = _server();
      final other = _till(server: server, store: store, employee: 'emp-2');
      expect(await other.resume(), isA<PaymentAttemptOtherActor>());
      other.container.dispose();

      final original = _till(server: server, store: store, employee: 'emp-1');
      expect(await original.resume(), isA<PaymentAttemptAccepted>());
    });
  });

  // =========================================================================
  group('PDR-008 — corrupt stored evidence is quarantined', () {
    Map<String, Object?> base() => _attempt().toJson();

    test('S1-008a an UNKNOWN refusal code is never coerced to generic', () {
      final json = base()
        ..['phase'] = 'refused'
        ..['refusal'] = 'future_refusal_code'
        ..['resolved_at'] = _pinnedNow.toIso8601String();
      expect(() => PaymentAttempt.fromJson(json), throwsFormatException);
    });

    test('S1-008b a wrongly TYPED refusal is rejected', () {
      final json = base()
        ..['phase'] = 'refused'
        ..['refusal'] = 7
        ..['resolved_at'] = _pinnedNow.toIso8601String();
      expect(() => PaymentAttempt.fromJson(json), throwsFormatException);
    });

    test('S1-008c refused WITHOUT a refusal code is rejected', () {
      final json = base()
        ..['phase'] = 'refused'
        ..['resolved_at'] = _pinnedNow.toIso8601String();
      expect(() => PaymentAttempt.fromJson(json), throwsFormatException);
    });

    test('S1-008d pending WITH a resolution is rejected', () {
      final json = base()
        ..['phase'] = 'pending'
        ..['resolution'] = <String, Object?>{
          'payment_id': 'p',
          'receipt_number': 'r',
          'change_due_minor': 0,
          'method': 'cash',
          'replay': false,
        };
      expect(() => PaymentAttempt.fromJson(json), throwsFormatException);
    });

    test('S1-008e accepted WITH a refusal code is rejected', () {
      final json = base()
        ..['phase'] = 'accepted'
        ..['refusal'] = 'rejected'
        ..['resolved_at'] = _pinnedNow.toIso8601String()
        ..['resolution'] = <String, Object?>{
          'payment_id': 'p',
          'receipt_number': 'r',
          'change_due_minor': 0,
          'method': 'cash',
          'replay': false,
        };
      expect(() => PaymentAttempt.fromJson(json), throwsFormatException);
    });

    test(
      'S1-008f a resolved phase WITHOUT a resolved timestamp is rejected',
      () {
        final json = base()
          ..['phase'] = 'refused'
          ..['refusal'] = 'rejected';
        expect(() => PaymentAttempt.fromJson(json), throwsFormatException);
      },
    );

    test(
      'S1-008g POSITIVE CONTROLS: valid pending and valid refused decode',
      () {
        expect(
          PaymentAttempt.fromJson(base()).phase,
          PaymentAttemptPhase.pending,
        );
        // CHANGED IN S1-R4: a refused record is one the server ANSWERED, so
        // the writer stamps the started-send marker and the monotonic history
        // with it. Flipping only the phase produced a shape this build never
        // emits, which the decoder now rightly refuses.
        final refused = base()
          ..['phase'] = 'refused'
          ..['refusal'] = 'order_not_chargeable'
          ..['sent_at'] = _pinnedNow.toIso8601String()
          ..['may_have_executed'] = true
          ..['resolved_at'] = _pinnedNow.toIso8601String();
        expect(
          PaymentAttempt.fromJson(refused).refusal,
          PaymentRefusalCode.notChargeable,
        );
      },
    );

    test('S1-008h a corrupt record is QUARANTINED verbatim by the store and '
        'blocks a new attempt for its order without being deleted', () async {
      final prefs = _CacheFirstPrefs();
      final corrupt = base()
        ..['phase'] = 'refused'
        ..['refusal'] = 'future_refusal_code'
        ..['resolved_at'] = _pinnedNow.toIso8601String();
      final key = paymentAttemptsStorageKey(_scopeA.key);
      final bytes = jsonEncode(<String, Object?>{
        'version': 1,
        'attempts': <Object?>[corrupt],
      });
      prefs.cache[key] = bytes;
      prefs.backing[key] = bytes;

      final store = SharedPrefsPaymentAttemptStore(prefs);
      final load = await store.load(_scopeA);
      expect(load.attempts, isEmpty);
      expect(load.quarantined, isNotEmpty);

      final server = _server();
      final till = _till(server: server, store: store);
      expect(await till.submit(), isA<PaymentAttemptQuarantined>());
      expect(server.attemptedPushes, isEmpty);
      expect(
        prefs.backing[key],
        bytes,
        reason: 'the raw evidence is preserved byte-for-byte',
      );
    });
  });

  // =========================================================================
  // S1-R2 — the external Codex probes, adopted as durable regressions. Their
  // `REVIEWER-` ids are preserved so each one stays traceable to the delta
  // review that raised it.
  group('REVIEWER — cache poisoning across later calls', () {
    test('REVIEWER-CACHE-001 cache-only FALSE is rejected on the first call '
        'when the independent backing view is absent', () async {
      final prefs = _CacheFirstPrefs()..failWrites = true;
      final server = _server();
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(
          prefs,
          backingReader: _MapBackingReader(prefs.backing),
        ),
      );

      expect(await till.submit(), isA<PaymentAttemptSaveBlocked>());
      expect(server.attemptedPushes, isEmpty);
      expect(prefs.backing, isEmpty);
      expect(prefs.cache, isNotEmpty);
    });

    test('REVIEWER-CACHE-002 a cache-only FALSE cannot authorize a SAME-STORE '
        'second submit', () async {
      final prefs = _CacheFirstPrefs()..failWrites = true;
      final server = _server();
      final store = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: _MapBackingReader(prefs.backing),
      );
      final till = _till(server: server, store: store);

      final first = await till.submit();
      final second = await till.submit();

      expect(first, isA<PaymentAttemptSaveBlocked>());
      expect(second, isA<PaymentAttemptSaveBlocked>());
      expect(
        server.attemptedPushes,
        isEmpty,
        reason: 'the optimistic cache must not become durable evidence later',
      );
      expect(prefs.backing, isEmpty);
    });

    test('REVIEWER-CACHE-003 a cache-only THROW cannot authorize a SAME-STORE '
        'second submit', () async {
      final prefs = _CacheFirstPrefs(throwInstead: true)..failWrites = true;
      final server = _server();
      final store = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: _MapBackingReader(prefs.backing),
      );
      final till = _till(server: server, store: store);

      final first = await till.submit();
      final second = await till.submit();

      expect(first, isA<PaymentAttemptSaveBlocked>());
      expect(second, isA<PaymentAttemptSaveBlocked>());
      expect(server.attemptedPushes, isEmpty);
      expect(prefs.backing, isEmpty);
    });

    test('REVIEWER-CACHE-004 a cache-only failed claim cannot be adopted by a '
        'new store/controller over the same legacy adapter cache', () async {
      final prefs = _CacheFirstPrefs()..failWrites = true;
      final server = _server();
      final reader = _MapBackingReader(prefs.backing);
      final first = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs, backingReader: reader),
      );
      expect(await first.submit(), isA<PaymentAttemptSaveBlocked>());

      final second = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs, backingReader: reader),
      );
      await second.payments.ensureHydrated();
      final outcome = await second.submit();

      expect(outcome, isA<PaymentAttemptSaveBlocked>());
      expect(
        server.attemptedPushes,
        isEmpty,
        reason: 'hydration must not promote a cache-only phantom to pending',
      );
      expect(prefs.backing, isEmpty);
    });

    test('REVIEWER-CACHE-005 POSITIVE CONTROL: exact complete backing bytes '
        'that land before FALSE recover the write', () async {
      final prefs = _CacheFirstPrefs()
        ..failWrites = true
        ..landBeforeFailure = true;
      final server = _server();
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(
          prefs,
          backingReader: _MapBackingReader(prefs.backing),
        ),
      );

      final outcome = await till.submit();

      expect(outcome, isA<PaymentAttemptAccepted>());
      expect(server.attemptedPushes, hasLength(1));
      expect(prefs.backing, isNotEmpty);
      expect(prefs.backing, prefs.cache);
    });

    test('REVIEWER-CACHE-006 a failed acceptance reservation cannot later be '
        'hydrated as a durable accepted/payment record', () async {
      final prefs = _CacheFirstPrefs()..failFromWrite = 2;
      final reader = _MapBackingReader(prefs.backing);
      final server = _server();
      final first = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs, backingReader: reader),
      );
      final firstOutcome = await first.submit();
      expect(firstOutcome, isA<PaymentAttemptAccepted>());
      expect((firstOutcome as PaymentAttemptAccepted).localSaveFailed, isTrue);
      expect(firstOutcome.automaticEffectsArmed, isFalse);

      final durable = await _durableView(prefs.backing).load(_scopeA);
      expect(durable.attempts.single.phase, PaymentAttemptPhase.pending);

      final second = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs, backingReader: reader),
      );
      await second.payments.ensureHydrated();
      final hydrated = second.state.attempts.values.single;
      final observed = <String, Object?>{
        'phase': hydrated.phase.name,
        'paymentMerged':
            second.state.paymentFor(PosOrderIdentity.server('order-1')) != null,
        'effectsArmed': second.state.effectsArmedFor(
          PosOrderIdentity.server('order-1'),
        ),
        'serverPushes': server.attemptedPushes.length,
      };
      expect(
        observed,
        <String, Object?>{
          'phase': PaymentAttemptPhase.pending.name,
          'paymentMerged': false,
          'effectsArmed': false,
          'serverPushes': 1,
        },
        reason:
            'a cache-only accepted/reserved image must not outrank the '
            'independent backing record',
      );
    });

    test(
      'REVIEWER-CACHE-007 a poisoned pending cache is not valid passive '
      'status evidence after the independent backing read proved absence',
      () async {
        final prefs = _CacheFirstPrefs()..failWrites = true;
        final reader = _MapBackingReader(prefs.backing);
        final server = _server();
        final first = _till(
          server: server,
          store: SharedPrefsPaymentAttemptStore(prefs, backingReader: reader),
        );
        expect(await first.submit(), isA<PaymentAttemptSaveBlocked>());

        final second = _till(
          server: server,
          store: SharedPrefsPaymentAttemptStore(prefs, backingReader: reader),
        );
        await second.payments.ensureHydrated();
        final checked = await second.check();
        final observed = <String, Object?>{
          'check': checked.runtimeType.toString(),
          'pushes': server.attemptedPushes.length,
          'effectsArmed': second.state.effectsArmedFor(
            PosOrderIdentity.server('order-1'),
          ),
          'backingRecords': (await _durableView(
            prefs.backing,
          ).load(_scopeA)).attempts.length,
        };
        expect(observed, <String, Object?>{
          'check': 'PaymentAttemptStatusNothingPending',
          'pushes': 0,
          'effectsArmed': false,
          'backingRecords': 0,
        });
      },
    );
  });

  group('REVIEWER — response and passive-ledger contradictions', () {
    final attempt = _attempt();

    Future<PaymentAttemptStatusLookup> lookup(List<Object?> rows) {
      final transport = _ScriptedTransport(<String, Object?>{
        'ok': true,
        'operation_statuses': <String, Object?>{
          'rows': rows,
          'has_more': false,
          'next_cursor': null,
        },
      });
      return RealPaymentRepository(
        transport,
        const SyncSession(pinSessionId: 'pin-A', deviceId: 'device-A'),
        FixedClientIdGenerator(const ['unused-1', 'unused-2']),
        clock: () => _pinnedNow,
      ).lookupAttemptStatus(attempt);
    }

    Map<String, Object?> row({
      Object? targetId = 'op-1-target',
      Object? result,
      String status = 'applied',
    }) => <String, Object?>{
      'local_operation_id': 'op-1',
      'operation_type': 'payment.create',
      'target_entity': 'payment',
      'target_id': targetId,
      'status': status,
      'result': result ?? _applied(),
      // CHANGED IN S1-R4: the feed projects its own identity fields on every
      // row (20260729090000_...sql:1334-1348).
      'id': 'so-00000001',
      'updated_at': '2026-09-08T12:00:01.000Z',
      // CHANGED IN S1-R5: and the REMAINING projected keys — the tracked
      // projection builds all fifteen for every row, with null for a SQL NULL
      // (nullability per 20260622110000_rf056_sync_operations_push.sql).
      'last_error_code': null,
      'last_error_class': null,
      'conflict_info': null,
      'rejection_reason': null,
      'retry_count': 0,
      'applied_at': '2026-09-08T12:00:01.000Z',
      'server_received_at': '2026-09-08T12:00:01.000Z',
    };

    test('REVIEWER-RESP-001 outer ok FALSE cannot wrap and accept an otherwise '
        'valid applied row', () {
      final raw = <String, Object?>{
        'ok': false,
        'results': <Object?>[_applied()],
      };
      expect(
        RealPaymentRepository.classifyEnvelope(raw, attempt),
        isA<PaymentSendUnconfirmed>(),
      );
    });

    test('REVIEWER-RESP-002 applied requires row ok TRUE, not missing', () {
      final applied = _applied()..remove('ok');
      expect(
        RealPaymentRepository.classifyEnvelope(_envelope(applied), attempt),
        isA<PaymentSendUnconfirmed>(),
      );
    });

    test(
      'REVIEWER-RESP-003 rejected/dead/conflict cannot carry row ok TRUE',
      () {
        final observed = <String, String>{};
        for (final status in const ['rejected', 'dead', 'conflict']) {
          final rejected = <String, Object?>{
            'local_operation_id': 'op-1',
            'operation_type': 'payment.create',
            'status': status,
            'ok': true,
            'error': status == 'conflict' ? 'conflict' : 'rejected',
          };
          observed[status] = RealPaymentRepository.classifyEnvelope(
            _envelope(rejected.cast<String, dynamic>()),
            attempt,
          ).runtimeType.toString();
        }
        expect(observed, <String, String>{
          'rejected': 'PaymentSendUnconfirmed',
          'dead': 'PaymentSendUnconfirmed',
          'conflict': 'PaymentSendUnconfirmed',
        });
      },
    );

    test('REVIEWER-STATUS-001 passive terminal row with NULL target cannot '
        'resolve the attempt', () async {
      final nullTarget = await lookup([row(targetId: null)]);
      final missingTargetRow = row()..remove('target_id');
      final missingTarget = await lookup([missingTargetRow]);
      expect(
        <bool>[
          nullTarget is PaymentAttemptStatusApplied,
          missingTarget is PaymentAttemptStatusApplied,
        ],
        <bool>[false, false],
        reason: 'both null and missing target must stay unresolved',
      );
    });

    test('REVIEWER-STATUS-002 contradictory inner operation identity/status '
        'cannot be masked by the outer row', () async {
      final inner = _applied()
        ..['local_operation_id'] = 'other-op'
        ..['operation_type'] = 'order.submit'
        ..['status'] = 'rejected';
      expect(
        await lookup([row(result: inner)]),
        isA<PaymentAttemptStatusCollision>(),
      );
    });

    test(
      'REVIEWER-STATUS-003 null/non-Map terminal result stays unresolved',
      () async {
        // CHANGED IN S1-R4: the row carries the feed's own identity fields, so
        // this case isolates the unreadable STORED RESULT it exists for rather
        // than tripping the new generic row-shape rule first.
        final withNullResult = <String, Object?>{
          'local_operation_id': 'op-1',
          'operation_type': 'payment.create',
          'target_entity': 'payment',
          'target_id': 'op-1-target',
          'status': 'rejected',
          'result': null,
          'id': 'so-00000001',
          'updated_at': '2026-09-08T12:00:01.000Z',
          // CHANGED IN S1-R5: completed to the tracked 15-key projection, so
          // this case still isolates the unreadable STORED RESULT it exists
          // for rather than tripping the generic row-shape rule first.
          'last_error_code': null,
          'last_error_class': null,
          'conflict_info': null,
          'rejection_reason': null,
          'retry_count': 0,
          'applied_at': null,
          'server_received_at': '2026-09-08T12:00:01.000Z',
        };
        final withScalarResult = <String, Object?>{
          ...withNullResult,
          'result': 'not-a-result-map',
        };
        final nullLookup = await lookup([withNullResult]);
        final scalarLookup = await lookup([withScalarResult]);
        expect(
          <String>[
            nullLookup.runtimeType.toString(),
            scalarLookup.runtimeType.toString(),
          ],
          <String>[
            'PaymentAttemptStatusCollision',
            'PaymentAttemptStatusCollision',
          ],
        );
      },
    );

    test('REVIEWER-STATUS-004 duplicate terminal rows for one operation are '
        'never resolved from the first row', () async {
      final identical = await lookup([row(), row()]);
      final contradictory = await lookup([
        row(),
        row(
          status: 'rejected',
          result: <String, Object?>{
            'local_operation_id': 'op-1',
            'operation_type': 'payment.create',
            'status': 'rejected',
            'ok': false,
            'error': 'rejected',
          },
        ),
      ]);
      expect(
        <String>[
          identical.runtimeType.toString(),
          contradictory.runtimeType.toString(),
        ],
        <String>[
          'PaymentAttemptStatusCollision',
          'PaymentAttemptStatusCollision',
        ],
      );
    });
  });

  // =========================================================================
  // S1-R2 / F001 — the durability-verification matrix.
  //
  // `_write` believes a REPORTED FAILURE unless an independent read returns
  // exactly the bytes it meant to store. Each row below is a different way
  // that read can fall short of proof, and every one of them must refuse the
  // write, send nothing, and leave the adapter's key untrusted so no later
  // call can read the optimistic cache back as evidence. The exact-bytes row
  // is the positive control that keeps the rest from passing vacuously.
  group('S1-R2/F001 — the durability-verification matrix', () {
    final physicalA = paymentAttemptsPhysicalKey(_scopeA.key);
    final physicalB = paymentAttemptsPhysicalKey(_scopeB.key);

    PaymentAttempt attemptB() => PaymentAttempt.mint(
      ids: FixedClientIdGenerator(const ['op-b', 'op-b-target']),
      now: _pinnedNow,
      orderId: 'order-b',
      orderNumber: '#B1',
      amountMinor: 2500,
      tenderedMinor: 2500,
      currencyCode: 'ILS',
      method: PaymentMethod.cash,
      expectedRevision: 2,
      organizationId: _scopeB.organizationId,
      restaurantId: _scopeB.restaurantId,
      branchId: _scopeB.branchId,
      deviceId: _scopeB.deviceId,
      employeeProfileId: 'emp-1',
    );

    /// Runs one refused-write row and asserts the shared contract.
    Future<_CacheFirstPrefs> expectRefused(
      PaymentAttemptBackingReader? Function(_CacheFirstPrefs prefs) readerOf, {
      required String because,
    }) async {
      final prefs = _CacheFirstPrefs()..failWrites = true;
      final store = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: readerOf(prefs),
      );
      await expectLater(
        store.createIfAbsent(_scopeA, _attempt()),
        throwsA(isA<PosPersistenceException>()),
        reason: because,
      );
      expect(
        prefs.backing,
        isEmpty,
        reason: 'nothing reached the backing store',
      );
      expect(
        paymentAttemptAdapterIsUntrusted(prefs, physicalA),
        isTrue,
        reason: 'the adapter holds bytes that never landed: contain the key',
      );
      return prefs;
    }

    test(
      'S1R2-F001a an ABSENT backing entry is not proof of durability',
      () async {
        await expectRefused(
          (prefs) => _ScriptedBackingReader(prefs.backing),
          because: 'the independent read found nothing at all',
        );
      },
    );

    test(
      'S1R2-F001b STALE backing bytes are not proof of durability',
      () async {
        final stale = jsonEncode(<String, Object?>{
          'version': PaymentAttempt.schemaVersion,
          'attempts': <Object?>[],
        });
        await expectRefused(
          (prefs) =>
              _ScriptedBackingReader(prefs.cache, transform: (_) => stale),
          because: 'an older envelope is evidence about an earlier write',
        );
      },
    );

    test(
      'S1R2-F001c WRONG backing bytes are not proof of durability',
      () async {
        final other = jsonEncode(<String, Object?>{
          'version': PaymentAttempt.schemaVersion,
          'attempts': <Object?>[_attempt(op: 'op-someone-else').toJson()],
        });
        await expectRefused(
          (prefs) =>
              _ScriptedBackingReader(prefs.cache, transform: (_) => other),
          because:
              'a well-formed envelope for a DIFFERENT attempt proves nothing '
              'about ours',
        );
      },
    );

    test(
      'S1R2-F001d a PARTIAL backing write is not proof of durability',
      () async {
        await expectRefused(
          (prefs) => _ScriptedBackingReader(
            prefs.cache,
            transform: (raw) => raw?.substring(0, (raw.length / 2).floor()),
          ),
          because: 'a truncated record is a torn write, never a durable one',
        );
      },
    );

    test(
      'S1R2-F001e CORRUPT backing bytes are not proof of durability',
      () async {
        await expectRefused(
          (prefs) => _ScriptedBackingReader(
            prefs.cache,
            transform: (_) => '{not-json',
          ),
          because: 'unreadable bytes cannot be compared to the intended bytes',
        );
      },
    );

    test(
      'S1R2-F001f a backing read that THROWS is not proof of durability',
      () async {
        await expectRefused(
          (prefs) => _ScriptedBackingReader(prefs.backing, shouldThrow: true),
          because: 'a failed read is doubt, and doubt refuses the write',
        );
      },
    );

    test('S1R2-F001g NO independent reader at all refuses the write', () async {
      await expectRefused(
        (_) => null,
        because: 'with no independent view the reported failure is final',
      );
    });

    test('S1R2-F001h POSITIVE CONTROL: the exact intended bytes in the '
        'backing store make the reported failure survivable', () async {
      final prefs = _CacheFirstPrefs()
        ..failWrites = true
        ..landBeforeFailure = true;
      final store = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: _ScriptedBackingReader(prefs.backing),
      );

      final claim = await store.createIfAbsent(_scopeA, _attempt());

      expect(claim.created, isTrue);
      expect(prefs.backing, isNotEmpty, reason: 'the bytes really landed');
      expect(
        paymentAttemptAdapterIsUntrusted(prefs, physicalA),
        isFalse,
        reason: 'a verified write leaves the key trusted',
      );
      // And the record is readable again through the ordinary path.
      final reread = await _durableView(prefs.backing).load(_scopeA);
      expect(reread.attempts.single.localOperationId, 'op-1');
    });

    test('S1R2-F001i containing one poisoned key does not spill over to an '
        'unrelated scope on the same adapter', () async {
      final prefs = await expectRefused(
        (prefs) => _ScriptedBackingReader(prefs.backing),
        because: 'poison scope A first',
      );

      // The same adapter, now healthy, is still fully usable for scope B.
      prefs.failWrites = false;
      final store = SharedPrefsPaymentAttemptStore(prefs);
      final claim = await store.createIfAbsent(_scopeB, attemptB());

      expect(claim.created, isTrue);
      expect(
        paymentAttemptAdapterIsUntrusted(prefs, physicalB),
        isFalse,
        reason: 'scope B was never written unverifiably',
      );
      expect((await store.load(_scopeB)).attempts.single.orderId, 'order-b');
      // ...while scope A stays contained.
      final poisoned = await store.load(_scopeA);
      expect(poisoned.attempts, isEmpty);
      expect(poisoned.quarantined.single.reason, 'untrusted');
    });

    test('S1R2-F001j a RECREATED store over the same adapter inherits the '
        'containment', () async {
      final prefs = await expectRefused(
        (prefs) => _ScriptedBackingReader(prefs.backing),
        because: 'poison the key through the first store',
      );

      // Exactly what a provider rebuild produces: a new store instance over
      // the SAME `SharedPreferences` singleton.
      prefs.failWrites = false;
      final rebuilt = SharedPrefsPaymentAttemptStore(prefs);

      final load = await rebuilt.load(_scopeA);
      expect(load.attempts, isEmpty);
      expect(load.quarantined.single.reason, 'untrusted');
      await expectLater(
        rebuilt.createIfAbsent(_scopeA, _attempt()),
        throwsA(isA<PosPersistenceException>()),
        reason: 'a new instance cannot launder the poisoned cache',
      );
    });

    test('S1R2-F001l the PRODUCTION composition carries an independent '
        'reader, and that reader refuses to guess on Android', () async {
      // The default provider is the real wiring: a lazy store with the async
      // backing reader attached.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(paymentAttemptStoreProvider),
        isA<SharedPrefsPaymentAttemptStore>(),
      );

      final original = debugDefaultTargetPlatformOverride;
      addTearDown(() => debugDefaultTargetPlatformOverride = original);

      // Android: the async API addresses Jetpack DataStore, a DIFFERENT
      // physical backend from the legacy XML file the writer uses, so this
      // reader declares itself unavailable rather than reading the wrong
      // store and reporting a confident answer about the wrong bytes.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(SharedPreferencesAsyncBackingReader.isSupportedTarget, isFalse);
      expect(
        SharedPreferencesAsyncBackingReader.targetSupport,
        PaymentAttemptBackingReadSupport.differentBackend,
      );
      await expectLater(
        SharedPreferencesAsyncBackingReader().readRaw(
          paymentAttemptsPhysicalKey(_scopeA.key),
        ),
        throwsA(isA<UnsupportedError>()),
      );

      // And with that reader attached, a reported write failure on Android
      // stays a failure: fail-closed, never a false confirmation.
      final prefs = _CacheFirstPrefs()..failWrites = true;
      final store = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: SharedPreferencesAsyncBackingReader(),
      );
      await expectLater(
        store.createIfAbsent(_scopeA, _attempt()),
        throwsA(isA<PosPersistenceException>()),
      );
      expect(prefs.backing, isEmpty);
      expect(
        paymentAttemptAdapterIsUntrusted(
          prefs,
          paymentAttemptsPhysicalKey(_scopeA.key),
        ),
        isTrue,
      );

      // CHANGED IN S1-R3. R2 declared every non-Android target able to read
      // its own backing independently. Codex read the INSTALLED packages and
      // proved that false for Linux and Windows — `shared_preferences_linux`
      // and `_windows` 2.4.1 each register ONE async platform singleton that
      // keeps `_cachedPreferences`, so a new facade re-reads that cache — and
      // showed that iOS/macOS independence from the UserDefaults process cache
      // was never verified here. Each target now names its own reason, and
      // none of them is treated as proof.
      const expected = <TargetPlatform, PaymentAttemptBackingReadSupport>{
        TargetPlatform.linux:
            PaymentAttemptBackingReadSupport.cachedPlatformSingleton,
        TargetPlatform.windows:
            PaymentAttemptBackingReadSupport.cachedPlatformSingleton,
        TargetPlatform.iOS:
            PaymentAttemptBackingReadSupport.independenceNotVerified,
        TargetPlatform.macOS:
            PaymentAttemptBackingReadSupport.independenceNotVerified,
      };
      final observed = <TargetPlatform, PaymentAttemptBackingReadSupport>{};
      final supported = <TargetPlatform, bool>{};
      for (final target in expected.keys) {
        debugDefaultTargetPlatformOverride = target;
        observed[target] = SharedPreferencesAsyncBackingReader.targetSupport;
        supported[target] =
            SharedPreferencesAsyncBackingReader.isSupportedTarget;
      }
      expect(observed, expected);
      expect(
        supported,
        <TargetPlatform, bool>{for (final k in expected.keys) k: false},
        reason:
            'an unproven reader is never promoted to proof; failure '
            'adjudication simply stays conservative there',
      );
    });

    test('S1R2-F001k containment does not blind a target that CAN read the '
        'backing store', () async {
      final prefs = await expectRefused(
        (prefs) => _ScriptedBackingReader(prefs.backing),
        because: 'poison the key first',
      );

      final reader = _ScriptedBackingReader(prefs.backing);
      final rebuilt = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: reader,
      );

      final load = await rebuilt.load(_scopeA);
      expect(reader.reads, greaterThan(0), reason: 'it went to the backing');
      expect(
        load.quarantined,
        isEmpty,
        reason: 'the backing store is readable and genuinely empty',
      );
      expect(
        load.attempts,
        isEmpty,
        reason:
            'the truth is empty; the optimistic cache record is never '
            'reported as a stored attempt',
      );
      expect(
        prefs.cache,
        isNotEmpty,
        reason:
            'the optimistic bytes are still in the adapter — they are simply '
            'never believed again',
      );
    });
  });

  // =========================================================================
  // S1-R2 / F002 — the remaining response and passive-ledger negatives.
  group('S1-R2/F002 — the remaining evidence negatives', () {
    final attempt = _attempt();

    PaymentSendResult classify(Map<String, dynamic> op) =>
        RealPaymentRepository.classifyEnvelope(_envelope(op), attempt);

    test('S1R2-F002a a MISSING outer ok is unconfirmed', () {
      final raw = <String, dynamic>{
        'results': <dynamic>[_applied()],
      };
      expect(
        RealPaymentRepository.classifyEnvelope(raw, attempt),
        isA<PaymentSendUnconfirmed>(),
      );
    });

    test('S1R2-F002b two IDENTICAL applied rows are unconfirmed, not one '
        'acceptance', () {
      final raw = <String, dynamic>{
        'ok': true,
        'results': <dynamic>[_applied(), _applied()],
        // CHANGED IN S1-R5: the outer reply stamp, so this case still isolates
        // the DUPLICATE-RESULT rule it exists for instead of being answered by
        // the new envelope-shape rule first.
        'server_ts': '2026-09-08T12:00:01.000Z',
      };
      final result = RealPaymentRepository.classifyEnvelope(raw, attempt);
      expect(result, isA<PaymentSendUnconfirmed>());
      expect(
        (result as PaymentSendUnconfirmed).reason,
        PaymentUnconfirmedReason.mismatchedResult,
      );
    });

    test('S1R2-F002c every unusable APPLIED field is unconfirmed, never an '
        'acceptance', () {
      final broken = <String, Map<String, dynamic>>{
        'blank receipt': _applied()..['receipt_number'] = '   ',
        'blank payment id': _applied()..['payment_id'] = '',
        'blank order id': _applied()..['order_id'] = ' ',
        'negative change': _applied()..['change_due_minor'] = -1,
        'non-integer change': _applied()..['change_due_minor'] = 10.5,
        'non-boolean replay': _applied()..['idempotency_replay'] = 'false',
        'blank order status': _applied()..['order_status'] = '',
        'non-string order status': _applied()..['order_status'] = 7,
      };
      final observed = <String, String>{
        for (final e in broken.entries)
          e.key: classify(e.value).runtimeType.toString(),
      };
      expect(observed, <String, String>{
        for (final k in broken.keys) k: 'PaymentSendUnconfirmed',
      });
    });

    test('S1R2-F002d an applied row recording a DIFFERENT tender is '
        'unconfirmed', () {
      expect(classify(_applied(method: 'card')), isA<PaymentSendUnconfirmed>());
    });

    test('S1R2-F002e POSITIVE CONTROL: the exact contract row is accepted '
        'with its values carried through', () {
      final result = classify(_applied()..['order_status'] = 'completed');
      expect(result, isA<PaymentSendAccepted>());
      final resolution = (result as PaymentSendAccepted).resolution;
      expect(resolution.paymentId, 'srv-pay-1');
      expect(resolution.receiptNumber, 'R-1');
      expect(resolution.changeDueMinor, 1000);
      expect(resolution.method, PaymentMethod.cash);
      expect(resolution.replay, isFalse);
      expect(resolution.orderStatus, 'completed');
    });

    // ---------------------------------------------------------------- passive
    Future<PaymentAttemptStatusLookup> lookup(
      List<Object?> rows, {
      bool hasMore = false,
      Object? nextCursor,
    }) {
      final transport = _ScriptedTransport(<String, Object?>{
        'ok': true,
        'operation_statuses': <String, Object?>{
          'rows': rows,
          'has_more': hasMore,
          'next_cursor': nextCursor,
        },
      });
      return RealPaymentRepository(
        transport,
        const SyncSession(pinSessionId: 'pin-A', deviceId: 'device-A'),
        FixedClientIdGenerator(const ['unused-1', 'unused-2']),
        clock: () => _pinnedNow,
      ).lookupAttemptStatus(attempt);
    }

    Map<String, Object?> terminalRow({
      Object? targetEntity = 'payment',
      String status = 'applied',
      Object? result,
    }) => <String, Object?>{
      'local_operation_id': 'op-1',
      'operation_type': 'payment.create',
      'target_entity': targetEntity,
      'target_id': 'op-1-target',
      'status': status,
      'result': result ?? _applied(),
      // CHANGED IN S1-R4: every projected feed row carries the feed's own
      // identity fields (20260729090000_...sql:1334-1348), whatever operation
      // it belongs to.
      'id': 'so-00000001',
      'updated_at': '2026-09-08T12:00:01.000Z',
      // CHANGED IN S1-R5: and the REMAINING projected keys — the tracked
      // projection builds all fifteen for every row, with null for a SQL NULL
      // (nullability per 20260622110000_rf056_sync_operations_push.sql).
      'last_error_code': null,
      'last_error_class': null,
      'conflict_info': null,
      'rejection_reason': null,
      'retry_count': 0,
      'applied_at': '2026-09-08T12:00:01.000Z',
      'server_received_at': '2026-09-08T12:00:01.000Z',
    };

    test('S1R2-F002f a terminal row for another ENTITY cannot resolve the '
        'attempt', () async {
      final wrong = await lookup([terminalRow(targetEntity: 'order')]);
      final missingRow = terminalRow()..remove('target_entity');
      final missing = await lookup([missingRow]);
      // CHANGED IN S1-R5 — the second expectation, and only it.
      //
      // A row for another ENTITY is still a well-formed feed row, so it is
      // adjudicated and remains collision-class. A row MISSING a projected key
      // is a different thing: the tracked projection emits all fifteen keys for
      // every row, so such a row is not a shape this feed produces and the SCAN
      // itself is untrusted. R4 skipped it silently, which is exactly how a
      // malformed page could become definitive absence; the R5 evidence suite
      // asserts the same rule directly for `target_entity`. Both answers here
      // are non-resolving and neither permits acceptance, absence, or a new
      // payment identity — the attempt stays pending either way.
      expect(
        <String>[wrong.runtimeType.toString(), missing.runtimeType.toString()],
        <String>[
          'PaymentAttemptStatusCollision',
          'PaymentAttemptStatusUnavailable',
        ],
      );
    });

    test('S1R2-F002g every NON-TERMINAL ledger word stays in progress, never '
        'a refusal', () async {
      const words = <String>['created', 'pending', 'in_flight', 'resolved'];
      final observed = <String, String>{};
      for (final status in words) {
        observed[status] = (await lookup([
          terminalRow(status: status),
        ])).runtimeType.toString();
      }
      expect(observed, <String, String>{
        for (final s in words) s: 'PaymentAttemptStatusInProgress',
      });
    });

    test('S1R2-F002h a MALFORMED next cursor answers unavailable, never an '
        'uncaught cast', () async {
      final result = await lookup(
        const <Object?>[],
        hasMore: true,
        nextCursor: 'not-a-cursor',
      );
      expect(result, isA<PaymentAttemptStatusUnavailable>());
      expect(
        (result as PaymentAttemptStatusUnavailable).reason,
        'malformed_cursor',
      );
    });

    test('S1R2-F002i a cursor that does not ADVANCE answers unavailable '
        'instead of looping', () async {
      final result = await lookup(
        const <Object?>[],
        hasMore: true,
        // CHANGED IN S1-R3: the cursor must now be the exact shape the feed
        // projects before its ORDERING is judged, so a pair of nulls is caught
        // one rule earlier as malformed. This fixture is a well-formed cursor
        // that points BACKWARDS, which is the case this test exists for.
        nextCursor: const <String, Object?>{
          'updated_at': '2026-01-01T00:00:00.000Z',
          'id': '00000000-0000-0000-0000-000000000000',
        },
      );
      expect(result, isA<PaymentAttemptStatusUnavailable>());
      expect(
        (result as PaymentAttemptStatusUnavailable).reason,
        'cursor_did_not_advance',
      );
    });

    test('S1R2-F002j POSITIVE CONTROL: one clean terminal row resolves the '
        'attempt from the ledger alone', () async {
      final result = await lookup([terminalRow()]);
      expect(result, isA<PaymentAttemptStatusApplied>());
      expect(
        (result as PaymentAttemptStatusApplied).resolution.receiptNumber,
        'R-1',
      );
    });

    Map<String, Object?> page({
      required List<Object?> rows,
      required bool hasMore,
      Object? cursorId,
    }) => <String, Object?>{
      'ok': true,
      'operation_statuses': <String, Object?>{
        'rows': rows,
        'has_more': hasMore,
        'next_cursor': hasMore
            ? <String, Object?>{
                'updated_at': '2026-09-08T12:00:0$cursorId.000Z',
                'id': 'cursor-$cursorId',
              }
            : null,
      },
    };

    Future<PaymentAttemptStatusLookup> walk(List<Object?> pages) {
      return RealPaymentRepository(
        _PagedTransport(pages),
        const SyncSession(pinSessionId: 'pin-A', deviceId: 'device-A'),
        FixedClientIdGenerator(const ['unused-1', 'unused-2']),
        clock: () => _pinnedNow,
      ).lookupAttemptStatus(attempt);
    }

    test('S1R2-F002k a feed that keeps advancing past the bounded window '
        'answers UNAVAILABLE, never "not found"', () async {
      // Every page advances honestly and never carries our row. The search is
      // bounded, and a bounded search that ran out is not evidence of absence.
      final result = await walk(<Object?>[
        for (var i = 0; i < 12; i++)
          page(rows: const <Object?>[], hasMore: true, cursorId: i),
      ]);
      expect(result, isA<PaymentAttemptStatusUnavailable>());
      expect(
        (result as PaymentAttemptStatusUnavailable).reason,
        'too_many_pages',
      );
    });

    test('S1R2-F002l POSITIVE CONTROL: a row on a LATER page is still found '
        'within the window', () async {
      final result = await walk(<Object?>[
        page(rows: const <Object?>[], hasMore: true, cursorId: 0),
        page(rows: const <Object?>[], hasMore: true, cursorId: 1),
        page(rows: <Object?>[terminalRow()], hasMore: false),
      ]);
      expect(result, isA<PaymentAttemptStatusApplied>());
    });

    test('S1R2-F002m an exhausted feed with no row at all is NOT FOUND, which '
        'is still not a refusal', () async {
      final result = await walk(<Object?>[
        page(rows: const <Object?>[], hasMore: false),
      ]);
      expect(result, isA<PaymentAttemptStatusNotFound>());
    });
  });

  // =========================================================================
  // S1-R2 / F004 — the FAILED-PERSISTENCE variants of the ambiguity sequences.
  //
  // The RECREATION variants live in
  // `payment_attempt_recovery_001_r2_b2_test.dart`; these two need the
  // write-refusing adapter, so they live with it. In both, the money question
  // is still open when the store refuses to record the answer, and the cashier
  // may never be shown a settled or refused outcome on that basis.
  group('S1-R2/F004 — an unrecordable outcome is never a settled one', () {
    // S1-R3 — adopted UNCHANGED in substance from Codex's external harness
    // `reviewer_f004_failed_marker_test.dart`. At 5159338a it failed twice:
    // the failed ambiguity-marker write left the durable record reading
    // `pending` / `last_outcome: none`, and a rebuilt controller with a
    // supported reader treated that stale record as proof the first dispatch
    // never happened.
    test('REVIEWER-R2-F004-FAILED-MARKER supported-reader rebuild keeps lost '
        'ambiguity monotonic', () async {
      final prefs = _CacheFirstPrefs();
      final server = _server()..faultNext(ServerFault.dropResponseAfterCommit);
      final transport = _SecondPushPreconditionTransport(server);
      final firstStore = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: _ScriptedBackingReader(prefs.backing),
      );
      final firstTill = _till(
        server: server,
        transport: transport,
        store: firstStore,
      );
      // The claim lands. Only the later write of `unconfirmed` is refused.
      prefs.failFromWrite = 2;

      final first = await firstTill.submit();
      // ADAPTED IN S1-R3, assertions untouched: a probe that asks what is
      // really on disk now reads through an INDEPENDENT view, because after an
      // unverified write the writing adapter's cache is no longer evidence.
      final durableAfterFirst = await _durableView(prefs.backing).load(_scopeA);
      expect(first, isA<PaymentAttemptUnconfirmed>());
      expect(
        durableAfterFirst.attempts.single.phase,
        PaymentAttemptPhase.pending,
      );
      expect(
        durableAfterFirst.attempts.single.lastOutcome,
        PaymentAttemptLastOutcome.none,
        reason: 'the unconfirmed-note write did not reach backing',
      );
      expect(
        paymentAttemptAdapterIsUntrusted(
          prefs,
          paymentAttemptsPhysicalKey(_scopeA.key),
        ),
        isTrue,
      );

      // Model a target with a genuine independent backing read. A controller
      // rebuild must not infer that the old `none` note erases the first send.
      prefs.failFromWrite = 0;
      final rebuilt = _till(
        server: server,
        transport: transport,
        store: SharedPrefsPaymentAttemptStore(
          prefs,
          backingReader: _ScriptedBackingReader(prefs.backing),
        ),
      );
      await rebuilt.payments.ensureHydrated();
      final second = await rebuilt.resume();
      final durableAfterSecond = await _durableView(
        prefs.backing,
      ).load(_scopeA);

      expect(
        <String, Object?>{
          'second': second.runtimeType.toString(),
          'phase': durableAfterSecond.attempts.single.phase.wire,
          'attempts': durableAfterSecond.attempts.length,
          'firstIds': firstTill.ids.calls,
          'rebuiltIds': rebuilt.ids.calls,
          'paymentPushes': transport.paymentPushes,
          'executions': server.executions,
          'payments': server.completedPaymentsFor('order-1'),
        },
        <String, Object?>{
          'second': 'PaymentAttemptUnconfirmed',
          'phase': 'pending',
          'attempts': 1,
          'firstIds': 2,
          'rebuiltIds': 0,
          'paymentPushes': 2,
          'executions': 1,
          'payments': 1,
        },
        reason:
            'fresh backing proves only the stale pending bytes; it does not '
            'prove that the already-dispatched invocation never executed',
      );
    });

    test('S1R2-F004d when the AMBIGUOUS outcome cannot be persisted the '
        'cashier is not told the payment resolved', () async {
      final prefs = _CacheFirstPrefs();
      final server = _server()..faultNext(ServerFault.dropResponseAfterCommit);
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );
      // The claim lands; the write that records the ambiguity does not.
      prefs.failFromWrite = 2;

      final outcome = await till.submit();

      expect(
        <String, Object?>{
          'accepted': outcome is PaymentAttemptAccepted,
          'refused': outcome is PaymentAttemptRefused,
          'settledElsewhere': outcome is PaymentAttemptSettledElsewhere,
          'ids': till.ids.calls,
          'paymentOps': server.paymentOpsSeen.length,
        },
        <String, Object?>{
          'accepted': false,
          'refused': false,
          'settledElsewhere': false,
          'ids': 2,
          'paymentOps': 1,
        },
        reason:
            'a lost reply plus a lost write is maximum doubt, and doubt is '
            'never reported as a resolution',
      );
      // The durable truth is the claim written before the send: still pending,
      // still the same identity, with no replacement minted beside it.
      final stored = await _durableView(prefs.backing).load(_scopeA);
      expect(stored.attempts.single.localOperationId, 'a-id-1');
      expect(stored.attempts.single.phase, PaymentAttemptPhase.pending);
    });

    test('S1R2-F004e a REFUSAL the store cannot record is still reported, '
        'but it can never become a second charge', () async {
      final prefs = _CacheFirstPrefs();
      // No open shift: the server MEMOIZES a definitive refusal for this key,
      // and nothing was charged.
      final server = _server(shifts: const <String>{});
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );
      // The claim lands; the write that records the refusal does not.
      prefs.failFromWrite = 2;

      final first = await till.submit();

      // Reporting the refusal is honest and safe: the evidence is the
      // SERVER's ledger, which holds it for this key forever, and no money
      // moved. What must never follow is a second charge built on a local
      // record this build could not write.
      expect(first, isA<PaymentAttemptRefused>());
      // S1-R3 / F004: BOTH truths, together. The remote refusal is exact and
      // stays exact; the failed local save is disclosed beside it instead of
      // being swallowed (which hid it) or relabelled as unconfirmed (which
      // would deny a refusal the server really made).
      expect(
        (first as PaymentAttemptRefused).localSaveFailed,
        isTrue,
        reason: 'the cashier is told this device could not record the refusal',
      );
      expect(first.code, PaymentRefusalCode.shiftRequired);
      expect(till.ids.calls, 2, reason: 'no replacement identity yet');
      expect(server.completedPaymentsFor('order-1'), 0);

      // The shift is opened and the cashier tries again on the SAME till.
      server.shiftOpenDevices.add('device-A');
      final second = await till.submit();

      expect(
        second,
        isA<PaymentAttemptSaveBlocked>(),
        reason:
            'the unverified write left this key untrusted, so a correction '
            'attempt cannot be claimed durably — and an unclaimable attempt '
            'is never sent',
      );
      expect(
        server.completedPaymentsFor('order-1'),
        0,
        reason: 'nothing was charged on a record that could not be stored',
      );
      expect(
        paymentAttemptAdapterIsUntrusted(
          prefs,
          paymentAttemptsPhysicalKey(_scopeA.key),
        ),
        isTrue,
      );

      // Repeated Confirm, then a REBUILT controller and store over the same
      // physical key: neither route may turn the unrecorded refusal into a
      // charge or a fresh identity.
      final third = await till.submit();
      expect(third, isA<PaymentAttemptSaveBlocked>());
      final rebuilt = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );
      await rebuilt.payments.ensureHydrated();
      final afterRebuild = await rebuilt.submit();
      // A rebuilt stack hydrates through the contained key first, so it says
      // "quarantined" rather than "save blocked". Both are the same safety
      // class — nothing sent, nothing minted — and this asserts that class
      // rather than one spelling of it.
      expect(
        <bool>[
          afterRebuild is PaymentAttemptAccepted,
          afterRebuild is PaymentAttemptRefused,
          afterRebuild is PaymentAttemptSettledElsewhere,
        ],
        <bool>[false, false, false],
        reason: 'a rebuilt stack inherits the containment, not the phantom',
      );

      // And on a target that CAN read its own backing, the truth it reads is
      // the durable pending record — never the cache's refused image.
      final supported = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(
          prefs,
          backingReader: _MapBackingReader(prefs.backing),
        ),
      );
      final durable = await _durableView(prefs.backing).load(_scopeA);
      expect(durable.attempts.single.phase, PaymentAttemptPhase.pending);
      expect(durable.attempts.single.mayHaveExecuted, isTrue);
      await supported.payments.ensureHydrated();
      expect(
        supported.state.attempts.values.single.phase,
        PaymentAttemptPhase.pending,
      );
      expect(
        server.completedPaymentsFor('order-1'),
        0,
        reason: 'no route produced a charge',
      );
    });

    test('S1R3-F004f CONTROL: a memoized refusal that DOES persist is a plain '
        'exact refusal, and still permits the linked correction', () async {
      final prefs = _CacheFirstPrefs();
      final server = _server(shifts: const <String>{});
      final till = _till(
        server: server,
        store: SharedPrefsPaymentAttemptStore(prefs),
      );

      final refused = await till.submit();
      expect(refused, isA<PaymentAttemptRefused>());
      expect(
        (refused as PaymentAttemptRefused).localSaveFailed,
        isFalse,
        reason: 'nothing to disclose when the record really was written',
      );
      expect(refused.code, PaymentRefusalCode.shiftRequired);
      final stored = await _durableView(prefs.backing).load(_scopeA);
      expect(stored.attempts.single.phase, PaymentAttemptPhase.refused);
      expect(stored.attempts.single.refusalMemoized, isTrue);

      // The authoritative precondition is corrected, and the existing explicit
      // linked correction still works.
      server.shiftOpenDevices.add('device-A');
      final corrected = await till.submit();
      expect(corrected, isA<PaymentAttemptAccepted>());
      final after = await _durableView(prefs.backing).load(_scopeA);
      expect(after.attempts, hasLength(2));
      expect(
        after.attempts.last.supersedes,
        after.attempts.first.localOperationId,
      );
      expect(server.completedPaymentsFor('order-1'), 1);
    });
  });
}
