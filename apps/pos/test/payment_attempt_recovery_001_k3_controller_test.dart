// PAYMENT-ATTEMPT-RECOVERY-001 / K3 follow-up — CONTROLLER-LEVEL regressions.
//
// The K3 suite proves the store, codec and registry contracts in isolation.
// These drive the REAL controller through a `ProviderContainer`, because the
// four behaviours below are properties of the production flow and a unit test
// of the substrate cannot show them:
//
//   A  the production Owner-B incident writer actually runs, and the next
//      confirm is blocked BEFORE any id is allocated;
//   B  a DEGRADED safety state blocks a fresh identity even though no accepted
//      truth is known;
//   C  `settledElsewhere` never reaches the mint — no id, no target, no send;
//   D  rule B publishes a live accepted record, merges its payment and clears
//      the refusal disclosure, and refuses to do any of that for a DIFFERENT
//      decision;
//   E  the generation retry still resolves an untrusted key end to end.
//
// Synthetic local storage and synthetic repository results only. No network, no
// hosted service, no device, no printer, no drawer, no real payment.
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
import 'package:restoflow_pos/src/data/payment_replacement_block.dart';
import 'package:restoflow_pos/src/data/payment_safety.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
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
  replay: false,
  orderStatus: 'completed',
);

/// Lets a test change a provider `PaymentController.build()` WATCHES, which is
/// what opens riverpod's dirty window (see `_goDirty`).
final _storeSwapProvider = StateProvider<PaymentAttemptStore?>((_) => null);

final _orderId = CanonicalOrderId.tryFrom('order-1')!;

/// A DIFFERENT activity key on the same till and the same isolate.
final _otherOrderId = CanonicalOrderId.tryFrom('order-2')!;
PaymentActivityKey get _otherActivityKey =>
    PaymentActivityKey(scope: _scope, orderId: _otherOrderId);

/// Installs an isolate-only fail-closed incident through the SAME production
/// API `_latchAcceptedFailClosed` uses, so a test that asserts about registry
/// commit discipline is exercising the real thing.
void _latchIsolateOnly(PaymentActivityKey key, PaymentAttempt parent) {
  final token = ActivityOwnerToken.issue(key);
  commitSafetyTransition(
    (live) => beginOwner(
      registry: live,
      key: key,
      ownerToken: token,
      binding: ExactAttemptBinding.of(parent),
    ),
  );
  commitSafetyTransition(
    (live) => enterOwnerFailClosed(
      registry: live,
      key: key,
      expectedOwnerToken: token,
      reason: IncidentReason.recordLoss,
    ),
  );
  commitSafetyTransition(
    (live) => installIncidentIfAbsent(
      registry: live,
      key: key,
      incident: PaymentFailClosedIncident(
        key: key,
        occurrence: null,
        operationId: parent.localOperationId,
        binding: ExactAttemptBinding.of(parent),
        serverTruth: acceptedTruthFromSend(_resolution),
        reason: IncidentReason.recordLoss,
        observedAt: '2026-09-09T15:02:00.000Z',
        durability: const IsolateLatchOnly(),
        state: IncidentState.active,
        conflictingDiagnosticEvidence: const <ServerTruth>[],
      ),
    ),
  );
}

String get _logicalKey => paymentAttemptsStorageKey(_scope.key);
PaymentActivityKey get _activityKey =>
    PaymentActivityKey(scope: _scope, orderId: _orderId);

// ---------------------------------------------------------------------------
// Doubles
// ---------------------------------------------------------------------------

class _Ids implements ClientIdGenerator {
  int calls = 0;

  @override
  String newId() => 'id-${++calls}';
}

class _Namespace {
  final Map<String, String> durable = <String, String>{};
}

class _Prefs implements SharedPreferences {
  _Prefs(this.ns);

  final _Namespace ns;
  final Map<String, String> cache = <String, String>{};

  /// Fired on every `getString`, with the running count for that key. Lets a
  /// test change the durable record between two specific reads.
  void Function(String key, int nth)? onGet;
  final Map<String, int> _reads = <String, int>{};

  /// Fired on every `setString`. Returning a future HOLDS the write open at
  /// its await, which is what makes a cross-order race deterministic.
  Future<void>? Function(String key)? onSet;

  @override
  Future<bool> setString(String key, String value) async {
    final hold = onSet?.call(key);
    if (hold != null) await hold;
    cache[key] = value;
    ns.durable[key] = value;
    return true;
  }

  @override
  String? getString(String key) {
    final nth = (_reads[key] ?? 0) + 1;
    _reads[key] = nth;
    onGet?.call(key, nth);
    return cache[key] ?? ns.durable[key];
  }

  @override
  bool containsKey(String key) =>
      cache.containsKey(key) || ns.durable.containsKey(key);

  @override
  Set<String> getKeys() => <String>{...cache.keys, ...ns.durable.keys};

  @override
  Future<bool> remove(String key) async {
    cache.remove(key);
    ns.durable.remove(key);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnsupportedError('unused: ${i.memberName}');
}

class _Reader implements PaymentAttemptBackingReader {
  _Reader(this.ns);

  final _Namespace ns;

  @override
  Future<String?> readRaw(String physicalKey) async =>
      ns.durable[physicalKey.substring(
        kLegacySharedPreferencesKeyPrefix.length,
      )];
}

/// Sends whatever the test scripts, and records every operation id it saw.
class _Repo implements PaymentRepository, PaymentAttemptSender {
  _Repo(this.results);

  /// One entry per send, in order. A `Future` so a test can hold a send open.
  final List<Future<PaymentSendResult> Function(PaymentAttempt)> results;
  final List<String> operationIds = <String>[];

  @override
  Future<PaymentSendResult> sendAttempt(PaymentAttempt attempt) {
    operationIds.add(attempt.localOperationId);
    final i = operationIds.length - 1;
    if (i >= results.length) {
      return Future<PaymentSendResult>.value(
        const PaymentSendAccepted(_resolution),
      );
    }
    return results[i](attempt);
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
  dynamic noSuchMethod(Invocation i) =>
      throw UnsupportedError('unused: ${i.memberName}');
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

typedef _World = ({
  ProviderContainer container,
  PaymentController controller,
  _Repo repo,
  _Ids ids,
  _Namespace ns,
  _Prefs prefs,
  SharedPrefsPaymentAttemptStore store,
});

Future<_World> _world(
  List<Future<PaymentSendResult> Function(PaymentAttempt)> results, {
  _Namespace? namespace,
  bool withReader = true,
}) async {
  final ns = namespace ?? _Namespace();
  final prefs = _Prefs(ns);
  final store = SharedPrefsPaymentAttemptStore(
    prefs,
    backingReader: withReader ? _Reader(ns) : null,
  );
  final repo = _Repo(results);
  final ids = _Ids();
  final container = ProviderContainer(
    overrides: <Override>[
      paymentRepositoryProvider.overrideWithValue(repo),
      paymentAttemptStoreProvider.overrideWith(
        (ref) => ref.watch(_storeSwapProvider) ?? store,
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
  final controller = container.read(paymentControllerProvider.notifier);
  await controller.ensureHydrated();
  return (
    container: container,
    controller: controller,
    repo: repo,
    ids: ids,
    ns: ns,
    prefs: prefs,
    store: store,
  );
}

Future<PaymentAttemptOutcome> _confirm(PaymentController c) => c.submitAttempt(
  identity: PosOrderIdentity.server(_orderId.value),
  orderId: _orderId.value,
  orderNumber: '#R-1',
  amountMinor: 4000,
  tenderedMinor: 5000,
  currencyCode: 'ILS',
  expectedRevision: 7,
);

void _seed(_Namespace ns, List<Object?> entries) {
  ns.durable[_logicalKey] = jsonEncode(<String, Object?>{
    'version': PaymentAttempt.schemaVersion,
    'attempts': entries,
  });
}

PaymentAttempt _mint(String op) => PaymentAttempt.mint(
  ids: FixedClientIdGenerator(<String>[op, '$op-target']),
  now: DateTime.utc(2026, 9, 9, 15),
  orderId: _orderId.value,
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

/// Rebuilds the controller IN PLACE, so a `submitAttempt` already in flight
/// finds its frozen generation stale — the production "the provider was rebuilt
/// mid-payment" race.
///
/// `PaymentController.build()` does `ref.watch(...)` and `++_generation`, and
/// riverpod 2.6.1 keeps the SAME `Notifier` instance across rebuilds
/// (`NotifierProviderElement.create` does `_notifierNotifier.result ??= ...`;
/// only `StateNotifierProvider` and `StateProvider` null theirs). So a refresh
/// re-runs `build()` on the very instance the in-flight call is running on.
///
/// MEASURED, NOT ASSUMED. `container.invalidate(provider)` alone does NOT
/// rebuild — it only marks the element dirty, and nothing flushes it before the
/// send resumes, so a test written that way is silently NOT stale and passes
/// vacuously. Both assertions below exist to make that impossible.
void _goStale(_World w) {
  final before = w.controller.generationForTest;
  final refreshed = w.container.refresh(paymentControllerProvider.notifier);
  expect(
    identical(refreshed, w.controller),
    isTrue,
    reason: 'the in-flight call must be running on THIS notifier instance',
  );
  expect(
    w.controller.generationForTest,
    greaterThan(before),
    reason: 'the generation must REALLY have moved, or the race is fake',
  );
}

/// A record carrying the operation id the controller will mint (`_Ids` hands out
/// `id-1`, `id-2`, ...) but describing a DIFFERENT decision.
PaymentAttempt _otherDecisionUnderSameOperation({required int amountMinor}) =>
    PaymentAttempt.mint(
      ids: FixedClientIdGenerator(<String>['id-1', 'id-1-target']),
      now: DateTime.utc(2026, 9, 9, 15),
      orderId: _orderId.value,
      orderNumber: '#R-1',
      amountMinor: amountMinor,
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

Future<PaymentSendResult> Function(PaymentAttempt) _accepted() =>
    (_) async => const PaymentSendAccepted(_resolution);

Future<PaymentSendResult> Function(PaymentAttempt) _refused({
  bool memoized = true,
}) =>
    (_) async => PaymentSendRefused(
      PaymentRefusalCode.shiftRequired,
      memoized: memoized,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetPaymentAttemptKeyGuardsForTest();
    resetPaymentSafetyRegistryForTest();
  });

  // =========================================================================
  // A — the PRODUCTION Owner-B incident writer
  // =========================================================================
  test('A the controller INSTALLS an Owner-B incident when an accepted server '
      'truth contradicts this device s stored refusal, and the next confirm is '
      'blocked BEFORE any id is allocated', () async {
    final hold = Completer<PaymentSendResult>();
    final w = await _world(<Future<PaymentSendResult> Function(PaymentAttempt)>[
      (_) => hold.future,
    ]);

    // The confirm is in flight; the record is PENDING on disk.
    final inFlight = _confirm(w.controller);
    await pumpEventQueue();
    final sent = w
        .controller
        .state
        .attempts[PosOrderIdentity.server(_orderId.value).key]!;
    expect(sent.phase, PaymentAttemptPhase.pending);

    // ANOTHER writer records a terminal REFUSAL for this very operation while
    // the send is outstanding. This is the contradiction Owner Option B exists
    // for: the server is about to say APPLIED.
    _seed(w.ns, <Object?>[
      sent
          .refused(
            PaymentRefusalCode.shiftRequired,
            at: '2026-09-09T15:01:00.000Z',
            memoized: true,
          )
          .toJson(),
    ]);
    w.prefs.cache.remove(_logicalKey); // the writer must re-read from backing

    hold.complete(const PaymentSendAccepted(_resolution));
    final outcome = await inFlight;

    // The money truth is preserved: accepted-class, honestly unproven locally.
    expect(outcome, isA<PaymentAttemptAccepted>());
    expect((outcome as PaymentAttemptAccepted).localSaveFailed, isTrue);
    expect(outcome.automaticEffectsArmed, isFalse);
    expect(moneyTruthOf(outcome), MoneyTruthView.movedUnproven);

    // THE POINT: a real incident now stands in the PRODUCTION registry.
    final incident = paymentSafetyRegistry().incidentOf(_activityKey);
    expect(incident, isNotNull, reason: 'the production writer must have run');
    expect(incident!.state, IncidentState.active);
    expect(incident.operationId, sent.localOperationId);
    expect(incident.acceptedTruth, isNotNull);
    expect(incident.acceptedTruth!.resolution.paymentId, _resolution.paymentId);
    expect(incident.reason, IncidentReason.ownerBContradiction);
    expect(incident.binding, ExactAttemptBinding.of(sent));
    final owner = paymentSafetyRegistry().ownerOf(_activityKey);
    expect(owner, isNotNull);
    expect(owner!.handoff.isFailClosed, isTrue);
    expect(owner.safetyEpoch, greaterThan(0), reason: 'the epoch moved');

    // Confirming again on THIS controller short-circuits at the accepted arm:
    // the order is settled from this device s point of view, so there is
    // nothing to send and no identity to allocate.
    final idsAfterFirst = w.ids.calls;
    final sendsAfterFirst = w.repo.operationIds.length;
    final immediate = await _confirm(w.controller);
    expect(immediate, isA<PaymentAttemptAccepted>());
    expect(w.ids.calls, idsAfterFirst, reason: 'no second identity');
    expect(w.repo.operationIds.length, sendsAfterFirst, reason: 'nothing sent');

    // THE PRODUCTION PATH THE GATE EXISTS FOR. The acceptance never reached
    // disk, so a rebuilt controller (sheet reopened, provider rebound, app
    // resumed) hydrates the REFUSED record and would otherwise mint a linked
    // correction for money that already moved. The incident is isolate-scoped
    // and outlives the container, which is exactly why it can stop this.
    final rebuilt = await _world(
      <Future<PaymentSendResult> Function(PaymentAttempt)>[_accepted()],
      namespace: w.ns,
    );
    expect(
      rebuilt
          .controller
          .state
          .attempts[PosOrderIdentity.server(_orderId.value).key]
          ?.phase,
      PaymentAttemptPhase.refused,
      reason: 'disk still holds the refusal',
    );

    final blocked = await _confirm(rebuilt.controller);

    // THE MONEY TRUTH SURVIVES THE BLOCK. The evidence that refuses the mint is
    // an accepted-class server truth, so the public answer is accepted-class -
    // never `Unconfirmed(identityCollision)`, which documents a DIFFERENT
    // operation under our key and offers Check-status and Resume, both inert
    // for a record that is already terminal.
    expect(blocked, isA<PaymentAttemptAccepted>());
    final acceptedBlock = blocked as PaymentAttemptAccepted;
    expect(acceptedBlock.payment.paymentId, _resolution.paymentId);
    expect(acceptedBlock.payment.receiptNumber, _resolution.receiptNumber);
    expect(
      acceptedBlock.localSaveFailed,
      isTrue,
      reason: 'this device s durable record is NOT the proof',
    );
    expect(
      acceptedBlock.automaticEffectsArmed,
      isFalse,
      reason: 'a refusal to mint is never a payment edge',
    );
    expect(moneyTruthOf(blocked), MoneyTruthView.movedUnproven);

    // AND NO SECOND IDENTITY.
    expect(
      rebuilt.ids.calls,
      0,
      reason: 'NO new local_operation_id and NO provisional target',
    );
    expect(rebuilt.repo.operationIds, isEmpty, reason: 'nothing was sent');
    expect(eligibilityOf(blocked), NewIdentityEligibility.forbidden);
  });

  test('A2 the contradiction is PROMOTED to a durable ACTIVE block, so the '
      'containment survives a process restart', () async {
    final hold = Completer<PaymentSendResult>();
    final w = await _world(<Future<PaymentSendResult> Function(PaymentAttempt)>[
      (_) => hold.future,
    ]);

    final inFlight = _confirm(w.controller);
    await pumpEventQueue();
    final key = PosOrderIdentity.server(_orderId.value).key;
    final sent = w.controller.state.attempts[key]!;
    _seed(w.ns, <Object?>[
      sent
          .refused(
            PaymentRefusalCode.shiftRequired,
            at: '2026-09-09T15:01:00.000Z',
            memoized: true,
          )
          .toJson(),
    ]);
    w.prefs.cache.remove(_logicalKey);
    hold.complete(const PaymentSendAccepted(_resolution));
    await inFlight;

    // ON DISK: an ACTIVE replacement_block now sits on the contradicted parent.
    final entries =
        (jsonDecode(w.ns.durable[_logicalKey]!) as Map)['attempts'] as List;
    expect(entries, hasLength(1));
    final stored = PaymentAttempt.fromJson(
      paymentAttemptProjection(entries.single),
    );
    expect(stored.phase, PaymentAttemptPhase.refused);
    final field = decodeReplacementBlockField(
      entries.single,
      PaymentAttemptParentFacts.of(stored),
    );
    expect(field, isA<BlockDecoded>());
    final block = (field as BlockDecoded).block;
    expect(block.status, BlockStatus.active);
    expect(block.serverTruth, isA<AcceptedTruth>());
    expect(
      (block.serverTruth as AcceptedTruth).resolution.paymentId,
      _resolution.paymentId,
    );
    expect(block.reason, IncidentReason.ownerBContradiction);

    // The isolate incident is now DURABLE, not a latch.
    expect(
      paymentSafetyRegistry().incidentOf(_activityKey)!.durability,
      isA<DurableRecordBlock>(),
    );

    // SIMULATED PROCESS RESTART: every scrap of isolate state is discarded.
    // Only the persisted envelope survives, which is exactly what a real
    // restart leaves behind.
    resetPaymentSafetyRegistryForTest();
    resetPaymentAttemptKeyGuardsForTest();
    expect(paymentSafetyRegistry().incidentOf(_activityKey), isNull);

    final restarted = await _world(
      <Future<PaymentSendResult> Function(PaymentAttempt)>[_accepted()],
      namespace: w.ns,
    );
    final blocked = await _confirm(restarted.controller);

    expect(
      restarted.ids.calls,
      0,
      reason: 'blocked BEFORE any operation or target id',
    );
    expect(restarted.repo.operationIds, isEmpty, reason: 'nothing sent');
    expect(
      blocked,
      isA<PaymentAttemptAccepted>(),
      reason: 'the block carries accepted-class truth; it is not erased',
    );
    expect((blocked as PaymentAttemptAccepted).localSaveFailed, isTrue);
    expect(blocked.automaticEffectsArmed, isFalse);
    expect(moneyTruthOf(blocked), MoneyTruthView.movedUnproven);
    expect(eligibilityOf(blocked), NewIdentityEligibility.forbidden);
  });

  test('A3 safety evidence installed by an in-flight resolve SURVIVES a later '
      'controller rebuild, and the rebuilt world is still blocked', () async {
    final hold = Completer<PaymentSendResult>();
    final w = await _world(<Future<PaymentSendResult> Function(PaymentAttempt)>[
      (_) => hold.future,
    ]);

    final inFlight = _confirm(w.controller);
    await pumpEventQueue();
    final key = PosOrderIdentity.server(_orderId.value).key;
    final sent = w.controller.state.attempts[key]!;
    _seed(w.ns, <Object?>[
      sent
          .refused(
            PaymentRefusalCode.shiftRequired,
            at: '2026-09-09T15:01:00.000Z',
            memoized: true,
          )
          .toJson(),
    ]);
    w.prefs.cache.remove(_logicalKey);

    // HONEST TIMING. `pumpEventQueue` drains the whole post-send continuation
    // — it is microtask-only, with no timer or external wait — so by the time
    // `_goStale` runs below, the incident is already installed and promoted.
    // This test therefore proves that evidence SURVIVES a later rebuild and
    // that the rebuilt world is still blocked; it does NOT exercise a rebuild
    // landing mid-install.
    //
    // An earlier version of this test claimed the mid-install property, which
    // it never had. That property is covered deterministically by T3, which
    // rebuilds inside `debugPaymentSafetyCommitBarrier`, and by R-A1..R-A4,
    // which go stale BEFORE the reply lands.
    //
    // The lever is `refresh`, not `invalidate`: an earlier draft used
    // `container.invalidate(paymentControllerProvider)`, which only marks the
    // element dirty. Nothing flushed it before the send resumed, so the
    // generation never moved and the test asserted against a controller that
    // was never stale. `_goStale` now proves the move.
    hold.complete(const PaymentSendAccepted(_resolution));
    await pumpEventQueue();
    _goStale(w);
    final outcome = await inFlight;

    // The caller is still told the truth about its own money.
    expect(outcome, isA<PaymentAttemptAccepted>());

    // AND the evidence survived the rebuild: an earlier draft gated the install
    // on the controller generation and dropped it here.
    final incident = paymentSafetyRegistry().incidentOf(_activityKey);
    expect(
      incident,
      isNotNull,
      reason: 'controller generation is not authority over money evidence',
    );
    expect(incident!.state, IncidentState.active);
    expect(incident.acceptedTruth, isNotNull);

    // A fresh controller over the same disk is blocked before any id.
    final fresh = await _world(
      <Future<PaymentSendResult> Function(PaymentAttempt)>[_accepted()],
      namespace: w.ns,
    );
    await _confirm(fresh.controller);
    expect(fresh.ids.calls, 0);
    expect(fresh.repo.operationIds, isEmpty);
  });

  test('A4 the NO-IN-MEMORY-ATTEMPT route also passes the pre-mint gate', () async {
    // The gate used to live inside the `refused` arm, so any route reaching
    // `PaymentAttempt.mint` with `state.attempts[key] == null` was ungated.
    //
    // This is a REAL production route, not a contrivance: `submitAttempt` takes
    // `identity` and `orderId` as INDEPENDENT arguments. The in-memory map is
    // keyed by the caller s `identity.key`, while the durable envelope is keyed
    // by the ORDER. A caller that has no authoritative server identity in hand
    // (a legacy display-code row) therefore looks up a key the map does not
    // hold - while the envelope still carries an ACTIVE replacement block for
    // that very order.
    final ns = _Namespace();
    final parent = _mint('op-gate')
        .markSent('2026-09-09T15:00:00.000Z')
        .refused(
          PaymentRefusalCode.shiftRequired,
          at: '2026-09-09T15:01:00.000Z',
          memoized: true,
        );
    final block = PaymentReplacementBlock(
      generation: 1,
      blockId: 'block-gate',
      status: BlockStatus.active,
      contradictedOperationId: parent.localOperationId,
      contradictedPhase: parent.phase,
      reason: IncidentReason.ownerBContradiction,
      evidenceSource: BlockEvidenceSource.directSend,
      observedAt: '2026-09-09T15:02:00.000Z',
      serverTruth: acceptedTruthFromSend(_resolution),
      resolution: null,
    );
    _seed(ns, <Object?>[
      <String, Object?>{
        ...parent.toJson(),
        kReplacementBlockKey: block.toJson(),
      },
    ]);

    final w = await _world(<Future<PaymentSendResult> Function(PaymentAttempt)>[
      _accepted(),
    ], namespace: ns);

    // A legacy display-code identity: `num:#R-1`, which the attempts map -
    // keyed by the derived `srv:order-1` - does not hold.
    final legacy = PosOrderIdentity.legacyDisplayCode('#R-1');
    expect(w.controller.state.attempts[legacy.key], isNull);
    expect(
      w.controller.state.attempts[PosOrderIdentity.server(_orderId.value).key],
      isNotNull,
      reason: 'the record IS loaded - under a different key',
    );

    final outcome = await w.controller.submitAttempt(
      identity: legacy,
      orderId: _orderId.value,
      orderNumber: '#R-1',
      amountMinor: 4000,
      tenderedMinor: 5000,
      currencyCode: 'ILS',
      expectedRevision: 7,
    );

    expect(
      w.ids.calls,
      0,
      reason: 'the gate runs even with no in-memory attempt for this key',
    );
    expect(w.repo.operationIds, isEmpty, reason: 'nothing was sent');
    expect(outcome, isA<PaymentAttemptAccepted>());
    expect((outcome as PaymentAttemptAccepted).localSaveFailed, isTrue);
    expect(moneyTruthOf(outcome), MoneyTruthView.movedUnproven);
  });

  test('A5 a healthy virgin snapshot still mints normally', () async {
    final w = await _world(<Future<PaymentSendResult> Function(PaymentAttempt)>[
      _accepted(),
    ]);
    final outcome = await _confirm(w.controller);
    expect(outcome, isA<PaymentAttemptAccepted>());
    expect(w.ids.calls, greaterThan(0), reason: 'a clean order still mints');
    expect(w.repo.operationIds, hasLength(1));
    expect(moneyTruthOf(outcome), MoneyTruthView.moved);
  });

  // =========================================================================
  // R-A — OD-2: A STALE CONTROLLER GENERATION MUST NOT DISCARD EXACT ACCEPTED
  // MONEY-SAFETY EVIDENCE.
  //
  // The blocker these close: the `PaymentSendAccepted` arm used to return on
  // `!_stillAuthoritative(gen)` BEFORE the store was consulted at all. On that
  // path a durable terminal REFUSAL contradicting the acceptance was never
  // discovered, nothing durable recorded it, and the rebuilt controller then
  // hydrated "clear" and minted a SECOND identity for money that had moved.
  //
  // Every test here asserts, via `_goStale`, that the generation really moved.
  // =========================================================================

  test('R-A1 a STALE generation still INSTALLS and PROMOTES the contradiction, '
      'claims nothing, and the rebuilt world is blocked before any id', () async {
    final hold = Completer<PaymentSendResult>();
    final w = await _world(<Future<PaymentSendResult> Function(PaymentAttempt)>[
      (_) => hold.future,
    ]);

    final inFlight = _confirm(w.controller);
    await pumpEventQueue();
    final key = PosOrderIdentity.server(_orderId.value).key;
    final sent = w.controller.state.attempts[key]!;

    // The durable record becomes a TERMINAL REFUSAL for this same decision
    // while the send is in flight: the replacement-risk contradiction.
    _seed(w.ns, <Object?>[
      sent
          .refused(
            PaymentRefusalCode.shiftRequired,
            at: '2026-09-09T15:01:00.000Z',
            memoized: true,
          )
          .toJson(),
    ]);
    w.prefs.cache.remove(_logicalKey);

    // THE RACE: the provider is rebuilt BEFORE the accepted reply lands, so the
    // old controller is already stale when it resolves.
    _goStale(w);
    hold.complete(const PaymentSendAccepted(_resolution));
    final outcome = await inFlight;
    await w.controller.ensureHydrated();

    // --- the stale controller still told the truth about the money ---------
    expect(outcome, isA<PaymentAttemptAccepted>());
    final accepted = outcome as PaymentAttemptAccepted;
    expect(accepted.payment.paymentId, _resolution.paymentId);
    expect(accepted.automaticEffectsArmed, isFalse);
    expect(accepted.localSaveFailed, isTrue);

    // --- and mutated NOTHING in the current world --------------------------
    expect(
      w.controller.state.payments[key],
      isNull,
      reason: 'no session merge from a replaced controller',
    );
    expect(
      w.controller.state.effectsArmed,
      isNot(contains(key)),
      reason: 'no automatic-effect reservation claimed',
    );
    expect(
      w.controller.state.attempts[key]?.phase,
      isNot(PaymentAttemptPhase.accepted),
      reason: 'no stale controller state publication',
    );
    expect(
      w.controller.state.attempts[key]?.autoEffectsReservedAt,
      isNull,
      reason: 'the one-time effect reservation was never taken',
    );

    // --- but the SAFETY EVIDENCE was installed AND promoted ----------------
    final incident = paymentSafetyRegistry().incidentOf(_activityKey);
    expect(incident, isNotNull, reason: 'OD-2: evidence is not discarded');
    expect(incident!.state, IncidentState.active);
    expect(incident.reason, IncidentReason.ownerBContradiction);
    expect(incident.acceptedTruth, isNotNull);
    expect(
      incident.durability,
      isA<DurableRecordBlock>(),
      reason: 'OD-2 requires the durable promotion, not only an isolate latch',
    );

    final entries =
        (jsonDecode(w.ns.durable[_logicalKey]!) as Map)['attempts'] as List;
    expect(entries, hasLength(1));
    final stored = PaymentAttempt.fromJson(
      paymentAttemptProjection(entries.single),
    );
    expect(stored.phase, PaymentAttemptPhase.refused);
    final field = decodeReplacementBlockField(
      entries.single,
      PaymentAttemptParentFacts.of(stored),
    );
    expect(field, isA<BlockDecoded>());
    final block = (field as BlockDecoded).block;
    expect(block.status, BlockStatus.active);
    expect(block.reason, IncidentReason.ownerBContradiction);
    expect(
      (block.serverTruth as AcceptedTruth).resolution.paymentId,
      _resolution.paymentId,
    );

    // --- SIMULATED PROCESS RESTART: only the disk survives ------------------
    resetPaymentSafetyRegistryForTest();
    resetPaymentAttemptKeyGuardsForTest();
    expect(paymentSafetyRegistry().incidentOf(_activityKey), isNull);

    final restarted = await _world(
      <Future<PaymentSendResult> Function(PaymentAttempt)>[_accepted()],
      namespace: w.ns,
    );
    final blocked = await _confirm(restarted.controller);

    expect(
      restarted.ids.calls,
      0,
      reason: 'blocked BEFORE any operation or target id',
    );
    expect(restarted.repo.operationIds, isEmpty, reason: 'nothing sent');
    expect(blocked, isA<PaymentAttemptAccepted>());
    expect((blocked as PaymentAttemptAccepted).localSaveFailed, isTrue);
    expect(blocked.automaticEffectsArmed, isFalse);
    expect(moneyTruthOf(blocked), MoneyTruthView.movedUnproven);
    expect(eligibilityOf(blocked), NewIdentityEligibility.forbidden);
  });

  test('R-A2 a STALE generation never installs accepted truth against ANOTHER '
      'decision, and never publishes that decision s payment', () async {
    final hold = Completer<PaymentSendResult>();
    final w = await _world(<Future<PaymentSendResult> Function(PaymentAttempt)>[
      (_) => hold.future,
    ]);

    final inFlight = _confirm(w.controller);
    await pumpEventQueue();
    final key = PosOrderIdentity.server(_orderId.value).key;

    // Same operation id on disk, a DIFFERENT decision: another amount. Exact
    // selection still finds it — the selector matches on the operation id —
    // so the 17-field binding check is the ONLY thing standing between this
    // accepted truth and the wrong record.
    _seed(w.ns, <Object?>[
      _otherDecisionUnderSameOperation(amountMinor: 9999)
          .markSent('2026-09-09T15:00:30.000Z')
          .refused(
            PaymentRefusalCode.shiftRequired,
            at: '2026-09-09T15:01:00.000Z',
            memoized: true,
          )
          .toJson(),
    ]);
    w.prefs.cache.remove(_logicalKey);

    _goStale(w);
    hold.complete(const PaymentSendAccepted(_resolution));
    await inFlight;
    await w.controller.ensureHydrated();

    expect(
      paymentSafetyRegistry().incidentOf(_activityKey),
      isNull,
      reason: 'this truth is never bound to a decision that is not ours',
    );
    final entries =
        (jsonDecode(w.ns.durable[_logicalKey]!) as Map)['attempts'] as List;
    expect(
      paymentAttemptRawBlock(entries.single),
      isNull,
      reason: 'no block is written onto another decision',
    );
    expect(
      w.controller.state.payments[key],
      isNull,
      reason: 'the other decision s payment is never published or merged',
    );
    expect(w.controller.state.effectsArmed, isNot(contains(key)));
  });

  test('R-A3 a STALE generation over an ALREADY ACCEPTED durable record raises '
      'no incident and re-arms nothing', () async {
    final hold = Completer<PaymentSendResult>();
    final w = await _world(<Future<PaymentSendResult> Function(PaymentAttempt)>[
      (_) => hold.future,
    ]);

    final inFlight = _confirm(w.controller);
    await pumpEventQueue();
    final key = PosOrderIdentity.server(_orderId.value).key;
    final sent = w.controller.state.attempts[key]!;

    // The acceptance is ALREADY durable — another writer got there first.
    _seed(w.ns, <Object?>[
      sent
          .accepted(
            _resolution,
            at: '2026-09-09T15:00:30.000Z',
            reserveEffects: true,
          )
          .toJson(),
    ]);
    w.prefs.cache.remove(_logicalKey);

    _goStale(w);
    hold.complete(const PaymentSendAccepted(_resolution));
    final outcome = await inFlight;
    await w.controller.ensureHydrated();

    expect(
      paymentSafetyRegistry().incidentOf(_activityKey),
      isNull,
      reason:
          'an accepted parent is not replacement-eligible; class A is a '
          'no-op and must not fail-close a settled order',
    );
    final entries =
        (jsonDecode(w.ns.durable[_logicalKey]!) as Map)['attempts'] as List;
    expect(entries, hasLength(1));
    expect(paymentAttemptRawBlock(entries.single), isNull);

    expect((outcome as PaymentAttemptAccepted).automaticEffectsArmed, isFalse);
    expect(
      w.controller.state.effectsArmed,
      isNot(contains(key)),
      reason:
          'the stale controller re-armed nothing; the reservation on disk '
          'was spent by whoever actually wrote it',
    );
  });

  test(
    'R-A4 a STALE generation whose record is GONE latches the isolate, '
    'fabricates no durable parent, and is NOT certified across a restart',
    () async {
      for (final wipe in <String>['empty', 'absent']) {
        resetPaymentAttemptKeyGuardsForTest();
        resetPaymentSafetyRegistryForTest();

        final hold = Completer<PaymentSendResult>();
        final w = await _world(
          <Future<PaymentSendResult> Function(PaymentAttempt)>[
            (_) => hold.future,
          ],
        );
        final inFlight = _confirm(w.controller);
        await pumpEventQueue();

        // The record this device wrote before sending is gone. `empty` leaves a
        // canonical envelope with no entries; `absent` removes the key entirely,
        // which is the ONE unreadable-looking snapshot the pre-mint gate does not
        // fail closed on by itself — a PROVEN absence, so a virgin order can still
        // be paid. Both must be latched here, or the money is forgotten.
        if (wipe == 'empty') {
          _seed(w.ns, <Object?>[]);
        } else {
          w.ns.durable.remove(_logicalKey);
        }
        w.prefs.cache.remove(_logicalKey);

        _goStale(w);
        hold.complete(const PaymentSendAccepted(_resolution));
        await inFlight;

        final incident = paymentSafetyRegistry().incidentOf(_activityKey);
        expect(incident, isNotNull, reason: '$wipe: money moved, record lost');
        expect(incident!.reason, IncidentReason.recordLoss);
        expect(incident.state, IncidentState.active);
        expect(incident.acceptedTruth, isNotNull);
        expect(
          incident.durability,
          isA<IsolateLatchOnly>(),
          reason: '$wipe: no durable parent exists, so none is fabricated',
        );
        expect(incident.occurrence, isNull);

        // SAME ISOLATE: a fresh controller over the same disk is blocked.
        final same = await _world(
          <Future<PaymentSendResult> Function(PaymentAttempt)>[_accepted()],
          namespace: w.ns,
        );
        await _confirm(same.controller);
        expect(same.ids.calls, 0, reason: '$wipe: no new identity in-isolate');
        expect(same.repo.operationIds, isEmpty);

        // PROCESS RESTART: the latch is isolate-only, so containment is
        // explicitly NOT CERTIFIED here. Recorded as behaviour, not hidden.
        resetPaymentSafetyRegistryForTest();
        resetPaymentAttemptKeyGuardsForTest();
        final restarted = await _world(
          <Future<PaymentSendResult> Function(PaymentAttempt)>[_accepted()],
          namespace: w.ns,
        );
        await _confirm(restarted.controller);
        expect(
          restarted.ids.calls,
          greaterThan(0),
          reason:
              '$wipe: a latch-only incident does NOT survive a restart — '
              'this is the documented residual, asserted so it cannot drift '
              'silently into a false durability claim',
        );
      }
    },
  );

  test('R-A5 CONTROL: the CURRENT generation accepted path is unchanged — it '
      'persists, merges and arms exactly as before', () async {
    final w = await _world(<Future<PaymentSendResult> Function(PaymentAttempt)>[
      _accepted(),
    ]);
    final key = PosOrderIdentity.server(_orderId.value).key;
    final genBefore = w.controller.generationForTest;

    final outcome = await _confirm(w.controller);

    expect(
      w.controller.generationForTest,
      genBefore,
      reason: 'the control must NOT be stale',
    );
    expect(outcome, isA<PaymentAttemptAccepted>());
    final accepted = outcome as PaymentAttemptAccepted;
    expect(accepted.localSaveFailed, isFalse, reason: 'it really was saved');
    expect(
      accepted.automaticEffectsArmed,
      isTrue,
      reason: 'effects armed once',
    );
    expect(w.controller.state.payments[key], isNotNull, reason: 'merged');
    expect(w.controller.state.effectsArmed, contains(key));
    expect(
      w.controller.state.attempts[key]!.phase,
      PaymentAttemptPhase.accepted,
    );
    expect(
      w.controller.state.attempts[key]!.autoEffectsReservedAt,
      isNotNull,
      reason: 'the durable one-time reservation was taken',
    );
    expect(w.repo.operationIds, hasLength(1));
    expect(moneyTruthOf(outcome), MoneyTruthView.moved);

    // And no safety evidence was invented for a perfectly ordinary payment.
    expect(paymentSafetyRegistry().incidentOf(_activityKey), isNull);
    final entries =
        (jsonDecode(w.ns.durable[_logicalKey]!) as Map)['attempts'] as List;
    expect(paymentAttemptRawBlock(entries.single), isNull);
  });

  test('T2 / R-A6 a DISPOSED controller still contains the contradiction, and '
      'claims nothing', () async {
    // REPLACES a vacuous predecessor. That test tried to reach riverpod's dirty
    // window by swapping a StateProvider the store override watched, but that
    // marks the OVERRIDE element dirty, not the controller element: the
    // controller only receives `_dependencyMayHaveChanged`, which does not trip
    // the guard. The proof is the test itself — had the controller really been
    // in that window, `_resolve`'s first statement would have thrown before any
    // containment and its own assertions would have failed.
    //
    // Disposal is the honest, deterministic form of the same hazard, and it is
    // the one that reaches RELEASE builds: riverpod's dirty-window guard is an
    // `assert`, but using `ref` on a disposed container is a `StateError` in
    // every mode.
    final hold = Completer<PaymentSendResult>();
    final w = await _world(<Future<PaymentSendResult> Function(PaymentAttempt)>[
      (_) => hold.future,
    ]);

    final inFlight = _confirm(w.controller);
    await pumpEventQueue();
    final key = PosOrderIdentity.server(_orderId.value).key;
    final sent = w.controller.state.attempts[key]!;
    _seed(w.ns, <Object?>[
      sent
          .refused(
            PaymentRefusalCode.shiftRequired,
            at: '2026-09-09T15:01:00.000Z',
            memoized: true,
          )
          .toJson(),
    ]);
    w.prefs.cache.remove(_logicalKey);

    // THE CONTROLLER'S WHOLE WORLD GOES AWAY while the send is in flight.
    w.container.dispose();
    hold.complete(const PaymentSendAccepted(_resolution));

    // The old implementation read `ref` on `_resolve`'s first line, so this
    // threw before a single line of containment ran. The outcome itself is not
    // what is under test — the container is gone, so there is nobody left to
    // show it to — but the containment is.
    try {
      await inFlight;
    } catch (_) {}

    final incident = paymentSafetyRegistry().incidentOf(_activityKey);
    expect(
      incident,
      isNotNull,
      reason: 'a disposed container must not erase accepted money evidence',
    );
    expect(incident!.state, IncidentState.active);
    expect(incident.reason, IncidentReason.ownerBContradiction);
    expect(incident.acceptedTruth, isNotNull);
    expect(
      incident.durability,
      isA<DurableRecordBlock>(),
      reason: 'the frozen clock and id source let the promotion run too',
    );

    final entries =
        (jsonDecode(w.ns.durable[_logicalKey]!) as Map)['attempts'] as List;
    final stored = PaymentAttempt.fromJson(
      paymentAttemptProjection(entries.single),
    );
    final field = decodeReplacementBlockField(
      entries.single,
      PaymentAttemptParentFacts.of(stored),
    );
    expect(field, isA<BlockDecoded>());
    expect((field as BlockDecoded).block.status, BlockStatus.active);

    // No effects, no session state, from a controller whose world is gone.
    expect(w.controller.state.payments[key], isNull);
    expect(w.controller.state.effectsArmed, isNot(contains(key)));

    // And a fresh world over the same disk is blocked before any id.
    resetPaymentSafetyRegistryForTest();
    resetPaymentAttemptKeyGuardsForTest();
    final restarted = await _world(
      <Future<PaymentSendResult> Function(PaymentAttempt)>[_accepted()],
      namespace: w.ns,
    );
    await _confirm(restarted.controller);
    expect(restarted.ids.calls, 0);
    expect(restarted.repo.operationIds, isEmpty);
  });

  test('T1 a promotion held at its durable write must not erase ANOTHER '
      'order s isolate-only containment', () async {
    // B1. The promotion samples the whole registry BEFORE its await and used to
    // install that value afterwards, so any key committed inside the window was
    // deleted. The classes that latch WITHOUT promoting have no second write to
    // restore them, so for those orders the erasure was permanent.
    final hold = Completer<PaymentSendResult>();
    final w = await _world(<Future<PaymentSendResult> Function(PaymentAttempt)>[
      (_) => hold.future,
    ]);

    final inFlight = _confirm(w.controller);
    await pumpEventQueue();
    final key = PosOrderIdentity.server(_orderId.value).key;
    final sent = w.controller.state.attempts[key]!;
    _seed(w.ns, <Object?>[
      sent
          .refused(
            PaymentRefusalCode.shiftRequired,
            at: '2026-09-09T15:01:00.000Z',
            memoized: true,
          )
          .toJson(),
    ]);
    w.prefs.cache.remove(_logicalKey);

    // Hold order A's DURABLE PROMOTION open at its write, and commit order B's
    // isolate-only incident inside that window.
    final atWrite = Completer<void>();
    final release = Completer<void>();
    w.prefs.onSet = (k) {
      if (k != _logicalKey) return null;
      w.prefs.onSet = null; // the promotion write only
      if (!atWrite.isCompleted) atWrite.complete();
      return release.future;
    };

    hold.complete(const PaymentSendAccepted(_resolution));
    await atWrite.future;

    expect(
      paymentSafetyRegistry().incidentOf(_activityKey),
      isNotNull,
      reason: 'A has already latched before it tries to promote',
    );
    _latchIsolateOnly(_otherActivityKey, _mint('op-other'));
    expect(paymentSafetyRegistry().incidentOf(_otherActivityKey), isNotNull);

    release.complete();
    await inFlight;

    // A promoted...
    final a = paymentSafetyRegistry().incidentOf(_activityKey);
    expect(a, isNotNull);
    expect(a!.durability, isA<DurableRecordBlock>());

    // ...AND B survived. This is the assertion the whole-map commit failed.
    final b = paymentSafetyRegistry().incidentOf(_otherActivityKey);
    expect(
      b,
      isNotNull,
      reason:
          'a key-scoped commit may never publish a stale view of another '
          'order; B had no durable block to fall back on',
    );
    expect(b!.state, IncidentState.active);
    expect(b.durability, isA<IsolateLatchOnly>());
    expect(
      paymentSafetyRegistry().ownerOf(_otherActivityKey)?.handoff.isFailClosed,
      isTrue,
    );

    // And order B is still blocked before any id.
    final beforeIds = w.ids.calls;
    final beforeSends = w.repo.operationIds.length;
    final blocked = await w.controller.submitAttempt(
      identity: PosOrderIdentity.server(_otherOrderId.value),
      orderId: _otherOrderId.value,
      orderNumber: '#R-2',
      amountMinor: 4000,
      tenderedMinor: 5000,
      currencyCode: 'ILS',
      expectedRevision: 7,
    );
    expect(w.ids.calls, beforeIds, reason: 'no id minted for order B');
    expect(w.repo.operationIds, hasLength(beforeSends), reason: 'nothing sent');
    expect(blocked, isA<PaymentAttemptAccepted>());
    expect(moneyTruthOf(blocked), MoneyTruthView.movedUnproven);
    expect(eligibilityOf(blocked), NewIdentityEligibility.forbidden);
  });

  test('T3 a controller rebuild landing between classification and the '
      'incident commit does not lose the evidence', () async {
    // B4. The window is otherwise not deterministically reachable, so the
    // production seam is a test-only barrier placed at exactly one point: after
    // exact evidence is classified and before anything is committed.
    final hold = Completer<PaymentSendResult>();
    final w = await _world(<Future<PaymentSendResult> Function(PaymentAttempt)>[
      (_) => hold.future,
    ]);

    final inFlight = _confirm(w.controller);
    await pumpEventQueue();
    final key = PosOrderIdentity.server(_orderId.value).key;
    final sent = w.controller.state.attempts[key]!;
    _seed(w.ns, <Object?>[
      sent
          .refused(
            PaymentRefusalCode.shiftRequired,
            at: '2026-09-09T15:01:00.000Z',
            memoized: true,
          )
          .toJson(),
    ]);
    w.prefs.cache.remove(_logicalKey);

    final atBarrier = Completer<void>();
    final release = Completer<void>();
    var generationAtBarrier = -1;
    debugPaymentSafetyCommitBarrier = () async {
      debugPaymentSafetyCommitBarrier = null;
      generationAtBarrier = w.controller.generationForTest;
      atBarrier.complete();
      await release.future;
    };
    addTearDown(() => debugPaymentSafetyCommitBarrier = null);

    hold.complete(const PaymentSendAccepted(_resolution));
    await atBarrier.future;

    // Nothing has been committed yet: this is the window.
    expect(paymentSafetyRegistry().incidentOf(_activityKey), isNull);

    // Rebuild the controller IN the window, and prove the in-flight call is now
    // running under a stale generation.
    _goStale(w);
    expect(
      w.controller.generationForTest,
      greaterThan(generationAtBarrier),
      reason: 'the rebuild really landed inside the commit window',
    );

    release.complete();
    final outcome = await inFlight;
    await w.controller.ensureHydrated();

    // Containment happened anyway — generation is not authority over evidence.
    final incident = paymentSafetyRegistry().incidentOf(_activityKey);
    expect(incident, isNotNull);
    expect(incident!.state, IncidentState.active);
    expect(incident.reason, IncidentReason.ownerBContradiction);
    expect(
      incident.durability,
      isA<DurableRecordBlock>(),
      reason: 'the durable promotion still proceeds when it is eligible',
    );

    // Stale UI / session / effects stay suppressed.
    expect(outcome, isA<PaymentAttemptAccepted>());
    expect((outcome as PaymentAttemptAccepted).automaticEffectsArmed, isFalse);
    expect(outcome.localSaveFailed, isTrue);
    expect(w.controller.state.payments[key], isNull);
    expect(w.controller.state.effectsArmed, isNot(contains(key)));
    expect(
      w.controller.state.attempts[key]?.phase,
      isNot(PaymentAttemptPhase.accepted),
    );

    // A fresh world over the same disk is blocked before any id.
    resetPaymentSafetyRegistryForTest();
    resetPaymentAttemptKeyGuardsForTest();
    final restarted = await _world(
      <Future<PaymentSendResult> Function(PaymentAttempt)>[_accepted()],
      namespace: w.ns,
    );
    await _confirm(restarted.controller);
    expect(restarted.ids.calls, 0);
    expect(restarted.repo.operationIds, isEmpty);
  });

  test('T4 OD-1: an UNTRUSTED envelope blocks the mint but never downgrades '
      'money that is known to have moved', () async {
    // The gate ladder puts "the envelope is unusable" above "an incident
    // stands", which is right for deciding whether to mint and wrong for
    // deciding what to SAY. Reported as `SaveBlocked`, this published
    // `nothingSent` for money the server had already applied.
    final ns = _Namespace();
    final w = await _world(<Future<PaymentSendResult> Function(PaymentAttempt)>[
      _accepted(),
    ], namespace: ns);

    // An ACTIVE incident carrying exact accepted truth for THIS order.
    _latchIsolateOnly(_activityKey, _mint('op-known'));
    expect(
      paymentSafetyRegistry().incidentOf(_activityKey)?.acceptedTruth,
      isNotNull,
    );

    // Make the key untrusted in the transient, self-healing way: a write that
    // is still in flight. `readEnvelopeSnapshot` then answers
    // SnapshotUntrusted(writeUnresolved), which rung 1 turns into
    // SafetyEnvelopeFailClosed and which used to hide the incident entirely.
    final release = Completer<void>();
    w.prefs.onSet = (k) => k == _logicalKey ? release.future : null;
    final blockedWrite = w.store
        .createIfAbsent(_scope, _mint('op-inflight').markSent('x'))
        .then<void>((_) {}, onError: (_) {});
    await pumpEventQueue();
    expect(
      paymentAttemptKeyHasWriteInFlightForTest(
        paymentAttemptsPhysicalKey(_scope.key),
      ),
      isTrue,
      reason: 'the untrusted state under test is a write in flight',
    );

    final before = w.ids.calls;
    final outcome = await _confirm(w.controller);

    // BLOCKED: eligibility is still decided by the gate alone.
    expect(w.ids.calls, before, reason: 'no new identity while degraded');
    expect(w.repo.operationIds, isEmpty, reason: 'nothing sent');

    // BUT the money is stated at its strongest known truth.
    expect(
      outcome,
      isA<PaymentAttemptAccepted>(),
      reason: 'OD-1: a storage failure never erases money that moved',
    );
    expect(moneyTruthOf(outcome), MoneyTruthView.movedUnproven);
    expect(moneyTruthOf(outcome), isNot(MoneyTruthView.nothingSent));
    expect(eligibilityOf(outcome), NewIdentityEligibility.forbidden);
    final accepted = outcome as PaymentAttemptAccepted;
    expect(accepted.automaticEffectsArmed, isFalse, reason: 'zero effects');
    expect(accepted.localSaveFailed, isTrue, reason: 'degraded stays true');
    expect(accepted.payment.paymentId, _resolution.paymentId);

    // §6 — the transient condition created no NEW permanent incident of its
    // own; the only one standing is the accepted-class one already known.
    expect(
      paymentSafetyRegistry().incidentOf(_activityKey)?.reason,
      IncidentReason.recordLoss,
    );

    release.complete();
    await blockedWrite;
    w.prefs.onSet = null;
  });

  test('R-A7 a contradiction that lands while resolveAccepted is QUEUED is '
      'still contained: the store sees what the pre-read could not', () async {
    // THE CONCURRENCY DOOR into R-A, which the generation fix alone does not
    // close. `readEnvelopeSnapshot` is a queue-free read; `resolveAccepted`
    // adjudicates inside the physical-key write queue. Another writer — a
    // concurrent `checkStatus` resolution, a second tab, another isolate — can
    // terminalize this record in that gap. The pre-read then classifies a
    // PENDING same attempt and correctly does nothing, the store throws
    // `conflict`, and if that throw installs nothing the disk is left holding a
    // plain `refused` record with no block beside an empty registry: the next
    // confirm hydrates SafetyClear and mints a SECOND identity.
    final hold = Completer<PaymentSendResult>();
    final w = await _world(<Future<PaymentSendResult> Function(PaymentAttempt)>[
      (_) => hold.future,
    ]);

    final inFlight = _confirm(w.controller);
    await pumpEventQueue();
    final key = PosOrderIdentity.server(_orderId.value).key;
    final sent = w.controller.state.attempts[key]!;

    // Read through to the namespace so the hook below decides what each read
    // returns; the record on disk right now is this attempt, still PENDING.
    w.prefs.cache.remove(_logicalKey);

    // Read 1 is the pre-read and sees PENDING. The terminal refusal lands
    // before read 2, which is the one `resolveAccepted` takes inside the queue.
    var reads = 0;
    w.prefs.onGet = (k, nth) {
      if (k != _logicalKey) return;
      reads++;
      // Read 1 is the queue-free pre-read and sees PENDING. Read 2 is the one
      // `resolveAccepted` takes INSIDE the write queue, and the flip lands
      // before it returns, so the store adjudicates against the terminal
      // refusal and throws `conflict`. Reads 3 and 4 are the second pass and
      // its promotion.
      if (reads != 2) return;
      _seed(w.ns, <Object?>[
        sent
            .refused(
              PaymentRefusalCode.shiftRequired,
              at: '2026-09-09T15:01:00.000Z',
              memoized: true,
            )
            .toJson(),
      ]);
    };

    hold.complete(const PaymentSendAccepted(_resolution));
    final outcome = await inFlight;
    w.prefs.onGet = null;

    expect(outcome, isA<PaymentAttemptAccepted>());
    expect(
      (outcome as PaymentAttemptAccepted).localSaveFailed,
      isTrue,
      reason: 'the acceptance could not be written over a terminal answer',
    );

    final incident = paymentSafetyRegistry().incidentOf(_activityKey);
    expect(
      incident,
      isNotNull,
      reason: 'the store discovered the contradiction; it must not be dropped',
    );
    expect(incident!.reason, IncidentReason.ownerBContradiction);
    expect(incident.state, IncidentState.active);
    expect(incident.acceptedTruth, isNotNull);
    expect(incident.durability, isA<DurableRecordBlock>());

    final entries =
        (jsonDecode(w.ns.durable[_logicalKey]!) as Map)['attempts'] as List;
    final stored = PaymentAttempt.fromJson(
      paymentAttemptProjection(entries.single),
    );
    final field = decodeReplacementBlockField(
      entries.single,
      PaymentAttemptParentFacts.of(stored),
    );
    expect(field, isA<BlockDecoded>());
    expect((field as BlockDecoded).block.status, BlockStatus.active);

    // And a restarted process is blocked before any id.
    resetPaymentSafetyRegistryForTest();
    resetPaymentAttemptKeyGuardsForTest();
    final restarted = await _world(
      <Future<PaymentSendResult> Function(PaymentAttempt)>[_accepted()],
      namespace: w.ns,
    );
    await _confirm(restarted.controller);
    expect(restarted.ids.calls, 0);
    expect(restarted.repo.operationIds, isEmpty);
  });

  // =========================================================================
  // T7 / T8 — THE PRE-MINT READ-SIDE RACE.
  //
  // The gate has to read the envelope, which suspends. The isolate safety
  // registry is a global other payment paths commit to. An earlier draft
  // sampled the registry BEFORE that read and hydrated with the sampled value
  // afterwards, so containment latched during the read was invisible: rungs 4
  // and 5 consulted a map that no longer existed, the gate answered
  // SafetyClear, and a second identity was minted for money already known to
  // have moved. This is the read-side twin of the write-side lost update T1
  // covers.
  //
  // The injection point is the envelope read itself: `_Prefs.onGet` fires
  // INSIDE `readEnvelopeSnapshot`, which is strictly after the old sample and
  // strictly before the hydrate — exactly the window under test, and with no
  // production seam needed to reach it.
  // =========================================================================

  test('T7 an incident latched WHILE the pre-mint envelope read is in flight '
      'is still observed, and blocks before any id', () async {
    final w = await _world(<Future<PaymentSendResult> Function(PaymentAttempt)>[
      _accepted(),
    ]);

    // Order-1 is otherwise perfectly mint-eligible: nothing in memory, nothing
    // on disk, no incident. A5 is the control that proves it mints when clear.
    expect(
      w.controller.state.attempts[PosOrderIdentity.server(_orderId.value).key],
      isNull,
    );
    expect(paymentSafetyRegistry().incidentOf(_activityKey), isNull);

    // Another payment path commits containment for THIS order during the read.
    // `_latchIsolateOnly` is idempotent, so firing on every read is harmless.
    w.prefs.onGet = (k, nth) {
      if (k != _logicalKey) return;
      _latchIsolateOnly(_activityKey, _mint('op-read-race'));
    };

    final outcome = await _confirm(w.controller);
    w.prefs.onGet = null;

    expect(
      paymentSafetyRegistry().incidentOf(_activityKey),
      isNotNull,
      reason: 'the latch really landed during the read',
    );
    expect(
      w.ids.calls,
      0,
      reason: 'blocked BEFORE any operation or target id was allocated',
    );
    expect(w.repo.operationIds, isEmpty, reason: 'nothing was sent');

    // And the money is stated at the incident's own truth.
    expect(outcome, isA<PaymentAttemptAccepted>());
    expect(moneyTruthOf(outcome), MoneyTruthView.movedUnproven);
    expect(eligibilityOf(outcome), NewIdentityEligibility.forbidden);
    final accepted = outcome as PaymentAttemptAccepted;
    expect(accepted.automaticEffectsArmed, isFalse);
    expect(accepted.localSaveFailed, isTrue);
    expect(accepted.payment.paymentId, _resolution.paymentId);
  });

  test('T8 CONTROL: an incident latched for a DIFFERENT order during the read '
      'does not block this one, and does block that one', () async {
    final w = await _world(<Future<PaymentSendResult> Function(PaymentAttempt)>[
      _accepted(),
    ]);

    // Same window as T7, but the containment belongs to order-2. A live re-read
    // must pick up the NEW registry without inheriting another key's verdict.
    w.prefs.onGet = (k, nth) {
      if (k != _logicalKey) return;
      _latchIsolateOnly(_otherActivityKey, _mint('op-other-order'));
    };

    final outcome = await _confirm(w.controller);
    w.prefs.onGet = null;

    expect(
      paymentSafetyRegistry().incidentOf(_otherActivityKey),
      isNotNull,
      reason: 'the other order really is contained',
    );
    expect(
      paymentSafetyRegistry().incidentOf(_activityKey),
      isNull,
      reason: 'and this one is not',
    );

    // ORDER-1 IS UNAFFECTED.
    expect(outcome, isA<PaymentAttemptAccepted>());
    expect(moneyTruthOf(outcome), MoneyTruthView.moved);
    expect(w.ids.calls, greaterThan(0), reason: 'a clear order still mints');
    expect(w.repo.operationIds, hasLength(1), reason: 'and still sends');

    // ORDER-2 IS BLOCKED.
    final beforeIds = w.ids.calls;
    final blocked = await w.controller.submitAttempt(
      identity: PosOrderIdentity.server(_otherOrderId.value),
      orderId: _otherOrderId.value,
      orderNumber: '#R-2',
      amountMinor: 4000,
      tenderedMinor: 5000,
      currencyCode: 'ILS',
      expectedRevision: 7,
    );
    expect(w.ids.calls, beforeIds, reason: 'no id minted for order-2');
    expect(w.repo.operationIds, hasLength(1), reason: 'order-2 sent nothing');
    expect(eligibilityOf(blocked), NewIdentityEligibility.forbidden);
  });

  // =========================================================================
  // B — a DEGRADED safety state blocks a fresh identity on its own
  // =========================================================================
  test('B a degraded envelope blocks a fresh identity even though NO accepted '
      'truth is known', () async {
    final w = await _world(<Future<PaymentSendResult> Function(PaymentAttempt)>[
      _refused(),
    ]);

    // First confirm resolves to a durable REFUSAL.
    final first = await _confirm(w.controller);
    expect(first, isA<PaymentAttemptRefused>());
    final idsAfterFirst = w.ids.calls;

    // The envelope is now corrupted in place: same content, but not the
    // production encoding, so it is not canonical.
    w.ns.durable[_logicalKey] = '{"version": 1, "attempts": []}';
    w.prefs.cache.remove(_logicalKey);

    // No incident, no block: the accepted-truth projection is null here.
    final snapshot = await w.store.readEnvelopeSnapshot(_scope, _orderId);
    final safety = hydratePaymentSafety(
      snapshotResult: snapshot,
      registry: paymentSafetyRegistry(),
    );
    expect(acceptedIncidentTruthOf(safety), isNull);
    expect(eligibilityOfSafety(safety), NewIdentityEligibility.forbidden);

    final second = await _confirm(w.controller);
    expect(
      second,
      isA<PaymentAttemptSaveBlocked>(),
      reason: 'nothing could be minted, stored or sent',
    );
    expect(
      w.ids.calls,
      idsAfterFirst,
      reason: 'the gate refuses BEFORE PaymentAttempt.mint',
    );
    expect(w.repo.operationIds, hasLength(1), reason: 'no second send');
    expect(moneyTruthOf(second), MoneyTruthView.nothingSent);
  });

  // =========================================================================
  // C — settledElsewhere never mints
  // =========================================================================
  test('C a settledElsewhere record never reaches the mint: no id, no target, '
      'no send', () async {
    final ns = _Namespace();
    final settled = _mint('op-settled')
        .markSent('2026-09-09T15:00:00.000Z')
        .settledElsewhere(at: '2026-09-09T15:01:00.000Z');
    _seed(ns, <Object?>[settled.toJson()]);

    final w = await _world(<Future<PaymentSendResult> Function(PaymentAttempt)>[
      _accepted(),
    ], namespace: ns);
    expect(
      w
          .controller
          .state
          .attempts[PosOrderIdentity.server(_orderId.value).key]
          ?.phase,
      PaymentAttemptPhase.settledElsewhere,
      reason: 'hydrated from disk',
    );

    final outcome = await _confirm(w.controller);
    expect(outcome, isA<PaymentAttemptSettledElsewhere>());
    expect(w.ids.calls, 0, reason: 'NO second identity was allocated');
    expect(w.repo.operationIds, isEmpty, reason: 'NO second tender was sent');
    expect(eligibilityOf(outcome), NewIdentityEligibility.forbidden);
    expect(moneyTruthOf(outcome), MoneyTruthView.didNotMove);
  });

  // =========================================================================
  // D — rule B
  // =========================================================================
  test(
    'D a LIVE accepted record outranks a later refusal: the payment lands '
    'in session state, the disclosure is cleared, and nothing re-arms',
    () async {
      final hold = Completer<PaymentSendResult>();
      final w = await _world(
        <Future<PaymentSendResult> Function(PaymentAttempt)>[
          (_) => hold.future,
        ],
      );

      final inFlight = _confirm(w.controller);
      await pumpEventQueue();
      final key = PosOrderIdentity.server(_orderId.value).key;
      final sent = w.controller.state.attempts[key]!;

      // The SAME decision is accepted durably while the send is outstanding.
      _seed(w.ns, <Object?>[
        sent
            .accepted(
              _resolution,
              at: '2026-09-09T15:01:00.000Z',
              reserveEffects: true,
            )
            .toJson(),
      ]);
      w.prefs.cache.remove(_logicalKey);

      hold.complete(
        const PaymentSendRefused(
          PaymentRefusalCode.shiftRequired,
          memoized: true,
        ),
      );
      final outcome = await inFlight;

      expect(
        outcome,
        isA<PaymentAttemptAccepted>(),
        reason: 'captured money is never reported as a refusal',
      );
      final accepted = outcome as PaymentAttemptAccepted;
      expect(accepted.replay, isTrue);
      expect(
        accepted.automaticEffectsArmed,
        isFalse,
        reason: 'the one-time claim was consumed when it was first written',
      );
      expect(accepted.localSaveFailed, isFalse);
      expect(accepted.attempt.phase, PaymentAttemptPhase.accepted);

      // The two reconciliations the sibling accepted path performs.
      expect(
        w.controller.state.payments[key],
        isNotNull,
        reason: 'the payment must land in session state',
      );
      expect(
        w.controller.state.payments[key]!.paymentId,
        _resolution.paymentId,
      );
      expect(
        w.controller.state.disclosures[key],
        isNull,
        reason: 'no refusal banner may stand over a settled order',
      );
      expect(
        w.controller.state.effectsArmed.contains(key),
        isFalse,
        reason: 'effects are at-most-once',
      );
      expect(moneyTruthOf(outcome), MoneyTruthView.moved);
    },
  );

  test('D a stored acceptance for a DIFFERENT decision is never published as '
      'this attempt s payment', () async {
    final hold = Completer<PaymentSendResult>();
    final w = await _world(<Future<PaymentSendResult> Function(PaymentAttempt)>[
      (_) => hold.future,
    ]);

    final inFlight = _confirm(w.controller);
    await pumpEventQueue();
    final key = PosOrderIdentity.server(_orderId.value).key;
    final sent = w.controller.state.attempts[key]!;

    // Same operation id, DIFFERENT frozen decision (another amount). Reconcile
    // answers `conflict` for a reason that is NOT "a newer terminal answer".
    final foreign = PaymentAttempt(
      localOperationId: sent.localOperationId,
      targetId: sent.targetId,
      clientCreatedAt: sent.clientCreatedAt,
      identityKey: sent.identityKey,
      orderId: sent.orderId,
      orderNumber: sent.orderNumber,
      expectedRevision: sent.expectedRevision,
      tenderType: sent.tenderType,
      amountMinor: 9999, // <- the different decision
      amountTenderedMinor: sent.amountTenderedMinor,
      currencyCode: sent.currencyCode,
      organizationId: sent.organizationId,
      restaurantId: sent.restaurantId,
      branchId: sent.branchId,
      deviceId: sent.deviceId,
      employeeProfileId: sent.employeeProfileId,
      phase: PaymentAttemptPhase.accepted,
      lastOutcome: PaymentAttemptLastOutcome.none,
      sentAt: '2026-09-09T15:00:00.000Z',
      resolvedAt: '2026-09-09T15:01:00.000Z',
      resolution: _resolution,
      refusal: null,
      refusalMemoized: false,
      autoEffectsReservedAt: '2026-09-09T15:01:00.000Z',
      supersedes: null,
      mayHaveExecuted: true,
    );
    _seed(w.ns, <Object?>[foreign.toJson()]);
    w.prefs.cache.remove(_logicalKey);

    hold.complete(
      const PaymentSendRefused(
        PaymentRefusalCode.shiftRequired,
        memoized: true,
      ),
    );
    final outcome = await inFlight;

    expect(
      outcome,
      isA<PaymentAttemptRefused>(),
      reason: 'another decision s acceptance may not be published as ours',
    );
    expect((outcome as PaymentAttemptRefused).localSaveFailed, isTrue);
    expect(
      w.controller.state.payments[key],
      isNull,
      reason: 'the wrong payment must never reach session state',
    );
  });

  // =========================================================================
  // E — the generation retry, end to end through the controller
  // =========================================================================
  test('E an untrusted key still resolves through the independent reader, so '
      'the controller can complete a payment', () async {
    final w = await _world(<Future<PaymentSendResult> Function(PaymentAttempt)>[
      _accepted(),
    ]);

    // Leave the physical key untrusted by hand, exactly as a failed write
    // would. With a backing reader present the retry must still resolve it.
    bumpPaymentAttemptGenerationForTest(paymentAttemptsPhysicalKey(_scope.key));

    final outcome = await _confirm(w.controller);
    expect(outcome, isA<PaymentAttemptAccepted>());
    expect((outcome as PaymentAttemptAccepted).localSaveFailed, isFalse);
    expect(w.repo.operationIds, hasLength(1));
    expect(moneyTruthOf(outcome), MoneyTruthView.moved);
  });
}
