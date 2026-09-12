// PAYMENT-ATTEMPT-RECOVERY-001 / K3-B01..K3-B06 — the EXECUTABLE gate.
//
// These are the implementation tests for the kernel contracts. They replace the
// architecture document's prose adjudication: every claim below is exercised
// against the real store, the real codecs and the real registry.
//
// Synthetic local storage only: no network, no hosted service, no device, no
// real payment.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_attempt.dart';
import 'package:restoflow_pos/src/data/payment_attempt_store.dart';
import 'package:restoflow_pos/src/data/payment_replacement_block.dart';
import 'package:restoflow_pos/src/data/payment_safety.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Scopes
// ---------------------------------------------------------------------------

const _scope = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'restaurant-1',
  branchId: 'branch-1',
  deviceId: 'device-1',
);

/// K3-B02 — two GENUINELY DIFFERENT tills whose raw fields sanitise to ONE
/// storage key. `PosSyncScope.key` joins with `.`, and `.` is inside its own
/// allowed character class, so nothing is even substituted.
const _aliasLeft = PosSyncScope(
  organizationId: 'acme.north',
  restaurantId: 'r1',
  branchId: 'b1',
  deviceId: 'd1',
);
const _aliasRight = PosSyncScope(
  organizationId: 'acme',
  restaurantId: 'north.r1',
  branchId: 'b1',
  deviceId: 'd1',
);

String _logical(PosSyncScope s) => paymentAttemptsStorageKey(s.key);
String _physical(PosSyncScope s) => paymentAttemptsPhysicalKey(s.key);

final _orderId = CanonicalOrderId.tryFrom('order-1')!;

// ---------------------------------------------------------------------------
// Storage doubles
// ---------------------------------------------------------------------------

/// One physical namespace shared by every wrapper, keyed LOGICALLY (the legacy
/// adapter prefixes on its way out).
class _Namespace {
  final Map<String, String> durable = <String, String>{};
}

class _Prefs implements SharedPreferences {
  _Prefs(this.ns);

  final _Namespace ns;
  final Map<String, String> cache = <String, String>{};

  /// From this 1-based write onwards, mutate the cache and then FAIL.
  int failFromWrite = 0;
  int writes = 0;

  /// When set, `getString` throws as the installed adapter's unguarded cast
  /// would on a non-String cached value.
  bool wrongCachedType = false;

  /// Holds every platform write open, modelling a write that is STILL IN
  /// FLIGHT: the adapter cache is already mutated, the backing is not.
  bool holdWrites = false;
  final List<Completer<void>> _held = <Completer<void>>[];

  void releaseWrites() {
    holdWrites = false;
    for (final c in _held) {
      if (!c.isCompleted) c.complete();
    }
    _held.clear();
  }

  @override
  Future<bool> setString(String key, String value) async {
    writes++;
    cache[key] = value; // the installed adapter's ordering
    if (holdWrites) {
      final c = Completer<void>();
      _held.add(c);
      await c.future;
    }
    if (failFromWrite > 0 && writes >= failFromWrite) return false;
    ns.durable[key] = value;
    return true;
  }

  @override
  String? getString(String key) {
    if (wrongCachedType) throw TypeError();
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

/// The independent reader. Production hands it the PHYSICAL key; the namespace
/// is keyed logically, so the prefix is stripped here — exactly the seam the
/// shipped tests use.
class _Reader implements PaymentAttemptBackingReader {
  _Reader(this.ns);

  final _Namespace ns;
  int reads = 0;

  /// Runs on every read, so a test can move the guard generation underneath an
  /// observation that is already in flight.
  void Function()? onRead;

  @override
  Future<String?> readRaw(String physicalKey) async {
    reads++;
    onRead?.call();
    expect(
      physicalKey.startsWith(kLegacySharedPreferencesKeyPrefix),
      isTrue,
      reason: 'the independent reader must receive the PHYSICAL key',
    );
    return ns.durable[physicalKey.substring(
      kLegacySharedPreferencesKeyPrefix.length,
    )];
  }
}

// ---------------------------------------------------------------------------
// Record + block builders
// ---------------------------------------------------------------------------

PaymentAttempt _mint(String op, {PosSyncScope scope = _scope}) =>
    PaymentAttempt.mint(
      ids: FixedClientIdGenerator(<String>[op, '$op-target']),
      now: DateTime.utc(2026, 9, 9, 12),
      orderId: _orderId.value,
      orderNumber: '#R-1',
      amountMinor: 4000,
      tenderedMinor: 5000,
      currencyCode: 'ILS',
      method: PaymentMethod.cash,
      expectedRevision: 7,
      organizationId: scope.organizationId,
      restaurantId: scope.restaurantId,
      branchId: scope.branchId,
      deviceId: scope.deviceId,
      employeeProfileId: 'employee-1',
    );

/// A REFUSED parent: sent, then definitively refused and memoized.
PaymentAttempt _refusedParent(String op, {PosSyncScope scope = _scope}) =>
    _mint(op, scope: scope)
        .markSent('2026-09-09T12:00:00.000Z')
        .refused(
          PaymentRefusalCode.shiftRequired,
          at: '2026-09-09T12:01:00.000Z',
          memoized: true,
        );

const _resolution = PaymentAttemptResolution(
  paymentId: 'pay-1',
  receiptNumber: 'R-0001',
  changeDueMinor: 1000,
  method: PaymentMethod.cash,
  replay: true,
  orderStatus: 'completed',
);

AcceptedTruth get _truth => acceptedTruthFromSend(_resolution);

PaymentReplacementBlock _activeBlock(
  PaymentAttempt parent, {
  int generation = 1,
}) => PaymentReplacementBlock(
  generation: generation,
  blockId: 'block-1',
  status: BlockStatus.active,
  contradictedOperationId: parent.localOperationId,
  contradictedPhase: parent.phase,
  reason: IncidentReason.ownerBContradiction,
  evidenceSource: BlockEvidenceSource.directSend,
  observedAt: '2026-09-09T12:02:00.000Z',
  serverTruth: _truth,
  resolution: null,
);

/// Writes an envelope containing [entries] straight into the namespace, in the
/// EXACT production encoding.
void _seed(_Namespace ns, PosSyncScope scope, List<Object?> entries) {
  ns.durable[_logical(scope)] = jsonEncode(<String, Object?>{
    'version': PaymentAttempt.schemaVersion,
    'attempts': entries,
  });
}

Map<String, Object?> _entryWithActiveBlock(PaymentAttempt parent) =>
    <String, Object?>{
      ...parent.toJson(),
      kReplacementBlockKey: _activeBlock(parent).toJson(),
    };

PaymentFailClosedIncident _incidentFor(
  PaymentAttempt parent, {
  PosSyncScope scope = _scope,
  BlockOccurrence? occurrence,
  ServerTruth? truth,
}) => PaymentFailClosedIncident(
  key: PaymentActivityKey(scope: scope, orderId: _orderId),
  occurrence: occurrence ?? const BlockOccurrence(1, 'block-1'),
  operationId: parent.localOperationId,
  binding: ExactAttemptBinding.of(parent),
  serverTruth: truth ?? _truth,
  reason: IncidentReason.ownerBContradiction,
  observedAt: '2026-09-09T12:02:00.000Z',
  durability: const DurableRecordBlock(BlockOccurrence(1, 'block-1')),
  state: IncidentState.active,
  conflictingDiagnosticEvidence: const <ServerTruth>[],
);

/// A registry holding a fail-closed owner and the incident for [parent].
({PaymentSafetyRegistry registry, ActivityOwnerToken token, int epoch})
_registryFor(PaymentAttempt parent, {PosSyncScope scope = _scope}) {
  final key = PaymentActivityKey(scope: scope, orderId: _orderId);
  final token = ActivityOwnerToken.issue(key);
  var reg = PaymentSafetyRegistry.empty();
  reg =
      (beginOwner(registry: reg, key: key, ownerToken: token)
              as RegistryTransitionApplied)
          .registry;
  reg =
      (enterOwnerFailClosed(
                registry: reg,
                key: key,
                expectedOwnerToken: token,
                reason: IncidentReason.ownerBContradiction,
              )
              as RegistryTransitionApplied)
          .registry;
  reg =
      (installIncidentIfAbsent(
                registry: reg,
                key: key,
                incident: _incidentFor(parent, scope: scope),
              )
              as RegistryTransitionApplied)
          .registry;
  return (registry: reg, token: token, epoch: reg.ownerOf(key)!.safetyEpoch);
}

List<Object?> _storedEntries(_Namespace ns, PosSyncScope scope) {
  final raw = ns.durable[_logical(scope)];
  if (raw == null) return const <Object?>[];
  return (jsonDecode(raw) as Map)['attempts'] as List<Object?>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetPaymentAttemptKeyGuardsForTest();
    resetPaymentSafetyRegistryForTest();
  });

  // =========================================================================
  // A — K3-B01: the authoritative snapshot
  // =========================================================================
  group('K3-B01 authoritative snapshot', () {
    test('B01-1 the logical and physical keys are distinct and each is used in '
        'its own role', () async {
      expect(
        _physical(_scope),
        '${kLegacySharedPreferencesKeyPrefix}'
        '${_logical(_scope)}',
      );
      expect(_logical(_scope), isNot(_physical(_scope)));

      final ns = _Namespace();
      final prefs = _Prefs(ns);
      final reader = _Reader(ns);
      final store = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: reader,
      );
      _seed(ns, _scope, <Object?>[_refusedParent('op-1').toJson()]);

      final snap = await store.readEnvelopeSnapshot(_scope, _orderId);
      expect(snap, isA<SnapshotReady>());
      final identity = snap.context.identity;
      // Derived from ONE scope; no caller supplies any of them.
      expect(identity.logicalPrefsKey, _logical(_scope));
      expect(identity.physicalBackingKey, _physical(_scope));
      expect(identity.guardKey, paymentAttemptGuardKey(_physical(_scope)));
      expect(identity.scope, _scope, reason: 'the RAW scope is carried whole');
    });

    test('B01-1 the guard consulted is the one for the PHYSICAL key, and the '
        'independent reader is asked for the physical name', () async {
      final ns = _Namespace();
      final prefs = _Prefs(ns);
      final reader = _Reader(ns);
      final store = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: reader,
      );
      _seed(ns, _scope, <Object?>[]);

      // Poison the key guard with a failed write. The durability check reads
      // through the independent reader, which asserts internally that it is
      // handed the PHYSICAL name.
      prefs.failFromWrite = 1;
      final readsBefore = reader.reads;
      await store
          .createIfAbsent(_scope, _mint('op-guard').markSent('x'))
          .then<void>((_) {}, onError: (_) {});
      expect(
        reader.reads,
        greaterThan(readsBefore),
        reason: 'the independent reader was consulted, with the physical key',
      );

      // And the GUARD itself is keyed physically, not logically.
      expect(paymentAttemptKeyIsUntrusted(_physical(_scope)), isTrue);
      expect(
        paymentAttemptKeyIsUntrusted(_logical(_scope)),
        isFalse,
        reason: 'the logical name addresses a DIFFERENT, untouched boundary',
      );
    });

    test('B01-2 a write that is STILL IN FLIGHT can never be reported as a '
        'virgin ABSENT that would authorise a fresh mint', () async {
      final ns = _Namespace();
      final prefs = _Prefs(ns);
      final reader = _Reader(ns);
      final store = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: reader,
      );

      // Hold the platform write open. While it is unresolved the backing store
      // is still EMPTY, so a naive independent read answers null - which would
      // look exactly like "this key was never used".
      prefs.holdWrites = true;
      final pending = store.createIfAbsent(
        _scope,
        _mint('op-inflight').markSent('2026-09-09T12:00:00.000Z'),
      );
      await pumpEventQueue();
      expect(ns.durable, isEmpty);

      final snap = await store.readEnvelopeSnapshot(_scope, _orderId);
      expect(
        snap,
        isA<SnapshotUntrusted>(),
        reason: 'a write in flight is not an absence',
      );
      expect(
        (snap as SnapshotUntrusted).reason,
        UntrustedReason.writeUnresolved,
      );
      final safety = hydratePaymentSafety(
        snapshotResult: snap,
        registry: PaymentSafetyRegistry.empty(),
      );
      expect(safety, isA<SafetyEnvelopeFailClosed>());
      expect(eligibilityOfSafety(safety), NewIdentityEligibility.forbidden);

      prefs.releaseWrites();
      await pending.then<void>((_) {}, onError: (_) {});
    });

    test('B01-2 the four-observation retry is PRESERVED: with no write in '
        'flight the snapshot reads through the independent reader', () async {
      // REPLACES an earlier assertion of mine that an unresolved-but-COMPLETED
      // write stays untrusted forever. That was a REGRESSION: the key guard
      // clears its retained bytes only when a failure was already outstanding,
      // so the extra condition made this retry unreachable for the life of the
      // isolate. The requirement is about a write IN FLIGHT (above); a write
      // that has completed and left nothing on disk is a genuine absence, and
      // the shipped reader path resolves it through the independent reader.
      final ns = _Namespace();
      final prefs = _Prefs(ns)..failFromWrite = 1;
      final reader = _Reader(ns);
      final store = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: reader,
      );

      await store
          .createIfAbsent(_scope, _mint('op-failed').markSent('x'))
          .then<void>((_) {}, onError: (_) {});
      expect(ns.durable, isEmpty, reason: 'nothing landed');

      final before = reader.reads;
      final snap = await store.readEnvelopeSnapshot(_scope, _orderId);
      expect(
        reader.reads,
        greaterThan(before),
        reason: 'the retry loop really ran against the independent reader',
      );
      expect(
        snap,
        isA<SnapshotAbsent>(),
        reason: 'the backing genuinely holds nothing for this key',
      );
    });

    test('B01-2 a generation that moves under EVERY independent read is never '
        'returned as authoritative, and the retry really runs', () async {
      final ns = _Namespace();
      final prefs = _Prefs(ns)..failFromWrite = 1;
      final reader = _Reader(ns);
      final store = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: reader,
      );

      // Leave the key untrusted through a real failed write, so the snapshot
      // takes the independent path.
      await store
          .createIfAbsent(_scope, _mint('op-race').markSent('x'))
          .then<void>((_) {}, onError: (_) {});
      expect(paymentAttemptKeyIsUntrusted(_physical(_scope)), isTrue);

      // Bytes ARE on the backing, so a stale first read would look authoritative
      // and could authorise acting on a store state that no longer exists.
      _seed(ns, _scope, <Object?>[_refusedParent('op-race-2').toJson()]);

      // Every independent read advances this key's generation underneath the
      // observation in flight, so none of the four can ever be confirmed.
      final before = reader.reads;
      reader.onRead = () => bumpPaymentAttemptGenerationForTest(
        paymentAttemptsPhysicalKey(_scope.key),
      );

      final snap = await store.readEnvelopeSnapshot(_scope, _orderId);
      reader.onRead = null;

      expect(
        snap,
        isA<SnapshotUntrusted>(),
        reason: 'a read whose generation moved describes a state that is gone',
      );
      expect(
        (snap as SnapshotUntrusted).reason,
        UntrustedReason.generationRaced,
      );
      expect(
        reader.reads - before,
        4,
        reason: 'all four bounded observations really ran',
      );
      expect(
        paymentAttemptKeyHasWriteInFlightForTest(_physical(_scope)),
        isFalse,
        reason: 'the race is a generation move, NOT a write in flight',
      );
      // And nothing about that stale read may authorise a mint.
      expect(
        eligibilityOfSafety(
          hydratePaymentSafety(
            snapshotResult: snap,
            registry: PaymentSafetyRegistry.empty(),
          ),
        ),
        NewIdentityEligibility.forbidden,
      );
    });

    test('B01-2 the retry RECOVERS: one generation move, then a stable '
        'observation succeeds', () async {
      final ns = _Namespace();
      final prefs = _Prefs(ns)..failFromWrite = 1;
      final reader = _Reader(ns);
      final store = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: reader,
      );
      await store
          .createIfAbsent(_scope, _mint('op-recover').markSent('x'))
          .then<void>((_) {}, onError: (_) {});
      _seed(ns, _scope, <Object?>[_refusedParent('op-recover-2').toJson()]);

      // Move the generation on the FIRST read only; the second observation is
      // stable and must be accepted.
      var bumped = false;
      final before = reader.reads;
      reader.onRead = () {
        if (bumped) return;
        bumped = true;
        bumpPaymentAttemptGenerationForTest(
          paymentAttemptsPhysicalKey(_scope.key),
        );
      };

      final snap = await store.readEnvelopeSnapshot(_scope, _orderId);
      reader.onRead = null;

      expect(
        snap,
        isA<SnapshotReady>(),
        reason: 'the retry recovered and confirmed a stable generation',
      );
      expect(reader.reads - before, 2, reason: 'exactly one retry was needed');
      expect((snap as SnapshotReady).entries, hasLength(1));
    });

    test('B01-2 a stable generation yields ONE accepted read', () async {
      final ns = _Namespace();
      final prefs = _Prefs(ns)..failFromWrite = 1;
      final reader = _Reader(ns);
      final store = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: reader,
      );
      await store
          .createIfAbsent(_scope, _mint('op-stable').markSent('x'))
          .then<void>((_) {}, onError: (_) {});
      _seed(ns, _scope, <Object?>[_refusedParent('op-stable-2').toJson()]);

      final before = reader.reads;
      final snap = await store.readEnvelopeSnapshot(_scope, _orderId);
      expect(snap, isA<SnapshotReady>());
      expect(
        reader.reads - before,
        1,
        reason: 'a stable generation confirms on the first observation',
      );
    });

    test('B01-2 with NO independent reader an untrusted key is fail-closed, '
        'never absent', () async {
      final ns = _Namespace();
      final prefs = _Prefs(ns)..failFromWrite = 1;
      final store = SharedPrefsPaymentAttemptStore(prefs);

      await store
          .createIfAbsent(_scope, _mint('op-noreader').markSent('x'))
          .then<void>((_) {}, onError: (_) {});

      final snap = await store.readEnvelopeSnapshot(_scope, _orderId);
      expect(snap, isA<SnapshotUntrusted>());
      expect(
        (snap as SnapshotUntrusted).reason,
        UntrustedReason.noIndependentReader,
      );
    });

    test(
      'B01-1 a wrong cached TYPE is a typed fail-closed result, not a throw',
      () async {
        final ns = _Namespace();
        final prefs = _Prefs(ns)..wrongCachedType = true;
        final store = SharedPrefsPaymentAttemptStore(
          prefs,
          backingReader: _Reader(ns),
        );

        final snap = await store.readEnvelopeSnapshot(_scope, _orderId);
        expect(snap, isA<SnapshotWrongCachedType>());
        expect(
          eligibilityOfSafety(
            hydratePaymentSafety(
              snapshotResult: snap,
              registry: PaymentSafetyRegistry.empty(),
            ),
          ),
          NewIdentityEligibility.forbidden,
        );
      },
    );

    test('B01-1 ABSENT and PRESENT-EMPTY are distinguished; only a PROVEN '
        'absence permits a mint', () async {
      final ns = _Namespace();
      final store = SharedPrefsPaymentAttemptStore(
        _Prefs(ns),
        backingReader: _Reader(ns),
      );

      final absent = await store.readEnvelopeSnapshot(_scope, _orderId);
      expect(absent, isA<SnapshotAbsent>());
      expect(
        eligibilityOfSafety(
          hydratePaymentSafety(
            snapshotResult: absent,
            registry: PaymentSafetyRegistry.empty(),
          ),
        ),
        NewIdentityEligibility.freshMintAllowed,
      );

      ns.durable[_logical(_scope)] = '';
      final empty = await store.readEnvelopeSnapshot(_scope, _orderId);
      expect(empty, isA<SnapshotPresentEmpty>());
      expect(
        eligibilityOfSafety(
          hydratePaymentSafety(
            snapshotResult: empty,
            registry: PaymentSafetyRegistry.empty(),
          ),
        ),
        NewIdentityEligibility.forbidden,
      );
    });

    test('B01-2 the snapshot carries the exact observed generation, and the '
        'raw bytes it was classified from', () async {
      final ns = _Namespace();
      final store = SharedPrefsPaymentAttemptStore(
        _Prefs(ns),
        backingReader: _Reader(ns),
      );
      _seed(ns, _scope, <Object?>[_refusedParent('op-gen').toJson()]);

      final snap =
          await store.readEnvelopeSnapshot(_scope, _orderId) as SnapshotReady;
      expect(snap.context.generation, isA<int>());
      expect(snap.rawBytes, ns.durable[_logical(_scope)]);
    });

    test(
      'B01-1 a non-canonical envelope is fail-closed and is never mutated',
      () async {
        final ns = _Namespace();
        final store = SharedPrefsPaymentAttemptStore(
          _Prefs(ns),
          backingReader: _Reader(ns),
        );
        // Byte-identical content, but NOT the production encoding (extra space).
        ns.durable[_logical(_scope)] = '{"version": 1, "attempts": []}';

        final snap = await store.readEnvelopeSnapshot(_scope, _orderId);
        expect(snap, isA<SnapshotNotCanonical>());
        expect(
          eligibilityOfSafety(
            hydratePaymentSafety(
              snapshotResult: snap,
              registry: PaymentSafetyRegistry.empty(),
            ),
          ),
          NewIdentityEligibility.forbidden,
        );
      },
    );
  });

  // =========================================================================
  // B — K3-B02 / K3-B03
  // =========================================================================
  group('K3-B02 subject + scope', () {
    test('B02-1 two raw scopes that sanitise to ONE storage key are NOT the '
        'same money-safety key', () {
      expect(_aliasLeft.key, _aliasRight.key, reason: 'the alias is real');
      expect(_logical(_aliasLeft), _logical(_aliasRight));
      expect(_aliasLeft, isNot(_aliasRight));
      expect(
        PaymentActivityKey(scope: _aliasLeft, orderId: _orderId),
        isNot(PaymentActivityKey(scope: _aliasRight, orderId: _orderId)),
      );
    });

    test('B02-1 the same order UUID under a DIFFERENT raw scope cannot be '
        'selected as the subject, and blocks it fail-closed', () async {
      final ns = _Namespace();
      final store = SharedPrefsPaymentAttemptStore(
        _Prefs(ns),
        backingReader: _Reader(ns),
      );
      // One envelope, two tills. The foreign record names the SAME order.
      final mine = _refusedParent('op-mine', scope: _aliasLeft);
      final theirs = _refusedParent('op-theirs', scope: _aliasRight);
      _seed(ns, _aliasLeft, <Object?>[
        _entryWithActiveBlock(mine),
        theirs.toJson(),
      ]);

      final snap =
          await store.readEnvelopeSnapshot(_aliasLeft, _orderId)
              as SnapshotReady;
      // The foreign record is classified as such by its OWN stored raw scope.
      expect(
        snap.entries
            .where((e) => e.kind == FrozenEntryKind.foreignScope)
            .length,
        1,
      );

      final selection = selectExactAttemptSubject(
        snapshot: snap,
        key: PaymentActivityKey(scope: _aliasLeft, orderId: _orderId),
        localOperationId: mine.localOperationId,
        requireActiveReplacementBlock: true,
      );
      expect(
        selection,
        isA<SubjectAliasedScope>(),
        reason: 'an alias naming this order is evidence we cannot adjudicate',
      );
    });

    test('B02-1 a foreign activity key cannot address this snapshot', () async {
      final ns = _Namespace();
      final store = SharedPrefsPaymentAttemptStore(
        _Prefs(ns),
        backingReader: _Reader(ns),
      );
      final parent = _refusedParent('op-x');
      _seed(ns, _scope, <Object?>[_entryWithActiveBlock(parent)]);
      final snap =
          await store.readEnvelopeSnapshot(_scope, _orderId) as SnapshotReady;

      expect(
        selectExactAttemptSubject(
          snapshot: snap,
          key: PaymentActivityKey(scope: _aliasRight, orderId: _orderId),
          localOperationId: parent.localOperationId,
          requireActiveReplacementBlock: true,
        ),
        isA<SubjectForeignSubject>(),
      );
    });

    test('B02-1 an UNREADABLE entry naming this order (or naming none) blocks '
        'the subject, mirroring the shipped mint guard', () async {
      final ns = _Namespace();
      final store = SharedPrefsPaymentAttemptStore(
        _Prefs(ns),
        backingReader: _Reader(ns),
      );
      final parent = _refusedParent('op-y');
      _seed(ns, _scope, <Object?>[
        _entryWithActiveBlock(parent),
        <String, Object?>{'order_id': _orderId.value, 'garbage': true},
      ]);
      final snap =
          await store.readEnvelopeSnapshot(_scope, _orderId) as SnapshotReady;

      expect(
        selectExactAttemptSubject(
          snapshot: snap,
          key: PaymentActivityKey(scope: _scope, orderId: _orderId),
          localOperationId: parent.localOperationId,
          requireActiveReplacementBlock: true,
        ),
        isA<SubjectBlockingQuarantine>(),
      );
    });

    test(
      'B02-1 a duplicate operation id is REFUSED, not resolved last-wins',
      () async {
        final ns = _Namespace();
        final store = SharedPrefsPaymentAttemptStore(
          _Prefs(ns),
          backingReader: _Reader(ns),
        );
        final parent = _refusedParent('op-dup');
        _seed(ns, _scope, <Object?>[parent.toJson(), parent.toJson()]);
        final snap =
            await store.readEnvelopeSnapshot(_scope, _orderId) as SnapshotReady;

        expect(
          selectExactAttemptSubject(
            snapshot: snap,
            key: PaymentActivityKey(scope: _scope, orderId: _orderId),
            localOperationId: parent.localOperationId,
            requireActiveReplacementBlock: false,
          ),
          isA<SubjectAmbiguous>(),
        );
      },
    );
  });

  group('K3-B03 registry compare-and-set', () {
    PaymentActivityKey key() =>
        PaymentActivityKey(scope: _scope, orderId: _orderId);

    test('B03 a stale reservation cannot promote after the owner went '
        'fail-closed', () {
      final k = key();
      final token = ActivityOwnerToken.issue(k);
      var reg =
          (beginOwner(registry: reg0(), key: k, ownerToken: token)
                  as RegistryTransitionApplied)
              .registry;

      final taken = reserveSameAttempt(
        registry: reg,
        key: k,
        expectedOwnerToken: token,
      );
      reg = taken.result.registry;
      final reservation = taken.reservation!;

      // The epoch moves when the owner enters fail-closed.
      reg =
          (enterOwnerFailClosed(
                    registry: reg,
                    key: k,
                    expectedOwnerToken: token,
                    reason: IncidentReason.ownerBContradiction,
                  )
                  as RegistryTransitionApplied)
              .registry;

      final promoted = promoteReservation(
        registry: reg,
        reservation: reservation,
      );
      expect(promoted.result, isA<RegistryTransitionRefused>());
      expect(
        (promoted.result as RegistryTransitionRefused).reason,
        RegistryRefusalReason.reservationStale,
      );
      expect(promoted.handle, isNull);
    });

    test('B03 participant A2 cannot release A', () {
      final k = key();
      final token = ActivityOwnerToken.issue(k);
      var reg =
          (beginOwner(registry: reg0(), key: k, ownerToken: token)
                  as RegistryTransitionApplied)
              .registry;

      final a = admitParticipant(
        registry: reg,
        key: k,
        expectedOwnerToken: token,
      );
      reg = a.result.registry;
      final b = admitParticipant(
        registry: reg,
        key: k,
        expectedOwnerToken: token,
      );
      reg = b.result.registry;
      expect(reg.ownerOf(k)!.participants.length, 2);

      // A2 leaves. A's participation — and the owner — must survive.
      reg = releaseParticipant(registry: reg, handle: b.handle!).registry;
      expect(reg.ownerOf(k), isNotNull);
      expect(
        reg.ownerOf(k)!.participants,
        contains(a.handle!.participantToken),
      );
      expect(
        reg.ownerOf(k)!.participants,
        isNot(contains(b.handle!.participantToken)),
      );
    });

    test('B03 a participant handle from another owner is refused', () {
      final k = key();
      final t1 = ActivityOwnerToken.issue(k);
      final t2 = ActivityOwnerToken.issue(k);
      var reg =
          (beginOwner(registry: reg0(), key: k, ownerToken: t1)
                  as RegistryTransitionApplied)
              .registry;
      final a = admitParticipant(registry: reg, key: k, expectedOwnerToken: t1);
      reg = a.result.registry;

      final forged = ParticipantHandle(
        key: k,
        ownerToken: t2, // a DIFFERENT owner
        participantToken: a.handle!.participantToken,
        safetyEpoch: 0,
      );
      final out = releaseParticipant(registry: reg, handle: forged);
      expect(out, isA<RegistryTransitionRefused>());
      expect(
        (out as RegistryTransitionRefused).reason,
        RegistryRefusalReason.ownerTokenMismatch,
      );
    });

    test('B03 clear-and-release refuses on a wrong owner token, a wrong epoch '
        'and a wrong occurrence — and leaves the registry untouched', () {
      final parent = _refusedParent('op-cas');
      final built = _registryFor(parent);
      final k = key();

      final wrongToken = clearIncidentAndReleaseOwnerIfExact(
        registry: built.registry,
        key: k,
        expectedOwnerToken: ActivityOwnerToken.issue(k),
        expectedOccurrence: const BlockOccurrence(1, 'block-1'),
        expectedSafetyEpoch: built.epoch,
      );
      expect(wrongToken, isA<RegistryTransitionRefused>());
      expect(wrongToken.registry.incidentOf(k), isNotNull);

      final wrongEpoch = clearIncidentAndReleaseOwnerIfExact(
        registry: built.registry,
        key: k,
        expectedOwnerToken: built.token,
        expectedOccurrence: const BlockOccurrence(1, 'block-1'),
        expectedSafetyEpoch: built.epoch + 99,
      );
      expect(
        (wrongEpoch as RegistryTransitionRefused).reason,
        RegistryRefusalReason.ownerEpochMismatch,
      );

      final wrongOccurrence = clearIncidentAndReleaseOwnerIfExact(
        registry: built.registry,
        key: k,
        expectedOwnerToken: built.token,
        expectedOccurrence: const BlockOccurrence(2, 'block-1'),
        expectedSafetyEpoch: built.epoch,
      );
      expect(
        (wrongOccurrence as RegistryTransitionRefused).reason,
        RegistryRefusalReason.incidentOccurrenceMismatch,
      );

      // The exact transition clears ONLY this incident and releases the owner.
      final ok = clearIncidentAndReleaseOwnerIfExact(
        registry: built.registry,
        key: k,
        expectedOwnerToken: built.token,
        expectedOccurrence: const BlockOccurrence(1, 'block-1'),
        expectedSafetyEpoch: built.epoch,
      );
      expect(ok, isA<RegistryTransitionApplied>());
      expect(ok.registry.incidentOf(k), isNull);
      expect(ok.registry.ownerOf(k), isNull, reason: 'nobody was inside it');
    });

    test('B03 an owner still holding a participant is RETAINED when its '
        'handoff is released', () {
      final parent = _refusedParent('op-retain');
      final built = _registryFor(parent);
      final k = key();
      final admitted = admitParticipant(
        registry: built.registry,
        key: k,
        expectedOwnerToken: built.token,
      );
      final reg = admitted.result.registry;

      final ok =
          clearIncidentAndReleaseOwnerIfExact(
                registry: reg,
                key: k,
                expectedOwnerToken: built.token,
                expectedOccurrence: const BlockOccurrence(1, 'block-1'),
                expectedSafetyEpoch: built.epoch,
              )
              as RegistryTransitionApplied;
      expect(ok.registry.incidentOf(k), isNull);
      expect(
        ok.registry.ownerOf(k),
        isNotNull,
        reason: 'a live participant must not lose its ownership record',
      );
      expect(ok.registry.ownerOf(k)!.handoff.isReleasable, isTrue);
    });
  });
  // =========================================================================
  // B2 - RETENTION, through the REAL prune path
  // =========================================================================
  group('retention preserves replacement-block evidence', () {
    /// A resolved, in-scope, legally prunable record.
    PaymentAttempt resolvedHistory(String op) => _mint(op)
        .markSent('2026-09-09T12:00:00.000Z')
        .refused(
          PaymentRefusalCode.generic,
          at: '2026-09-09T12:01:00.000Z',
          memoized: true,
        );

    /// A PENDING record. Resolving it through `update` is a genuine `applied`
    /// merge, which is what actually drives `_rebuild` and the prune. Updating
    /// an already-resolved record with the same terminal answer is `redundant`
    /// and writes NOTHING - an earlier draft of these tests made that mistake
    /// and silently exercised no retention at all.
    PaymentAttempt pendingRecord(String op) =>
        _mint(op).markSent('2026-09-09T12:00:00.000Z');

    test('an ACTIVE replacement block is never chosen as the retention '
        'victim, and a plain resolved record is pruned instead', () async {
      final ns = _Namespace();
      final store = SharedPrefsPaymentAttemptStore(
        _Prefs(ns),
        backingReader: _Reader(ns),
      );

      // The OLDEST entry carries the ACTIVE block, so a first-in-stored-order
      // victim search would take it first.
      final blocked = _refusedParent('op-blocked');
      final entries = <Object?>[_entryWithActiveBlock(blocked)];
      for (var i = 0; i < kPaymentAttemptsResolvedRetention - 1; i++) {
        entries.add(resolvedHistory('op-hist-$i').toJson());
      }
      entries.add(pendingRecord('op-pending').toJson());
      _seed(ns, _scope, entries);
      expect(
        _storedEntries(ns, _scope),
        hasLength(kPaymentAttemptsResolvedRetention + 1),
      );

      // Resolving the pending record takes the resolved count one OVER the cap,
      // so exactly one victim must be dropped.
      final merge = await store.update(_scope, resolvedHistory('op-pending'));
      expect(merge.writes, isTrue, reason: 'a real write must have happened');

      final after = _storedEntries(ns, _scope);
      expect(
        after,
        hasLength(kPaymentAttemptsResolvedRetention),
        reason: 'the cap dropped exactly one record',
      );

      // THE POINT: the block-carrying entry survived, byte-for-byte.
      final kept = after.where((e) => paymentAttemptRawBlock(e) != null);
      expect(
        kept,
        hasLength(1),
        reason: 'an ACTIVE block is not a legal retention victim',
      );
      expect(
        jsonEncode(kept.single),
        jsonEncode(_entryWithActiveBlock(blocked)),
        reason: 'protected evidence is re-emitted unchanged',
      );
      // And a plain history record went instead.
      final ids = after
          .map((e) => (e! as Map)['local_operation_id'] as String)
          .toList();
      expect(ids, isNot(contains('op-hist-0')));
    });

    test(
      'a RESOLVED block is also protected, because the next occurrence is '
      'generation + 1 and a stale clear must never match a reused id',
      () async {
        final ns = _Namespace();
        final store = SharedPrefsPaymentAttemptStore(
          _Prefs(ns),
          backingReader: _Reader(ns),
        );

        final parent = _refusedParent('op-resolved-block');
        final resolvedBlock = _activeBlock(parent).resolvedWith(
          BlockResolution(
            kind: BlockResolutionKind.applied,
            resolvedAt: '2026-09-09T12:03:00.000Z',
            resolutionOperationId: parent.localOperationId,
            resolutionTruth: _truth,
          ),
        );
        final built =
            buildAcceptedCandidateFromContradictedParent(
                  parent: parent,
                  freshTruth: _truth,
                  resolvedBlock: resolvedBlock,
                  at: '2026-09-09T12:03:00.000Z',
                )
                as AcceptedCandidateBuilt;

        final entries = <Object?>[built.entryValue];
        for (var i = 0; i < kPaymentAttemptsResolvedRetention - 1; i++) {
          entries.add(resolvedHistory('op-h-$i').toJson());
        }
        entries.add(pendingRecord('op-pending2').toJson());
        _seed(ns, _scope, entries);

        final merge = await store.update(
          _scope,
          resolvedHistory('op-pending2'),
        );
        expect(merge.writes, isTrue);

        final after = _storedEntries(ns, _scope);
        expect(after, hasLength(kPaymentAttemptsResolvedRetention));
        expect(
          after.where((e) => paymentAttemptRawBlock(e) != null),
          hasLength(1),
          reason: 'resolved-block evidence is retained for the ABA guard',
        );
      },
    );

    test('CONTROL: ordinary history still prunes deterministically, oldest '
        'first', () async {
      final ns = _Namespace();
      final store = SharedPrefsPaymentAttemptStore(
        _Prefs(ns),
        backingReader: _Reader(ns),
      );
      final entries = <Object?>[];
      for (var i = 0; i < kPaymentAttemptsResolvedRetention; i++) {
        entries.add(resolvedHistory('op-p-$i').toJson());
      }
      entries.add(pendingRecord('op-p-last').toJson());
      _seed(ns, _scope, entries);

      final merge = await store.update(_scope, resolvedHistory('op-p-last'));
      expect(merge.writes, isTrue);

      final after = _storedEntries(ns, _scope);
      expect(after, hasLength(kPaymentAttemptsResolvedRetention));
      final ids = after
          .map((e) => (e! as Map)['local_operation_id'] as String)
          .toList();
      expect(ids, isNot(contains('op-p-0')), reason: 'oldest went first');
      expect(ids, contains('op-p-1'));
      expect(ids, contains('op-p-last'));
    });
  });

  // =========================================================================
  // C — K3-B04: the codecs
  // =========================================================================
  group('K3-B04 codecs', () {
    test('B04 a non-String nested map key is a TYPED malformed result, never a '
        'throw', () {
      final parent = _refusedParent('op-codec');
      final bad = <Object?, Object?>{1: 'x'};
      final out = decodeReplacementBlock(
        bad,
        PaymentAttemptParentFacts.of(parent),
      );
      expect(out, isA<BlockMalformed>());
      expect((out as BlockMalformed).rule, 'S0');

      // And the strict map converter reports it as data.
      expect(strictStringObjectMap(bad), isA<StrictMapBadKey>());
      expect(strictStringObjectMap('nope'), isA<StrictMapNotAMap>());
      expect(strictStringObjectMap(null), isA<StrictMapNotAMap>());
    });

    test(
      'B04 ABSENT, PRESENT-NULL and PRESENT-MAP are three different answers',
      () {
        final parent = _refusedParent('op-presence');
        final facts = PaymentAttemptParentFacts.of(parent);

        expect(
          decodeReplacementBlockField(parent.toJson(), facts),
          isA<BlockAbsent>(),
        );
        expect(
          decodeReplacementBlockField(<String, Object?>{
            ...parent.toJson(),
            kReplacementBlockKey: null,
          }, facts),
          isA<BlockMalformed>(),
        );
        expect(
          decodeReplacementBlockField(_entryWithActiveBlock(parent), facts),
          isA<BlockDecoded>(),
        );
      },
    );

    test('B04 an unknown key and a missing key are both malformed', () {
      final parent = _refusedParent('op-keys');
      final facts = PaymentAttemptParentFacts.of(parent);
      final good = _activeBlock(parent).toJson();

      final extra = <String, Object?>{...good, 'surprise': 1};
      expect(
        (decodeReplacementBlock(extra, facts) as BlockMalformed).rule,
        'S2',
      );

      final missing = <String, Object?>{...good}..remove('observed_at');
      expect(
        (decodeReplacementBlock(missing, facts) as BlockMalformed).rule,
        'S2',
      );
    });

    test('B04 a malformed RESOLVED block on a REFUSED parent returns S6d and '
        'does NOT throw — counterexample I', () {
      final parent = _refusedParent('op-I');
      final active = _activeBlock(parent);
      final resolved = active.resolvedWith(
        BlockResolution(
          kind: BlockResolutionKind.applied,
          resolvedAt: '2026-09-09T12:03:00.000Z',
          resolutionOperationId: parent.localOperationId,
          resolutionTruth: _truth,
        ),
      );

      final out = decodeReplacementBlock(
        resolved.toJson(),
        PaymentAttemptParentFacts.of(parent), // STILL REFUSED
      );
      expect(out, isA<BlockMalformed>());
      expect((out as BlockMalformed).rule, 'S6d');
      expect(out.message, contains('non-accepted parent'));
    });

    test('B04 a non-canonical timestamp is rejected even though tryParse '
        'accepts it', () {
      final parent = _refusedParent('op-time');
      final facts = PaymentAttemptParentFacts.of(parent);
      final j = _activeBlock(parent).toJson();
      // `DateTime.tryParse` accepts this; the producers never write it.
      j['observed_at'] = '2026-09-09 12:02:00Z';
      expect(isCanonicalInstant(j['observed_at']), isFalse);
      expect((decodeReplacementBlock(j, facts) as BlockMalformed).rule, 'S3g');
    });

    test('B04 a zero/negative generation is rejected', () {
      final parent = _refusedParent('op-gen0');
      final facts = PaymentAttemptParentFacts.of(parent);
      final j = _activeBlock(parent).toJson()..['generation'] = 0;
      expect((decodeReplacementBlock(j, facts) as BlockMalformed).rule, 'S3a');
    });

    test('B04 ServerTruth round-trips for every variant and rejects unknown '
        'wire values', () {
      final truths = <ServerTruth>[
        _truth,
        const MemoizedRefusalTruth(PaymentRefusalCode.shiftRequired),
        const NonMemoizedRefusalTruth(PaymentRefusalCode.revisionConflict),
        DiagnosticTruth.unconfirmed(PaymentUnconfirmedReason.transport),
        DiagnosticTruth.notApplied('rolled_back'),
        DiagnosticTruth.authRequired(),
        DiagnosticTruth.collision(),
      ];
      for (final t in truths) {
        final back = decodeServerTruth(t.toJson());
        expect(back, isA<ServerTruthOk>(), reason: t.kind);
        expect((back as ServerTruthOk).truth, t, reason: t.kind);
        // Encoding is stable, so the bytes round-trip too.
        expect(jsonEncode(back.truth.toJson()), jsonEncode(t.toJson()));
      }

      expect(
        decodeServerTruth(<String, Object?>{'kind': 'nope'}),
        isA<ServerTruthMalformed>(),
      );
      expect(
        decodeServerTruth(<String, Object?>{
          'kind': 'memoized_refusal',
          'refusal_code': 'not-a-code',
        }),
        isA<ServerTruthMalformed>(),
      );
      // A memoized and a non-memoized refusal for the same code are NOT equal.
      expect(
        const MemoizedRefusalTruth(PaymentRefusalCode.generic),
        isNot(const NonMemoizedRefusalTruth(PaymentRefusalCode.generic)),
      );
    });

    test('B04 an accepted truth whose evidence_source disagrees with the '
        "block's is malformed", () {
      final parent = _refusedParent('op-prov');
      final facts = PaymentAttemptParentFacts.of(parent);
      final j = _activeBlock(parent).toJson();
      j['evidence_source'] = BlockEvidenceSource.passiveStatusLookup.wire;
      expect((decodeReplacementBlock(j, facts) as BlockMalformed).rule, 'S4a');
    });

    test('B04 the block round-trips and equality is by value', () {
      final parent = _refusedParent('op-rt');
      final block = _activeBlock(parent);
      final back = decodeReplacementBlock(
        block.toJson(),
        PaymentAttemptParentFacts.of(parent),
      );
      expect(back, isA<BlockDecoded>());
      expect((back as BlockDecoded).block, block);
      expect(block.occurrence, const BlockOccurrence(1, 'block-1'));
    });
  });

  // =========================================================================
  // D — K3-B05 / counterexample H
  // =========================================================================
  group('K3-B05 accepted candidate and H', () {
    test('B05 the shipped accepted() helper RETAINS refusal facts — which is '
        'why the explicit builder exists', () {
      final parent = _refusedParent('op-why');
      final viaHelper = parent.accepted(
        _resolution,
        at: '2026-09-09T12:03:00.000Z',
        reserveEffects: true,
      );
      expect(viaHelper.phase, PaymentAttemptPhase.accepted);
      expect(
        viaHelper.refusal,
        isNotNull,
        reason: '_copy null-coalesces, so the refusal survives',
      );
      // And the strict decoder rejects exactly that shape.
      expect(
        () => PaymentAttempt.fromJson(viaHelper.toJson()),
        throwsA(isA<FormatException>()),
      );
    });

    test('B05-1 the explicit builder clears the refusal facts and the whole '
        'candidate strict-decodes', () {
      final parent = _refusedParent('op-build');
      final resolved = _activeBlock(parent).resolvedWith(
        BlockResolution(
          kind: BlockResolutionKind.applied,
          resolvedAt: '2026-09-09T12:03:00.000Z',
          resolutionOperationId: parent.localOperationId,
          resolutionTruth: _truth,
        ),
      );
      final out = buildAcceptedCandidateFromContradictedParent(
        parent: parent,
        freshTruth: _truth,
        resolvedBlock: resolved,
        at: '2026-09-09T12:03:00.000Z',
      );
      expect(out, isA<AcceptedCandidateBuilt>());
      final built = out as AcceptedCandidateBuilt;

      expect(built.candidate.phase, PaymentAttemptPhase.accepted);
      expect(built.candidate.refusal, isNull);
      expect(built.candidate.refusalMemoized, isFalse);
      expect(built.candidate.autoEffectsReservedAt, isNotNull);

      // B05-1: the fresh truth cannot differ from what was written.
      expect(
        identicalResolution(_truth.resolution, built.candidate.resolution!),
        isTrue,
      );
      expect(built.candidate.resolution!.orderStatus, 'completed');
      expect(built.candidate.resolution!.replay, isTrue);

      // The candidate came back OUT of the shipped strict decoder.
      final reDecoded = PaymentAttempt.fromJson(
        paymentAttemptProjection(built.entryValue),
      );
      expect(reDecoded.phase, PaymentAttemptPhase.accepted);
    });

    test('B05 a tender mismatch is refused before anything is built', () {
      final parent = _refusedParent('op-tender');
      final cardResolution = PaymentAttemptResolution(
        paymentId: 'pay-1',
        receiptNumber: 'R-0001',
        changeDueMinor: 0,
        method: PaymentMethod.card,
        replay: false,
      );
      final truth = acceptedTruthFromSend(cardResolution);
      final resolved = _activeBlock(parent).resolvedWith(
        BlockResolution(
          kind: BlockResolutionKind.applied,
          resolvedAt: '2026-09-09T12:03:00.000Z',
          resolutionOperationId: parent.localOperationId,
          resolutionTruth: truth,
        ),
      );
      final out = buildAcceptedCandidateFromContradictedParent(
        parent: parent,
        freshTruth: truth,
        resolvedBlock: resolved,
        at: '2026-09-09T12:03:00.000Z',
      );
      expect((out as AcceptedCandidateInvalid).rule, 'B5');
    });

    test(
      'H the APPLIED resolution writes the accepted parent AND the resolved '
      'block in ONE durable write, then clears exactly this incident',
      () async {
        final ns = _Namespace();
        final prefs = _Prefs(ns);
        final store = SharedPrefsPaymentAttemptStore(
          prefs,
          backingReader: _Reader(ns),
        );
        final parent = _refusedParent('op-H');
        _seed(ns, _scope, <Object?>[_entryWithActiveBlock(parent)]);
        final built = _registryFor(parent);

        final writesBefore = prefs.writes;
        final out = await store.resolveIncidentApplied(
          scope: _scope,
          registry: built.registry,
          incident: built.registry.incidentOf(
            PaymentActivityKey(scope: _scope, orderId: _orderId),
          )!,
          expectedOwnerToken: built.token,
          expectedOccurrence: const BlockOccurrence(1, 'block-1'),
          expectedSafetyEpoch: built.epoch,
          freshTruth: _truth,
          at: '2026-09-09T12:03:00.000Z',
          sameWorld: true,
        );

        expect(out, isA<IncidentResolvedApplied>());
        final applied = out as IncidentResolvedApplied;
        expect(prefs.writes - writesBefore, 1, reason: 'exactly ONE write');

        // The parent no longer remains refused.
        expect(applied.acceptedParent.phase, PaymentAttemptPhase.accepted);
        expect(applied.acceptedParent.refusal, isNull);
        expect(applied.acceptedParent.refusalMemoized, isFalse);
        expect(applied.block.status, BlockStatus.resolved);

        // On disk, in the same write.
        final entries = _storedEntries(ns, _scope);
        expect(entries, hasLength(1));
        final stored = PaymentAttempt.fromJson(
          paymentAttemptProjection(entries.single),
        );
        expect(stored.phase, PaymentAttemptPhase.accepted);
        expect(stored.refusal, isNull);
        final storedBlock = decodeReplacementBlockField(
          entries.single,
          PaymentAttemptParentFacts.of(stored),
        );
        expect(
          (storedBlock as BlockDecoded).block.status,
          BlockStatus.resolved,
        );

        // Exactly this incident cleared; the owner released.
        final k = PaymentActivityKey(scope: _scope, orderId: _orderId);
        expect(applied.registry.incidentOf(k), isNull);
        expect(applied.registry.ownerOf(k), isNull);
        expect(applied.effectsArmed, isTrue);
      },
    );

    test(
      'H a passive status lookup resolves the incident but arms NOTHING',
      () async {
        final ns = _Namespace();
        final store = SharedPrefsPaymentAttemptStore(
          _Prefs(ns),
          backingReader: _Reader(ns),
        );
        final parent = _refusedParent('op-passive');
        // The block itself records the passive provenance.
        final block = PaymentReplacementBlock(
          generation: 1,
          blockId: 'block-1',
          status: BlockStatus.active,
          contradictedOperationId: parent.localOperationId,
          contradictedPhase: parent.phase,
          reason: IncidentReason.ownerBContradiction,
          evidenceSource: BlockEvidenceSource.passiveStatusLookup,
          observedAt: '2026-09-09T12:02:00.000Z',
          serverTruth: acceptedTruthFromLookup(_resolution),
          resolution: null,
        );
        _seed(ns, _scope, <Object?>[
          <String, Object?>{
            ...parent.toJson(),
            kReplacementBlockKey: block.toJson(),
          },
        ]);
        final k = PaymentActivityKey(scope: _scope, orderId: _orderId);
        final token = ActivityOwnerToken.issue(k);
        var reg =
            (beginOwner(registry: reg0(), key: k, ownerToken: token)
                    as RegistryTransitionApplied)
                .registry;
        reg =
            (enterOwnerFailClosed(
                      registry: reg,
                      key: k,
                      expectedOwnerToken: token,
                      reason: IncidentReason.ownerBContradiction,
                    )
                    as RegistryTransitionApplied)
                .registry;
        reg =
            (installIncidentIfAbsent(
                      registry: reg,
                      key: k,
                      incident: _incidentFor(
                        parent,
                        truth: acceptedTruthFromLookup(_resolution),
                      ),
                    )
                    as RegistryTransitionApplied)
                .registry;

        final out = await store.resolveIncidentApplied(
          scope: _scope,
          registry: reg,
          incident: reg.incidentOf(k)!,
          expectedOwnerToken: token,
          expectedOccurrence: const BlockOccurrence(1, 'block-1'),
          expectedSafetyEpoch: reg.ownerOf(k)!.safetyEpoch,
          freshTruth: acceptedTruthFromLookup(_resolution),
          at: '2026-09-09T12:03:00.000Z',
          sameWorld: true,
        );
        expect(out, isA<IncidentResolvedApplied>());
        expect(
          (out as IncidentResolvedApplied).effectsArmed,
          isFalse,
          reason: 'a query is never a payment edge (PDR-005)',
        );
      },
    );

    test(
      'H a write that is not provably durable leaves the incident ACTIVE '
      'and the owner fail-closed, and claims nothing about the old bytes',
      () async {
        final ns = _Namespace();
        final prefs = _Prefs(ns);
        final store = SharedPrefsPaymentAttemptStore(
          prefs,
          backingReader: _Reader(ns),
        );
        final parent = _refusedParent('op-nodurable');
        _seed(ns, _scope, <Object?>[_entryWithActiveBlock(parent)]);
        final built = _registryFor(parent);
        final k = PaymentActivityKey(scope: _scope, orderId: _orderId);
        final before = ns.durable[_logical(_scope)];

        prefs.failFromWrite = 1; // the platform write fails from here on

        final out = await store.resolveIncidentApplied(
          scope: _scope,
          registry: built.registry,
          incident: built.registry.incidentOf(k)!,
          expectedOwnerToken: built.token,
          expectedOccurrence: const BlockOccurrence(1, 'block-1'),
          expectedSafetyEpoch: built.epoch,
          freshTruth: _truth,
          at: '2026-09-09T12:03:00.000Z',
          sameWorld: true,
        );

        expect(out, isA<IncidentResolutionWriteFailed>());
        final failed = out as IncidentResolutionWriteFailed;
        // The backing store never changed, so the OLD bytes are provably there.
        expect(failed.knowledge, DurabilityKnowledge.verifiedOld);
        expect(ns.durable[_logical(_scope)], before);

        // Nothing released.
        expect(failed.registry.incidentOf(k), isNotNull);
        expect(failed.registry.incidentOf(k)!.state, IncidentState.active);
        expect(failed.registry.ownerOf(k)!.handoff.isFailClosed, isTrue);
      },
    );

    test('H OD-1: money that differs from the recorded acceptance is REFUSED '
        'and the incident stands', () async {
      final ns = _Namespace();
      final store = SharedPrefsPaymentAttemptStore(
        _Prefs(ns),
        backingReader: _Reader(ns),
      );
      final parent = _refusedParent('op-od1');
      _seed(ns, _scope, <Object?>[_entryWithActiveBlock(parent)]);
      final built = _registryFor(parent);
      final k = PaymentActivityKey(scope: _scope, orderId: _orderId);

      final otherMoney = acceptedTruthFromSend(
        const PaymentAttemptResolution(
          paymentId: 'pay-DIFFERENT',
          receiptNumber: 'R-0002',
          changeDueMinor: 1000,
          method: PaymentMethod.cash,
          replay: false,
        ),
      );

      final out = await store.resolveIncidentApplied(
        scope: _scope,
        registry: built.registry,
        incident: built.registry.incidentOf(k)!,
        expectedOwnerToken: built.token,
        expectedOccurrence: const BlockOccurrence(1, 'block-1'),
        expectedSafetyEpoch: built.epoch,
        freshTruth: otherMoney,
        at: '2026-09-09T12:03:00.000Z',
        sameWorld: true,
      );
      expect(out, isA<IncidentResolutionRefusedContradictoryTruth>());
      expect(out.registry.incidentOf(k), isNotNull);
      expect(_storedEntries(ns, _scope), hasLength(1));
      expect(
        PaymentAttempt.fromJson(
          paymentAttemptProjection(_storedEntries(ns, _scope).single),
        ).phase,
        PaymentAttemptPhase.refused,
        reason: 'the parent must remain refused',
      );
    });

    test('H a REPLAY of the same money still resolves — replay is a property '
        'of the reply, not of the money', () async {
      final ns = _Namespace();
      final store = SharedPrefsPaymentAttemptStore(
        _Prefs(ns),
        backingReader: _Reader(ns),
      );
      final parent = _refusedParent('op-replay');
      _seed(ns, _scope, <Object?>[_entryWithActiveBlock(parent)]);
      final built = _registryFor(parent);
      final k = PaymentActivityKey(scope: _scope, orderId: _orderId);

      // Same money, different `replay` flag.
      final sameMoneyDifferentReply = acceptedTruthFromSend(
        const PaymentAttemptResolution(
          paymentId: 'pay-1',
          receiptNumber: 'R-0001',
          changeDueMinor: 1000,
          method: PaymentMethod.cash,
          replay: false,
          orderStatus: 'completed',
        ),
      );
      expect(
        sameMoneyTruth(sameMoneyDifferentReply.resolution, _truth.resolution),
        isTrue,
      );
      expect(
        identicalResolution(
          sameMoneyDifferentReply.resolution,
          _truth.resolution,
        ),
        isFalse,
      );

      final out = await store.resolveIncidentApplied(
        scope: _scope,
        registry: built.registry,
        incident: built.registry.incidentOf(k)!,
        expectedOwnerToken: built.token,
        expectedOccurrence: const BlockOccurrence(1, 'block-1'),
        expectedSafetyEpoch: built.epoch,
        freshTruth: sameMoneyDifferentReply,
        at: '2026-09-09T12:03:00.000Z',
        sameWorld: true,
      );
      expect(out, isA<IncidentResolvedApplied>());
    });

    test(
      'H a registry whose incident moved BEFORE the write aborts the write',
      () async {
        final ns = _Namespace();
        final prefs = _Prefs(ns);
        final store = SharedPrefsPaymentAttemptStore(
          prefs,
          backingReader: _Reader(ns),
        );
        final parent = _refusedParent('op-moved');
        _seed(ns, _scope, <Object?>[_entryWithActiveBlock(parent)]);
        final built = _registryFor(parent);
        final k = PaymentActivityKey(scope: _scope, orderId: _orderId);
        final incident = built.registry.incidentOf(k)!;

        // Another writer cleared the incident first.
        final moved = PaymentSafetyRegistry(
          built.registry.owners,
          const <PaymentActivityKey, PaymentFailClosedIncident>{},
        );
        final writesBefore = prefs.writes;

        final out = await store.resolveIncidentApplied(
          scope: _scope,
          registry: moved,
          incident: incident,
          expectedOwnerToken: built.token,
          expectedOccurrence: const BlockOccurrence(1, 'block-1'),
          expectedSafetyEpoch: built.epoch,
          freshTruth: _truth,
          at: '2026-09-09T12:03:00.000Z',
          sameWorld: true,
        );
        expect(out, isA<IncidentResolutionRefusedOccurrence>());
        expect(
          prefs.writes,
          writesBefore,
          reason: 'nothing may be written once the registry disagrees',
        );
        expect(
          PaymentAttempt.fromJson(
            paymentAttemptProjection(_storedEntries(ns, _scope).single),
          ).phase,
          PaymentAttemptPhase.refused,
        );
      },
    );

    test(
      'H an absent ACTIVE block is refused: a resolution needs one',
      () async {
        final ns = _Namespace();
        final store = SharedPrefsPaymentAttemptStore(
          _Prefs(ns),
          backingReader: _Reader(ns),
        );
        final parent = _refusedParent('op-noblock');
        _seed(ns, _scope, <Object?>[parent.toJson()]); // NO block
        final built = _registryFor(parent);
        final k = PaymentActivityKey(scope: _scope, orderId: _orderId);

        final out = await store.resolveIncidentApplied(
          scope: _scope,
          registry: built.registry,
          incident: built.registry.incidentOf(k)!,
          expectedOwnerToken: built.token,
          expectedOccurrence: const BlockOccurrence(1, 'block-1'),
          expectedSafetyEpoch: built.epoch,
          freshTruth: _truth,
          at: '2026-09-09T12:03:00.000Z',
          sameWorld: true,
        );
        expect(out, isA<IncidentResolutionSubjectUnusable>());
        expect(
          (out as IncidentResolutionSubjectUnusable).selection,
          isA<SubjectBlockAbsent>(),
        );
      },
    );

    test('G a promotion whose parent is GONE writes nothing', () async {
      final ns = _Namespace();
      final prefs = _Prefs(ns);
      final store = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: _Reader(ns),
      );
      final parent = _refusedParent('op-gone');
      _seed(ns, _scope, <Object?>[]); // the record is not on disk
      final built = _registryFor(parent);
      final k = PaymentActivityKey(scope: _scope, orderId: _orderId);
      final writesBefore = prefs.writes;

      final out = await store.promoteIncidentToDurable(
        scope: _scope,
        registry: built.registry,
        incident: built.registry.incidentOf(k)!,
        expectedOwnerToken: built.token,
        expectedSafetyEpoch: built.epoch,
        blockId: 'block-1',
        at: '2026-09-09T12:02:00.000Z',
      );
      expect(out, isA<IncidentPromotionSubjectUnusable>());
      expect(prefs.writes, writesBefore);
    });

    test('§8 preservation: an UNREADABLE sibling entry survives the APPLIED '
        'write byte-for-byte', () async {
      final ns = _Namespace();
      final store = SharedPrefsPaymentAttemptStore(
        _Prefs(ns),
        backingReader: _Reader(ns),
      );
      final parent = _refusedParent('op-preserve');
      // It names a DIFFERENT order: an entry that cannot name its order at all
      // blocks EVERY order by the shipped rule, which is asserted separately.
      final foreign = <String, Object?>{
        'order_id': 'order-OTHER',
        'unknown_shape': 'keep me verbatim',
      };
      _seed(ns, _scope, <Object?>[foreign, _entryWithActiveBlock(parent)]);
      final frozen = jsonEncode(foreign);
      final built = _registryFor(parent);
      final k = PaymentActivityKey(scope: _scope, orderId: _orderId);

      final out = await store.resolveIncidentApplied(
        scope: _scope,
        registry: built.registry,
        incident: built.registry.incidentOf(k)!,
        expectedOwnerToken: built.token,
        expectedOccurrence: const BlockOccurrence(1, 'block-1'),
        expectedSafetyEpoch: built.epoch,
        freshTruth: _truth,
        at: '2026-09-09T12:03:00.000Z',
        sameWorld: true,
      );
      expect(out, isA<IncidentResolvedApplied>());

      final entries = _storedEntries(ns, _scope);
      expect(entries, hasLength(2));
      expect(
        jsonEncode(entries.first),
        frozen,
        reason: 'an entry this build cannot read is never rewritten',
      );
    });
  });

  // =========================================================================
  // E — K3-B06: public money truth
  // =========================================================================
  group('K3-B06 public money truth', () {
    test('B06-1 an accepted outcome whose local save failed is STILL '
        'accepted-class, and says the record is not the proof', () {
      final parent = _mint('op-money').markSent('2026-09-09T12:00:00.000Z');
      final accepted = parent.accepted(
        _resolution,
        at: '2026-09-09T12:03:00.000Z',
        reserveEffects: true,
      );
      final outcome = PaymentAttemptAccepted(
        attempt: accepted,
        payment: accepted.payment!,
        replay: true,
        automaticEffectsArmed: false,
        localSaveFailed: true,
      );
      expect(moneyTruthOf(outcome), MoneyTruthView.movedUnproven);
      expect(eligibilityOf(outcome), NewIdentityEligibility.forbidden);
    });

    test('B06 rule B: a LIVE DURABLE ACCEPTED record outranks a later refusal, '
        'and the store hands back the record that STANDS', () async {
      final ns = _Namespace();
      final store = SharedPrefsPaymentAttemptStore(
        _Prefs(ns),
        backingReader: _Reader(ns),
      );
      final base = _mint('op-ruleB').markSent('2026-09-09T12:00:00.000Z');
      final accepted = base.accepted(
        _resolution,
        at: '2026-09-09T12:03:00.000Z',
        reserveEffects: true,
      );
      _seed(ns, _scope, <Object?>[accepted.toJson()]);

      // A late refusal for the SAME operation arrives.
      final lateRefusal = base.refused(
        PaymentRefusalCode.shiftRequired,
        at: '2026-09-09T12:05:00.000Z',
        memoized: true,
      );
      final merge = await store.update(_scope, lateRefusal);

      expect(merge.writes, isFalse, reason: 'the downgrade is refused on disk');
      expect(
        merge.outcome,
        PaymentAttemptMergeOutcome.conflict,
        reason: 'two different terminal answers for one decision',
      );
      // `merge.record` is the record that STANDS — the accepted one. This is
      // what the controller now publishes, instead of reporting a refusal for
      // captured money.
      expect(merge.record.phase, PaymentAttemptPhase.accepted);
      expect(merge.record.payment, isNotNull);
      expect(
        moneyTruthOf(
          PaymentAttemptAccepted(
            attempt: merge.record,
            payment: merge.record.payment!,
            replay: true,
            automaticEffectsArmed: false,
            localSaveFailed: false,
          ),
        ),
        MoneyTruthView.moved,
      );

      // And the stored bytes still hold the acceptance.
      expect(
        PaymentAttempt.fromJson(
          paymentAttemptProjection(_storedEntries(ns, _scope).single),
        ).phase,
        PaymentAttemptPhase.accepted,
      );
    });

    test('B06 the corrected identity eligibility', () {
      final a = _mint('op-elig').markSent('2026-09-09T12:00:00.000Z');

      // No second tender, ever.
      expect(
        eligibilityOf(PaymentAttemptSettledElsewhere(a)),
        NewIdentityEligibility.forbidden,
      );
      // Resume the SAME attempt; do NOT mint.
      expect(
        eligibilityOf(PaymentAttemptNotApplied(a)),
        NewIdentityEligibility.sameAttemptOnly,
      );
      expect(
        eligibilityOf(PaymentAttemptAuthRequired(a)),
        NewIdentityEligibility.sameAttemptOnly,
      );
      // A send is already in flight.
      expect(
        eligibilityOf(PaymentAttemptBusy(a)),
        NewIdentityEligibility.forbidden,
      );
      // A refusal permits a LINKED correction.
      expect(
        eligibilityOf(
          PaymentAttemptRefused(
            attempt: a,
            code: PaymentRefusalCode.shiftRequired,
          ),
        ),
        NewIdentityEligibility.linkedCorrectionOnly,
      );
      // Nothing was minted, stored or sent.
      expect(
        eligibilityOf(const PaymentAttemptSaveBlocked()),
        NewIdentityEligibility.freshMintAllowed,
      );
    });

    test('B06 a status of NOTHING PENDING does not, by itself, authorise a '
        'fresh mint', () {
      final reading = readStatusCheck(
        const PaymentAttemptStatusNothingPending(),
        const PostureFailClosed(IncidentReason.ownerBContradiction),
        NewIdentityEligibility.forbidden,
      );
      expect(reading.outcome, isNull);
      expect(reading.money, MoneyTruthView.nothingSent);
      expect(
        reading.eligibility,
        NewIdentityEligibility.forbidden,
        reason: 'eligibility comes from the authoritative state, not the label',
      );
      expect(reading.safety, isA<PostureFailClosed>());
    });

    test('B06 a resolved status never erases a standing fail-closed posture '
        'and never contradicts moneyTruthOf', () {
      final a = _mint('op-status').markSent('2026-09-09T12:00:00.000Z');
      final outcome = PaymentAttemptUnconfirmed(
        attempt: a,
        reason: PaymentUnconfirmedReason.transport,
      );
      final reading = readStatusCheck(
        PaymentAttemptStatusResolved(outcome),
        const PostureFailClosed(IncidentReason.ownerBContradiction),
        NewIdentityEligibility.forbidden,
      );
      expect(reading.money, moneyTruthOf(outcome));
      expect(reading.safety, isA<PostureFailClosed>());
    });

    test('B06 money truth and safety posture are ORTHOGONAL: a fail-closed '
        'posture does not erase known accepted money', () {
      final parent = _refusedParent('op-orth');
      final safety = SafetyDurableBlocked(
        const BlockOccurrence(1, 'block-1'),
        _activeBlock(parent),
        parent,
      );
      expect(postureOf(safety), isA<PostureFailClosed>());
      expect(
        acceptedIncidentTruthOf(safety),
        isNotNull,
        reason: 'OD-1 must see the accepted truth a durable block carries',
      );
      expect(eligibilityOfSafety(safety), NewIdentityEligibility.forbidden);
    });

    test('OD-1 an accepted-class incident keeps conflicting refusal evidence '
        'beside it, and never lets it resolve or clear', () {
      final parent = _refusedParent('op-od1b');
      final incident = _incidentFor(parent);
      final withEvidence = incident.withConflictingEvidence(
        const MemoizedRefusalTruth(PaymentRefusalCode.shiftRequired),
      );
      expect(withEvidence.state, IncidentState.active);
      expect(withEvidence.serverTruth, _truth, reason: 'truth is unchanged');
      expect(withEvidence.conflictingDiagnosticEvidence, hasLength(1));
      expect(withEvidence.acceptedTruth, isNotNull);
      expect(acceptedIncidentTruthOf(SafetyIncident(withEvidence)), isNotNull);
      expect(
        eligibilityOfSafety(SafetyIncident(withEvidence)),
        NewIdentityEligibility.forbidden,
      );
    });
  });

  // =========================================================================
  // F — A-M, the cases the kernel document adjudicated in prose
  // =========================================================================
  group('A-M executable coverage', () {
    test('A a PENDING record can never carry an effect claim', () {
      final j = _mint('op-A').markSent('2026-09-09T12:00:00.000Z').toJson();
      j['auto_effects_reserved_at'] = '2026-09-09T12:01:00.000Z';
      // Unrepresentable, not merely disallowed: the decoder refuses a pending
      // record that carries a one-time effect claim. It reaches the
      // claim-without-resolution rule first, which is the same invariant seen
      // from the other side.
      expect(
        () => PaymentAttempt.fromJson(j),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('effect claim'),
          ),
        ),
      );

      // And with a resolution added it is refused as a pending record instead.
      final withResolution = <String, Object?>{
        ...j,
        'resolved_at': '2026-09-09T12:01:00.000Z',
        'resolution': _resolution.toJson(),
      };
      expect(
        () => PaymentAttempt.fromJson(withResolution),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('pending with a resolution'),
          ),
        ),
      );
    });

    test('B accepted and refused are never the same terminal answer', () {
      final base = _mint('op-B').markSent('2026-09-09T12:00:00.000Z');
      final accepted = base.accepted(
        _resolution,
        at: '2026-09-09T12:03:00.000Z',
        reserveEffects: true,
      );
      final refused = base.refused(
        PaymentRefusalCode.shiftRequired,
        at: '2026-09-09T12:03:00.000Z',
        memoized: true,
      );
      expect(accepted.sameTerminalAnswerAs(refused), isFalse);
      expect(
        reconcilePaymentAttempt(refused, accepted).outcome,
        PaymentAttemptMergeOutcome.conflict,
      );
    });

    // C, D — see the K3-B03 group (stale reservation, A2 release).

    test('E a diagnostic never becomes a refusal', () {
      final a = _mint('op-E').markSent('2026-09-09T12:00:00.000Z');
      final diagnostic = PaymentAttemptUnconfirmed(
        attempt: a,
        reason: PaymentUnconfirmedReason.transport,
      );
      expect(moneyTruthOf(diagnostic), MoneyTruthView.mayHaveMoved);
      expect(
        moneyTruthOf(
          PaymentAttemptRefused(
            attempt: a,
            code: PaymentRefusalCode.shiftRequired,
          ),
        ),
        MoneyTruthView.didNotMove,
      );
      // The diagnostic truth keeps its EXACT reason.
      final t = DiagnosticTruth.unconfirmed(
        PaymentUnconfirmedReason.identityCollision,
      );
      final back = decodeServerTruth(t.toJson()) as ServerTruthOk;
      expect(
        (back.truth as DiagnosticTruth).unconfirmedReason,
        PaymentUnconfirmedReason.identityCollision,
      );
    });

    test('F a storage failure never releases a fail-closed owner', () {
      final parent = _refusedParent('op-F');
      final built = _registryFor(parent);
      final k = PaymentActivityKey(scope: _scope, orderId: _orderId);
      // Unknown durability is NOT a release.
      expect(built.registry.ownerOf(k)!.handoff.isFailClosed, isTrue);
      final snapshotFailure = hydratePaymentSafety(
        snapshotResult: SnapshotUntrusted(
          context: EnvelopeSnapshotContext(
            PaymentEnvelopeIdentity.fromScope(_scope, _orderId),
            0,
            SnapshotTrust.untrusted,
          ),
          reason: UntrustedReason.noIndependentReader,
        ),
        registry: built.registry,
      );
      expect(snapshotFailure, isA<SafetyEnvelopeFailClosed>());
      expect(
        eligibilityOfSafety(snapshotFailure),
        NewIdentityEligibility.forbidden,
      );
    });

    // G — see 'a promotion whose parent is GONE writes nothing'.
    // H, I — see the K3-B05 and K3-B04 groups.

    test('J a colliding generated id refuses only the candidate', () {
      // `FixedClientIdGenerator` repeats its LAST id forever, so occurrence
      // uniqueness must not rest on the id source.
      final ids = FixedClientIdGenerator(<String>['only-one']);
      expect(ids.newId(), 'only-one');
      expect(ids.newId(), 'only-one', reason: 'it repeats, by design');
      // The GENERATION is what separates two occurrences.
      expect(
        const BlockOccurrence(1, 'only-one'),
        isNot(const BlockOccurrence(2, 'only-one')),
      );
    });

    test(
      'K an identifier-less unrelated record does not brick every order',
      () {
        // A quarantine that CAN name its order blocks only that order.
        final other = CanonicalOrderId.tryFrom('order-2')!;
        final blocked = SafetyRecordQuarantined(0, _orderId.value);
        expect(blocked.orderId, _orderId.value);
        expect(blocked.orderId, isNot(other.value));
        // And one that cannot name it blocks everything — the shipped rule.
        const blanket = SafetyRecordQuarantined(0, null);
        expect(blanket.orderId, isNull);
      },
    );

    test('L a same-operation caller that disagrees on caller-real fields is '
        'rejected', () {
      final a = _mint('op-L');
      expect(
        a.sameDecision(
          orderId: _orderId.value,
          tenderType: 'cash',
          amountMinor: 4000,
          amountTenderedMinor: 5000,
          currencyCode: 'ILS',
        ),
        isTrue,
      );
      expect(
        a.sameDecision(
          orderId: _orderId.value,
          tenderType: 'cash',
          amountMinor: 9999, // a DIFFERENT amount
          amountTenderedMinor: 5000,
          currencyCode: 'ILS',
        ),
        isFalse,
      );
    });

    test(
      'M an accepted record already holding an effect claim cannot re-arm',
      () {
        final a = _mint('op-M').markSent('2026-09-09T12:00:00.000Z');
        final first = a.accepted(
          _resolution,
          at: '2026-09-09T12:03:00.000Z',
          reserveEffects: true,
        );
        expect(first.autoEffectsReservedAt, isNotNull);
        // A second acceptance cannot move the one-time claim.
        final second = first.accepted(
          _resolution,
          at: '2026-09-09T12:09:00.000Z',
          reserveEffects: true,
        );
        expect(second.autoEffectsReservedAt, first.autoEffectsReservedAt);
      },
    );
  });
}

/// A fresh empty registry, spelled once.
PaymentSafetyRegistry reg0() => PaymentSafetyRegistry.empty();
