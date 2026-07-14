import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/order_confirmation.dart';
import 'package:restoflow_pos/src/data/order_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// POS-OPERATIONS-SYNC-001 — the independent-review corrections.
///
/// Every one of these reaches the REAL production seam that was defective. None of
/// them hand the code a pre-computed answer and then congratulate it for agreeing.
void main() {
  final t0 = DateTime.utc(2026, 7, 14, 12);

  PosOrderSnapshot snap({
    String id = 'o-1',
    String status = 'served',
    PosSettlement settlement = PosSettlement.unpaid,
    int grand = 4000,
    int revision = 3,
    int minutesAgo = 0,
  }) {
    final at = t0.subtract(Duration(minutes: minutesAgo));
    return PosOrderSnapshot(
      orderId: id,
      orderCode: '#$id',
      revision: revision,
      status: status,
      settlement: settlement,
      subtotalMinor: grand,
      discountTotalMinor: 0,
      taxTotalMinor: 0,
      grandTotalMinor: grand,
      createdAt: at,
      updatedAt: at,
      syncAt: at,
      currencyCode: 'ILS',
    );
  }

  SubmittedOrderView view({String? orderId = 'o-1', int subtotal = 4000}) =>
      SubmittedOrderView(
        orderNumber: '#o-1',
        orderType: OrderType.dineIn,
        currencyCode: 'ILS',
        subtotalMinor: subtotal,
        lines: const <SubmittedLineView>[],
        orderId: orderId,
      );

  // ===========================================================================
  group('BLOCKER 1 — recent-order cache is scoped by the FULL sync scope', () {
    // The store used to key on the DEVICE ID ALONE while the cursor already used
    // org+restaurant+branch+device. A till re-paired into another branch kept the SAME
    // key and was served the previous branch's orders. The scope is also WATCHED now,
    // so the controller actually reacts instead of freezing it at first build.
    const branchA = DeviceContext(
      organizationId: 'org1',
      restaurantId: 'r1',
      branchId: 'branch-A',
      deviceId: 'SAME-DEVICE',
    );
    const branchB = DeviceContext(
      organizationId: 'org1',
      restaurantId: 'r1',
      branchId: 'branch-B',
      deviceId: 'SAME-DEVICE', //  <-- the SAME till
    );

    ProviderContainer harness(PosRecentOrdersStore store) {
      final c = ProviderContainer(
        overrides: [
          posRecentOrdersStoreProvider.overrideWithValue(store),
          // REAL mode, so the scope is derived from the device context rather than
          // collapsing to the fixed demo scope.
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posSyncSessionProvider.overrideWithValue(
            const SyncSession(pinSessionId: 'pin', deviceId: 'SAME-DEVICE'),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test(
      'A/B/C same device, different branch — no leak, and it comes back',
      () async {
        final store = InMemoryRecentOrdersStore();
        final c = harness(store);

        // --- Branch A: submit an order there.
        c.read(posDeviceContextProvider.notifier).set(branchA);
        c
            .read(posRecentOrdersControllerProvider.notifier)
            .recordSubmitted(view());
        await Future<void>.delayed(Duration.zero);
        expect(
          c.read(posRecentOrdersControllerProvider).single.orderId,
          'o-1',
          reason: 'branch A sees its own order',
        );

        // --- Move the SAME till to branch B.
        c.read(posDeviceContextProvider.notifier).set(branchB);
        // The controller WATCHES the scope, so it rebuilt; give _recover a turn.
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(
          c.read(posRecentOrdersControllerProvider),
          isEmpty,
          reason: "branch A's orders must NEVER surface in branch B",
        );

        // --- Back to A: its own cache is still there, unharmed.
        c.read(posDeviceContextProvider.notifier).set(branchA);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(
          c.read(posRecentOrdersControllerProvider).single.orderId,
          'o-1',
          reason: "branch A's cache is restored, not destroyed",
        );
      },
    );

    test('D the scope KEY itself carries every component', () {
      const a = PosSyncScope(
        organizationId: 'org1',
        restaurantId: 'r1',
        branchId: 'branch-A',
        deviceId: 'SAME-DEVICE',
      );
      const b = PosSyncScope(
        organizationId: 'org1',
        restaurantId: 'r1',
        branchId: 'branch-B',
        deviceId: 'SAME-DEVICE',
      );
      expect(
        a.key == b.key,
        isFalse,
        reason: 'the device id alone is NOT an identity for a cache',
      );
    });
  });

  // ===========================================================================
  group('BLOCKER 3 — a SharedPreferences `false` is a real failure', () {
    // setString returns Future<bool> and can report FALSE WITHOUT THROWING. The old
    // code ignored it, so a failed write looked exactly like a successful one — and
    // the cursor advanced past rows that were never stored.

    test('1 the recent-order store treats false as failure', () async {
      final store = SharedPrefsRecentOrdersStore(_RefusingPrefs());
      await expectLater(
        store.persist('scope', <PosRecentOrder>[
          PosRecentOrder(order: view(), submittedAt: t0),
        ]),
        throwsA(isA<PosPersistenceException>()),
      );
    });

    test('2 the cursor store treats false as failure', () async {
      final store = SharedPrefsSyncCursorStore(_RefusingPrefs());
      await expectLater(
        store.save(
          const PosSyncScope(
            organizationId: 'o',
            restaurantId: 'r',
            branchId: 'b',
            deviceId: 'd',
          ),
          PosSyncCursor(at: t0, id: 'x'),
        ),
        throwsA(isA<PosPersistenceException>()),
      );
    });

    test('3 snapshot persistence failure PREVENTS cursor advancement', () async {
      final cursors = InMemorySyncCursorStore();
      final repo = DemoOrderSnapshotRepository(
        seed: <PosOrderSnapshot>[snap(id: 'o-1')],
      )..clock = t0;

      final c = ProviderContainer(
        overrides: [
          // A store whose durable write REFUSES (returns false, does not throw).
          posRecentOrdersStoreProvider.overrideWithValue(
            SharedPrefsRecentOrdersStore(_RefusingPrefs()),
          ),
          posSyncCursorStoreProvider.overrideWithValue(cursors),
          orderSnapshotRepositoryProvider.overrideWithValue(repo),
          posSyncClockProvider.overrideWithValue(() => t0),
          posSyncPollIntervalProvider.overrideWithValue(null),
          posSyncSessionProvider.overrideWithValue(
            const SyncSession(pinSessionId: 'pin', deviceId: 'demo-device'),
          ),
        ],
      );
      addTearDown(c.dispose);

      await c.read(posOrderSyncControllerProvider.notifier).refreshWindow();

      expect(
        await cursors.load(kDemoSyncScope),
        isNull,
        reason:
            'the cursor only moves FORWARD — advancing past rows we failed to '
            'store loses them, because the server never offers them again',
      );
      final status = c.read(posOrderSyncControllerProvider);
      expect(status.error, PosSyncError.persistence);
      expect(
        status.lastSyncedAt,
        isNull,
        reason: 'lastSyncedAt is a promise, not a decoration',
      );

      // 7. RETRY can process the very same server data again.
      expect((await repo.fetchWindow()).orders.single.orderId, 'o-1');
    });
  });

  // ===========================================================================
  group('BLOCKER 4 — the window pages NEWEST-FIRST', () {
    // The window used to page ASCENDING from the start, so the FIRST page held the
    // OLDEST rows. Past the drain cap the newest order was NEVER reached — while the
    // UI still reported a successful sync.

    DemoOrderSnapshotRepository busyBranch({int rows = 500}) {
      final seed = <PosOrderSnapshot>[
        for (var i = 0; i < rows; i++)
          snap(
            id: 'o$i',
            minutesAgo: rows - i,
          ), // o0 oldest ... o(rows-1) newest
      ];
      return DemoOrderSnapshotRepository(seed: seed)
        ..clock = t0
        ..pageLimit = 50;
    }

    test(
      '1+2 on a branch far bigger than the old cap, the NEWEST order is on page 1',
      () async {
        final repo = busyBranch(rows: 500);
        final page = await repo.fetchWindow(limit: 50);
        expect(
          page.orders.first.orderId,
          'o499',
          reason:
              'the newest order is the FIRST row of the FIRST page, by construction',
        );
      },
    );

    test('4+5+6+7 load-more walks backward: no duplicate, no skip', () async {
      final repo = busyBranch(rows: 200);
      final p1 = await repo.fetchWindow(limit: 50);
      final p2 = await repo.fetchWindow(before: p1.nextCursor, limit: 50);

      final ids1 = p1.orders.map((o) => o.orderId).toSet();
      final ids2 = p2.orders.map((o) => o.orderId).toSet();
      expect(ids1.intersection(ids2), isEmpty, reason: 'no duplicate');
      expect(
        p2.orders.first.syncAt.isBefore(p1.orders.last.syncAt),
        isTrue,
        reason: 'strictly older — monotonic descent, no skip',
      );
    });

    test('3 equal sync_at rows page deterministically by ORDER ID', () async {
      // Every row shares one timestamp to the microsecond. Only the id can break it.
      final same = <PosOrderSnapshot>[
        for (var i = 0; i < 6; i++) snap(id: 'x$i', minutesAgo: 0),
      ];
      final repo = DemoOrderSnapshotRepository(seed: same)
        ..clock = t0
        ..pageLimit = 3;
      final p1 = await repo.fetchWindow(limit: 3);
      final p2 = await repo.fetchWindow(before: p1.nextCursor, limit: 3);

      final all = <String>[
        ...p1.orders.map((o) => o.orderId),
        ...p2.orders.map((o) => o.orderId),
      ];
      expect(all.toSet().length, 6, reason: 'no duplicate across pages');
      expect(all.length, 6, reason: 'no row skipped between pages');
    });

    test('8+9 the two cursors are INDEPENDENT', () async {
      final cursors = InMemorySyncCursorStore();
      final repo = busyBranch(rows: 120);
      final c = ProviderContainer(
        overrides: [
          posRecentOrdersStoreProvider.overrideWithValue(
            InMemoryRecentOrdersStore(),
          ),
          posSyncCursorStoreProvider.overrideWithValue(cursors),
          orderSnapshotRepositoryProvider.overrideWithValue(repo),
          posSyncClockProvider.overrideWithValue(() => t0),
          posSyncPollIntervalProvider.overrideWithValue(null),
          posSyncSessionProvider.overrideWithValue(
            const SyncSession(pinSessionId: 'pin', deviceId: 'demo-device'),
          ),
        ],
      );
      addTearDown(c.dispose);
      final sync = c.read(posOrderSyncControllerProvider.notifier);

      await sync.refreshWindow();
      final seeded = await cursors.load(kDemoSyncScope);
      expect(
        seeded,
        isNotNull,
        reason: 'the durable cursor is SEEDED to the newest row',
      );

      // LOAD MORE must not touch the durable change-feed cursor.
      await sync.loadMore();
      expect(
        await cursors.load(kDemoSyncScope),
        seeded,
        reason: 'paging back through history says NOTHING about what changed',
      );
      expect(sync.windowCursor, isNotNull);

      // An incremental refresh must not reset the window paging.
      final windowBefore = sync.windowCursor;
      await sync.syncNow(pushFirst: false);
      expect(sync.windowCursor, windowBefore);
    });

    test(
      '10 a refresh returns the RECENT rows, not the oldest prefix',
      () async {
        final repo = busyBranch(rows: 400);
        final c = ProviderContainer(
          overrides: [
            posRecentOrdersStoreProvider.overrideWithValue(
              InMemoryRecentOrdersStore(),
            ),
            posSyncCursorStoreProvider.overrideWithValue(
              InMemorySyncCursorStore(),
            ),
            orderSnapshotRepositoryProvider.overrideWithValue(repo),
            posSyncClockProvider.overrideWithValue(() => t0),
            posSyncPollIntervalProvider.overrideWithValue(null),
            posSyncSessionProvider.overrideWithValue(
              const SyncSession(pinSessionId: 'pin', deviceId: 'demo-device'),
            ),
          ],
        );
        addTearDown(c.dispose);

        await c.read(posOrderSyncControllerProvider.notifier).refreshWindow();
        final ids = c
            .read(posRecentOrdersControllerProvider)
            .map((o) => o.orderId)
            .toSet();
        expect(
          ids.contains('o399'),
          isTrue,
          reason: 'the newest order IS there',
        );
        expect(
          ids.contains('o0'),
          isFalse,
          reason: 'and not the oldest prefix',
        );
      },
    );
  });

  // ===========================================================================
  group('BLOCKER 5 — dedupe by the AUTHORITATIVE order id', () {
    // The row map used to key on `orderNumber` — a SHORTENED display code. Two
    // genuinely different server orders sharing one silently collapsed into a single
    // row, and one of them vanished from the till.

    ProviderContainer harness() {
      final c = ProviderContainer(
        overrides: [
          posRecentOrdersStoreProvider.overrideWithValue(
            InMemoryRecentOrdersStore(),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test(
      '1 two DIFFERENT orders that share a display code BOTH survive',
      () async {
        final c = harness();
        final ctl = c.read(posRecentOrdersControllerProvider.notifier);

        // Same display code (#DUP), different authoritative server ids.
        ctl.recordSubmitted(
          SubmittedOrderView(
            orderNumber: '#DUP',
            orderType: OrderType.dineIn,
            currencyCode: 'ILS',
            subtotalMinor: 1000,
            lines: const <SubmittedLineView>[],
            orderId: 'server-A',
          ),
        );
        ctl.recordSubmitted(
          SubmittedOrderView(
            orderNumber: '#DUP',
            orderType: OrderType.dineIn,
            currencyCode: 'ILS',
            subtotalMinor: 2000,
            lines: const <SubmittedLineView>[],
            orderId: 'server-B',
          ),
        );

        final ids = c
            .read(posRecentOrdersControllerProvider)
            .map((o) => o.orderId)
            .toSet();
        expect(ids, <String>{
          'server-A',
          'server-B',
        }, reason: 'a display code is for reading, not for identity');
      },
    );

    test('2 the SAME server order from two origins becomes ONE row', () async {
      final c = harness();
      final ctl = c.read(posRecentOrdersControllerProvider.notifier);
      ctl.recordSubmitted(view(orderId: 'same'));
      await ctl.applySnapshots(<PosOrderSnapshot>[
        snap(id: 'same', revision: 9),
      ]);

      final rows = c.read(posRecentOrdersControllerProvider);
      expect(rows.length, 1);
      expect(rows.single.origin, PosOrderOrigin.deviceOwned);
      expect(rows.single.revision, 9);
    });

    test('3 a local draft cannot be swallowed by a server row', () async {
      final c = harness();
      final ctl = c.read(posRecentOrdersControllerProvider.notifier);
      // No server id: a queued submit keyed by its own local operation identity.
      ctl.recordSubmitted(
        SubmittedOrderView(
          orderNumber: '#DUP',
          orderType: OrderType.dineIn,
          currencyCode: 'ILS',
          subtotalMinor: 1000,
          lines: const <SubmittedLineView>[],
          localOperationId: 'local-op-1',
        ),
      );
      ctl.recordSubmitted(
        SubmittedOrderView(
          orderNumber: '#DUP',
          orderType: OrderType.dineIn,
          currencyCode: 'ILS',
          subtotalMinor: 2000,
          lines: const <SubmittedLineView>[],
          orderId: 'server-A',
        ),
      );
      expect(
        c.read(posRecentOrdersControllerProvider).length,
        2,
        reason: 'the unsent order must not disappear into a server row',
      );
    });
  });

  // ===========================================================================
  group('BLOCKER 2 — OrderConfirmation binds to AUTHORITATIVE state', () {
    // It rendered a frozen SubmittedOrderView and decided its own actions. While it
    // sat open the order could be comped, paid elsewhere, completed or voided — and it
    // carried on showing the old total and offering Take payment.

    Future<ProviderContainer> pumpConfirmation(WidgetTester tester) async {
      final c = ProviderContainer(
        overrides: [
          posRecentOrdersStoreProvider.overrideWithValue(
            InMemoryRecentOrdersStore(),
          ),
          posSyncCursorStoreProvider.overrideWithValue(
            InMemorySyncCursorStore(),
          ),
          posSyncPollIntervalProvider.overrideWithValue(null),
          posSyncClockProvider.overrideWithValue(() => t0),
        ],
      );
      addTearDown(c.dispose);

      // The order exists on this till, submitted at 40.
      c
          .read(posRecentOrdersControllerProvider.notifier)
          .recordSubmitted(view());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(
              body: OrderConfirmation(order: view(), onNewOrder: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets(
      '1-3 a comp landing WHILE THE SCREEN IS OPEN updates it in place',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final c = await pumpConfirmation(tester);

        // Opens showing 40, and offering payment.
        expect(find.text('₪40.00'), findsWidgets);
        expect(find.byKey(const Key('pay-cash-button')), findsOneWidget);

        // The server comps it to zero. NO reopen, NO new fixture — the SAME screen.
        await c.read(posRecentOrdersControllerProvider.notifier).applySnapshots(
          <PosOrderSnapshot>[
            snap(
              id: 'o-1',
              revision: 4,
              grand: 0,
              settlement: PosSettlement.notChargeable,
            ),
          ],
        );
        await tester.pumpAndSettle();

        expect(
          find.text('₪0.00'),
          findsWidgets,
          reason: 'the stale 40 is GONE',
        );
        expect(
          find.byKey(const Key('pay-cash-button')),
          findsNothing,
          reason: 'an order that owes nothing must not offer Take payment',
        );
      },
    );

    testWidgets('4-6 a TERMINAL transition while open strips every action', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final c = await pumpConfirmation(tester);
      expect(find.byKey(const Key('pay-cash-button')), findsOneWidget);

      // The KITCHEN completed it. This device did nothing.
      await c.read(posRecentOrdersControllerProvider.notifier).applySnapshots(
        <PosOrderSnapshot>[
          snap(
            id: 'o-1',
            status: 'completed',
            settlement: PosSettlement.paid,
            revision: 6,
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pay-cash-button')), findsNothing);
      expect(find.byKey(const Key('apply-discount-button')), findsNothing);
    });

    testWidgets('8 a GENERIC error does NOT make the order look terminal', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final c = await pumpConfirmation(tester);
      // A refusal that says nothing about the order's state must not change it.
      c
          .read(posRecentOrdersControllerProvider.notifier)
          .recordSyncRefusal(PosOrderIdentity.server('o-1'), 'rejected');
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('pay-cash-button')),
        findsOneWidget,
        reason:
            'terminality is read from the STATUS, never guessed from an error',
      );
    });
  });
}

/// A SharedPreferences whose writes REFUSE — returning `false` WITHOUT throwing.
///
/// This is the exact production failure mode the review caught: a full disk, or a
/// browser refusing localStorage. It does not throw, so code that ignores the returned
/// bool cannot tell it apart from success.
class _RefusingPrefs implements SharedPreferences {
  @override
  Future<bool> setString(String key, String value) async => false;

  @override
  String? getString(String key) => null;

  @override
  Future<bool> remove(String key) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
