import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/discount.dart';
import 'package:restoflow_pos/src/data/discount_repository.dart';
import 'package:restoflow_pos/src/data/order_identity.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/order_snapshot_repository.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/discount_controller.dart'
    show discountRepositoryProvider;
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/discount_sheet.dart';
import 'package:restoflow_pos/src/widgets/order_confirmation.dart';

/// POS-OPERATIONS-SYNC-001 — the SECOND independent-review corrections.
///
/// Every test here drives the REAL production seam that was defective: the actual
/// controllers, the actual providers, the actual scope transitions. None of them hands
/// the code a pre-computed key, a pre-deduped list or a pre-decided eligibility and
/// then congratulates it for agreeing.
void main() {
  final t0 = DateTime.now().toUtc().subtract(
    const Duration(hours: 2),
  ); // stabilization: anchor to real clock (recent-orders 1-day window)

  // The SAME till, moved between two branches. This is the whole point: the device id
  // is identical, so nothing but the full scope can tell the two situations apart.
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
    deviceId: 'SAME-DEVICE',
  );

  PosOrderSnapshot snap({
    String id = 'o-1',
    String code = '#o-1',
    String status = 'served',
    PosSettlement settlement = PosSettlement.unpaid,
    int grand = 4000,
    int revision = 3,
    int minutesAgo = 0,
  }) {
    final at = t0.subtract(Duration(minutes: minutesAgo));
    return PosOrderSnapshot(
      orderId: id,
      orderCode: code,
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

  SubmittedOrderView view({
    String? orderId = 'o-1',
    String code = '#o-1',
    int subtotal = 4000,
  }) => SubmittedOrderView(
    orderNumber: code,
    orderType: OrderType.dineIn,
    currencyCode: 'ILS',
    subtotalMinor: subtotal,
    lines: const <SubmittedLineView>[],
    orderId: orderId,
  );

  CashPayment payment({
    String? orderId = 'o-1',
    String code = '#o-1',
    int amount = 4000,
  }) => CashPayment(
    paymentId: 'pay-$orderId',
    orderId: orderId,
    orderNumber: code,
    deviceId: 'SAME-DEVICE',
    localOperationId: 'op-$orderId',
    method: PaymentMethod.cash,
    status: PaymentStatus.completed,
    amountMinor: amount,
    tenderedMinor: amount,
    changeMinor: 0,
    currencyCode: 'ILS',
    receiptNumber: 'R-1',
    paidAt: t0,
  );

  ProviderContainer harness({
    PosRecentOrdersStore? store,
    OrderSnapshotRepository? repo,
    PosSyncCursorStore? cursors,
    DiscountRepository? discounts,
    PaymentRepository? payments,
  }) {
    final c = ProviderContainer(
      overrides: [
        // REAL mode: the scope comes from the device context, instead of collapsing
        // onto the single fixed demo scope where a branch change cannot even happen.
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posSyncSessionProvider.overrideWithValue(
          const SyncSession(pinSessionId: 'pin', deviceId: 'SAME-DEVICE'),
        ),
        posSyncClockProvider.overrideWithValue(() => t0),
        if (store != null)
          posRecentOrdersStoreProvider.overrideWithValue(store),
        if (repo != null)
          orderSnapshotRepositoryProvider.overrideWithValue(repo),
        if (cursors != null)
          posSyncCursorStoreProvider.overrideWithValue(cursors),
        if (discounts != null)
          discountRepositoryProvider.overrideWithValue(discounts),
        // The REAL payment repository needs a live transport; the association under
        // test is the same either way, so these use the production demo store.
        if (payments != null)
          paymentRepositoryProvider.overrideWithValue(payments),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Lets the microtasks that a scope change kicks off actually run.
  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  // ===========================================================================
  group('HIGH 1 — a stale async result cannot cross a scope boundary', () {
    test(
      '1E-1/2 a window refresh begun in A, landing after the move, never touches B',
      () async {
        final gate = Completer<PosSnapshotPage>();
        final repo = _GatedRepo(window: gate);
        final store = InMemoryRecentOrdersStore();
        final cursors = InMemorySyncCursorStore();
        final c = harness(store: store, repo: repo, cursors: cursors);

        c.read(posDeviceContextProvider.notifier).set(branchA);
        await settle();
        final sync = c.read(posOrderSyncControllerProvider.notifier);

        // A refresh starts in branch A and BLOCKS on the network.
        final pending = sync.refreshWindow();

        // The till is re-paired into branch B while it is in flight.
        c.read(posDeviceContextProvider.notifier).set(branchB);
        await settle();

        // NOW branch A's response arrives.
        gate.complete(
          PosSnapshotPage(
            orders: [snap(id: 'A-ORDER')],
            hasMore: true,
            nextCursor: PosSyncCursor(at: t0, id: 'A-ORDER'),
          ),
        );
        await pending;
        await settle();

        // Branch A's order is not on branch B's screen...
        expect(
          c.read(posRecentOrdersControllerProvider),
          isEmpty,
          reason: "branch A's order must never appear in branch B",
        );
        // ...nor in branch B's storage...
        final bScope = c.read(posSyncScopeProvider)!;
        expect(await store.load(bScope.key), isEmpty);
        // ...nor may A's fetch have made a promise on B's behalf.
        final status = c.read(posOrderSyncControllerProvider);
        expect(status.lastSyncedAt, isNull);
        expect(status.hasEverSynced, isFalse);
        expect(
          status.error,
          isNull,
          reason:
              'obsolete work is CANCELLED, not failed — B has nothing to apologise for',
        );
        // ...and B's window cursor is its own (untouched by A's page).
        expect(sync.windowCursor, isNull);
        // The cursor A's page would have seeded belongs to A alone.
        expect(await cursors.load(bScope), isNull);
      },
    );

    test(
      '1E-2 an INCREMENTAL run begun in A is discarded when B arrives',
      () async {
        final gate = Completer<PosSnapshotPage>();
        final repo = _GatedRepo(changes: gate);
        final store = InMemoryRecentOrdersStore();
        final cursors = InMemorySyncCursorStore();
        final c = harness(store: store, repo: repo, cursors: cursors);

        c.read(posDeviceContextProvider.notifier).set(branchA);
        await settle();
        // A durable cursor exists for A, so syncNow takes the INCREMENTAL path.
        final aScope = c.read(posSyncScopeProvider)!;
        await cursors.save(aScope, PosSyncCursor(at: t0, id: 'seed'));

        final sync = c.read(posOrderSyncControllerProvider.notifier);
        final pending = sync.syncNow(pushFirst: false);

        c.read(posDeviceContextProvider.notifier).set(branchB);
        await settle();

        gate.complete(
          PosSnapshotPage(
            orders: [snap(id: 'A-CHANGED')],
            hasMore: false,
            nextCursor: PosSyncCursor(at: t0, id: 'A-CHANGED'),
          ),
        );
        await pending;
        await settle();

        expect(c.read(posRecentOrdersControllerProvider), isEmpty);
        final bScope = c.read(posSyncScopeProvider)!;
        expect(await store.load(bScope.key), isEmpty);
        expect(await cursors.load(bScope), isNull, reason: "B's cursor is B's");
        expect(c.read(posOrderSyncControllerProvider).lastSyncedAt, isNull);
      },
    );

    test('1E-3 a TARGETED refresh begun in A cannot mutate B', () async {
      final gate = Completer<PosSnapshotPage>();
      final repo = _GatedRepo(targeted: gate);
      final store = InMemoryRecentOrdersStore();
      final c = harness(store: store, repo: repo);

      c.read(posDeviceContextProvider.notifier).set(branchA);
      await settle();

      final pending = c
          .read(posOrderSyncControllerProvider.notifier)
          .refreshOrders(<String>['A-ORDER']);

      c.read(posDeviceContextProvider.notifier).set(branchB);
      await settle();

      gate.complete(
        const PosSnapshotPage(orders: <PosOrderSnapshot>[], hasMore: false),
      );
      // The page is non-empty in the dangerous case; use one.
      await pending;
      await settle();

      expect(c.read(posRecentOrdersControllerProvider), isEmpty);
      expect(
        c.read(posOrderSyncControllerProvider).lastSyncedAt,
        isNull,
        reason: "A's targeted refresh must not stamp B as freshly synced",
      );
    });

    test('1E-4 a targeted refresh with REAL rows still cannot cross', () async {
      final gate = Completer<PosSnapshotPage>();
      final repo = _GatedRepo(targeted: gate);
      final store = InMemoryRecentOrdersStore();
      final c = harness(store: store, repo: repo);

      c.read(posDeviceContextProvider.notifier).set(branchA);
      await settle();

      final pending = c
          .read(posOrderSyncControllerProvider.notifier)
          .refreshOrders(<String>['A-ORDER']);

      c.read(posDeviceContextProvider.notifier).set(branchB);
      await settle();

      gate.complete(
        PosSnapshotPage(orders: [snap(id: 'A-ORDER')], hasMore: false),
      );
      await pending;
      await settle();

      expect(
        c.read(posRecentOrdersControllerProvider),
        isEmpty,
        reason: "A's authoritative row must not be applied into B",
      );
      final bScope = c.read(posSyncScopeProvider)!;
      expect(await store.load(bScope.key), isEmpty);
    });

    test('1D a _recover begun for A is discarded once B is active', () async {
      final store = _GatedStore();
      final c = harness(store: store);

      // Branch A: the controller builds and _recover() blocks on the load.
      c.read(posDeviceContextProvider.notifier).set(branchA);
      c.read(posRecentOrdersControllerProvider); // force the build
      await settle();
      expect(store.pending.length, 1, reason: 'A recovery is in flight');

      // Move to B. Its own recovery starts and completes with nothing.
      c.read(posDeviceContextProvider.notifier).set(branchB);
      c.read(posRecentOrdersControllerProvider);
      await settle();
      store.completeFor('branch-B', const <PosRecentOrder>[]);
      await settle();

      // NOW A's load finally returns — with A's orders.
      store.completeFor('branch-A', [
        PosRecentOrder(
          order: view(orderId: 'A-ORDER'),
          submittedAt: t0,
        ),
      ]);
      await settle();

      expect(
        c.read(posRecentOrdersControllerProvider),
        isEmpty,
        reason: "branch A's recovered day must not land on branch B's till",
      );
      expect(
        store.persisted.keys.where((k) => k.contains('branch-B')),
        isEmpty,
        reason: "and it must not be written under B's key",
      );
    });

    test(
      '1C the window cursor belongs to ONE scope — B never inherits A\'s',
      () async {
        final repo = _PagingRepo();
        final c = harness(store: InMemoryRecentOrdersStore(), repo: repo);

        c.read(posDeviceContextProvider.notifier).set(branchA);
        await settle();
        final sync = c.read(posOrderSyncControllerProvider.notifier);

        await sync.refreshWindow();
        await settle();
        expect(sync.windowCursor, isNotNull, reason: 'A has paged somewhere');
        expect(c.read(posOrderSyncControllerProvider).hasMoreHistory, isTrue);

        // Move to B.
        c.read(posDeviceContextProvider.notifier).set(branchB);
        await settle();

        expect(
          sync.windowCursor,
          isNull,
          reason: "B starts from B's newest order, not from A's position",
        );
        expect(
          c.read(posOrderSyncControllerProvider).hasMoreHistory,
          isFalse,
          reason:
              'B has not looked yet, so it claims nothing about its history',
        );

        // Loading more in B must not send A's cursor.
        repo.sentBefore.clear();
        await sync.refreshWindow();
        await sync.loadMore();
        await settle();
        expect(
          repo.sentBefore.first,
          isNull,
          reason: "B's first window page starts at B's newest order",
        );
      },
    );
  });

  // ===========================================================================
  group('HIGH 2 — payment/void/receipt identity is the order, not its code', () {
    test(
      '2G-1..6 two orders share #DUP: paying one leaves the other unpaid',
      () async {
        final c = harness(
          store: InMemoryRecentOrdersStore(),
          payments: DemoPaymentStore(),
        );
        c.read(posDeviceContextProvider.notifier).set(branchA);
        await settle();

        final orders = c.read(posRecentOrdersControllerProvider.notifier);
        // TWO GENUINELY DIFFERENT SERVER ORDERS THAT SHARE A DISPLAY CODE.
        orders.recordSubmitted(view(orderId: 'ORDER-A', code: '#DUP'));
        orders.recordSubmitted(view(orderId: 'ORDER-B', code: '#DUP'));
        await settle();
        expect(
          c.read(posRecentOrdersControllerProvider).length,
          2,
          reason: 'a shared code is not a shared order',
        );

        // Pay A through the REAL payment controller (demo repo), so the identity
        // travels the production path rather than being handed to the lookup.
        await c
            .read(paymentControllerProvider.notifier)
            .payCash(
              identity: PosOrderIdentity.server('ORDER-A'),
              orderId: 'ORDER-A',
              orderNumber: '#DUP',
              amountMinor: 4000,
              tenderedMinor: 4000,
              currencyCode: 'ILS',
            );
        await settle();

        final rows = c.read(posRecentOrdersControllerProvider);
        final a = rows.firstWhere((o) => o.orderId == 'ORDER-A');
        final b = rows.firstWhere((o) => o.orderId == 'ORDER-B');

        expect(a.isPaid, isTrue, reason: 'the order that was paid is paid');
        expect(
          b.isPaid,
          isFalse,
          reason: 'the OTHER order was not paid and must not say it was',
        );
        expect(b.payment, isNull, reason: "B must not inherit A's payment");
        expect(b.settlement, PosSettlement.unpaid);
        expect(
          b.canReprintReceipt,
          isFalse,
          reason: "B must not be able to print A's receipt",
        );
        expect(
          orders.unpaidCount,
          1,
          reason: 'exactly one of the two still owes money',
        );
      },
    );

    test('2G-8 markVoided targets the identity, not the code', () async {
      final c = harness(store: InMemoryRecentOrdersStore());
      c.read(posDeviceContextProvider.notifier).set(branchA);
      await settle();

      final orders = c.read(posRecentOrdersControllerProvider.notifier);
      orders.recordSubmitted(view(orderId: 'ORDER-A', code: '#DUP'));
      orders.recordSubmitted(view(orderId: 'ORDER-B', code: '#DUP'));
      await settle();

      orders.markVoided(PosOrderIdentity.server('ORDER-A'), 'wrong order');
      await settle();

      final rows = c.read(posRecentOrdersControllerProvider);
      expect(rows.firstWhere((o) => o.orderId == 'ORDER-A').isVoided, isTrue);
      expect(
        rows.firstWhere((o) => o.orderId == 'ORDER-B').isVoided,
        isFalse,
        reason: 'cancelling one order must not cancel the other',
      );
    });

    test('2G-9 orderFor resolves by identity', () async {
      final c = harness(store: InMemoryRecentOrdersStore());
      c.read(posDeviceContextProvider.notifier).set(branchA);
      await settle();
      final orders = c.read(posRecentOrdersControllerProvider.notifier);
      orders.recordSubmitted(
        view(orderId: 'ORDER-A', code: '#DUP', subtotal: 1000),
      );
      orders.recordSubmitted(
        view(orderId: 'ORDER-B', code: '#DUP', subtotal: 2000),
      );
      await settle();

      expect(
        orders.orderFor(PosOrderIdentity.server('ORDER-B'))!.subtotalMinor,
        2000,
      );
      expect(
        orders.orderFor(PosOrderIdentity.server('ORDER-A'))!.subtotalMinor,
        1000,
      );
    });

    test('2G-10/11/13 a restart round-trip keeps both #DUP orders — and the legacy '
        'payment (no order_id) stays on the order that recorded it', () async {
      final store = InMemoryRecentOrdersStore();
      final c = harness(store: store);
      c.read(posDeviceContextProvider.notifier).set(branchA);
      await settle();
      final scope = c.read(posSyncScopeProvider)!;

      // A PRE-UPGRADE persisted day: two orders sharing a code, one of them paid,
      // and the payment carries NO order_id (the field did not exist).
      final legacyPaid = PosRecentOrder(
        order: view(orderId: 'ORDER-A', code: '#DUP'),
        submittedAt: t0,
        payment: payment(orderId: null, code: '#DUP'),
      );
      final unpaid = PosRecentOrder(
        order: view(orderId: 'ORDER-B', code: '#DUP'),
        submittedAt: t0,
      );
      await store.persist(scope.key, <PosRecentOrder>[legacyPaid, unpaid]);

      // Restart: a brand-new container recovers from that storage.
      final c2 = harness(store: store);
      c2.read(posDeviceContextProvider.notifier).set(branchA);
      c2.read(posRecentOrdersControllerProvider);
      await settle();

      final rows = c2.read(posRecentOrdersControllerProvider);
      expect(
        rows.length,
        2,
        reason: 'recovery keyed on the code collapsed these into one',
      );
      final a = rows.firstWhere((o) => o.orderId == 'ORDER-A');
      final b = rows.firstWhere((o) => o.orderId == 'ORDER-B');
      expect(a.isPaid, isTrue, reason: 'the legacy payment stays where it was');
      expect(
        a.payment!.orderId,
        isNull,
        reason: 'we do not fabricate an id the record never had',
      );
      expect(
        b.isPaid,
        isFalse,
        reason:
            'a legacy payment must never be re-attached by code to a second order',
      );
    });

    test(
      '2G-11 the same server order seen twice (device-owned + discovered) is ONE row',
      () async {
        final c = harness(store: InMemoryRecentOrdersStore());
        c.read(posDeviceContextProvider.notifier).set(branchA);
        await settle();
        final orders = c.read(posRecentOrdersControllerProvider.notifier);

        orders.recordSubmitted(view(orderId: 'ORDER-A', code: '#DUP'));
        await settle();
        // The same order arrives again on the branch feed.
        await orders.applySnapshots([snap(id: 'ORDER-A', code: '#DUP')]);
        await settle();

        expect(c.read(posRecentOrdersControllerProvider).length, 1);
        expect(
          c.read(posRecentOrdersControllerProvider).single.origin,
          PosOrderOrigin.deviceOwned,
          reason:
              'a snapshot does not demote an order we still hold the lines for',
        );
      },
    );

    test(
      '2G-12 different order ids with the same code stay TWO rows',
      () async {
        final c = harness(store: InMemoryRecentOrdersStore());
        c.read(posDeviceContextProvider.notifier).set(branchA);
        await settle();
        final orders = c.read(posRecentOrdersControllerProvider.notifier);

        await orders.applySnapshots([
          snap(id: 'ORDER-A', code: '#DUP'),
          snap(id: 'ORDER-B', code: '#DUP'),
        ]);
        await settle();

        expect(c.read(posRecentOrdersControllerProvider).length, 2);
      },
    );

    test(
      "2E the payment repository's own duplicate check is by identity: paying a "
      'SECOND order that shares a code is not mistaken for a duplicate',
      () async {
        final repo = DemoPaymentStore();

        final a = await repo.recordCashPayment(
          orderId: 'ORDER-A',
          orderNumber: '#DUP',
          amountMinor: 4000,
          tenderedMinor: 4000,
          currencyCode: 'ILS',
        );
        final b = await repo.recordCashPayment(
          orderId: 'ORDER-B',
          orderNumber: '#DUP', //  <-- the same PRINTED code, a different ORDER
          amountMinor: 1500,
          tenderedMinor: 1500,
          currencyCode: 'ILS',
        );

        expect(
          b.paymentId,
          isNot(a.paymentId),
          reason:
              "keyed on the code, the second order was handed the FIRST order's "
              'payment and its own money was never recorded',
        );
        expect(b.amountMinor, 1500);
        expect(b.orderId, 'ORDER-B');

        // ...and the idempotency it DOES owe still holds, per order.
        final again = await repo.recordCashPayment(
          orderId: 'ORDER-A',
          orderNumber: '#DUP',
          amountMinor: 4000,
          tenderedMinor: 4000,
          currencyCode: 'ILS',
        );
        expect(
          again.paymentId,
          a.paymentId,
          reason: 'paying the SAME order twice is still idempotent',
        );
      },
    );

    test('2B a payment records the order it settled', () async {
      final c = harness(
        store: InMemoryRecentOrdersStore(),
        payments: DemoPaymentStore(),
      );
      c.read(posDeviceContextProvider.notifier).set(branchA);
      await settle();

      final p = await c
          .read(paymentControllerProvider.notifier)
          .payCash(
            identity: PosOrderIdentity.server('ORDER-A'),
            orderId: 'ORDER-A',
            orderNumber: '#DUP',
            amountMinor: 4000,
            tenderedMinor: 4000,
            currencyCode: 'ILS',
          );

      expect(
        p.orderId,
        'ORDER-A',
        reason: 'the payment knows which order it settled, not just its code',
      );
      expect(
        c
            .read(paymentControllerProvider)
            .paymentFor(PosOrderIdentity.server('ORDER-B')),
        isNull,
        reason: 'and the OTHER order has no payment',
      );
    });
  });

  // ===========================================================================
  group('MEDIUM 4 — a targeted refresh that cannot store is NOT a success', () {
    test(
      'applySnapshots fails durably -> persistence error, no lastSyncedAt, rows kept',
      () async {
        final store = _RefusingStore();
        // A REAL targeted page: there must be something to store for the write to be
        // able to fail.
        final repo = _GatedRepo(
          targeted: Completer<PosSnapshotPage>()
            ..complete(
              PosSnapshotPage(orders: [snap(revision: 7)], hasMore: false),
            ),
        );
        final c = harness(store: store, repo: repo);
        c.read(posDeviceContextProvider.notifier).set(branchA);
        await settle();

        final orders = c.read(posRecentOrdersControllerProvider.notifier);
        orders.recordSubmitted(view(orderId: 'o-1'));
        await settle();

        final sync = c.read(posOrderSyncControllerProvider.notifier);
        await sync.refreshOrders(<String>['o-1']);
        await settle();

        final status = c.read(posOrderSyncControllerProvider);
        expect(
          status.error,
          PosSyncError.persistence,
          reason: 'the write failed and the till must say so',
        );
        expect(
          status.lastSyncedAt,
          isNull,
          reason:
              'this path used to stamp a fresh sync time over rows it never stored',
        );
        expect(
          c.read(posRecentOrdersControllerProvider),
          isNotEmpty,
          reason: 'the rows already on screen are preserved',
        );
        // RETRY REMAINS POSSIBLE: the same call can be made again.
        await sync.refreshOrders(<String>['o-1']);
        expect(
          c.read(posOrderSyncControllerProvider).error,
          PosSyncError.persistence,
        );
      },
    );

    test('a scopeless till stores nothing and claims nothing', () async {
      final store = InMemoryRecentOrdersStore();
      final c = harness(store: store, repo: _GatedRepo());
      // NO device context: the till does not know where it is.
      final ok = await c
          .read(posRecentOrdersControllerProvider.notifier)
          .applySnapshots([snap(id: 'o-1')]);
      expect(
        ok,
        isFalse,
        reason:
            '`` is a shared bucket, not a branch — we refuse to write there',
      );
    });
  });

  // ===========================================================================
  group('MEDIUM 5 — OrderConfirmation shows the AUTHORITATIVE status', () {
    Future<ProviderContainer> pump(
      WidgetTester tester, {
      PosRecentOrdersStore? store,
    }) async {
      final c = harness(store: store ?? InMemoryRecentOrdersStore());
      // A REAL paired till: without a scope the controller correctly refuses to store
      // anything at all, which is a different behaviour from the one under test here.
      c.read(posDeviceContextProvider.notifier).set(branchA);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
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

    testWidgets('a local Submitted order keeps the safe local fallback', (
      tester,
    ) async {
      await pump(tester);
      expect(
        find.byKey(const Key('confirmation-local-status')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('order-status-confirmation')), findsNothing);
    });

    testWidgets(
      'reconciliation to COMPLETED updates the open screen and strips actions',
      (tester) async {
        final c = await pump(tester);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        expect(find.byKey(const Key('pay-cash-button')), findsOneWidget);

        await c.read(posRecentOrdersControllerProvider.notifier).applySnapshots(
          [snap(status: 'completed', settlement: PosSettlement.paid)],
        );
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.posOrdersStatusCompleted),
          findsOneWidget,
          reason: 'the screen used to say "Submitted" forever',
        );
        expect(find.text(l10n.posPaidChip), findsOneWidget);
        expect(
          find.byKey(const Key('pay-cash-button')),
          findsNothing,
          reason: 'a completed order cannot be paid',
        );
      },
    );

    testWidgets(
      'a 40 order comped to 0 shows No charge, total 0, and no Pay button',
      (tester) async {
        final c = await pump(tester);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        await c.read(posRecentOrdersControllerProvider.notifier).applySnapshots(
          [
            snap(
              status: 'served',
              settlement: PosSettlement.notChargeable,
              grand: 0,
            ),
          ],
        );
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.posNoChargeChip),
          findsOneWidget,
          reason: 'a comped order is neither Paid nor Unpaid',
        );
        expect(find.text(l10n.posPaidChip), findsNothing);
        expect(find.byKey(const Key('pay-cash-button')), findsNothing);
        expect(
          find.text(l10n.posOrdersStatusServed),
          findsOneWidget,
          reason: 'the lifecycle is the SERVER\'s, not a frozen "Submitted"',
        );
      },
    );

    testWidgets('Unpaid renders as Unpaid', (tester) async {
      final c = await pump(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await c.read(posRecentOrdersControllerProvider.notifier).applySnapshots([
        snap(settlement: PosSettlement.unpaid),
      ]);
      await tester.pumpAndSettle();

      expect(find.text(l10n.posUnpaidChip), findsOneWidget);
      expect(find.byKey(const Key('pay-cash-button')), findsOneWidget);
    });

    testWidgets('an UNKNOWN settlement token fails closed to Unpaid', (
      tester,
    ) async {
      final c = await pump(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // The wire parser is the production seam: a token we cannot classify must
      // keep asking to be dealt with, never quietly settle itself.
      final malformed = PosOrderSnapshot(
        orderId: 'o-1',
        orderCode: '#o-1',
        revision: 3,
        status: 'served',
        settlement: PosSettlement.fromWire('who-knows'),
        subtotalMinor: 4000,
        discountTotalMinor: 0,
        taxTotalMinor: 0,
        grandTotalMinor: 4000,
        createdAt: t0,
        updatedAt: t0,
        syncAt: t0,
        currencyCode: 'ILS',
      );
      await c.read(posRecentOrdersControllerProvider.notifier).applySnapshots([
        malformed,
      ]);
      await tester.pumpAndSettle();

      expect(find.text(l10n.posUnpaidChip), findsOneWidget);
      expect(find.text(l10n.posPaidChip), findsNothing);
      expect(find.text(l10n.posNoChargeChip), findsNothing);
    });
  });

  // ===========================================================================
  group('MEDIUM 3 — a discount conflict cannot be retried at the old revision', () {
    Future<ProviderContainer> pumpSheet(
      WidgetTester tester,
      DiscountRepository repo, {
      int expectedRevision = 3,
    }) async {
      final c = harness(
        store: InMemoryRecentOrdersStore(),
        discounts: repo,
        repo: _GatedRepo(
          targeted: Completer<PosSnapshotPage>()
            ..complete(
              PosSnapshotPage(
                orders: [snap(revision: 4, grand: 3000)],
                hasMore: false,
              ),
            ),
        ),
      );
      c.read(posDeviceContextProvider.notifier).set(branchA);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(
              body: DiscountSheet(
                orderId: 'o-1',
                subtotalMinor: 4000,
                taxTotalMinor: 0,
                currencyCode: 'ILS',
                expectedRevision: expectedRevision,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return c;
    }

    Future<void> apply(WidgetTester tester) async {
      await tester.enterText(
        find.byKey(const Key('discount-value-field')),
        '5',
      );
      await tester.enterText(
        find.byKey(const Key('discount-reason-field')),
        'manager',
      );
      await tester.tap(find.byKey(const Key('discount-apply-button')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'a CONFLICT refreshes, explains, and RETIRES the sheet — no second attempt '
      'at the stale revision',
      (tester) async {
        final repo = _ConflictOnceRepo();
        final c = await pumpSheet(tester, repo);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        await apply(tester);

        expect(repo.sentRevisions, <int?>[
          3,
        ], reason: 'the first attempt went out');
        expect(find.text(l10n.posOrdersConflictRefreshed), findsOneWidget);

        // THE APPLY BUTTON IS GONE. There is no way to re-send revision 3.
        expect(
          find.byKey(const Key('discount-apply-button')),
          findsNothing,
          reason: 'a sheet built on a rejected revision cannot be re-submitted',
        );
        expect(
          find.byKey(const Key('discount-conflict-close-button')),
          findsOneWidget,
        );
        expect(
          repo.sentRevisions.length,
          1,
          reason: 'NEVER auto-retried — the cashier decides, against the truth',
        );

        // The order was reconciled to the authoritative revision 4 / total 3000.
        final row = c.read(posRecentOrdersControllerProvider).single;
        expect(row.revision, 4);
        expect(row.grandTotalMinor, 3000);

        // Acknowledge: the sheet closes, so a new attempt starts from the refreshed
        // order (which is what carries revision 4).
        await tester.tap(
          find.byKey(const Key('discount-conflict-close-button')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DiscountSheet), findsNothing);
        expect(repo.sentRevisions, <int?>[
          3,
        ], reason: 'closing is not a re-submit');
      },
    );

    testWidgets('a reopened sheet sends the REFRESHED revision', (
      tester,
    ) async {
      final repo = _RecordingRepo();
      // The sheet the confirmation screen would now open: the authoritative revision.
      await pumpSheet(tester, repo, expectedRevision: 4);
      await apply(tester);
      expect(
        repo.sentRevisions,
        <int?>[4],
        reason: 'the new attempt is made against the state the server holds',
      );
    });

    testWidgets('a TRANSPORT failure stays retryable — Apply survives', (
      tester,
    ) async {
      final repo = _FailingRepo(const DiscountException('failed'));
      await pumpSheet(tester, repo);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await apply(tester);

      expect(find.text(l10n.posDiscountFailed), findsOneWidget);
      expect(
        find.byKey(const Key('discount-apply-button')),
        findsOneWidget,
        reason:
            'an ordinary failure is not staleness: the same entry can be retried',
      );
      expect(
        find.byKey(const Key('discount-conflict-close-button')),
        findsNothing,
      );
    });

    testWidgets('a PERMISSION denial stays distinct and retryable', (
      tester,
    ) async {
      final repo = _FailingRepo(
        const DiscountException('permission_denied', permissionDenied: true),
      );
      await pumpSheet(tester, repo);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await apply(tester);

      expect(find.text(l10n.posDiscountPermissionDenied), findsOneWidget);
      expect(find.byKey(const Key('discount-apply-button')), findsOneWidget);
    });
  });
}

// =============================================================================
// Fakes. They control TIMING and FAILURE — never the answer under test.
// =============================================================================

/// A repository whose responses are held open until the test says otherwise, so a
/// scope change can be made to land in the middle of a real in-flight call.
class _GatedRepo implements OrderSnapshotRepository {
  _GatedRepo({this.window, this.changes, this.targeted});

  final Completer<PosSnapshotPage>? window;
  final Completer<PosSnapshotPage>? changes;
  final Completer<PosSnapshotPage>? targeted;

  @override
  Future<PosSnapshotPage> fetchWindow({
    PosSyncCursor? before,
    int limit = 50,
    int windowDays = 2,
  }) => window?.future ?? Future.value(PosSnapshotPage.empty);

  @override
  Future<PosSnapshotPage> fetchChanges({
    PosSyncCursor? cursor,
    int limit = 50,
    int windowDays = 2,
  }) => changes?.future ?? Future.value(PosSnapshotPage.empty);

  @override
  Future<PosSnapshotPage> fetchOrders(List<String> orderIds) =>
      targeted?.future ?? Future.value(PosSnapshotPage.empty);
}

/// Serves a bounded window page and records the cursor it was asked for.
class _PagingRepo implements OrderSnapshotRepository {
  final List<PosSyncCursor?> sentBefore = <PosSyncCursor?>[];
  final DateTime _t = DateTime.now().toUtc().subtract(const Duration(hours: 2));

  @override
  Future<PosSnapshotPage> fetchWindow({
    PosSyncCursor? before,
    int limit = 50,
    int windowDays = 2,
  }) async {
    sentBefore.add(before);
    return PosSnapshotPage(
      orders: <PosOrderSnapshot>[
        PosOrderSnapshot(
          orderId: 'w-${sentBefore.length}',
          orderCode: '#w',
          revision: 1,
          status: 'served',
          settlement: PosSettlement.unpaid,
          subtotalMinor: 100,
          discountTotalMinor: 0,
          taxTotalMinor: 0,
          grandTotalMinor: 100,
          createdAt: _t,
          updatedAt: _t,
          syncAt: _t,
          currencyCode: 'ILS',
        ),
      ],
      hasMore: true,
      nextCursor: PosSyncCursor(at: _t, id: 'w-${sentBefore.length}'),
    );
  }

  @override
  Future<PosSnapshotPage> fetchChanges({
    PosSyncCursor? cursor,
    int limit = 50,
    int windowDays = 2,
  }) async => PosSnapshotPage.empty;

  @override
  Future<PosSnapshotPage> fetchOrders(List<String> orderIds) async =>
      PosSnapshotPage.empty;
}

/// A store whose loads are held open per branch, so an A-recovery can be made to
/// complete after B is already the active scope.
class _GatedStore implements PosRecentOrdersStore {
  final Map<String, Completer<List<PosRecentOrder>>> pending = {};
  final Map<String, List<PosRecentOrder>> persisted = {};

  @override
  Future<List<PosRecentOrder>> load(String scopeKey) {
    final c = Completer<List<PosRecentOrder>>();
    pending[scopeKey] = c;
    return c.future;
  }

  @override
  Future<void> persist(String scopeKey, List<PosRecentOrder> orders) async {
    persisted[scopeKey] = orders;
  }

  void completeFor(String branchFragment, List<PosRecentOrder> orders) {
    final key = pending.keys.firstWhere((k) => k.contains(branchFragment));
    pending.remove(key)!.complete(orders);
  }
}

/// A store that REFUSES to write — the shape a full disk or a browser refusing
/// localStorage actually takes.
class _RefusingStore implements PosRecentOrdersStore {
  @override
  Future<List<PosRecentOrder>> load(String scopeKey) async =>
      const <PosRecentOrder>[];

  @override
  Future<void> persist(String scopeKey, List<PosRecentOrder> orders) async {
    throw const PosPersistenceException('recent orders could not be persisted');
  }
}

class _RecordingRepo implements DiscountRepository {
  final List<int?> sentRevisions = <int?>[];

  @override
  Future<OrderDiscount> applyOrderDiscount({
    required String orderId,
    required DiscountType type,
    required int value,
    required String reason,
    required int subtotalMinor,
    required int taxTotalMinor,
    int? expectedRevision,
  }) async {
    sentRevisions.add(expectedRevision);
    return const OrderDiscount(discountTotalMinor: 500, grandTotalMinor: 3500);
  }
}

/// Refuses the FIRST attempt with an exact `conflict`, and would happily accept a
/// second one — so the test proves the CLIENT refuses to make it, not the server.
class _ConflictOnceRepo implements DiscountRepository {
  final List<int?> sentRevisions = <int?>[];

  @override
  Future<OrderDiscount> applyOrderDiscount({
    required String orderId,
    required DiscountType type,
    required int value,
    required String reason,
    required int subtotalMinor,
    required int taxTotalMinor,
    int? expectedRevision,
  }) async {
    sentRevisions.add(expectedRevision);
    if (sentRevisions.length == 1) {
      throw const DiscountException('conflict', conflict: true);
    }
    return const OrderDiscount(discountTotalMinor: 500, grandTotalMinor: 2500);
  }
}

class _FailingRepo implements DiscountRepository {
  _FailingRepo(this.error);

  final DiscountException error;

  @override
  Future<OrderDiscount> applyOrderDiscount({
    required String orderId,
    required DiscountType type,
    required int value,
    required String reason,
    required int subtotalMinor,
    required int taxTotalMinor,
    int? expectedRevision,
  }) async => throw error;
}
