import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/order_snapshot_repository.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';

/// POS-OPERATIONS-SYNC-001 — the coordinator wired into real providers.
void main() {
  final t0 = DateTime.utc(2026, 7, 14, 10);

  PosOrderSnapshot snap({
    String orderId = 'o-1',
    int revision = 2,
    String status = 'served',
    PosSettlement settlement = PosSettlement.unpaid,
    int grand = 4000,
    DateTime? syncAt,
  }) => PosOrderSnapshot(
    orderId: orderId,
    orderCode: '#0000O1',
    revision: revision,
    status: status,
    settlement: settlement,
    subtotalMinor: grand,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: grand,
    createdAt: t0,
    updatedAt: syncAt ?? t0,
    syncAt: syncAt ?? t0,
  );

  PosRecentOrder local({String orderId = 'o-1'}) => PosRecentOrder(
    order: SubmittedOrderView(
      orderNumber: '#0000O1',
      orderType: OrderType.dineIn,
      currencyCode: 'ILS',
      subtotalMinor: 4000,
      lines: const <SubmittedLineView>[],
      orderId: orderId,
    ),
    submittedAt: t0,
  );

  ProviderContainer harness({
    required OrderSnapshotRepository repo,
    PosRecentOrdersStore? store,
    PosSyncCursorStore? cursors,
    bool withScope = true,
    Duration? pollInterval,
  }) {
    final container = ProviderContainer(
      overrides: [
        orderSnapshotRepositoryProvider.overrideWithValue(repo),
        // Null by default — a live periodic Timer would make pumpAndSettle hang.
        // The polling test opts in explicitly.
        posSyncPollIntervalProvider.overrideWithValue(pollInterval),
        posRecentOrdersStoreProvider.overrideWithValue(
          store ?? InMemoryRecentOrdersStore(),
        ),
        posSyncCursorStoreProvider.overrideWithValue(
          cursors ?? InMemorySyncCursorStore(),
        ),
        posSyncClockProvider.overrideWithValue(() => t0),
        // REAL mode: the scope is derived from the paired device context, so
        // `withScope: false` genuinely means "this till is not paired yet". In demo
        // mode the scope is a fixed constant and there is no such thing as unpaired.
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        if (withScope)
          posSyncSessionProvider.overrideWithValue(
            const SyncSession(pinSessionId: 'pin1', deviceId: 'dev1'),
          ),
      ],
    );
    addTearDown(container.dispose);
    if (withScope) {
      // posDeviceContextProvider is a NotifierProvider (the pairing gate publishes
      // into it), so it is seeded through its own API rather than overridden.
      container
          .read(posDeviceContextProvider.notifier)
          .set(
            const DeviceContext(
              organizationId: 'org1',
              branchId: 'branch-A',
              restaurantId: 'r1',
              deviceId: 'dev1',
            ),
          );
    }
    return container;
  }

  group('A. applying snapshots', () {
    test(
      'A1 an authoritative snapshot updates the order AND the unpaid count',
      () async {
        final container = harness(repo: DemoOrderSnapshotRepository());
        final orders = container.read(
          posRecentOrdersControllerProvider.notifier,
        );
        orders.recordSubmitted(local().order!);

        expect(orders.unpaidCount, 1);

        final ok = await orders.applySnapshots(<PosOrderSnapshot>[
          snap(revision: 3, grand: 0, settlement: PosSettlement.notChargeable),
        ]);

        expect(ok, isTrue);
        final o = container.read(posRecentOrdersControllerProvider).single;
        expect(o.grandTotalMinor, 0, reason: 'the stale total is corrected');
        expect(orders.unpaidCount, 0, reason: 'a comp owes nothing');
      },
    );

    test(
      'A2 a persistence FAILURE reports false so the cursor cannot advance',
      () async {
        // The cursor only moves forward. Advancing it past data we failed to store
        // would lose those orders permanently.
        final container = harness(
          repo: DemoOrderSnapshotRepository(),
          store: _ExplodingStore(),
        );
        final orders = container.read(
          posRecentOrdersControllerProvider.notifier,
        );
        orders.recordSubmitted(local().order!);

        final ok = await orders.applySnapshots(<PosOrderSnapshot>[
          snap(revision: 3),
        ]);

        expect(ok, isFalse, reason: 'the caller must NOT advance the cursor');
        // The in-memory state is still correct and usable — only durability failed.
        expect(
          container.read(posRecentOrdersControllerProvider).single.revision,
          3,
        );
      },
    );

    test('A3 re-applying the same snapshot is a genuine no-op', () async {
      final container = harness(repo: DemoOrderSnapshotRepository());
      final orders = container.read(posRecentOrdersControllerProvider.notifier);
      orders.recordSubmitted(local().order!);
      await orders.applySnapshots(<PosOrderSnapshot>[snap(revision: 3)]);
      final first = container.read(posRecentOrdersControllerProvider);

      await orders.applySnapshots(<PosOrderSnapshot>[snap(revision: 3)]);
      final second = container.read(posRecentOrdersControllerProvider);

      expect(identical(first, second), isTrue);
    });

    test('A4 a typed refusal is recorded against the RIGHT order', () async {
      final container = harness(repo: DemoOrderSnapshotRepository());
      final orders = container.read(posRecentOrdersControllerProvider.notifier);
      orders.recordSubmitted(local().order!);

      orders.recordSyncRefusal('#0000O1', 'order_not_chargeable');

      final o = container.read(posRecentOrdersControllerProvider).single;
      expect(o.syncState, PosOrderSyncState.rejected);
      expect(o.lastSyncError, 'order_not_chargeable');
    });
  });

  group('B. the coordinator', () {
    test('B1 a pull reconciles and advances the cursor', () async {
      final cursors = InMemorySyncCursorStore();
      final repo = DemoOrderSnapshotRepository(
        seed: <PosOrderSnapshot>[
          snap(
            revision: 3,
            status: 'completed',
            settlement: PosSettlement.paid,
          ),
        ],
      );
      final container = harness(repo: repo, cursors: cursors);
      container
          .read(posRecentOrdersControllerProvider.notifier)
          .recordSubmitted(local().order!);

      await container
          .read(posOrderSyncControllerProvider.notifier)
          .syncNow(pushFirst: false);

      final o = container.read(posRecentOrdersControllerProvider).single;
      expect(o.serverStatus, 'completed');
      expect(o.isTerminal, isTrue);

      const scope = PosSyncScope(
        organizationId: 'org1',
        restaurantId: 'r1',
        branchId: 'branch-A',
        deviceId: 'dev1',
      );
      expect(await cursors.load(scope), isNotNull, reason: 'cursor advanced');

      final status = container.read(posOrderSyncControllerProvider);
      expect(status.lastSyncedAt, t0);
      expect(status.error, isNull);
      expect(status.hasEverSynced, isTrue);
    });

    test(
      'B2 a TRANSPORT failure preserves the rows and reports offline',
      () async {
        final repo = DemoOrderSnapshotRepository()
          ..nextFailure = const PosSnapshotException(
            PosSnapshotFailure.transport,
          );
        final container = harness(repo: repo);
        container
            .read(posRecentOrdersControllerProvider.notifier)
            .recordSubmitted(local().order!);

        await container
            .read(posOrderSyncControllerProvider.notifier)
            .syncNow(pushFirst: false);

        expect(
          container.read(posRecentOrdersControllerProvider).length,
          1,
          reason: 'a failed refresh must NEVER blank the till',
        );
        expect(
          container.read(posOrderSyncControllerProvider).error,
          PosSyncError.offline,
        );
      },
    );

    test('B3 a MALFORMED page does NOT advance the cursor', () async {
      final cursors = InMemorySyncCursorStore();
      final repo = DemoOrderSnapshotRepository()
        ..nextFailure = const PosSnapshotException(
          PosSnapshotFailure.malformed,
        );
      final container = harness(repo: repo, cursors: cursors);

      await container
          .read(posOrderSyncControllerProvider.notifier)
          .syncNow(pushFirst: false);

      const scope = PosSyncScope(
        organizationId: 'org1',
        restaurantId: 'r1',
        branchId: 'branch-A',
        deviceId: 'dev1',
      );
      expect(await cursors.load(scope), isNull);
      expect(
        container.read(posOrderSyncControllerProvider).error,
        PosSyncError.malformed,
      );
    });

    test(
      'B4 concurrent callers JOIN the one in-flight pull — no overlap',
      () async {
        final repo = _CountingRepo();
        final container = harness(repo: repo);
        final sync = container.read(posOrderSyncControllerProvider.notifier);

        await Future.wait(<Future<void>>[
          sync.syncNow(pushFirst: false),
          sync.syncNow(pushFirst: false),
          sync.syncNow(pushFirst: false),
        ]);

        expect(
          repo.calls,
          1,
          reason:
              'three racing pulls means two losers silently overwrite a winner',
        );
      },
    );

    test(
      'B5 polling starts with the first visible consumer and STOPS with the last',
      () {
        final container = harness(
          repo: DemoOrderSnapshotRepository(),
          pollInterval: const Duration(seconds: 30),
        );
        final sync = container.read(posOrderSyncControllerProvider.notifier);

        expect(sync.isPolling, isFalse);
        sync.addVisibleConsumer();
        expect(sync.isPolling, isTrue);
        sync.addVisibleConsumer();
        sync.removeVisibleConsumer();
        expect(sync.isPolling, isTrue, reason: 'one consumer still visible');
        sync.removeVisibleConsumer();
        expect(
          sync.isPolling,
          isFalse,
          reason: 'a POS in a drawer must not poll all night',
        );
      },
    );

    test('B6 with NO device/PIN context the coordinator stays quiet', () async {
      final repo = _CountingRepo();
      final container = harness(repo: repo, withScope: false);

      await container
          .read(posOrderSyncControllerProvider.notifier)
          .syncNow(pushFirst: false);

      expect(repo.calls, 0);
      expect(
        container.read(posOrderSyncControllerProvider).error,
        isNull,
        reason: 'no scope yet is not an error — no scary banner at boot',
      );
    });

    test('B7 a TARGETED refresh updates only the named order', () async {
      final repo = DemoOrderSnapshotRepository(
        seed: <PosOrderSnapshot>[
          snap(
            orderId: 'o-1',
            revision: 3,
            grand: 0,
            settlement: PosSettlement.notChargeable,
          ),
          snap(orderId: 'o-2', revision: 9, status: 'completed'),
        ],
      );
      final container = harness(repo: repo);
      final orders = container.read(posRecentOrdersControllerProvider.notifier);
      orders.recordSubmitted(local(orderId: 'o-1').order!);
      orders.recordSubmitted(
        SubmittedOrderView(
          orderNumber: '#0000O2',
          orderType: OrderType.dineIn,
          currencyCode: 'ILS',
          subtotalMinor: 4000,
          lines: const <SubmittedLineView>[],
          orderId: 'o-2',
        ),
      );

      await container
          .read(posOrderSyncControllerProvider.notifier)
          .refreshOrders(<String>['o-1']);

      final list = container.read(posRecentOrdersControllerProvider);
      final o1 = list.firstWhere((o) => o.orderId == 'o-1');
      final o2 = list.firstWhere((o) => o.orderId == 'o-2');
      expect(o1.grandTotalMinor, 0, reason: 'the targeted order reconciled');
      expect(o2.snapshot, isNull, reason: 'the other order was left alone');
    });
  });
}

/// A store whose persist always fails — proves a durability failure is REPORTED
/// rather than silently swallowed (which would let the cursor run ahead of the data).
class _ExplodingStore implements PosRecentOrdersStore {
  @override
  Future<List<PosRecentOrder>> load(String scopeKey) async =>
      <PosRecentOrder>[];

  @override
  Future<void> persist(String scopeKey, List<PosRecentOrder> orders) async =>
      throw Exception('disk full');
}

/// Counts pulls and yields, so concurrent callers genuinely overlap in time.
class _CountingRepo implements OrderSnapshotRepository {
  int calls = 0;

  @override
  Future<PosSnapshotPage> fetchChanges({
    PosSyncCursor? cursor,
    int limit = 50,
    int windowDays = 2,
  }) async {
    calls++;
    await Future<void>.delayed(Duration.zero);
    return PosSnapshotPage.empty;
  }

  @override
  Future<PosSnapshotPage> fetchWindow({
    PosSyncCursor? before,
    int limit = 50,
    int windowDays = 2,
  }) => fetchChanges(limit: limit, windowDays: windowDays);

  @override
  Future<PosSnapshotPage> fetchOrders(List<String> orderIds) async {
    calls++;
    return PosSnapshotPage.empty;
  }
}
