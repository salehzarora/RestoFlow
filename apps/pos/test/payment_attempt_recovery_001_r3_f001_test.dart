// PAYMENT-ATTEMPT-RECOVERY-001 / S1-R3 — the PHYSICAL-KEY lifetime regressions.
//
// These are the SAFETY twins of the seven `F001-NEG-*` bug demonstrations in
// Codex's external harness `reviewer_f001_lifetime_test.dart` (SHA-256
// FB8537A1129A10BCD9678ECA70578B125EC95BDAB4515596FF779A5DD1E714A7). That
// harness passes ONLY when the unsafe result is observed, so it is a record of
// the defect and is deliberately NOT committed as a green regression: it is
// kept immutable outside the repository, and after this correction it fails.
//
// Each test below keeps the original's composition and its exact write-failure
// schedule and asserts the REQUIRED SAFE outcome instead. The one difference in
// mechanism is stated where it occurs: the two overlapping-write cases now
// capture the concurrent claim's typed refusal before releasing the held
// platform write, because the corrected build refuses that claim rather than
// adopting optimistic bytes.
//
// The eighth case, the same-writer positive control, is carried over unchanged
// so the containment cannot pass by disabling ordinary progress.
//
// Synthetic local storage only: no network, no hosted service, no device.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_attempt.dart';
import 'package:restoflow_pos/src/data/payment_attempt_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosPersistenceException, PosSyncScope;
import 'package:shared_preferences/shared_preferences.dart';

const _scopeA = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'restaurant-1',
  branchId: 'branch-1',
  deviceId: 'device-1',
);

String get _logicalKey => paymentAttemptsStorageKey(_scopeA.key);
String get _physicalKey => paymentAttemptsPhysicalKey(_scopeA.key);

PaymentAttempt _attempt(String operationId) => PaymentAttempt.mint(
  ids: FixedClientIdGenerator([operationId, '$operationId-target']),
  now: DateTime.utc(2026, 9, 9, 12),
  orderId: 'order-1',
  orderNumber: '#R-1',
  amountMinor: 4000,
  tenderedMinor: 5000,
  currencyCode: 'ILS',
  method: PaymentMethod.cash,
  expectedRevision: 7,
  organizationId: _scopeA.organizationId,
  restaurantId: _scopeA.restaurantId,
  branchId: _scopeA.branchId,
  deviceId: _scopeA.deviceId,
  employeeProfileId: 'employee-1',
);

PaymentAttemptResolution get _resolution => const PaymentAttemptResolution(
  paymentId: 'payment-1',
  receiptNumber: 'receipt-1',
  changeDueMinor: 1000,
  method: PaymentMethod.cash,
  replay: false,
  orderStatus: 'completed',
);

String _logical(String physicalKey) =>
    physicalKey.startsWith(kLegacySharedPreferencesKeyPrefix)
    ? physicalKey.substring(kLegacySharedPreferencesKeyPrefix.length)
    : physicalKey;

/// One physical namespace with two deliberately distinct views:
/// [visible] models the process/plugin-visible value after a cache-first write;
/// [durable] models the bytes that actually reached persistent storage.
class _PhysicalNamespace {
  final Map<String, String> visible = <String, String>{};
  final Map<String, String> durable = <String, String>{};
}

enum _Failure { none, returnsFalse, throws }

/// A writer wrapper with its own Dart-side cache over one physical namespace.
/// Constructing a second instance is the exact writer-identity falsification:
/// it addresses the same key/backend but is a different Dart object.
class _WriterPrefs implements SharedPreferences {
  _WriterPrefs(
    this.namespace, {
    this.failure = _Failure.none,
    bool seedFromVisible = true,
  }) {
    cache.addAll(seedFromVisible ? namespace.visible : namespace.durable);
  }

  final _PhysicalNamespace namespace;
  final Map<String, String> cache = <String, String>{};
  _Failure failure;

  @override
  String? getString(String key) => cache[key];

  @override
  Future<bool> setString(String key, String value) async {
    cache[key] = value;
    namespace.visible[key] = value;
    switch (failure) {
      case _Failure.none:
        namespace.durable[key] = value;
        return true;
      case _Failure.returnsFalse:
        return false;
      case _Failure.throws:
        throw StateError('synthetic platform write failure');
    }
  }

  @override
  Future<bool> remove(String key) async {
    cache.remove(key);
    namespace.visible.remove(key);
    namespace.durable.remove(key);
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

class _DurableReader implements PaymentAttemptBackingReader {
  const _DurableReader(this.namespace);
  final _PhysicalNamespace namespace;

  @override
  Future<String?> readRaw(String physicalKey) async =>
      namespace.durable[_logical(physicalKey)];
}

/// A cache-first writer whose first write can be held in-flight. The legacy
/// adapter-visible value changes before the platform result is delivered.
class _DelayedWriterPrefs extends _WriterPrefs {
  _DelayedWriterPrefs(super.namespace, this.finalFailure);

  final _Failure finalFailure;
  final Completer<void> writeEntered = Completer<void>();
  final Completer<void> releaseWrite = Completer<void>();

  @override
  Future<bool> setString(String key, String value) async {
    cache[key] = value;
    namespace.visible[key] = value;
    if (!writeEntered.isCompleted) writeEntered.complete();
    await releaseWrite.future;
    if (finalFailure == _Failure.throws) {
      throw StateError('synthetic delayed platform write failure');
    }
    if (finalFailure == _Failure.returnsFalse) return false;
    namespace.durable[key] = value;
    return true;
  }
}

/// Source-faithful model of the installed Linux/Windows async plugin cache:
/// the first read snapshots the backing map and later reads reuse that snapshot
/// until an explicit reload the product never performs.
class _StickyAsyncBackingReader implements PaymentAttemptBackingReader {
  _StickyAsyncBackingReader(this.namespace);
  final _PhysicalNamespace namespace;
  Map<String, String>? _cachedPreferences;

  @override
  Future<String?> readRaw(String physicalKey) async {
    _cachedPreferences ??= Map<String, String>.from(namespace.durable);
    return _cachedPreferences![_logical(physicalKey)];
  }
}

Future<Object?> _capture(Future<Object?> future) =>
    future.then<Object?>((value) => value, onError: (Object error, _) => error);

List<Object?> _durableAttempts(_PhysicalNamespace namespace) {
  final raw = namespace.durable[_logicalKey];
  if (raw == null) return const <Object?>[];
  return (jsonDecode(raw) as Map)['attempts'] as List<Object?>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The physical-key trust boundary is isolate-wide by design, so each test
  // starts from a clean one. Only a real process restart clears it in
  // production, and a restart is a new isolate.
  setUp(resetPaymentAttemptKeyGuardsForTest);

  for (final failure in <_Failure>[_Failure.returnsFalse, _Failure.throws]) {
    test('S1R3-F001-WRAPPER-${failure.name}: a distinct writer wrapper over '
        'the same namespace/key INHERITS the containment', () async {
      final namespace = _PhysicalNamespace();
      final firstWriter = _WriterPrefs(namespace, failure: failure);
      final reader = _DurableReader(namespace);
      final firstStore = SharedPrefsPaymentAttemptStore(
        firstWriter,
        backingReader: reader,
      );
      final original = _attempt('op-original-${failure.name}');

      final failed = await _capture(
        firstStore.createIfAbsent(_scopeA, original),
      );
      expect(failed, isA<PosPersistenceException>());
      expect(namespace.durable, isEmpty);
      expect(
        paymentAttemptAdapterIsUntrusted(firstWriter, _physicalKey),
        isTrue,
      );

      // New object, identical physical namespace/key. It inherits the lower
      // process-visible phantom in its own cache — and, now, the containment.
      final secondWriter = _WriterPrefs(namespace);
      final secondStore = SharedPrefsPaymentAttemptStore(
        secondWriter,
        backingReader: reader,
      );
      expect(
        paymentAttemptAdapterIsUntrusted(secondWriter, _physicalKey),
        isTrue,
        reason:
            'the boundary is the physical namespace/key, not one Dart object',
      );
      expect(
        secondWriter.cache[_logicalKey],
        isNotNull,
        reason: 'the phantom really is visible to this wrapper',
      );

      final loaded = await secondStore.load(_scopeA);
      expect(
        loaded.attempts,
        isEmpty,
        reason: 'the read came from the independent backing, which is empty',
      );
      expect(loaded.quarantined, isEmpty);

      final retry = await secondStore.createIfAbsent(
        _scopeA,
        _attempt('op-retry-${failure.name}'),
      );
      expect(
        retry.created,
        isTrue,
        reason:
            'nothing was ever durable for this order, so the retry is a real '
            'new attempt rather than an adoption of a phantom',
      );
      expect(retry.attempt.localOperationId, 'op-retry-${failure.name}');
      expect(_durableAttempts(namespace), hasLength(1));
      expect(
        (_durableAttempts(namespace).single as Map)['local_operation_id'],
        'op-retry-${failure.name}',
      );
    });
  }

  test('S1R3-F001-PROVIDER-REBIND: a replacement store reached through the real '
      'provider route cannot consume the in-flight optimistic cache', () async {
    final namespace = _PhysicalNamespace();
    final prefs = _DelayedWriterPrefs(namespace, _Failure.returnsFalse);
    final reader = _DurableReader(namespace);
    final firstStore = SharedPrefsPaymentAttemptStore(
      prefs,
      backingReader: reader,
    );
    final replacementStore = SharedPrefsPaymentAttemptStore(
      prefs,
      backingReader: reader,
    );
    final container = ProviderContainer(
      overrides: <Override>[
        paymentAttemptStoreProvider.overrideWithValue(firstStore),
      ],
    );
    addTearDown(container.dispose);

    final original = _attempt('op-provider-old');
    final oldOutcome = _capture(
      container
          .read(paymentAttemptStoreProvider)
          .createIfAbsent(_scopeA, original),
    );
    await prefs.writeEntered.future;
    expect(
      paymentAttemptAdapterIsUntrusted(prefs, _physicalKey),
      isTrue,
      reason: 'the boundary is entered BEFORE the platform result arrives',
    );

    // This is the same override-update mechanism used when main.dart sees a
    // new PosDeviceSeams identity and rebuilds its overrides.
    container.updateOverrides(<Override>[
      paymentAttemptStoreProvider.overrideWithValue(replacementStore),
    ]);
    final rebound = container.read(paymentAttemptStoreProvider);
    expect(identical(rebound, replacementStore), isTrue);

    // CHANGED MECHANISM, stated: the original harness awaited this claim before
    // releasing the held write, which was only possible because the old build
    // answered it immediately from the optimistic cache. The corrected build
    // refuses it, so the refusal is captured rather than thrown into the test.
    final adopted = await _capture(
      rebound.createIfAbsent(_scopeA, _attempt('op-provider-new')),
    );

    prefs.releaseWrite.complete();
    expect(await oldOutcome, isA<PosPersistenceException>());
    expect(
      adopted,
      isA<PosPersistenceException>(),
      reason:
          'a replacement store may wait or fail closed, never adopt bytes a '
          'still-unresolved write left in the cache',
    );
    expect(namespace.durable, isEmpty);
    expect(paymentAttemptAdapterIsUntrusted(prefs, _physicalKey), isTrue);
  });

  test(
    'S1R3-F001-ACCEPTED: a failed accepted-state save cannot be laundered into '
    'authority by recreating the writer wrapper',
    () async {
      final namespace = _PhysicalNamespace();
      final firstWriter = _WriterPrefs(namespace);
      final reader = _DurableReader(namespace);
      final firstStore = SharedPrefsPaymentAttemptStore(
        firstWriter,
        backingReader: reader,
      );
      final pending = _attempt('op-accepted');
      expect(
        (await firstStore.createIfAbsent(_scopeA, pending)).created,
        isTrue,
      );

      firstWriter.failure = _Failure.returnsFalse;
      final failed = await _capture(
        firstStore.resolveAccepted(
          _scopeA,
          pending,
          _resolution,
          at: '2026-09-09T12:01:00.000Z',
          armCaller: true,
        ),
      );
      expect(failed, isA<PosPersistenceException>());
      expect(
        paymentAttemptAdapterIsUntrusted(firstWriter, _physicalKey),
        isTrue,
      );

      final durableEnvelope =
          jsonDecode(namespace.durable[_logicalKey]!) as Map;
      final durableAttempt =
          (durableEnvelope['attempts'] as List).single as Map;
      expect(durableAttempt['phase'], 'pending');

      final recreatedWriter = _WriterPrefs(namespace);
      final recreatedStore = SharedPrefsPaymentAttemptStore(
        recreatedWriter,
        backingReader: reader,
      );
      expect(
        paymentAttemptAdapterIsUntrusted(recreatedWriter, _physicalKey),
        isTrue,
      );

      final observed = await recreatedStore.load(_scopeA);
      expect(
        observed.attempts.single.phase,
        PaymentAttemptPhase.pending,
        reason: 'the durable record is what the store reports, not the cache',
      );
      expect(
        observed.attempts.single.autoEffectsReservedAt,
        isNull,
        reason: 'an unwritten one-time effect claim was never taken',
      );
      expect(
        namespace.durable[_logicalKey],
        isNot(recreatedWriter.cache[_logicalKey]),
        reason: 'the phantom is still in the cache; it is simply not believed',
      );
    },
  );

  for (final failure in <_Failure>[_Failure.returnsFalse, _Failure.throws]) {
    test('S1R3-F001-RACE-${failure.name}: an overlapping store cannot adopt '
        'the phantom while the first write is still unresolved', () async {
      final namespace = _PhysicalNamespace();
      final prefs = _DelayedWriterPrefs(namespace, failure);
      final reader = _DurableReader(namespace);
      final oldStore = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: reader,
      );
      final newStore = SharedPrefsPaymentAttemptStore(
        prefs,
        backingReader: reader,
      );
      final original = _attempt('op-race-old-${failure.name}');

      final oldOutcome = _capture(oldStore.createIfAbsent(_scopeA, original));
      await prefs.writeEntered.future;
      expect(
        paymentAttemptAdapterIsUntrusted(prefs, _physicalKey),
        isTrue,
        reason:
            'the mark is installed BEFORE the cache-mutating call, not after '
            'the platform result',
      );

      // CHANGED MECHANISM, stated: as in the provider case, the concurrent
      // claim is captured because the corrected build refuses it instead of
      // answering it from the optimistic cache.
      final concurrentClaim = await _capture(
        newStore.createIfAbsent(
          _scopeA,
          _attempt('op-race-new-${failure.name}'),
        ),
      );
      prefs.releaseWrite.complete();
      final oldResult = await oldOutcome;

      expect(oldResult, isA<PosPersistenceException>());
      expect(concurrentClaim, isA<PosPersistenceException>());
      expect(namespace.durable, isEmpty);
      expect(paymentAttemptAdapterIsUntrusted(prefs, _physicalKey), isTrue);
    });
  }

  test('S1R3-F001-STICKY-READER: a cached platform reader cannot erase a later '
      'genuinely durable record or free a replacement identity', () async {
    final namespace = _PhysicalNamespace();
    final writer = _WriterPrefs(namespace, failure: _Failure.returnsFalse);
    final stickyReader = _StickyAsyncBackingReader(namespace);
    final store = SharedPrefsPaymentAttemptStore(
      writer,
      backingReader: stickyReader,
    );

    final first = await _capture(
      store.createIfAbsent(_scopeA, _attempt('op-sticky-failed')),
    );
    expect(first, isA<PosPersistenceException>());
    expect(namespace.durable, isEmpty);

    writer.failure = _Failure.none;
    final second = await store.createIfAbsent(
      _scopeA,
      _attempt('op-sticky-durable'),
    );
    expect(second.created, isTrue);
    expect(namespace.durable[_logicalKey], isNotNull);

    // A write the platform CONFIRMED is newer than the failure it supersedes,
    // so the key is trusted again and the stale snapshot is never consulted.
    expect(paymentAttemptAdapterIsUntrusted(writer, _physicalKey), isFalse);
    final visible = await store.load(_scopeA);
    expect(
      visible.attempts.single.localOperationId,
      'op-sticky-durable',
      reason: 'a durable record cannot be made invisible by a stale snapshot',
    );

    final third = await store.createIfAbsent(
      _scopeA,
      _attempt('op-sticky-replacement'),
    );
    expect(
      third.created,
      isFalse,
      reason: 'the pending durable attempt is adopted, not replaced',
    );
    expect(third.attempt.localOperationId, 'op-sticky-durable');
    final entries = _durableAttempts(namespace);
    expect(entries, hasLength(1));
    expect(
      (entries.single as Map)['local_operation_id'],
      'op-sticky-durable',
      reason: 'the durable record survived',
    );
  });

  test('S1R3-F001-CONTROL-SAME-WRITER: after failure settles, the same writer '
      'object remains contained and routes reads to durable backing', () async {
    final namespace = _PhysicalNamespace();
    final writer = _WriterPrefs(namespace, failure: _Failure.returnsFalse);
    final store = SharedPrefsPaymentAttemptStore(
      writer,
      backingReader: _DurableReader(namespace),
    );

    final first = await _capture(
      store.createIfAbsent(_scopeA, _attempt('op-control-failed')),
    );
    expect(first, isA<PosPersistenceException>());
    expect(paymentAttemptAdapterIsUntrusted(writer, _physicalKey), isTrue);
    expect((await store.load(_scopeA)).attempts, isEmpty);

    writer.failure = _Failure.none;
    final safe = await store.createIfAbsent(
      _scopeA,
      _attempt('op-control-durable'),
    );
    expect(safe.created, isTrue);
    expect(
      (await store.load(_scopeA)).attempts.single.localOperationId,
      'op-control-durable',
    );
  });

  test('S1R3-F001-CONTROL-UNRELATED-KEY: containing one physical key leaves '
      'every other key and preference untouched', () async {
    const scopeB = PosSyncScope(
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-2',
      deviceId: 'device-1',
    );
    final namespace = _PhysicalNamespace();
    final writer = _WriterPrefs(namespace, failure: _Failure.returnsFalse);
    final store = SharedPrefsPaymentAttemptStore(
      writer,
      backingReader: _DurableReader(namespace),
    );
    namespace.durable['unrelated.setting'] = 'kept';
    writer.cache['unrelated.setting'] = 'kept';

    expect(
      await _capture(store.createIfAbsent(_scopeA, _attempt('op-a'))),
      isA<PosPersistenceException>(),
    );
    expect(paymentAttemptAdapterIsUntrusted(writer, _physicalKey), isTrue);
    expect(
      paymentAttemptAdapterIsUntrusted(
        writer,
        paymentAttemptsPhysicalKey(scopeB.key),
      ),
      isFalse,
      reason: 'an unrelated payment key never inherits the containment',
    );

    writer.failure = _Failure.none;
    final attemptB = PaymentAttempt.mint(
      ids: FixedClientIdGenerator(const ['op-b', 'op-b-target']),
      now: DateTime.utc(2026, 9, 9, 12),
      orderId: 'order-b',
      orderNumber: '#R-B',
      amountMinor: 2500,
      tenderedMinor: 2500,
      currencyCode: 'ILS',
      method: PaymentMethod.cash,
      expectedRevision: 2,
      organizationId: scopeB.organizationId,
      restaurantId: scopeB.restaurantId,
      branchId: scopeB.branchId,
      deviceId: scopeB.deviceId,
      employeeProfileId: 'employee-1',
    );
    expect((await store.createIfAbsent(scopeB, attemptB)).created, isTrue);
    expect(
      namespace.durable['unrelated.setting'],
      'kept',
      reason: 'no unrelated preference was cleared, reloaded or rewritten',
    );
  });
}
