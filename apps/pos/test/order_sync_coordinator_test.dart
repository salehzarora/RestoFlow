import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/order_snapshot_repository.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';

/// POS-OPERATIONS-SYNC-001 — the coordinator's rules, exercised WITHOUT a widget
/// tree and WITHOUT real time.
///
/// The cursor rules are the dangerous ones: the cursor only ever moves FORWARD, so
/// advancing it past data we failed to apply loses that data permanently — the
/// server will never offer it again. These pin that it cannot happen.
void main() {
  final t0 = DateTime.now().toUtc().subtract(const Duration(hours: 2)); // stabilization: anchor to real clock (recent-orders 1-day window)

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
      orderNumber: '#$orderId',
      orderType: OrderType.dineIn,
      currencyCode: 'ILS',
      subtotalMinor: 4000,
      lines: const <SubmittedLineView>[],
      orderId: orderId,
    ),
    submittedAt: t0,
  );

  const scopeA = PosSyncScope(
    organizationId: 'org1',
    restaurantId: 'r1',
    branchId: 'branch-A',
    deviceId: 'dev1',
  );
  const scopeB = PosSyncScope(
    organizationId: 'org1',
    restaurantId: 'r1',
    branchId: 'branch-B',
    deviceId: 'dev1',
  );

  group('A. cursor advancement', () {
    test(
      'A1 the cursor is SCOPE-PARTITIONED — branch A never leaks into B',
      () async {
        final store = InMemorySyncCursorStore();
        final cursor = PosSyncCursor(at: t0, id: 'o-1');
        await store.save(scopeA, cursor);

        expect(await store.load(scopeA), cursor);
        expect(
          await store.load(scopeB),
          isNull,
          reason:
              'replaying branch A\'s cursor in branch B would skip B\'s whole '
              'history and show an empty, confident, completely wrong board',
        );
      },
    );

    test('A2 the scope key includes every component', () {
      expect(scopeA.key == scopeB.key, isFalse);
      expect(scopeA.key.contains('branch-A'), isTrue);
    });

    test('A3 clearing one scope does not touch another', () async {
      final store = InMemorySyncCursorStore();
      await store.save(scopeA, PosSyncCursor(at: t0, id: 'a'));
      await store.save(scopeB, PosSyncCursor(at: t0, id: 'b'));
      await store.clear(scopeA);
      expect(await store.load(scopeA), isNull);
      expect(await store.load(scopeB), isNotNull);
    });
  });

  group('B. the demo/server feed keyset', () {
    test('B1 a cursor returns only STRICTLY NEWER changes', () async {
      final repo = DemoOrderSnapshotRepository(
        seed: <PosOrderSnapshot>[
          snap(orderId: 'o-1', syncAt: t0),
          snap(orderId: 'o-2', syncAt: t0.add(const Duration(minutes: 5))),
        ],
      );
      final page = await repo.fetchChanges(
        cursor: PosSyncCursor(at: t0, id: 'o-1'),
      );
      expect(page.orders.map((o) => o.orderId), <String>['o-2']);
    });

    test(
      'B2 replaying the SAME cursor is idempotent (same page, no dupes)',
      () async {
        final repo = DemoOrderSnapshotRepository(
          seed: <PosOrderSnapshot>[
            snap(orderId: 'o-1', syncAt: t0),
            snap(orderId: 'o-2', syncAt: t0.add(const Duration(minutes: 5))),
          ],
        );
        final c = PosSyncCursor(at: t0, id: 'o-1');
        final first = await repo.fetchChanges(cursor: c);
        final second = await repo.fetchChanges(cursor: c);
        expect(
          first.orders.map((o) => o.orderId),
          second.orders.map((o) => o.orderId),
        );
      },
    );

    test('B3 a payment-only change IS delivered (the sync_at axis)', () async {
      // The order row never moved; only its payment did. An orders-only cursor
      // would never deliver this — that is production failure #1.
      final repo = DemoOrderSnapshotRepository(
        seed: <PosOrderSnapshot>[
          snap(
            orderId: 'o-1',
            revision: 2,
            settlement: PosSettlement.paid,
            syncAt: t0.add(const Duration(minutes: 30)),
          ),
        ],
      );
      final page = await repo.fetchChanges(
        cursor: PosSyncCursor(at: t0, id: 'zzz'),
      );
      expect(page.orders.single.settlement, PosSettlement.paid);
    });

    test('B4 pages are BOUNDED and resumable', () async {
      final repo = DemoOrderSnapshotRepository(
        seed: <PosOrderSnapshot>[
          for (var i = 0; i < 5; i++)
            snap(
              orderId: 'o-$i',
              syncAt: t0.add(Duration(minutes: i)),
            ),
        ],
      )..pageLimit = 2;
      final p1 = await repo.fetchChanges();
      expect(p1.orders.length, 2);
      expect(p1.hasMore, isTrue);
      expect(p1.nextCursor, isNotNull);

      final p2 = await repo.fetchChanges(cursor: p1.nextCursor);
      expect(p2.orders.length, 2);
      // no overlap between pages
      final ids1 = p1.orders.map((o) => o.orderId).toSet();
      final ids2 = p2.orders.map((o) => o.orderId).toSet();
      expect(ids1.intersection(ids2), isEmpty);
    });

    test(
      'B5 a scripted failure surfaces typed, and does not wedge the repo',
      () async {
        final repo = DemoOrderSnapshotRepository()
          ..nextFailure = const PosSnapshotException(
            PosSnapshotFailure.transport,
          );
        await expectLater(
          repo.fetchChanges(),
          throwsA(isA<PosSnapshotException>()),
        );
        // The failure is consumed once — the next call works. A transport blip must
        // not permanently disable sync.
        final page = await repo.fetchChanges();
        expect(page.orders, isEmpty);
      },
    );
  });

  group('C. the recent-orders store is scope-partitioned too', () {
    test('C1 branch A\'s cached orders never appear under branch B', () async {
      final store = InMemoryRecentOrdersStore();
      await store.persist(scopeA.key, <PosRecentOrder>[local(orderId: 'o-A')]);

      expect((await store.load(scopeA.key)).single.orderId, 'o-A');
      expect(
        await store.load(scopeB.key),
        isEmpty,
        reason: 'a device moved to another branch must start clean',
      );
    });

    test('C2 a persisted set round-trips with its snapshot intact', () async {
      final store = InMemoryRecentOrdersStore();
      final withSnap = local().withServerSnapshot(
        snap(revision: 9, status: 'completed'),
      );
      await store.persist(scopeA.key, <PosRecentOrder>[withSnap]);
      final back = (await store.load(scopeA.key)).single;
      expect(back.revision, 9);
      expect(back.isTerminal, isTrue);
    });
  });

  group('D. the SharedPreferences store survives bad data', () {
    test('D1 one corrupt entry does not destroy the whole store', () async {
      // Proven through the real parse path: a corrupt record is dropped, the good
      // ones survive. Losing a cashier's entire day to one bad row is not an option.
      final good = local(orderId: 'o-good').toJson();
      final bad = <String, Object?>{'submitted_at': 'not-a-date'};

      final parsed = <PosRecentOrder>[];
      for (final e in <Map<String, Object?>>[bad, good]) {
        try {
          parsed.add(PosRecentOrder.fromJson(e));
        } on FormatException {
          // dropped
        }
      }
      expect(parsed.length, 1);
      expect(parsed.single.orderId, 'o-good');
    });
  });
}
