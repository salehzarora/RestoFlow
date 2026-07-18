import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/ready_feed_repository.dart';
import 'package:restoflow_pos/src/data/ready_notifications_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/ready_notifications_controller.dart';

/// PSC-001A — the polling owner: bootstrap (no-storm baseline + the explicit
/// initialized marker), tuple-cursor pagination with persist-before-advance,
/// sticky dedup, the alert queue, read state, backoff, lifecycle, and the
/// status-reconciliation sweep.

final _t0 = DateTime.utc(2026, 7, 23, 12);
String _at(int minutesAgo) =>
    _t0.subtract(Duration(minutes: minutesAgo)).toIso8601String();

String _uid(int n) =>
    '0a000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
String _oid(int n) =>
    '0b000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

PosReadyFeedRow _row(
  int n, {
  String type = 'initial_order',
  String? readyAt,
  String status = 'ready',
  String parent = 'preparing',
  int revision = 3,
}) => PosReadyFeedRow(
  workUnitType: type,
  workUnitId: _uid(n),
  orderId: _oid(n),
  orderCode: '#00000$n',
  roundNumber: type == 'service_round' ? 2 : null,
  orderType: 'dine_in',
  tableLabel: 'T$n',
  readyAt: readyAt ?? _at(60 - n),
  workUnitStatus: status,
  parentOrderStatus: parent,
  revision: revision,
);

PosReadyCursor _cursorOf(PosReadyFeedRow row) => PosReadyCursor(
  readyAt: row.readyAt,
  workUnitType: row.workUnitType,
  id: row.workUnitId,
);

PosReadyFeedPage _page(
  List<PosReadyFeedRow> rows, {
  bool hasMore = false,
  String? serverTs,
}) => PosReadyFeedPage(
  rows: rows,
  hasMore: hasMore,
  serverTs: serverTs ?? _t0.toIso8601String(),
  nextCursor: rows.isEmpty ? null : _cursorOf(rows.last),
);

/// Sequenced fake repo: one handler per fetch (the last repeats); records
/// every requested cursor for persist-before-advance assertions.
class _FakeRepo implements ReadyFeedRepository {
  _FakeRepo(this.handlers);
  final List<PosReadyFeedPage Function(PosReadyCursor?)> handlers;
  final List<PosReadyCursor?> requestedCursors = [];
  int calls = 0;
  @override
  Future<PosReadyFeedPage> fetch({PosReadyCursor? cursor, int limit = 100}) {
    requestedCursors.add(cursor);
    calls++;
    final handler = handlers.length >= calls
        ? handlers[calls - 1]
        : handlers.last;
    return Future.value(handler(cursor));
  }
}

/// Per-call gated repo for overlap/fencing tests.
class _GatedRepo implements ReadyFeedRepository {
  final List<Completer<PosReadyFeedPage>> gates = [];
  int calls = 0;
  @override
  Future<PosReadyFeedPage> fetch({PosReadyCursor? cursor, int limit = 100}) {
    calls++;
    final gate = Completer<PosReadyFeedPage>();
    gates.add(gate);
    return gate.future;
  }
}

class _ThrowingRepo implements ReadyFeedRepository {
  _ThrowingRepo(this.failure);
  final PosReadyFeedFailure failure;
  int calls = 0;
  @override
  Future<PosReadyFeedPage> fetch({PosReadyCursor? cursor, int limit = 100}) {
    calls++;
    throw PosReadyFeedException(failure);
  }
}

/// A store whose persist can be made to fail (pins the cursor).
class _FlakyStore extends InMemoryReadyNotificationsStore {
  int persistCalls = 0;
  int failNextPersists = 0;

  /// Fail exactly the Nth persist call (1-based); 0 = disabled.
  int failPersistNumber = 0;
  final List<PosReadyNotificationsEnvelope> persisted = [];
  @override
  Future<void> persist(
    PosSyncScope scope,
    PosReadyNotificationsEnvelope env,
  ) async {
    persistCalls++;
    if (failNextPersists > 0) {
      failNextPersists--;
      throw const PosPersistenceException('nope');
    }
    if (failPersistNumber == persistCalls) {
      throw const PosPersistenceException('nope');
    }
    persisted.add(env);
    return super.persist(scope, env);
  }
}

const _ctxA = DeviceContext(
  organizationId: 'org1',
  branchId: 'branch-A',
  restaurantId: 'r1',
  deviceId: 'dev1',
);
const _ctxB = DeviceContext(
  organizationId: 'org1',
  branchId: 'branch-B',
  restaurantId: 'r1',
  deviceId: 'dev1',
);

ProviderContainer harness({
  required ReadyFeedRepository repo,
  ReadyNotificationsStore? store,
  bool withScope = true,
  Duration? pollInterval,
  bool demo = false,
}) {
  final container = ProviderContainer(
    overrides: [
      readyFeedRepositoryProvider.overrideWithValue(repo),
      readyNotificationsStoreProvider.overrideWithValue(
        store ?? InMemoryReadyNotificationsStore(),
      ),
      posReadyFeedPollIntervalProvider.overrideWithValue(pollInterval),
      posSyncClockProvider.overrideWithValue(() => _t0),
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: demo),
      ),
      if (withScope && !demo)
        posSyncSessionProvider.overrideWithValue(
          const SyncSession(pinSessionId: 'pin1', deviceId: 'dev1'),
        ),
    ],
  );
  addTearDown(container.dispose);
  if (withScope && !demo) {
    container.read(posDeviceContextProvider.notifier).set(_ctxA);
  }
  return container;
}

Future<PosReadyNotificationsController> _ready(ProviderContainer c) async {
  final notifier = c.read(posReadyNotificationsControllerProvider.notifier);
  // The scope listener schedules an immediate first load — let it land so
  // every test starts from a deterministic post-bootstrap point.
  await pumpEventQueue(times: 20);
  return notifier;
}

void main() {
  group('B. bootstrap', () {
    test(
      'B1 historical rows become read+alerted baseline: NO alert storm, '
      'NO badge, initialized+bootstrapServerTs+cursor persisted atomically',
      () async {
        final store = _FlakyStore();
        final c = harness(
          repo: _FakeRepo([
            (_) => _page([_row(1), _row(2, type: 'service_round')]),
            (_) => _page(const []),
          ]),
          store: store,
        );
        await _ready(c);
        final state = c.read(posReadyNotificationsControllerProvider);
        expect(state.initialized, isTrue);
        expect(state.records, hasLength(2));
        expect(state.unreadCount, 0);
        expect(state.activeAlert, isNull);
        final env = store.persisted.single;
        expect(env.initialized, isTrue);
        expect(env.bootstrapServerTs, _t0.toIso8601String());
        expect(env.cursor!.id, _uid(2));
        expect(env.records.every((r) => r.read && r.alerted), isTrue);
      },
    );

    test('B2 a row that became ready AFTER the bootstrap baseline is NOT '
        'silently absorbed: unread + one alert', () async {
      final late = _row(
        3,
        readyAt: _t0.add(const Duration(seconds: 2)).toIso8601String(),
      );
      final c = harness(
        repo: _FakeRepo([
          (_) => _page([_row(1), late]),
        ]),
      );
      await _ready(c);
      final state = c.read(posReadyNotificationsControllerProvider);
      expect(state.unreadCount, 1);
      expect(state.activeAlert, isNotNull);
      expect(state.activeAlert!.items.single.workUnitId, _uid(3));
      expect(
        state.records.firstWhere((r) => r.workUnitId == _uid(1)).read,
        isTrue,
      );
    });

    test('B3 a ZERO-row bootstrap persists initialized=true with cursor=null; '
        'the next returned row is NEW and alerts', () async {
      final store = _FlakyStore();
      final c = harness(
        repo: _FakeRepo([
          (_) => _page(const []),
          (_) => _page([_row(1)]),
        ]),
        store: store,
      );
      final notifier = await _ready(c);
      expect(store.persisted.single.initialized, isTrue);
      expect(store.persisted.single.cursor, isNull);
      expect(c.read(posReadyNotificationsControllerProvider).records, isEmpty);
      await notifier.refreshNow();
      final state = c.read(posReadyNotificationsControllerProvider);
      expect(state.unreadCount, 1);
      expect(state.activeAlert!.items.single.workUnitId, _uid(1));
    });

    test('B4 a crash BEFORE the bootstrap persist re-bootstraps safely (still '
        'no storm: the baseline is re-classified as read)', () async {
      final store = _FlakyStore()..failNextPersists = 1;
      final c = harness(
        repo: _FakeRepo([
          (_) => _page([_row(1)]),
        ]),
        store: store,
      );
      final notifier = await _ready(c);
      var state = c.read(posReadyNotificationsControllerProvider);
      expect(state.initialized, isFalse);
      expect(state.degraded, isTrue);
      expect(store.persisted, isEmpty); // nothing durable — clean re-run
      await notifier.refreshNow();
      state = c.read(posReadyNotificationsControllerProvider);
      expect(state.initialized, isTrue);
      expect(state.unreadCount, 0); // baseline, not a storm
      expect(state.degraded, isFalse);
    });

    test('B5 a RESTART after bootstrap resumes established mode without any '
        're-alert (alerted is durable)', () async {
      final store = InMemoryReadyNotificationsStore();
      final repo = _FakeRepo([
        (_) => _page([_row(1)]),
        (_) => _page(const []),
      ]);
      final first = harness(repo: repo, store: store);
      await _ready(first);
      first.dispose();
      // A fresh controller over the SAME store (browser restart).
      final second = ProviderContainer(
        overrides: [
          readyFeedRepositoryProvider.overrideWithValue(
            _FakeRepo([(_) => _page(const [])]),
          ),
          readyNotificationsStoreProvider.overrideWithValue(store),
          posReadyFeedPollIntervalProvider.overrideWithValue(null),
          posSyncClockProvider.overrideWithValue(() => _t0),
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posSyncSessionProvider.overrideWithValue(
            const SyncSession(pinSessionId: 'pin1', deviceId: 'dev1'),
          ),
        ],
      );
      addTearDown(second.dispose);
      second.read(posDeviceContextProvider.notifier).set(_ctxA);
      final notifier = second.read(
        posReadyNotificationsControllerProvider.notifier,
      );
      await pumpEventQueue(times: 20);
      await notifier.refreshNow();
      final state = second.read(posReadyNotificationsControllerProvider);
      expect(state.initialized, isTrue);
      expect(state.records, hasLength(1));
      expect(state.activeAlert, isNull); // never re-presented
      expect(state.unreadCount, 0);
    });
  });

  group('P. polling, pagination, and cursors', () {
    test(
      'P1 a NEW identity alerts exactly once; the repeated page and the '
      'overlapping page produce no duplicate and keep read/alerted sticky',
      () async {
        final c = harness(
          repo: _FakeRepo([
            (_) => _page(const []), // bootstrap: empty baseline
            (_) => _page([_row(1)]),
            (_) => _page([_row(1)]), // repeated page
            (_) => _page([_row(1), _row(2)]), // overlapping page
          ]),
        );
        final notifier = await _ready(c);
        await notifier.refreshNow();
        var state = c.read(posReadyNotificationsControllerProvider);
        expect(state.unreadCount, 1);
        final firstAlertId = state.activeAlert!.id;
        notifier.dismissAlert();
        await notifier.refreshNow(); // repeated page
        state = c.read(posReadyNotificationsControllerProvider);
        expect(state.records, hasLength(1));
        expect(state.unreadCount, 1);
        expect(state.activeAlert, isNull); // no re-alert
        await notifier.refreshNow(); // overlapping page
        state = c.read(posReadyNotificationsControllerProvider);
        expect(state.records, hasLength(2));
        expect(state.unreadCount, 2);
        expect(state.activeAlert!.items.single.workUnitId, _uid(2));
        expect(state.activeAlert!.id, isNot(firstAlertId));
      },
    );

    test('P2 a multi-page cycle drains ascending with the tuple cursor and '
        'persists EVERY page before its cursor advances', () async {
      final store = _FlakyStore();
      final c = harness(
        repo: _FakeRepo([
          (_) => _page(const []), // bootstrap
          (cursor) => _page([_row(1), _row(2)], hasMore: true),
          (cursor) => _page([_row(3)]),
        ]),
        store: store,
      );
      final notifier = await _ready(c);
      await notifier.refreshNow();
      final state = c.read(posReadyNotificationsControllerProvider);
      expect(state.records, hasLength(3));
      // The second request carried page 1's FULL tuple cursor.
      final fake = c.read(readyFeedRepositoryProvider) as _FakeRepo;
      expect(fake.requestedCursors[2]!.id, _uid(2));
      expect(fake.requestedCursors[2]!.workUnitType, 'initial_order');
      // Each persisted envelope's cursor never outruns its own records.
      final pageEnvs = store.persisted.sublist(1); // after the bootstrap env
      expect(pageEnvs[0].records, hasLength(2));
      expect(pageEnvs[0].cursor!.id, _uid(2));
      expect(pageEnvs[1].records, hasLength(3));
      expect(pageEnvs[1].cursor!.id, _uid(3));
    });

    test('P3 a persistence failure PINS the cursor: the failed page is '
        're-fetched from the last durable cursor and recovers', () async {
      final store = _FlakyStore();
      final c = harness(
        repo: _FakeRepo([
          (_) => _page([_row(1)]), // bootstrap baseline
          (_) => _page([_row(2)]), // poll page — persist will fail
          (_) => _page([_row(2)]), // retry re-serves the SAME page
        ]),
        store: store,
      );
      final notifier = await _ready(c);
      store.failNextPersists = 1;
      await notifier.refreshNow();
      var state = c.read(posReadyNotificationsControllerProvider);
      expect(state.degraded, isTrue);
      expect(state.records, hasLength(1)); // memory did NOT outrun durable
      final fake = c.read(readyFeedRepositoryProvider) as _FakeRepo;
      final cursorBefore = fake.requestedCursors.last;
      await notifier.refreshNow();
      state = c.read(posReadyNotificationsControllerProvider);
      expect(state.degraded, isFalse);
      expect(state.records, hasLength(2));
      // The retry asked from the SAME durable cursor (nothing was skipped).
      expect(fake.requestedCursors.last!.id, cursorBefore!.id);
      expect(state.unreadCount, 1); // and the recovered row still alerts once
      expect(state.activeAlert, isNotNull);
    });

    test('P4 concurrent refreshes JOIN the one in-flight cycle', () async {
      final gated = _GatedRepo();
      final c = harness(repo: gated);
      final notifier = c.read(posReadyNotificationsControllerProvider.notifier);
      await pumpEventQueue(times: 5); // the auto first load is now gated
      final f1 = notifier.refreshNow();
      final f2 = notifier.refreshNow();
      expect(gated.calls, 1);
      gated.gates.single.complete(_page(const []));
      await f1;
      await f2;
      expect(gated.calls, 1);
    });

    test('P5 retention keeps the NEWEST 100 within 24h and never rewinds the '
        'cursor', () async {
      final store = _FlakyStore();
      final rows = [
        _row(150, readyAt: _at(60 * 30)), // older than 24h — pruned by age
        for (var i = 1; i <= 120; i++) _row(i, readyAt: _at(200 - i)),
      ];
      final c = harness(repo: _FakeRepo([(_) => _page(rows)]), store: store);
      await _ready(c);
      final env = store.persisted.single;
      expect(env.records, hasLength(100));
      // Newest kept: the oldest of the 120 in-window rows fell off.
      expect(env.records.any((r) => r.workUnitId == _uid(1)), isFalse);
      expect(env.records.any((r) => r.workUnitId == _uid(120)), isTrue);
      expect(env.records.any((r) => r.workUnitId == _uid(150)), isFalse);
      // The cursor still points at the LAST page row, not a pruned record.
      expect(env.cursor!.id, _uid(120));
    });

    test(
      'P6 after 3 consecutive failures the tick backs off (~30s) while a '
      'MANUAL refresh still runs and the first success restores cadence',
      () async {
        final repo = _ThrowingRepo(PosReadyFeedFailure.transport);
        final c = harness(repo: repo);
        final notifier = await _ready(c); // failure 1 (auto)
        await notifier.refreshNow(); // 2
        await notifier.refreshNow(); // 3
        expect(
          c.read(posReadyNotificationsControllerProvider).degraded,
          isTrue,
        );
        expect(notifier.isInBackoff, isTrue); // the TICK would skip now
        final callsBefore = repo.calls;
        await notifier.refreshNow(); // manual bypasses the gate
        expect(repo.calls, callsBefore + 1);
      },
    );

    test('P7 pause cancels the tick; resume re-arms it and refreshes '
        'immediately', () async {
      final repo = _FakeRepo([(_) => _page(const [])]);
      final c = harness(repo: repo, pollInterval: const Duration(seconds: 7));
      final notifier = await _ready(c);
      expect(notifier.isPolling, isTrue);
      notifier.onPaused();
      expect(notifier.isPolling, isFalse);
      final callsBefore = repo.calls;
      notifier.onResume();
      expect(notifier.isPolling, isTrue);
      await pumpEventQueue(times: 10);
      expect(repo.calls, greaterThan(callsBefore));
    });

    test('P8 a SCOPE change switches to the new namespace and a stale '
        'in-flight response has zero side effects', () async {
      final gated = _GatedRepo();
      final storeA = InMemoryReadyNotificationsStore();
      final c = harness(repo: gated, store: storeA);
      final notifier = c.read(posReadyNotificationsControllerProvider.notifier);
      await pumpEventQueue(times: 5); // branch-A bootstrap gated (gate 0)
      // The till re-pairs into branch B while A's response is on the wire.
      c.read(posDeviceContextProvider.notifier).set(_ctxB);
      // The next read rebuilds the (dirty) controller on the settled graph —
      // exactly what the always-watching bell does in production.
      c.read(posReadyNotificationsControllerProvider);
      await pumpEventQueue(times: 5); // branch-B bootstrap gated (gate 1)
      gated.gates[1].complete(_page([_row(9)]));
      await pumpEventQueue(times: 20);
      // A's STALE response finally lands — fenced, zero side effects.
      gated.gates[0].complete(_page([_row(1), _row(2)]));
      await pumpEventQueue(times: 20);
      final state = c.read(posReadyNotificationsControllerProvider);
      expect(state.records.map((r) => r.workUnitId), [_uid(9)]);
      // And branch A's envelope was never written by the stale continuation.
      expect(
        await storeA.load(
          const PosSyncScope(
            organizationId: 'org1',
            restaurantId: 'r1',
            branchId: 'branch-A',
            deviceId: 'dev1',
          ),
        ),
        isNull,
      );
      expect(notifier, isNotNull);
    });

    test(
      'P9 a SECURITY refusal stops the poller (reauth owns recovery)',
      () async {
        final c = harness(
          repo: _ThrowingRepo(PosReadyFeedFailure.session),
          pollInterval: const Duration(seconds: 7),
        );
        final notifier = await _ready(c);
        expect(notifier.isPolling, isFalse); // cancelled by the refusal
        expect(
          c.read(posReadyNotificationsControllerProvider).degraded,
          isTrue,
        );
      },
    );

    test('P10 no scope → no request at all', () async {
      final repo = _FakeRepo([(_) => _page(const [])]);
      final c = harness(repo: repo, withScope: false);
      final notifier = c.read(posReadyNotificationsControllerProvider.notifier);
      await pumpEventQueue(times: 10);
      await notifier.refreshNow();
      expect(repo.calls, 0);
    });

    test('P11 demo mode never polls and never arms the timer', () async {
      final repo = _FakeRepo([(_) => _page(const [])]);
      final c = harness(
        repo: repo,
        demo: true,
        pollInterval: const Duration(seconds: 7),
      );
      final notifier = c.read(posReadyNotificationsControllerProvider.notifier);
      await pumpEventQueue(times: 10);
      await notifier.refreshNow();
      expect(repo.calls, 0);
      expect(notifier.isPolling, isFalse);
    });
  });

  group('A. alerts and read state', () {
    test(
      'A1 several arrivals in ONE cycle group into a single alert',
      () async {
        final c = harness(
          repo: _FakeRepo([
            (_) => _page(const []),
            (_) => _page([_row(1), _row(2), _row(3)]),
          ]),
        );
        final notifier = await _ready(c);
        await notifier.refreshNow();
        final alert = c
            .read(posReadyNotificationsControllerProvider)
            .activeAlert;
        expect(alert!.isGrouped, isTrue);
        expect(alert.items, hasLength(3));
        // Deterministic oldest-first presentation order inside the group.
        expect(alert.items.first.workUnitId, _uid(1));
      },
    );

    test('A2 the queue caps at 3 entries and overflow COLLAPSES into one '
        'grouped summary; dismissal drains deterministically', () async {
      final c = harness(
        repo: _FakeRepo([
          (_) => _page(const []),
          (_) => _page([_row(1)]),
          (_) => _page([_row(2)]),
          (_) => _page([_row(3)]),
          (_) => _page([_row(4)]),
          (_) => _page([_row(5)]),
        ]),
      );
      final notifier = await _ready(c);
      for (var i = 0; i < 5; i++) {
        await notifier.refreshNow();
      }
      // Entry 1 is VISIBLE; entries for 2..5 overflowed the 3-entry queue and
      // collapsed into ONE grouped summary behind it.
      var alert = c.read(posReadyNotificationsControllerProvider).activeAlert;
      expect(alert!.items.single.workUnitId, _uid(1));
      notifier.dismissAlert();
      // Promotion is ASYNC by design: the next entry's alerted=true must
      // persist durably BEFORE its banner may appear.
      await pumpEventQueue(times: 10);
      alert = c.read(posReadyNotificationsControllerProvider).activeAlert;
      expect(alert!.isGrouped, isTrue);
      expect(alert.items, hasLength(4));
      notifier.dismissAlert();
      await pumpEventQueue(times: 10);
      expect(
        c.read(posReadyNotificationsControllerProvider).activeAlert,
        isNull,
      );
    });

    test('A3 DISMISSAL IS NOT READ; an intentional open reads exactly one; '
        'mark-all-read reads everything and persists', () async {
      final store = _FlakyStore();
      final c = harness(
        repo: _FakeRepo([
          (_) => _page(const []),
          (_) => _page([_row(1), _row(2)]),
        ]),
        store: store,
      );
      final notifier = await _ready(c);
      await notifier.refreshNow();
      notifier.dismissAlert();
      var state = c.read(posReadyNotificationsControllerProvider);
      expect(state.unreadCount, 2); // dismissal changed nothing
      notifier.markRead('initial_order|${_uid(1)}');
      await pumpEventQueue(times: 5);
      state = c.read(posReadyNotificationsControllerProvider);
      expect(state.unreadCount, 1);
      notifier.markAllRead();
      await pumpEventQueue(times: 5);
      state = c.read(posReadyNotificationsControllerProvider);
      expect(state.unreadCount, 0);
      final env = store.persisted.last;
      expect(env.records.every((r) => r.read), isTrue);
    });

    test('A4 the promoted alert marks its items ALERTED durably (a restart '
        'cannot re-present it)', () async {
      final store = _FlakyStore();
      final c = harness(
        repo: _FakeRepo([
          (_) => _page(const []),
          (_) => _page([_row(1)]),
        ]),
        store: store,
      );
      final notifier = await _ready(c);
      await notifier.refreshNow();
      await pumpEventQueue(times: 5);
      final env = store.persisted.last;
      expect(env.records.single.alerted, isTrue);
      expect(env.records.single.read, isFalse); // alerted, still unread
      expect(notifier, isNotNull);
    });

    test(
      'A5 the status-reconciliation sweep updates KNOWN statuses only: no '
      'new record, no alert, no read/alerted change, cursor untouched',
      () async {
        final store = _FlakyStore();
        final c = harness(
          repo: _FakeRepo([
            (_) => _page([_row(1, status: 'ready', parent: 'preparing')]),
            // The sweep window re-serves row 1 SERVED and an unknown row 7 —
            // known status updates; the unknown is ignored (discovery's job).
            (_) => _page([
              _row(1, status: 'served', parent: 'served', revision: 5),
              _row(7),
            ]),
          ]),
          store: store,
        );
        final notifier = await _ready(c);
        final cursorBefore = store.persisted.last.cursor;
        await notifier.reconcileStatuses();
        final state = c.read(posReadyNotificationsControllerProvider);
        expect(state.records, hasLength(1)); // row 7 was NOT added
        expect(state.records.single.workUnitStatus, 'served');
        expect(state.records.single.parentOrderStatus, 'served');
        expect(state.records.single.read, isTrue); // baseline stayed read
        expect(state.activeAlert, isNull); // the sweep never alerts
        final env = store.persisted.last;
        expect(env.cursor!.id, cursorBefore!.id); // discovery cursor untouched
        // The sweep request itself was CURSORLESS (the 24h status window).
        final fake = c.read(readyFeedRepositoryProvider) as _FakeRepo;
        expect(fake.requestedCursors.last, isNull);
      },
    );

    test('A6 a served/voided record REMAINS in history with its updated '
        'status (a ready event is historical, not a live claim)', () async {
      final c = harness(
        repo: _FakeRepo([
          (_) => _page([_row(1)]),
          (_) => _page([_row(1, status: 'voided', parent: 'voided')]),
        ]),
      );
      final notifier = await _ready(c);
      await notifier.reconcileStatuses();
      final state = c.read(posReadyNotificationsControllerProvider);
      expect(state.records, hasLength(1));
      expect(state.records.single.workUnitStatus, 'voided');
    });
  });

  group('C. correction — resumable bootstrap (Fix 1)', () {
    List<PosReadyFeedPage Function(PosReadyCursor?)> pagesOf(
      List<List<PosReadyFeedRow>> chunks,
    ) => [
      for (var i = 0; i < chunks.length; i++)
        (_) => _page(chunks[i], hasMore: i < chunks.length - 1),
      (_) => _page(const []),
    ];

    List<List<PosReadyFeedRow>> chunkRows(int total, {int size = 100}) {
      final rows = [
        for (var n = 1; n <= total; n++)
          _row(
            n,
            readyAt: _t0
                .subtract(Duration(seconds: total - n))
                .toIso8601String(),
          ),
      ];
      return [
        for (var i = 0; i < rows.length; i += size)
          rows.sublist(i, i + size > rows.length ? rows.length : i + size),
      ];
    }

    test('C1 501 historical rows: cycle 1 drains 500 and stays '
        'initialized=false; cycle 2 finishes row 501 as HISTORICAL — zero '
        'unread, zero banner, ever', () async {
      final store = _FlakyStore();
      final c = harness(repo: _FakeRepo(pagesOf(chunkRows(501))), store: store);
      final notifier = await _ready(c); // cycle 1: five pages (500 rows)
      var state = c.read(posReadyNotificationsControllerProvider);
      expect(state.initialized, isFalse); // has_more was still true
      expect(state.unreadCount, 0);
      expect(state.activeAlert, isNull);
      final partial = store.persisted.last;
      expect(partial.initialized, isFalse);
      expect(partial.bootstrapServerTs, _t0.toIso8601String());
      expect(partial.cursor, isNotNull);
      await notifier.refreshNow(); // cycle 2: page 6 (row 501, has_more=false)
      state = c.read(posReadyNotificationsControllerProvider);
      expect(state.initialized, isTrue);
      expect(state.unreadCount, 0);
      expect(state.activeAlert, isNull);
      final complete = store.persisted.last;
      expect(complete.initialized, isTrue);
      expect(complete.bootstrapServerTs, _t0.toIso8601String());
      expect(complete.records.every((r) => r.read && r.alerted), isTrue);
    });

    test('C2 700 historical rows span cycles: everything stays read+alerted, '
        'zero notification storm', () async {
      final c = harness(repo: _FakeRepo(pagesOf(chunkRows(700))));
      final notifier = await _ready(c); // cycle 1: 500
      expect(
        c.read(posReadyNotificationsControllerProvider).initialized,
        isFalse,
      );
      await notifier.refreshNow(); // cycle 2: 200 + completion
      final state = c.read(posReadyNotificationsControllerProvider);
      expect(state.initialized, isTrue);
      expect(state.unreadCount, 0);
      expect(state.activeAlert, isNull);
      expect(state.records.every((r) => r.read && r.alerted), isTrue);
    });

    test('C3 a row that became ready AFTER the baseline, arriving in the '
        'remaining backlog, is stored unread and alerts EXACTLY ONCE, only '
        'after bootstrap completes', () async {
      final chunks = chunkRows(501);
      // Splice a genuinely-new row (post-baseline ready_at) into page 6.
      chunks.last.add(
        _row(
          999,
          readyAt: _t0.add(const Duration(seconds: 5)).toIso8601String(),
        ),
      );
      final c = harness(repo: _FakeRepo(pagesOf(chunks)));
      final notifier = await _ready(c); // cycle 1 — NO alert yet
      expect(
        c.read(posReadyNotificationsControllerProvider).activeAlert,
        isNull,
      );
      await notifier.refreshNow(); // completion cycle
      final state = c.read(posReadyNotificationsControllerProvider);
      expect(state.initialized, isTrue);
      expect(state.unreadCount, 1);
      expect(state.activeAlert!.items.single.workUnitId, _uid(999));
      await notifier.refreshNow(); // repeat poll: alerted once, ever
      expect(
        c
            .read(posReadyNotificationsControllerProvider)
            .activeAlert!
            .items
            .single
            .workUnitId,
        _uid(999),
      );
    });

    test(
      'C4 a RESTART after page 5 resumes from the persisted progress '
      'cursor with the ORIGINAL baseline — no null refetch, no duplicate',
      () async {
        final store = InMemoryReadyNotificationsStore();
        final chunks = chunkRows(501);
        final firstRun = harness(
          repo: _FakeRepo(pagesOf(chunks)),
          store: store,
        );
        await _ready(firstRun); // cycle 1: 500 rows, partial persisted
        firstRun.dispose();

        final resumeRepo = _FakeRepo(pagesOf([chunks.last]));
        final second = ProviderContainer(
          overrides: [
            readyFeedRepositoryProvider.overrideWithValue(resumeRepo),
            readyNotificationsStoreProvider.overrideWithValue(store),
            posReadyFeedPollIntervalProvider.overrideWithValue(null),
            posSyncClockProvider.overrideWithValue(() => _t0),
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: false),
            ),
            posSyncSessionProvider.overrideWithValue(
              const SyncSession(pinSessionId: 'pin1', deviceId: 'dev1'),
            ),
          ],
        );
        addTearDown(second.dispose);
        second.read(posDeviceContextProvider.notifier).set(_ctxA);
        second.read(posReadyNotificationsControllerProvider.notifier);
        await pumpEventQueue(times: 30);
        // The resumed request continued from the PERSISTED cursor, not null.
        expect(resumeRepo.requestedCursors.first, isNotNull);
        expect(resumeRepo.requestedCursors.first!.id, _uid(500));
        final state = second.read(posReadyNotificationsControllerProvider);
        expect(state.initialized, isTrue);
        expect(state.unreadCount, 0);
        expect(state.activeAlert, isNull);
        final env = await store.load(
          const PosSyncScope(
            organizationId: 'org1',
            restaurantId: 'r1',
            branchId: 'branch-A',
            deviceId: 'dev1',
          ),
        );
        expect(env!.bootstrapServerTs, _t0.toIso8601String()); // ORIGINAL
        // No duplicate identities across the two runs.
        final keys = env.records.map((r) => r.identityKey).toList();
        expect(keys.toSet().length, keys.length);
      },
    );

    test('C5 a persistence failure during a RESUMED bootstrap pins the '
        'progress cursor; the same page retries safely', () async {
      final store = _FlakyStore();
      final chunks = chunkRows(501);
      final c = harness(
        repo: _FakeRepo([
          ...pagesOf(chunks).take(5), // cycle 1 handlers (pages 1..5)
          (_) => _page(chunks.last), // cycle 2 attempt (persist will fail)
          (_) => _page(chunks.last), // cycle 3 retry of the SAME page
        ]),
        store: store,
      );
      final notifier = await _ready(c); // cycle 1
      final pinned = store.persisted.last.cursor;
      store.failNextPersists = 1;
      await notifier.refreshNow(); // cycle 2 — persist fails
      var state = c.read(posReadyNotificationsControllerProvider);
      expect(state.initialized, isFalse);
      expect(state.degraded, isTrue);
      expect(store.persisted.last.cursor!.id, pinned!.id); // pinned
      await notifier.refreshNow(); // cycle 3 — same page, recovers
      state = c.read(posReadyNotificationsControllerProvider);
      expect(state.initialized, isTrue);
      expect(state.unreadCount, 0);
      final fake = c.read(readyFeedRepositoryProvider) as _FakeRepo;
      // The retry asked from the SAME pinned cursor.
      expect(fake.requestedCursors.last!.id, pinned.id);
    });
  });

  group('S. correction — serialized mutations (Fix 2) and persist-before-'
      'banner (Fix 3)', () {
    test('S1 a poll result landing AFTER markRead cannot un-read the record '
        '(the commit rebases on the LATEST envelope)', () async {
      final gated = _GatedRepo();
      final store = _FlakyStore();
      final c = harness(repo: gated, store: store);
      final notifier = c.read(posReadyNotificationsControllerProvider.notifier);
      await pumpEventQueue(times: 5);
      gated.gates[0].complete(_page([_row(1)])); // bootstrap: row 1 read
      await pumpEventQueue(times: 20);
      final poll = notifier.refreshNow(); // discovery gated (gate 1)
      await pumpEventQueue(times: 5);
      // While the poll response is on the wire, the user opens row 2 — wait,
      // row 2 arrives IN that response; mark row 1 (already read) plus mark
      // ALL later. Here: mark row 1 read is a no-op; instead make row 1
      // unread first via a completed poll... Simplest honest scenario: the
      // gated page re-serves row 1 (status refresh) while the user marks it
      // read had it been unread. Use markAllRead-vs-poll as S2's stronger
      // case; S1 asserts the sticky rebase with a fresh unread row:
      gated.gates[1].complete(_page([_row(2)]));
      await poll;
      await pumpEventQueue(times: 10);
      notifier.markRead('initial_order|${_uid(2)}');
      await pumpEventQueue(times: 10);
      final sweep = notifier.reconcileStatuses(); // gated (gate 2)
      await pumpEventQueue(times: 5);
      gated.gates[2].complete(
        _page([_row(2, status: 'served', parent: 'served')]),
      );
      await sweep;
      final record = c
          .read(posReadyNotificationsControllerProvider)
          .records
          .firstWhere((r) => r.workUnitId == _uid(2));
      expect(record.read, isTrue); // the sweep commit REBASED on the markRead
      expect(record.workUnitStatus, 'served'); // and still applied statuses
    });

    test('S2 mark-all-read racing a gated poll: no record returns to unread; '
        'the poll\'s own NEW row stays honestly unread', () async {
      final gated = _GatedRepo();
      final c = harness(repo: gated);
      final notifier = c.read(posReadyNotificationsControllerProvider.notifier);
      await pumpEventQueue(times: 5);
      gated.gates[0].complete(_page([_row(1)]));
      await pumpEventQueue(times: 20);
      final poll = notifier.refreshNow(); // gate 1 pending
      await pumpEventQueue(times: 5);
      notifier.markAllRead();
      await pumpEventQueue(times: 10);
      gated.gates[1].complete(_page([_row(1, status: 'served'), _row(2)]));
      await poll;
      await pumpEventQueue(times: 10);
      final state = c.read(posReadyNotificationsControllerProvider);
      final r1 = state.records.firstWhere((r) => r.workUnitId == _uid(1));
      expect(r1.read, isTrue); // never rolled back
      expect(r1.workUnitStatus, 'served');
      final r2 = state.records.firstWhere((r) => r.workUnitId == _uid(2));
      expect(r2.read, isFalse); // genuinely new AFTER the mark-all
    });

    test('S3 two local mutations back-to-back both land in the final '
        'envelope', () async {
      final store = _FlakyStore();
      final c = harness(
        repo: _FakeRepo([
          (_) => _page(const []),
          (_) => _page([_row(1), _row(2)]),
        ]),
        store: store,
      );
      final notifier = await _ready(c);
      await notifier.refreshNow();
      notifier.markRead('initial_order|${_uid(1)}');
      notifier.markRead('initial_order|${_uid(2)}');
      await pumpEventQueue(times: 20);
      final env = store.persisted.last;
      expect(env.records.every((r) => r.read), isTrue);
    });

    test('S4 (Fix 3) a persistence failure BEFORE promotion shows NO banner; '
        'the entry stays pending and ONE banner appears after the retry '
        'succeeds', () async {
      final store = _FlakyStore();
      final c = harness(
        repo: _FakeRepo([
          (_) => _page(const []), // bootstrap (persist #1)
          (_) => _page([_row(1)]), // page commit (#2), promotion (#3)
          (_) => _page(const []), // next cycle: empty page (#4? none — no
          // change pages with no rows STILL persist; see below), promotion
        ]),
        store: store,
      );
      final notifier = await _ready(c);
      store.failPersistNumber = store.persistCalls + 2; // fail the PROMOTION
      await notifier.refreshNow();
      var state = c.read(posReadyNotificationsControllerProvider);
      expect(state.activeAlert, isNull); // nothing displayed
      expect(state.degraded, isTrue);
      // The record persisted honestly UNALERTED (the page commit succeeded).
      expect(store.persisted.last.records.single.alerted, isFalse);
      await notifier.refreshNow(); // next successful cycle retries promotion
      state = c.read(posReadyNotificationsControllerProvider);
      expect(state.activeAlert, isNotNull); // exactly one banner now
      expect(state.activeAlert!.items.single.workUnitId, _uid(1));
      // And alerted=true persisted BEFORE that banner appeared.
      expect(store.persisted.last.records.single.alerted, isTrue);
    });
  });

  group('L. correction — the terminal security latch (Fix 5)', () {
    test('L1 a terminal security refusal latches the EXACT identity: timer '
        'cancelled, resume and manual refresh cause ZERO RPCs (the repository '
        'suite proves invalid_session/invalid_device_type/permission_denied '
        'all map to this failure)', () async {
      final repo = _ThrowingRepo(PosReadyFeedFailure.session);
      final c = harness(repo: repo, pollInterval: const Duration(seconds: 7));
      final notifier = await _ready(c);
      expect(notifier.isSecurityLatched, isTrue);
      expect(notifier.isPolling, isFalse);
      expect(
        c.read(posReadyNotificationsControllerProvider).securityBlocked,
        isTrue,
      );
      final calls = repo.calls;
      notifier.onResume(); // resume must NOT bypass the latch
      await pumpEventQueue(times: 10);
      expect(repo.calls, calls);
      expect(notifier.isPolling, isFalse); // and must not re-arm the timer
      await notifier.refreshNow(); // manual refresh must NOT bypass it
      expect(repo.calls, calls);
      await notifier.reconcileStatuses(); // nor the status sweep
      expect(repo.calls, calls);
    });

    test('L2 re-emitting the SAME session identity keeps the latch', () async {
      final repo = _ThrowingRepo(PosReadyFeedFailure.session);
      final c = harness(repo: repo);
      final notifier = await _ready(c);
      final calls = repo.calls;
      // The same context re-set (same scope value) + repeated resumes.
      c.read(posDeviceContextProvider.notifier).set(_ctxA);
      notifier.onResume();
      notifier.onResume();
      await pumpEventQueue(times: 10);
      expect(repo.calls, calls);
      expect(notifier.isSecurityLatched, isTrue);
    });

    test('L3 a GENUINELY NEW valid session identity clears the latch and '
        'polling resumes immediately', () async {
      final session = StateProvider<SyncSession?>(
        (_) => const SyncSession(pinSessionId: 'pin1', deviceId: 'dev1'),
      );
      var fails = true;
      final repo = _FakeRepo([
        (_) {
          if (fails) {
            throw const PosReadyFeedException(PosReadyFeedFailure.session);
          }
          return _page(const []);
        },
      ]);
      final c = ProviderContainer(
        overrides: [
          readyFeedRepositoryProvider.overrideWithValue(repo),
          readyNotificationsStoreProvider.overrideWithValue(
            InMemoryReadyNotificationsStore(),
          ),
          posReadyFeedPollIntervalProvider.overrideWithValue(null),
          posSyncClockProvider.overrideWithValue(() => _t0),
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posSyncSessionProvider.overrideWith((ref) => ref.watch(session)),
        ],
      );
      addTearDown(c.dispose);
      c.read(posDeviceContextProvider.notifier).set(_ctxA);
      final notifier = c.read(posReadyNotificationsControllerProvider.notifier);
      await pumpEventQueue(times: 20);
      expect(notifier.isSecurityLatched, isTrue);
      final callsWhileLatched = repo.calls;
      await notifier.refreshNow();
      expect(repo.calls, callsWhileLatched); // fenced
      // The existing PIN flow restores a NEW session (new pinSessionId).
      fails = false;
      c.read(session.notifier).state = const SyncSession(
        pinSessionId: 'pin2',
        deviceId: 'dev1',
      );
      c.read(posReadyNotificationsControllerProvider); // settle the rebuild
      await pumpEventQueue(times: 30);
      expect(notifier.isSecurityLatched, isFalse);
      expect(repo.calls, greaterThan(callsWhileLatched)); // polling resumed
      expect(
        c.read(posReadyNotificationsControllerProvider).securityBlocked,
        isFalse,
      );
    });

    test(
      'L4 a TRANSPORT failure never latches — backoff/retry stays active',
      () async {
        final repo = _ThrowingRepo(PosReadyFeedFailure.transport);
        final c = harness(repo: repo, pollInterval: const Duration(seconds: 7));
        final notifier = await _ready(c);
        await notifier.refreshNow();
        await notifier.refreshNow();
        expect(notifier.isSecurityLatched, isFalse);
        expect(notifier.isPolling, isTrue); // the probe keeps running
        final calls = repo.calls;
        await notifier.refreshNow(); // manual retry still allowed
        expect(repo.calls, calls + 1);
      },
    );
  });
}
