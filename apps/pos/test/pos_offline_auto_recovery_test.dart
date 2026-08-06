// POS-OFFLINE-OPERATIONS-002 Pass B — D8-F2: automatic delivery must survive
// an outage longer than ~100s.
//
// The old contract parked a transiently-failed entry FOREVER once its
// persisted attemptCount reached 5 (`_maxAutoAttempts` as a TERMINAL
// eligibility gate; nothing ever reset the count), so with the 25s sweep tick
// delivery stopped ≈100s into any outage and only a manual Retry-all — worth
// exactly ONE more attempt — could revive it. The new contract implements the
// schedule docs/OFFLINE_SYNC_SPEC.md already prescribed: per-entry
// `nextAttemptAt` = failure time + 2s × 2^min(attempt,8), clamped to 5min,
// with DETERMINISTIC ±20% jitter derived from the localOperationId (no
// Random()); reconnect/startup/resume reset the schedule to "now". There is
// no terminal cap: the 5-minute ceiling is the throttle and idempotent replay
// (D-022) makes extra attempts safe.
//
// Harness: the _ScriptedSyncTransport house pattern (pos_offline_order_flow /
// pos_offline_authhold idiom) over the REAL RealOutboxRepository + controller,
// with an ADVANCEABLE pinned clock (the fixed_pos_clock.dart contract, made
// mutable because backoff is precisely about time moving).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show
        SyncRpcTransport,
        SyncSession,
        SyncTransportErrorKind,
        SyncTransportException;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_pos/src/data/durable_outbox_store.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/state/local_storage_health_provider.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart'
    show posSyncClockProvider;
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_offline_state.dart';
import 'package:restoflow_pos/src/widgets/outbox_status_summary.dart';
import 'package:shared_preferences/shared_preferences.dart';

const SyncSession _session = SyncSession(
  pinSessionId: 'pin-1',
  deviceId: 'dev-1',
);

const _transientFailure = SyncTransportException(
  SyncTransportErrorKind.transient,
  code: 'network',
);

const _applied = <String, Object?>{'ok': true, 'status': 'applied'};

/// An advanceable pinned clock — the fixed_pos_clock contract, mutable.
class _TestClock {
  _TestClock(this.now);
  DateTime now;
}

/// Scripted sync_push transport (the 024/025 idiom): throws or answers each
/// step (the last step repeats) and records every pushed operation identity.
class _ScriptedTransport implements SyncRpcTransport {
  _ScriptedTransport(this._steps);
  final List<Object> _steps;
  int pushes = 0;
  final List<String> pushedLocalOperationIds = [];
  final List<String> pushedDeviceIds = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function != 'sync_push') return <String, dynamic>{'ok': false};
    final op = (params['p_operations'] as List).first as Map;
    pushedLocalOperationIds.add(op['local_operation_id'] as String);
    pushedDeviceIds.add(params['p_device_id'] as String);
    final step = _steps[pushes < _steps.length ? pushes : _steps.length - 1];
    pushes++;
    if (step is SyncTransportException) throw step;
    return <String, dynamic>{
      'ok': true,
      'results': <dynamic>[
        <String, dynamic>{
          'local_operation_id': op['local_operation_id'],
          'operation_type': 'order.submit',
          ...(step as Map).cast<String, Object?>(),
        },
      ],
      'server_ts': '2026-08-06T09:00:01Z',
    };
  }
}

class _MemoryStore implements DurableOutboxStore {
  final Map<String, List<Map<String, Object?>>> saved = {};
  @override
  Future<List<OutboxEntry>> load(String scopeKey) async => [
    for (final j in saved[scopeKey] ?? const <Map<String, Object?>>[])
      OutboxEntry.fromJson(j),
  ];
  @override
  Future<void> persist(String scopeKey, List<OutboxEntry> entries) async {
    saved[scopeKey] = [for (final e in entries) e.toJson()];
  }
}

OutboxEntry _seed({String id = 'e1', String op = 'op-1'}) => OutboxEntry(
  id: id,
  deviceId: 'dev-1',
  localOperationId: op,
  operationType: 'order.submit',
  targetEntity: 'order',
  targetId: 'order-$op',
  payloadJson: '{"order_id":"order-$op","subtotal_minor":4200}',
  summary: const OrderSummary(
    orderNumber: '#3F7A2C',
    orderType: OrderType.takeaway,
    tableLabel: null,
    itemCount: 1,
    subtotalMinor: 4200,
    currencyCode: 'ILS',
  ),
  syncState: OutboxSyncState.pending,
  clientCreatedAt: DateTime.utc(2026, 8, 6),
);

final DateTime _t0 = DateTime.utc(2026, 8, 6, 9);

({
  ProviderContainer container,
  OutboxController controller,
  _ScriptedTransport transport,
  DurableOutboxStore store,
  _TestClock clock,
})
_wire(
  List<Object> steps, {
  List<OutboxEntry> preload = const [],
  DurableOutboxStore? store,
}) {
  final clock = _TestClock(_t0);
  final transport = _ScriptedTransport(steps);
  final s = store ?? _MemoryStore();
  if (preload.isNotEmpty && s is _MemoryStore) {
    s.saved['dev-1'] = [for (final e in preload) e.toJson()];
  }
  final repo = RealOutboxRepository(
    transport,
    _session,
    store: s,
    now: () => clock.now,
  );
  final container = ProviderContainer(
    overrides: [
      outboxRepositoryProvider.overrideWithValue(repo),
      posSyncClockProvider.overrideWithValue(() => clock.now),
    ],
  );
  addTearDown(container.dispose);
  return (
    container: container,
    controller: container.read(outboxControllerProvider.notifier),
    transport: transport,
    store: s,
    clock: clock,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('1. an outage beyond the old 5-attempt cap keeps delivering: the 6th+ '
      'attempt still runs and the recovery applies exactly one op', () async {
    final w = _wire([for (var i = 0; i < 6; i++) _transientFailure, _applied]);
    final repo = w.container.read(outboxRepositoryProvider);
    await repo.enqueue(_seed());
    await w.controller.pushEntry('e1');
    await pumpEventQueue();
    expect(w.transport.pushes, 1);

    // Five more failing sweeps, each after its own honest backoff — the OLD
    // contract would have gone dormant after attempt 5.
    for (var attempt = 2; attempt <= 6; attempt++) {
      final entry = w.controller.entryById('e1')!;
      expect(entry.nextAttemptAt, isNotNull);
      w.clock.now = entry.nextAttemptAt!;
      await w.controller.pushQueued();
      await pumpEventQueue();
      expect(w.transport.pushes, attempt, reason: 'attempt $attempt must run');
      expect(w.controller.entryById('e1')!.attemptCount, attempt);
    }

    // The backend recovers: the SEVENTH attempt applies.
    w.clock.now = w.controller.entryById('e1')!.nextAttemptAt!;
    await w.controller.pushQueued();
    await pumpEventQueue();
    expect(w.transport.pushes, 7);
    final entry = w.controller.entryById('e1')!;
    expect(entry.syncState, OutboxSyncState.applied);
    expect(entry.outcome, PosOrderOutcome.accepted);
    // ONE operation identity on EVERY envelope — the server dedupes on it, so
    // seven attempts can never become a second order (D-022).
    expect(w.transport.pushedLocalOperationIds.toSet(), <String>{'op-1'});
    expect(w.transport.pushedDeviceIds.toSet(), <String>{'dev-1'});
  });

  test('2. the backoff schedule is honored: not due before nextAttemptAt, due '
      'at it — and the schedule is the deterministic pinned value', () async {
    final w = _wire([_transientFailure, _applied]);
    final repo = w.container.read(outboxRepositoryProvider);
    await repo.enqueue(_seed());
    await w.controller.pushEntry('e1');
    await pumpEventQueue();
    expect(w.transport.pushes, 1);

    final entry = w.controller.entryById('e1')!;
    // Deterministic jitter: the exact schedule is a pure function of the
    // attempt count and the operation id — pin it, and bound it to ±20%.
    final expected = outboxRetryBackoff(1, 'op-1');
    expect(entry.nextAttemptAt, _t0.add(expected));
    expect(
      expected.inMilliseconds,
      inInclusiveRange(3200, 4800),
      reason: '2s × 2^1 = 4s ± 20%',
    );

    // One microsecond early: the sweep SKIPS it (no transport spend).
    w.clock.now = _t0.add(expected - const Duration(microseconds: 1));
    await w.controller.pushQueued();
    await pumpEventQueue();
    expect(w.transport.pushes, 1, reason: 'not due yet — sweep must skip');
    expect(w.controller.entryById('e1')!.syncState, OutboxSyncState.rejected);

    // Exactly at the boundary: due.
    w.clock.now = _t0.add(expected);
    await w.controller.pushQueued();
    await pumpEventQueue();
    expect(w.transport.pushes, 2);
    expect(w.controller.entryById('e1')!.syncState, OutboxSyncState.applied);
  });

  test('3. resume/startup: pushQueued(resetBackoff: true) makes a far-future '
      'schedule immediately eligible', () async {
    final farFuture = _t0.add(const Duration(hours: 6));
    final w = _wire(
      [_applied],
      preload: [
        _seed().copyWith(
          syncState: OutboxSyncState.rejected,
          attemptCount: 9,
          lastErrorCode: 'network',
          lastErrorKind: 'transient',
          nextAttemptAt: farFuture,
        ),
      ],
    );
    await pumpEventQueue(); // recovery sweep — the entry is NOT due
    expect(w.transport.pushes, 0);
    await w.controller.pushQueued(); // plain sweep — still not due
    await pumpEventQueue();
    expect(w.transport.pushes, 0);

    await w.controller.pushQueued(resetBackoff: true);
    await pumpEventQueue();
    expect(w.transport.pushes, 1, reason: 'reset makes it due NOW');
    expect(w.controller.entryById('e1')!.syncState, OutboxSyncState.applied);
  });

  test('4. process restart: next_attempt_at round-trips through the durable '
      'store; a not-yet-due entry waits, a due entry syncs on the FIRST '
      'sweep', () async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final clock = _TestClock(_t0);
    DurableOutboxStore store() => SharedPrefsOutboxStore(prefs);

    // Container 1: enqueue + one failing push stamps the schedule durably.
    final t1 = _ScriptedTransport(const [_transientFailure]);
    final repo1 = RealOutboxRepository(
      t1,
      _session,
      store: store(),
      now: () => clock.now,
    );
    await repo1.enqueue(_seed());
    await repo1.push('e1');
    final expected = _t0.add(outboxRetryBackoff(1, 'op-1'));

    // "Restart" #1, BEFORE the entry is due: the recovery sweep must wait.
    final t2 = _ScriptedTransport(const [_applied]);
    final repo2 = RealOutboxRepository(
      t2,
      _session,
      store: store(),
      now: () => clock.now,
    );
    final c2 = ProviderContainer(
      overrides: [
        outboxRepositoryProvider.overrideWithValue(repo2),
        posSyncClockProvider.overrideWithValue(() => clock.now),
      ],
    );
    addTearDown(c2.dispose);
    final controller2 = c2.read(outboxControllerProvider.notifier);
    await pumpEventQueue();
    // The schedule survived the restart byte-honestly...
    expect(controller2.entryById('e1')!.nextAttemptAt, expected);
    // ...and the not-yet-due entry was NOT pushed by the recovery sweep.
    expect(t2.pushes, 0, reason: 'not due — the restart sweep must wait');

    // "Restart" #2, AFTER the schedule: the first recovery sweep delivers
    // WITHOUT any manual call.
    clock.now = expected;
    final t3 = _ScriptedTransport(const [_applied]);
    final repo3 = RealOutboxRepository(
      t3,
      _session,
      store: store(),
      now: () => clock.now,
    );
    final c3 = ProviderContainer(
      overrides: [
        outboxRepositoryProvider.overrideWithValue(repo3),
        posSyncClockProvider.overrideWithValue(() => clock.now),
      ],
    );
    addTearDown(c3.dispose);
    final controller3 = c3.read(outboxControllerProvider.notifier);
    await pumpEventQueue();
    expect(t3.pushes, 1, reason: 'due — the recovery sweep delivers');
    expect(controller3.entryById('e1')!.syncState, OutboxSyncState.applied);
    expect(t3.pushedLocalOperationIds.single, 'op-1');
  });

  test('5. reconnect evidence: offlineCached -> online triggers an automatic '
      'reset sweep — delivery with NO manual retry call', () async {
    final farFuture = _t0.add(const Duration(hours: 6));
    final w = _wire(
      [_applied],
      preload: [
        _seed().copyWith(
          syncState: OutboxSyncState.rejected,
          attemptCount: 7,
          lastErrorCode: 'network',
          lastErrorKind: 'transient',
          nextAttemptAt: farFuture,
        ),
      ],
    );
    await pumpEventQueue(); // recovery sweep — not due, nothing pushed
    expect(w.transport.pushes, 0);

    // The offline phase is driven ONLY by real fetch outcomes in production
    // (pos_offline_state.dart); the test records the same transitions.
    w.container
        .read(posOfflineModeProvider.notifier)
        .recordOfflineCacheServed(snapshotFetchedAt: DateTime.utc(2026, 8, 6));
    await pumpEventQueue();
    expect(w.transport.pushes, 0, reason: 'going offline must not sweep');

    w.container.read(posOfflineModeProvider.notifier).recordOnlineFetch();
    await pumpEventQueue();
    expect(
      w.transport.pushes,
      1,
      reason: 'the reconnect listener resets the backoff and sweeps',
    );
    expect(w.controller.entryById('e1')!.syncState, OutboxSyncState.applied);
    expect(w.transport.pushedLocalOperationIds.single, 'op-1');
  });

  test('6. a LEGACY row without next_attempt_at decodes due-now (today\'s '
      'behavior preserved for pre-Pass-B envelopes)', () async {
    final legacyJson = _seed()
        .copyWith(
          syncState: OutboxSyncState.rejected,
          attemptCount: 3,
          lastErrorCode: 'network',
          lastErrorKind: 'transient',
        )
        .toJson();
    expect(legacyJson.containsKey('next_attempt_at'), isFalse);

    final decoded = OutboxEntry.fromJson(legacyJson);
    expect(decoded.nextAttemptAt, isNull);
    expect(decoded.isDueAt(DateTime.utc(1970)), isTrue);

    // And behaviorally: the very first plain sweep delivers it.
    final store = _MemoryStore()..saved['dev-1'] = [legacyJson];
    final w = _wire(const [_applied], store: store);
    await pumpEventQueue();
    expect(w.transport.pushes, 1, reason: 'legacy row is due immediately');
    expect(w.controller.entryById('e1')!.syncState, OutboxSyncState.applied);
  });

  test('7. resetBackoff never touches AUTH_HOLD entries or definitive '
      'verdicts (the 002/024 gates hold — see pos_offline_authhold_test and '
      'push_boundary_guard_025_test for the full surfaces)', () async {
    final farFuture = _t0.add(const Duration(hours: 6));
    final held = _seed(id: 'held-1', op: 'held-op').copyWith(
      syncState: OutboxSyncState.authHold,
      lastErrorCode: '42501',
      lastErrorKind: 'auth',
    );
    final definitive = _seed(id: 'ver-1', op: 'ver-op').copyWith(
      syncState: OutboxSyncState.rejected,
      lastErrorCode: 'rejected',
      lastErrorKind: kServerVerdictErrorKind,
    );
    final retryable = _seed(id: 'ret-1', op: 'ret-op').copyWith(
      syncState: OutboxSyncState.rejected,
      attemptCount: 4,
      lastErrorCode: 'network',
      lastErrorKind: 'transient',
      nextAttemptAt: farFuture,
    );
    final w = _wire(const [_applied], preload: [held, definitive, retryable]);
    await pumpEventQueue();
    expect(w.transport.pushes, 0);

    await w.controller.pushQueued(resetBackoff: true);
    await pumpEventQueue();

    // ONLY the retryable transient failure was reset + resubmitted.
    expect(w.transport.pushes, 1);
    expect(w.transport.pushedLocalOperationIds.single, 'ret-op');
    expect(w.controller.entryById('ret-1')!.syncState, OutboxSyncState.applied);
    // The hold is released by sign-in, not by time or resets.
    expect(
      w.controller.entryById('held-1')!.syncState,
      OutboxSyncState.authHold,
    );
    // The recorded verdict stands untouched, attempt count unspent.
    final verdict = w.controller.entryById('ver-1')!;
    expect(verdict.syncState, OutboxSyncState.rejected);
    expect(verdict.lastErrorKind, kServerVerdictErrorKind);
    expect(verdict.attemptCount, 0);
  });

  test('8. "all synced" only after completion: isAllApplied stays false while '
      'the entry waits out its backoff, true only once applied', () async {
    PosOutboxStatusSummary summarize(List<OutboxEntry> entries) =>
        PosOutboxStatusSummary.from(
          entries: entries,
          storage: const PosLocalStorageHealth(),
        );

    final w = _wire([_transientFailure, _applied]);
    final repo = w.container.read(outboxRepositoryProvider);
    await repo.enqueue(_seed());
    await w.controller.pushEntry('e1');
    await pumpEventQueue();

    // Waiting out the schedule is NOT synced — the chip may never claim it.
    expect(w.controller.entryById('e1')!.nextAttemptAt, isNotNull);
    expect(
      summarize(w.container.read(outboxControllerProvider)).isAllApplied,
      isFalse,
      reason: 'a scheduled retry is unfinished work',
    );

    w.clock.now = w.controller.entryById('e1')!.nextAttemptAt!;
    await w.controller.pushQueued();
    await pumpEventQueue();
    expect(w.controller.entryById('e1')!.syncState, OutboxSyncState.applied);
    expect(
      summarize(w.container.read(outboxControllerProvider)).isAllApplied,
      isTrue,
    );
  });
}
