// PAYMENT-ATTEMPT-RECOVERY-001 / S1-R5 — the MUTATION-AUTHORITY regressions
// (F001), plus the stale-operation disclosure schedule (F004).
//
// Adopted UNCHANGED in substance from two retained Codex harnesses:
//   * `reviewer_s1_r4_f001_residual_schedules_test.dart` (SHA-256
//     F3897E5FA504B32C14FAEA74DEEDBB99F054DE135C9F6784920329C184DDEB82) —
//     eleven cases, of which seven are the R4 regressions this file
//     supersedes and four are the R5 residuals; at 8d6b804f it ran
//     7 pass / 4 fail, twice.
//   * `reviewer_s1_r4_stale_disclosure_test.dart` (SHA-256
//     D3F41FB59C62E99A793E69FB991B8A0B204395735DACAD3A3C8B45D53E191335) —
//     the same base plus CODEX-S1R4-F001-F004-STALE-DISCLOSURE, which is the
//     only case carried across from it (its own double travels with it);
//     at 8d6b804f that case ran 0/1, twice.
//
// Every case asserts the REQUIRED SAFE outcome, so none needed a twin. Not one
// assertion, input or fixture was altered — only this header, the per-test
// reset of the two isolate-wide registers, and the merge of the two files.
//
// The four residuals cover: authority lapsing while `resolveAccepted` waits in
// the physical-key queue; a stored terminal refusal being turned into
// acceptance; a proposal matching only on operation id; and a superseded
// operation contaminating the current one's disclosure.
//
// Synthetic local storage and synthetic repository results only. No network,
// no hosted service, no device, no printer, no drawer.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/order_identity.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_attempt.dart';
import 'package:restoflow_pos/src/data/payment_attempt_store.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosPersistenceException, PosSyncScope;
import 'package:restoflow_pos/src/state/order_sync_controller.dart'
    show posSyncClockProvider;
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart'
    show posSignedInEmployeeProfileIdProvider, posSyncSessionProvider;
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _scope = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'restaurant-1',
  branchId: 'branch-1',
  deviceId: 'device-1',
);

const _session = SyncSession(
  pinSessionId: 'pin-session-1',
  deviceId: 'device-1',
);

const _resolution = PaymentAttemptResolution(
  paymentId: 'payment-1',
  receiptNumber: 'receipt-1',
  changeDueMinor: 1000,
  method: PaymentMethod.cash,
  replay: true,
  orderStatus: 'completed',
);

String get _logicalKey => paymentAttemptsStorageKey(_scope.key);
String get _physicalKey => paymentAttemptsPhysicalKey(_scope.key);

String _logical(String physicalKey) =>
    physicalKey.startsWith(kLegacySharedPreferencesKeyPrefix)
    ? physicalKey.substring(kLegacySharedPreferencesKeyPrefix.length)
    : physicalKey;

PaymentAttempt _attempt(String operationId) => PaymentAttempt.mint(
  ids: FixedClientIdGenerator([operationId, '$operationId-target']),
  now: DateTime.utc(2026, 9, 9, 15),
  orderId: 'order-1',
  orderNumber: '#R-1',
  amountMinor: 4000,
  tenderedMinor: 5000,
  currencyCode: 'ILS',
  method: PaymentMethod.cash,
  expectedRevision: 7,
  organizationId: _scope.organizationId,
  restaurantId: _scope.restaurantId,
  branchId: _scope.branchId,
  deviceId: _scope.deviceId,
  employeeProfileId: 'employee-1',
);

class _Ids implements ClientIdGenerator {
  int calls = 0;

  @override
  String newId() => 'id-${++calls}';
}

class _Namespace {
  final Map<String, String> visible = <String, String>{};
  final Map<String, String> durable = <String, String>{};
}

class _Writer implements SharedPreferences {
  _Writer(this.namespace, {this.fail = false}) {
    cache.addAll(namespace.visible);
  }

  final _Namespace namespace;
  final Map<String, String> cache = <String, String>{};
  bool fail;

  @override
  String? getString(String key) => cache[key];

  @override
  Future<bool> setString(String key, String value) async {
    cache[key] = value;
    namespace.visible[key] = value;
    if (fail) return false;
    namespace.durable[key] = value;
    return true;
  }

  @override
  bool containsKey(String key) => cache.containsKey(key);

  @override
  Set<String> getKeys() => cache.keys.toSet();

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused ${invocation.memberName}');
}

class _DirectReader implements PaymentAttemptBackingReader {
  const _DirectReader(this.namespace);
  final _Namespace namespace;

  @override
  Future<String?> readRaw(String physicalKey) async =>
      namespace.durable[_logical(physicalKey)];
}

/// A reader whose FIRST read is held open, so a newer write can land while an
/// older read is still in flight.
///
/// CHANGED MECHANISM, stated: the reviewer's version can be entered only once
/// (it completes a single `Completer` on entry), so a store that correctly
/// re-reads after the generation moved would crash rather than recover. This
/// version holds only the first read and answers later ones normally, which is
/// what a real reader does — and is the only way to observe the SAFE outcome
/// rather than merely the absence of the unsafe one.
class _HoldFirstReadReader implements PaymentAttemptBackingReader {
  _HoldFirstReadReader(this.namespace);
  final _Namespace namespace;
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();
  int reads = 0;

  @override
  Future<String?> readRaw(String physicalKey) async {
    reads++;
    if (reads == 1) {
      final snapshot = namespace.durable[_logical(physicalKey)];
      if (!entered.isCompleted) entered.complete();
      await release.future;
      return snapshot;
    }
    return namespace.durable[_logical(physicalKey)];
  }
}

class _BackingReader implements PaymentAttemptBackingReader {
  const _BackingReader(this.prefs);
  final SharedPreferences prefs;

  @override
  Future<String?> readRaw(String physicalKey) async =>
      prefs.getString(_logical(physicalKey));
}

/// The first send is parked; every later send is accepted.
class _TwoResultRepository implements PaymentRepository, PaymentAttemptSender {
  final Completer<void> firstSendEntered = Completer<void>();
  final Completer<PaymentSendResult> firstResult =
      Completer<PaymentSendResult>();
  final List<String> operationIds = <String>[];

  @override
  Future<PaymentSendResult> sendAttempt(PaymentAttempt attempt) {
    operationIds.add(attempt.localOperationId);
    if (operationIds.length == 1) {
      firstSendEntered.complete();
      return firstResult.future;
    }
    return Future<PaymentSendResult>.value(
      const PaymentSendAccepted(_resolution),
    );
  }

  @override
  Future<PaymentAttemptStatusLookup> lookupAttemptStatus(
    PaymentAttempt attempt,
  ) async => const PaymentAttemptStatusUnavailable('not-used');

  @override
  Future<CashPayment> recordCashPayment({
    required String orderId,
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    PaymentMethod method = PaymentMethod.cash,
    int? expectedRevision,
  }) => throw UnsupportedError('durable attempt path only');

  @override
  ShiftContext shiftContext() => const ShiftContext(
    shiftOpen: true,
    drawerOpen: true,
    openingFloatMinor: 0,
    cashInDrawerMinor: 0,
    lastPaymentMinor: null,
    currencyCode: 'ILS',
  );

  @override
  CashPayment? paymentFor(PosOrderIdentity identity) => null;
}

Future<Object?> _capture(Future<Object?> future) =>
    future.then<Object?>((value) => value, onError: (Object error, _) => error);

Future<void> _settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

List<Object?> _durableAttempts(_Namespace namespace) {
  final raw = namespace.durable[_logicalKey];
  if (raw == null) return const <Object?>[];
  return (jsonDecode(raw) as Map)['attempts'] as List<Object?>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetPaymentAttemptKeyGuardsForTest);
  setUp(resetPaymentDisclosuresForTest);

  test('S1R4-F001-REBIND: a late diagnostic from a REPLACED controller cannot '
      'downgrade a newer acceptance or re-arm its effects', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final reader = _BackingReader(prefs);
    final firstStore = SharedPrefsPaymentAttemptStore(
      prefs,
      backingReader: reader,
    );
    final secondStore = SharedPrefsPaymentAttemptStore(
      prefs,
      backingReader: reader,
    );
    final activeStore = StateProvider<PaymentAttemptStore>((_) => firstStore);
    final repository = _TwoResultRepository();
    final ids = _Ids();
    final container = ProviderContainer(
      overrides: <Override>[
        paymentRepositoryProvider.overrideWithValue(repository),
        paymentAttemptStoreProvider.overrideWith(
          (ref) => ref.watch(activeStore),
        ),
        posSyncScopeProvider.overrideWithValue(_scope),
        posSyncSessionProvider.overrideWithValue(_session),
        clientIdGeneratorProvider.overrideWithValue(ids),
        posSyncClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 9, 9, 15),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(posSignedInEmployeeProfileIdProvider.notifier)
        .set('employee-1');

    final firstController = container.read(paymentControllerProvider.notifier);
    await firstController.ensureHydrated();
    final first = firstController.submitAttempt(
      identity: PosOrderIdentity.server('order-1'),
      orderId: 'order-1',
      orderNumber: '#R-1',
      amountMinor: 4000,
      tenderedMinor: 5000,
      currencyCode: 'ILS',
      expectedRevision: 7,
    );
    await repository.firstSendEntered.future;

    // The production override rebuild: a new store object over the SAME boot
    // preferences instance, exactly as main.dart does on a device-seams change.
    container.read(activeStore.notifier).state = secondStore;
    final reboundController = container.read(
      paymentControllerProvider.notifier,
    );
    await reboundController.ensureHydrated();

    final second = await reboundController.submitAttempt(
      identity: PosOrderIdentity.server('order-1'),
      orderId: 'order-1',
      orderNumber: '#R-1',
      amountMinor: 4000,
      tenderedMinor: 5000,
      currencyCode: 'ILS',
      expectedRevision: 7,
    );
    expect(second, isA<PaymentAttemptAccepted>());
    expect(
      (second as PaymentAttemptAccepted).automaticEffectsArmed,
      isTrue,
      reason: 'the CURRENT world legitimately arms the one-time effects once',
    );

    repository.firstResult.complete(const PaymentSendAuthRequired());
    expect(await first, isA<PaymentAttemptAuthRequired>());
    await _settle();

    expect(repository.operationIds, hasLength(2));
    expect(
      repository.operationIds.toSet(),
      hasLength(1),
      reason: 'one decision, one identity throughout',
    );

    final stored = await secondStore.load(_scope);
    expect(stored.attempts, hasLength(1));
    final preserved = stored.attempts.single;
    expect(
      preserved.phase,
      PaymentAttemptPhase.accepted,
      reason: 'a stale diagnostic may not downgrade a terminal record',
    );
    expect(preserved.lastOutcome, PaymentAttemptLastOutcome.none);
    expect(preserved.resolution, isNotNull);
    expect(preserved.resolution!.paymentId, 'payment-1');
    expect(preserved.resolution!.receiptNumber, 'receipt-1');
    expect(
      preserved.autoEffectsReservedAt,
      isNotNull,
      reason: 'the one-time effect claim survives the stale callback',
    );
    expect(preserved.mayHaveExecuted, isTrue);

    // A third world reads the PRESERVED record. Because the acceptance still
    // stands, this is a replay of a settled decision and must not arm paper or
    // a drawer a second time for one payment.
    final thirdStore = SharedPrefsPaymentAttemptStore(
      prefs,
      backingReader: reader,
    );
    container.read(activeStore.notifier).state = thirdStore;
    final thirdController = container.read(paymentControllerProvider.notifier);
    await thirdController.ensureHydrated();
    final third = await thirdController.submitAttempt(
      identity: PosOrderIdentity.server('order-1'),
      orderId: 'order-1',
      orderNumber: '#R-1',
      amountMinor: 4000,
      tenderedMinor: 5000,
      currencyCode: 'ILS',
      expectedRevision: 7,
    );
    expect(third, isA<PaymentAttemptAccepted>());
    expect(
      (third as PaymentAttemptAccepted).automaticEffectsArmed,
      isFalse,
      reason: 'the durable reservation still stands, so nothing re-arms',
    );
    expect(
      repository.operationIds,
      hasLength(2),
      reason: 'a settled decision is answered from its record, not re-sent',
    );
  });

  test(
    'S1R4-F001-WRAPPER-CACHE: a wrapper that made an unconfirmed write '
    'never regains authority, even after a newer write clears the key',
    () async {
      final namespace = _Namespace();
      final oldWriter = _Writer(namespace, fail: true);
      final oldStore = SharedPrefsPaymentAttemptStore(
        oldWriter,
        backingReader: _DirectReader(namespace),
      );
      final oldAttempt = _attempt('op-old-unverified');

      expect(
        await _capture(oldStore.createIfAbsent(_scope, oldAttempt)),
        isA<PosPersistenceException>(),
      );
      expect(paymentAttemptKeyIsUntrusted(_physicalKey), isTrue);
      expect(
        paymentAttemptAdapterHoldsPhantom(oldWriter, _physicalKey),
        isTrue,
        reason: 'this wrapper holds bytes that never landed',
      );
      expect(namespace.durable, isEmpty);

      final currentWriter = _Writer(namespace);
      final currentStore = SharedPrefsPaymentAttemptStore(
        currentWriter,
        backingReader: _DirectReader(namespace),
      );
      final currentAttempt = _attempt('op-current-durable');
      expect(
        (await currentStore.createIfAbsent(_scope, currentAttempt)).created,
        isTrue,
      );
      // The KEY is trusted again — a confirmed write superseded the failure.
      expect(paymentAttemptKeyIsUntrusted(_physicalKey), isFalse);
      // The old WRAPPER still is not: its own cache was never repaired.
      expect(
        paymentAttemptAdapterHoldsPhantom(oldWriter, _physicalKey),
        isTrue,
      );

      final staleClaim = await oldStore.createIfAbsent(
        _scope,
        _attempt('op-third-cashier-decision'),
      );
      expect(
        staleClaim.created,
        isFalse,
        reason: 'a pending attempt for this order already exists durably',
      );
      expect(
        staleClaim.attempt.localOperationId,
        currentAttempt.localOperationId,
        reason: 'the DURABLE current attempt is adopted, never the phantom',
      );
    },
  );

  test('S1R4-F001-STALE-UPDATE: a stale wrapper cannot overwrite the newer '
      'durable attempt', () async {
    final namespace = _Namespace();
    final oldWriter = _Writer(namespace, fail: true);
    final oldStore = SharedPrefsPaymentAttemptStore(
      oldWriter,
      backingReader: _DirectReader(namespace),
    );
    final oldAttempt = _attempt('op-old-unverified');
    expect(
      await _capture(oldStore.createIfAbsent(_scope, oldAttempt)),
      isA<PosPersistenceException>(),
    );

    final currentWriter = _Writer(namespace);
    final currentStore = SharedPrefsPaymentAttemptStore(
      currentWriter,
      backingReader: _DirectReader(namespace),
    );
    final currentAttempt = _attempt('op-current-durable');
    expect(
      (await currentStore.createIfAbsent(_scope, currentAttempt)).created,
      isTrue,
    );

    oldWriter.fail = false;
    final outcome = await _capture(
      oldStore.update(_scope, oldAttempt.markSent('2026-09-09T15:01:00.000Z')),
    );
    expect(
      outcome,
      isA<PosPersistenceException>(),
      reason: 'an update has no stored record of its own to transition',
    );

    final entries = _durableAttempts(namespace);
    expect(entries, hasLength(1));
    expect(
      (entries.single as Map)['local_operation_id'],
      currentAttempt.localOperationId,
      reason: 'the newer durable attempt is intact',
    );
  });

  test('S1R4-F001-DELAYED-READ: an independent read that finishes after the '
      'key moved on is never returned as authoritative', () async {
    final namespace = _Namespace();
    final failedWriter = _Writer(namespace, fail: true);
    final failedStore = SharedPrefsPaymentAttemptStore(
      failedWriter,
      backingReader: _DirectReader(namespace),
    );
    expect(
      await _capture(
        failedStore.createIfAbsent(_scope, _attempt('op-unverified')),
      ),
      isA<PosPersistenceException>(),
    );

    final holdingReader = _HoldFirstReadReader(namespace);
    final staleLoadStore = SharedPrefsPaymentAttemptStore(
      _Writer(namespace),
      backingReader: holdingReader,
    );
    final staleLoad = staleLoadStore.load(_scope);
    await holdingReader.entered.future;

    final currentStore = SharedPrefsPaymentAttemptStore(
      _Writer(namespace),
      backingReader: _DirectReader(namespace),
    );
    final currentAttempt = _attempt('op-current-durable');
    expect(
      (await currentStore.createIfAbsent(_scope, currentAttempt)).created,
      isTrue,
    );

    holdingReader.release.complete();
    final staleResult = await staleLoad;

    expect(
      holdingReader.reads,
      greaterThan(1),
      reason: 'the read that spanned a generation change was re-taken',
    );
    expect(
      staleResult.attempts.single.localOperationId,
      currentAttempt.localOperationId,
      reason: 'the caller is given the CURRENT truth, not the stale snapshot',
    );
    expect(staleResult.quarantined, isEmpty);
  });

  test('S1R4-F001-SAME-WRITER-DOWNGRADE: a stale callback on the SAME writer '
      'cannot downgrade a newer accepted record', () async {
    final namespace = _Namespace();
    final writer = _Writer(namespace);
    final store = SharedPrefsPaymentAttemptStore(
      writer,
      backingReader: _DirectReader(namespace),
    );
    final original = _attempt(
      'op-same-writer',
    ).markSent('2026-09-09T15:00:00.000Z');
    expect((await store.createIfAbsent(_scope, original)).created, isTrue);

    writer.fail = true;
    expect(
      await _capture(
        store.update(
          _scope,
          original.withLastOutcome(PaymentAttemptLastOutcome.unconfirmed),
        ),
      ),
      isA<PosPersistenceException>(),
    );
    expect(paymentAttemptKeyIsUntrusted(_physicalKey), isTrue);

    writer.fail = false;
    final acceptance = await store.resolveAccepted(
      _scope,
      original,
      _resolution,
      at: '2026-09-09T15:02:00.000Z',
      armCaller: true,
    );
    expect(acceptance.attempt.phase, PaymentAttemptPhase.accepted);
    expect(acceptance.attempt.autoEffectsReservedAt, isNotNull);

    // The late diagnostic path calls the same update API with its stale value.
    final merge = await store.update(
      _scope,
      original.withLastOutcome(PaymentAttemptLastOutcome.authRequired),
    );
    expect(
      merge.outcome,
      PaymentAttemptMergeOutcome.stale,
      reason: 'the caller is told its proposal was older than the record',
    );

    final loaded = await store.load(_scope);
    expect(loaded.attempts, hasLength(1));
    final preserved = loaded.attempts.single;
    expect(preserved.phase, PaymentAttemptPhase.accepted);
    expect(preserved.lastOutcome, PaymentAttemptLastOutcome.none);
    expect(preserved.resolution, isNotNull);
    expect(preserved.autoEffectsReservedAt, isNotNull);
    expect(preserved.mayHaveExecuted, isTrue);
  });

  test('S1R4-F001-CONTROL-PROGRESS: legitimate current-owner transitions and '
      'same-key convergence still advance', () async {
    final namespace = _Namespace();
    final writer = _Writer(namespace);
    final store = SharedPrefsPaymentAttemptStore(
      writer,
      backingReader: _DirectReader(namespace),
    );
    final original = _attempt(
      'op-progress',
    ).markSent('2026-09-09T15:00:00.000Z');
    expect((await store.createIfAbsent(_scope, original)).created, isTrue);

    // pending -> pending with a note: a real advance.
    final noted = await store.update(
      _scope,
      original.withLastOutcome(PaymentAttemptLastOutcome.unconfirmed),
    );
    expect(noted.outcome, PaymentAttemptMergeOutcome.applied);
    expect(noted.record.lastOutcome, PaymentAttemptLastOutcome.unconfirmed);

    // the SAME note again: redundant, not an error and not a downgrade.
    final again = await store.update(
      _scope,
      original.withLastOutcome(PaymentAttemptLastOutcome.unconfirmed),
    );
    expect(again.outcome, PaymentAttemptMergeOutcome.redundant);

    // pending -> accepted: a real terminal advance that reserves once.
    final acceptance = await store.resolveAccepted(
      _scope,
      original,
      _resolution,
      at: '2026-09-09T15:02:00.000Z',
      armCaller: true,
    );
    expect(acceptance.armed, isTrue);
    expect(
      (await store.load(_scope)).attempts.single.phase,
      PaymentAttemptPhase.accepted,
    );
  });

  test('S1R4-F001-CONTROL-CONFLICT: a proposal for a DIFFERENT decision under '
      'the same operation id is a conflict, never a merge', () async {
    final namespace = _Namespace();
    final writer = _Writer(namespace);
    final store = SharedPrefsPaymentAttemptStore(
      writer,
      backingReader: _DirectReader(namespace),
    );
    final original = _attempt(
      'op-conflict',
    ).markSent('2026-09-09T15:00:00.000Z');
    expect((await store.createIfAbsent(_scope, original)).created, isTrue);

    // Same operation id, different frozen money — not the same decision.
    final impostor = PaymentAttempt.mint(
      ids: FixedClientIdGenerator(const ['op-conflict', 'op-conflict-target']),
      now: DateTime.utc(2026, 9, 9, 15),
      orderId: 'order-1',
      orderNumber: '#R-1',
      amountMinor: 9999,
      tenderedMinor: 9999,
      currencyCode: 'ILS',
      method: PaymentMethod.cash,
      expectedRevision: 7,
      organizationId: _scope.organizationId,
      restaurantId: _scope.restaurantId,
      branchId: _scope.branchId,
      deviceId: _scope.deviceId,
      employeeProfileId: 'employee-1',
    ).markSent('2026-09-09T15:00:00.000Z');

    final merge = await store.update(_scope, impostor);
    expect(merge.outcome, PaymentAttemptMergeOutcome.conflict);
    expect(merge.record.amountMinor, 4000, reason: 'the stored record stands');
    expect(
      (await store.load(_scope)).attempts.single.amountMinor,
      4000,
      reason: 'nothing composite was invented',
    );
  });

  test(
    'CODEX-S1R4-F001-RESIDUAL-AUTHORITY-001: losing controller authority '
    'while resolveAccepted waits in the key queue cannot reserve effects',
    () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final reader = _BackingReader(prefs);
      final firstStore = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: reader,
      );
      final secondStore = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: reader,
      );
      final activeStore = StateProvider<PaymentAttemptStore>((_) => firstStore);
      final repository = _TwoResultRepository();
      final container = ProviderContainer(
        overrides: <Override>[
          paymentRepositoryProvider.overrideWithValue(repository),
          paymentAttemptStoreProvider.overrideWith(
            (ref) => ref.watch(activeStore),
          ),
          posSyncScopeProvider.overrideWithValue(_scope),
          posSyncSessionProvider.overrideWithValue(_session),
          clientIdGeneratorProvider.overrideWithValue(_Ids()),
          posSyncClockProvider.overrideWithValue(
            () => DateTime.utc(2026, 9, 9, 15),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(posSignedInEmployeeProfileIdProvider.notifier)
          .set('employee-1');

      final oldController = container.read(paymentControllerProvider.notifier);
      await oldController.ensureHydrated();
      final oldResult = oldController.submitAttempt(
        identity: PosOrderIdentity.server('order-1'),
        orderId: 'order-1',
        orderNumber: '#R-1',
        amountMinor: 4000,
        tenderedMinor: 5000,
        currencyCode: 'ILS',
        expectedRevision: 7,
      );
      await repository.firstSendEntered.future;
      final pending = (await firstStore.load(_scope)).attempts.single;

      // Occupy the physical-key queue before the old acceptance arrives, but
      // before a platform write begins. The controller can therefore pass its
      // pre-call generation check and enqueue behind this operation.
      final gate = _GatePrefsResolver(prefs);
      final frontStore = SharedPrefsPaymentAttemptStore.lazy(
        prefs: gate.resolve,
        backingReader: reader,
      );
      final front = frontStore.update(_scope, pending);
      await gate.entered.future;
      repository.firstResult.complete(const PaymentSendAccepted(_resolution));
      await _settle();

      // Authority changes while resolveAccepted is queued, after the only
      // controller check but before the storage mutation.
      container.read(activeStore.notifier).state = secondStore;
      final currentController = container.read(
        paymentControllerProvider.notifier,
      );
      await currentController.ensureHydrated();
      gate.release.complete();
      await front;
      final outcome = await oldResult;
      await _settle();

      final durable = (await secondStore.load(_scope)).attempts.single;
      // Diagnostic output is retained in the raw reviewer log.
      // ignore: avoid_print
      print(
        'AUTHORITY-001 outcome=${outcome.runtimeType} '
        'armed=${outcome is PaymentAttemptAccepted ? outcome.automaticEffectsArmed : null} '
        'phase=${durable.phase.name} reservation=${durable.autoEffectsReservedAt}',
      );
      expect(durable.phase, PaymentAttemptPhase.pending);
      expect(durable.autoEffectsReservedAt, isNull);
      expect(durable.resolution, isNull);
    },
  );

  test('CODEX-S1R4-F001-RESIDUAL-DISCLOSURE-002: a late refusal for superseded '
      'operation A cannot contaminate accepted operation B', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final reader = _BackingReader(prefs);
    final firstStore = SharedPrefsPaymentAttemptStore(
      prefs,
      backingReader: reader,
    );
    final secondStore = SharedPrefsPaymentAttemptStore(
      prefs,
      backingReader: reader,
    );
    final activeStore = StateProvider<PaymentAttemptStore>((_) => firstStore);
    final repository = _ThreeResultRepository();
    final container = ProviderContainer(
      overrides: <Override>[
        paymentRepositoryProvider.overrideWithValue(repository),
        paymentAttemptStoreProvider.overrideWith(
          (ref) => ref.watch(activeStore),
        ),
        posSyncScopeProvider.overrideWithValue(_scope),
        posSyncSessionProvider.overrideWithValue(_session),
        clientIdGeneratorProvider.overrideWithValue(_Ids()),
        posSyncClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 9, 9, 15),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(posSignedInEmployeeProfileIdProvider.notifier)
        .set('employee-1');

    final oldController = container.read(paymentControllerProvider.notifier);
    await oldController.ensureHydrated();
    final oldResult = oldController.submitAttempt(
      identity: PosOrderIdentity.server('order-1'),
      orderId: 'order-1',
      orderNumber: '#R-1',
      amountMinor: 4000,
      tenderedMinor: 5000,
      currencyCode: 'ILS',
      expectedRevision: 7,
    );
    await repository.firstSendEntered.future;

    container.read(activeStore.notifier).state = secondStore;
    final currentController = container.read(
      paymentControllerProvider.notifier,
    );
    await currentController.ensureHydrated();

    final refusal = await currentController.submitAttempt(
      identity: PosOrderIdentity.server('order-1'),
      orderId: 'order-1',
      orderNumber: '#R-1',
      amountMinor: 4000,
      tenderedMinor: 5000,
      currencyCode: 'ILS',
      expectedRevision: 7,
    );
    expect(refusal, isA<PaymentAttemptRefused>());
    final operationA = (refusal as PaymentAttemptRefused).attempt;

    final accepted = await currentController.submitAttempt(
      identity: PosOrderIdentity.server('order-1'),
      orderId: 'order-1',
      orderNumber: '#R-1',
      amountMinor: 4000,
      tenderedMinor: 5000,
      currencyCode: 'ILS',
      expectedRevision: 7,
    );
    expect(accepted, isA<PaymentAttemptAccepted>());
    final operationB = (accepted as PaymentAttemptAccepted).attempt;
    expect(operationB.localOperationId, isNot(operationA.localOperationId));
    expect(operationB.supersedes, operationA.localOperationId);
    expect(
      currentController.state.disclosureFor(PosOrderIdentity.server('order-1')),
      isNull,
    );

    repository.firstResult.complete(
      const PaymentSendRefused(
        PaymentRefusalCode.permissionDenied,
        memoized: true,
      ),
    );
    final late = await oldResult;
    await _settle();
    final disclosure = currentController.state.disclosureFor(
      PosOrderIdentity.server('order-1'),
    );
    // ignore: avoid_print
    print(
      'DISCLOSURE-002 A=${operationA.localOperationId} '
      'B=${operationB.localOperationId} late=${late.runtimeType} '
      'disclosure=${disclosure?.refusalCode?.wire}/'
      '${disclosure?.localSaveFailed}',
    );
    expect(disclosure, isNull);

    final durable = await secondStore.load(_scope);
    expect(durable.attempts, hasLength(2));
    final durableB = durable.attempts.singleWhere(
      (a) => a.localOperationId == operationB.localOperationId,
    );
    expect(durableB.phase, PaymentAttemptPhase.accepted);
    expect(durableB.autoEffectsReservedAt, isNotNull);
  });

  test('CODEX-S1R4-F001-RESIDUAL-CONFLICT-003: resolveAccepted cannot turn a '
      'stored terminal refusal into accepted evidence', () async {
    final namespace = _Namespace();
    final store = SharedPrefsPaymentAttemptStore(
      _Writer(namespace),
      backingReader: _DirectReader(namespace),
    );
    final original = _attempt(
      'op-terminal-conflict',
    ).markSent('2026-09-09T15:00:00.000Z');
    expect((await store.createIfAbsent(_scope, original)).created, isTrue);
    final refusal = original.refused(
      PaymentRefusalCode.permissionDenied,
      at: '2026-09-09T15:01:00.000Z',
      memoized: true,
    );
    expect(
      (await store.update(_scope, refusal)).outcome,
      PaymentAttemptMergeOutcome.applied,
    );

    final outcome = await _capture(
      store.resolveAccepted(
        _scope,
        original,
        _resolution,
        at: '2026-09-09T15:02:00.000Z',
        armCaller: true,
      ),
    );
    final loaded = await store.load(_scope);
    // ignore: avoid_print
    print(
      'CONFLICT-003 outcome=${outcome.runtimeType} '
      'readable=${loaded.attempts.length} quarantine=${loaded.quarantined.length} '
      'raw=${namespace.durable[_logicalKey]}',
    );
    expect(outcome, isA<PosPersistenceException>());
    expect(loaded.attempts, hasLength(1));
    expect(loaded.attempts.single.phase, PaymentAttemptPhase.refused);
    expect(loaded.attempts.single.autoEffectsReservedAt, isNull);
  });

  test('CODEX-S1R4-F001-RESIDUAL-IDENTITY-004: resolveAccepted requires the '
      'full frozen decision identity, not only operation id', () async {
    final namespace = _Namespace();
    final store = SharedPrefsPaymentAttemptStore(
      _Writer(namespace),
      backingReader: _DirectReader(namespace),
    );
    final original = _attempt(
      'op-identity-conflict',
    ).markSent('2026-09-09T15:00:00.000Z');
    expect((await store.createIfAbsent(_scope, original)).created, isTrue);
    final impostor = PaymentAttempt.mint(
      ids: FixedClientIdGenerator(const [
        'op-identity-conflict',
        'op-identity-conflict-target',
      ]),
      now: DateTime.utc(2026, 9, 9, 15),
      orderId: 'order-1',
      orderNumber: '#R-1',
      amountMinor: 9999,
      tenderedMinor: 9999,
      currencyCode: 'ILS',
      method: PaymentMethod.cash,
      expectedRevision: 7,
      organizationId: _scope.organizationId,
      restaurantId: _scope.restaurantId,
      branchId: _scope.branchId,
      deviceId: _scope.deviceId,
      employeeProfileId: 'employee-1',
    ).markSent('2026-09-09T15:00:00.000Z');

    final outcome = await _capture(
      store.resolveAccepted(
        _scope,
        impostor,
        _resolution,
        at: '2026-09-09T15:02:00.000Z',
        armCaller: true,
      ),
    );
    final loaded = await store.load(_scope);
    // ignore: avoid_print
    print(
      'IDENTITY-004 outcome=${outcome.runtimeType} '
      'storedAmount=${loaded.attempts.single.amountMinor} '
      'phase=${loaded.attempts.single.phase.name}',
    );
    expect(outcome, isA<PosPersistenceException>());
    expect(loaded.attempts.single.phase, PaymentAttemptPhase.pending);
    expect(loaded.attempts.single.amountMinor, 4000);
    expect(loaded.attempts.single.autoEffectsReservedAt, isNull);
  });

  test(
    'CODEX-S1R4-F001-F004-STALE-DISCLOSURE: a delayed refusal from the '
    'replaced controller cannot disclose over a newer linked acceptance',
    () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final reader = _BackingReader(prefs);
      final firstStore = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: reader,
      );
      final secondStore = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: reader,
      );
      final activeStore = StateProvider<PaymentAttemptStore>((_) => firstStore);
      final repository = _DelayedRefusalThenAcceptanceRepository();
      final ids = _Ids();
      final container = ProviderContainer(
        overrides: <Override>[
          paymentRepositoryProvider.overrideWithValue(repository),
          paymentAttemptStoreProvider.overrideWith(
            (ref) => ref.watch(activeStore),
          ),
          posSyncScopeProvider.overrideWithValue(_scope),
          posSyncSessionProvider.overrideWithValue(_session),
          clientIdGeneratorProvider.overrideWithValue(ids),
          posSyncClockProvider.overrideWithValue(
            () => DateTime.utc(2026, 9, 9, 15),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(posSignedInEmployeeProfileIdProvider.notifier)
          .set('employee-1');
      final identity = PosOrderIdentity.server('order-1');

      final oldController = container.read(paymentControllerProvider.notifier);
      await oldController.ensureHydrated();
      final delayed = oldController.submitAttempt(
        identity: identity,
        orderId: 'order-1',
        orderNumber: '#R-1',
        amountMinor: 4000,
        tenderedMinor: 5000,
        currencyCode: 'ILS',
        expectedRevision: 7,
      );
      await repository.firstSendEntered.future;

      // Production-shaped provider rebind over the same physical store.
      container.read(activeStore.notifier).state = secondStore;
      final currentController = container.read(
        paymentControllerProvider.notifier,
      );
      await currentController.ensureHydrated();

      // Replay operation A and persist its exact memoized refusal.
      final replayedRefusal = await currentController.submitAttempt(
        identity: identity,
        orderId: 'order-1',
        orderNumber: '#R-1',
        amountMinor: 4000,
        tenderedMinor: 5000,
        currencyCode: 'ILS',
        expectedRevision: 7,
      );
      expect(replayedRefusal, isA<PaymentAttemptRefused>());
      expect(
        (replayedRefusal as PaymentAttemptRefused).localSaveFailed,
        isFalse,
      );

      // A linked new cashier decision B is accepted and becomes current truth.
      final accepted = await currentController.submitAttempt(
        identity: identity,
        orderId: 'order-1',
        orderNumber: '#R-1',
        amountMinor: 4000,
        tenderedMinor: 5000,
        currencyCode: 'ILS',
        expectedRevision: 7,
      );
      expect(accepted, isA<PaymentAttemptAccepted>());
      expect(
        (accepted as PaymentAttemptAccepted).automaticEffectsArmed,
        isTrue,
      );
      expect(
        container.read(paymentControllerProvider).disclosureFor(identity),
        isNull,
      );

      // The delayed response for A now reaches the obsolete callback.
      repository.firstResult.complete(
        const PaymentSendRefused(
          PaymentRefusalCode.shiftRequired,
          memoized: true,
        ),
      );
      final staleOutcome = await delayed;
      expect(staleOutcome, isA<PaymentAttemptRefused>());
      await _settle();

      final current = container.read(paymentControllerProvider);
      expect(
        current.paymentFor(identity),
        isNotNull,
        reason: 'linked operation B remains the accepted current payment',
      );
      expect(
        current.disclosureFor(identity),
        isNull,
        reason: 'obsolete operation A may not write into current disclosure',
      );
      expect(repository.operationIds, hasLength(3));
      expect(repository.operationIds[0], repository.operationIds[1]);
      expect(repository.operationIds[2], isNot(repository.operationIds[0]));
    },
  );
}

/// A source-faithful late-response schedule:
///
/// 1. the first call for operation A is held after the server has memoized an
///    exact refusal;
/// 2. a replacement controller replays A and receives that refusal;
/// 3. the cashier starts linked operation B, which is accepted;
/// 4. the delayed response for A reaches the obsolete controller last.
///
/// A stale callback may report its own outcome to its awaiting caller, but it
/// must not write a disclosure for A into B's current order state.
class _DelayedRefusalThenAcceptanceRepository
    implements PaymentRepository, PaymentAttemptSender {
  final Completer<void> firstSendEntered = Completer<void>();
  final Completer<PaymentSendResult> firstResult =
      Completer<PaymentSendResult>();
  final List<String> operationIds = <String>[];

  @override
  Future<PaymentSendResult> sendAttempt(PaymentAttempt attempt) {
    operationIds.add(attempt.localOperationId);
    if (operationIds.length == 1) {
      firstSendEntered.complete();
      return firstResult.future;
    }
    if (operationIds.length == 2) {
      return Future<PaymentSendResult>.value(
        const PaymentSendRefused(
          PaymentRefusalCode.shiftRequired,
          memoized: true,
        ),
      );
    }
    return Future<PaymentSendResult>.value(
      const PaymentSendAccepted(_resolution),
    );
  }

  @override
  Future<PaymentAttemptStatusLookup> lookupAttemptStatus(
    PaymentAttempt attempt,
  ) async => const PaymentAttemptStatusUnavailable('not-used');

  @override
  Future<CashPayment> recordCashPayment({
    required String orderId,
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    PaymentMethod method = PaymentMethod.cash,
    int? expectedRevision,
  }) => throw UnsupportedError('durable attempt path only');

  @override
  ShiftContext shiftContext() => const ShiftContext(
    shiftOpen: true,
    drawerOpen: true,
    openingFloatMinor: 0,
    cashInDrawerMinor: 0,
    lastPaymentMinor: null,
    currencyCode: 'ILS',
  );

  @override
  CashPayment? paymentFor(PosOrderIdentity identity) => null;
}

class _GatePrefsResolver {
  _GatePrefsResolver(this.prefs);
  final SharedPreferences prefs;
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();

  Future<SharedPreferences> resolve() async {
    entered.complete();
    await release.future;
    return prefs;
  }
}

class _ThreeResultRepository
    implements PaymentRepository, PaymentAttemptSender {
  final Completer<void> firstSendEntered = Completer<void>();
  final Completer<PaymentSendResult> firstResult =
      Completer<PaymentSendResult>();
  final List<String> operationIds = <String>[];

  @override
  Future<PaymentSendResult> sendAttempt(PaymentAttempt attempt) {
    operationIds.add(attempt.localOperationId);
    if (operationIds.length == 1) {
      firstSendEntered.complete();
      return firstResult.future;
    }
    if (operationIds.length == 2) {
      return Future<PaymentSendResult>.value(
        const PaymentSendRefused(
          PaymentRefusalCode.permissionDenied,
          memoized: true,
        ),
      );
    }
    return Future<PaymentSendResult>.value(
      const PaymentSendAccepted(_resolution),
    );
  }

  @override
  Future<PaymentAttemptStatusLookup> lookupAttemptStatus(
    PaymentAttempt attempt,
  ) async => const PaymentAttemptStatusUnavailable('not-used');

  @override
  Future<CashPayment> recordCashPayment({
    required String orderId,
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    PaymentMethod method = PaymentMethod.cash,
    int? expectedRevision,
  }) => throw UnsupportedError('durable attempt path only');

  @override
  ShiftContext shiftContext() => const ShiftContext(
    shiftOpen: true,
    drawerOpen: true,
    openingFloatMinor: 0,
    cashInDrawerMinor: 0,
    lastPaymentMinor: null,
    currencyCode: 'ILS',
  );

  @override
  CashPayment? paymentFor(PosOrderIdentity identity) => null;
}
