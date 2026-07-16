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
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_identity.dart';
import 'package:restoflow_pos/src/data/order_reconciler.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/order_snapshot_repository.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosPersistenceException;
import 'package:restoflow_pos/src/data/void_repository.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/payment_controller.dart'
    show paymentRepositoryProvider;
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/state/void_controller.dart'
    show voidRepositoryProvider;
import 'package:restoflow_pos/src/widgets/cancel_order_sheet.dart';
import 'package:restoflow_pos/src/widgets/cash_payment_sheet.dart';

/// POS-OPERATIONS-SYNC-001 — final stabilization regressions.
///
/// Every test drives the production seam that was defective. None hands the code a
/// pre-computed answer.
void main() {
  final t0 = DateTime.now().toUtc().subtract(
    const Duration(hours: 2),
  ); // stabilization: anchor to real clock (recent-orders 1-day window)

  PosOrderSnapshot snap({
    String id = 'o-1',
    String status = 'served',
    PosSettlement settlement = PosSettlement.unpaid,
    int grand = 4000,
    int revision = 3,
  }) => PosOrderSnapshot(
    orderId: id,
    orderCode: '#o-1',
    revision: revision,
    status: status,
    settlement: settlement,
    subtotalMinor: grand,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: grand,
    createdAt: t0,
    updatedAt: t0,
    syncAt: t0,
    currencyCode: 'ILS',
  );

  SubmittedOrderView view({String? orderId = 'o-1'}) => SubmittedOrderView(
    orderNumber: '#o-1',
    orderType: OrderType.dineIn,
    currencyCode: 'ILS',
    subtotalMinor: 4000,
    lines: const [
      SubmittedLineView(
        name: 'Burger',
        quantity: 1,
        lineTotalMinor: 4000,
        currencyCode: 'ILS',
      ),
    ],
    orderId: orderId,
  );

  CashPayment payment({int amount = 4000, String? orderStatus}) => CashPayment(
    paymentId: 'pay-1',
    orderId: 'o-1',
    orderNumber: '#o-1',
    deviceId: 'd1',
    localOperationId: 'op-1',
    method: PaymentMethod.cash,
    status: PaymentStatus.completed,
    amountMinor: amount,
    tenderedMinor: amount,
    changeMinor: 0,
    currencyCode: 'ILS',
    receiptNumber: 'R-1',
    paidAt: t0,
    orderStatus: orderStatus,
  );

  // ===========================================================================
  group('TERMINAL/SETTLEMENT RATCHET — a retained older snapshot cannot outvote a '
      'server confirmation this device already holds', () {
    test('a server-confirmed VOID stays terminal even when the targeted refresh '
        'failed and the stale snapshot still says served/unpaid', () {
      // The row as it stands after: pull (snapshot served/unpaid) -> the void
      // RPC SUCCEEDS -> markVoided stamps it -> the follow-up targeted refresh
      // FAILS (network blip). The stale snapshot is still attached.
      final voided = PosRecentOrder(
        order: view(),
        submittedAt: t0,
        snapshot: snap(status: 'served', settlement: PosSettlement.unpaid),
        voidedAt: t0,
        voidReason: 'wrong order',
        status: 'voided',
      );

      expect(
        voided.isTerminal,
        isTrue,
        reason:
            'the void was SERVER-CONFIRMED; a snapshot retained from before '
            'it is the OLDER fact and must not re-open the order',
      );
      expect(
        isCountedUnpaid(voided),
        isFalse,
        reason: 'a cancelled order is not a debt — it must leave the badge',
      );
      final actions = resolveOrderActions(voided);
      expect(actions.canPay, isFalse);
      expect(actions.canVoid, isFalse);
      expect(actions.canDiscount, isFalse);
    });

    test('a server-confirmed PAYMENT settles the order even when the stale '
        'snapshot still says unpaid', () {
      // record_payment succeeded (a server fact), the targeted refresh failed,
      // and the retained snapshot predates the payment.
      final paid = PosRecentOrder(
        order: view(),
        submittedAt: t0,
        snapshot: snap(settlement: PosSettlement.unpaid, grand: 4000),
        payment: payment(amount: 4000),
      );

      expect(
        paid.settlement,
        PosSettlement.paid,
        reason:
            'the confirmed payment COVERS the snapshot total — two server '
            'facts under the app.order_is_fully_settled rule',
      );
      expect(isCountedUnpaid(paid), isFalse);
      expect(resolveOrderActions(paid).canPay, isFalse);
    });

    test('an UNDER-COVERING payment does not settle — fail closed', () {
      final under = PosRecentOrder(
        order: view(),
        submittedAt: t0,
        snapshot: snap(settlement: PosSettlement.unpaid, grand: 4000),
        payment: payment(amount: 3000),
      );
      expect(
        under.settlement,
        PosSettlement.unpaid,
        reason: 'money still owed must stay visible',
      );
    });

    test('a NEWER snapshot remains the authority when it says more', () {
      // The normal case: the snapshot already reflects the payment.
      final row = PosRecentOrder(
        order: view(),
        submittedAt: t0,
        snapshot: snap(
          status: 'completed',
          settlement: PosSettlement.paid,
          revision: 5,
        ),
        payment: payment(amount: 4000),
      );
      expect(row.settlement, PosSettlement.paid);
      expect(row.isTerminal, isTrue);
    });
  });

  // ===========================================================================
  group('SHEET RETIREMENT — a refused revision cannot be re-sent', () {
    const branchA = DeviceContext(
      organizationId: 'org1',
      restaurantId: 'r1',
      branchId: 'branch-A',
      deviceId: 'DEV-1',
    );

    ProviderContainer harness({
      PaymentRepository? payments,
      VoidRepository? voids,
      OrderSnapshotRepository? repo,
    }) {
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posSyncSessionProvider.overrideWithValue(
            const SyncSession(pinSessionId: 'pin', deviceId: 'DEV-1'),
          ),
          posSyncClockProvider.overrideWithValue(() => t0),
          orderSnapshotRepositoryProvider.overrideWithValue(
            repo ?? _EmptyRepo(),
          ),
          if (payments != null)
            paymentRepositoryProvider.overrideWithValue(payments),
          if (voids != null) voidRepositoryProvider.overrideWithValue(voids),
        ],
      );
      addTearDown(c.dispose);
      c.read(posDeviceContextProvider.notifier).set(branchA);
      return c;
    }

    Future<void> pump(
      WidgetTester tester,
      ProviderContainer c,
      Widget sheet,
    ) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(body: sheet),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'PAYMENT conflict: typed banner, Confirm replaced by Close, the stale '
      'revision goes out exactly once',
      (tester) async {
        final repo = _ConflictPaymentRepo();
        final c = harness(payments: repo);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        await pump(
          tester,
          c,
          CashPaymentSheet(
            identity: PosOrderIdentity.server('o-1'),
            orderId: 'o-1',
            orderNumber: '#o-1',
            amountMinor: 4000,
            currencyCode: 'ILS',
            expectedRevision: 3,
          ),
        );

        await tester.tap(find.byKey(const Key('quick-cash-exact')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm-payment-button')));
        await tester.pumpAndSettle();

        expect(repo.sentRevisions, <int?>[3], reason: 'one attempt went out');
        // The TYPED conflict, not the generic "check the connection" lie.
        expect(
          find.byKey(const Key('payment-conflict-banner')),
          findsOneWidget,
        );
        expect(find.text(l10n.posOrdersConflictRefreshed), findsOneWidget);
        expect(find.byKey(const Key('payment-failed-banner')), findsNothing);
        // RETIRED: there is no Confirm left to re-send the refused revision with.
        expect(find.byKey(const Key('confirm-payment-button')), findsNothing);
        expect(
          find.byKey(const Key('payment-conflict-close-button')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const Key('payment-conflict-close-button')),
        );
        await tester.pumpAndSettle();
        expect(
          repo.sentRevisions,
          <int?>[3],
          reason: 'closing is not a re-submit — revision 3 went out ONCE',
        );
      },
    );

    testWidgets(
      'CANCEL conflict: Confirm replaced by Close; the stale revision cannot '
      'be re-sent',
      (tester) async {
        final voids = _ConflictVoidRepo();
        final c = harness(voids: voids);

        final order = PosRecentOrder(
          order: view(),
          submittedAt: t0,
          snapshot: snap(revision: 3),
        );
        await pump(tester, c, CancelOrderSheet(order: order));

        await tester.enterText(
          find.byKey(const Key('cancel-reason-field')),
          'wrong order',
        );
        await tester.tap(find.byKey(const Key('cancel-confirm-button')));
        await tester.pumpAndSettle();

        expect(voids.sentRevisions, <int?>[3]);
        expect(find.byKey(const Key('cancel-order-error')), findsOneWidget);
        expect(find.byKey(const Key('cancel-confirm-button')), findsNothing);
        expect(
          find.byKey(const Key('cancel-conflict-close-button')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('cancel-conflict-close-button')));
        await tester.pumpAndSettle();
        expect(
          voids.sentRevisions,
          <int?>[3],
          reason: 'revision 3 was refused once and never re-sent',
        );
      },
    );

    testWidgets(
      'CANCEL order_not_voidable: the sheet retires too — "already closed" '
      'must not sit above a live Confirm',
      (tester) async {
        final voids = _NotVoidableRepo();
        final c = harness(voids: voids);

        final order = PosRecentOrder(
          order: view(),
          submittedAt: t0,
          snapshot: snap(revision: 3),
        );
        await pump(tester, c, CancelOrderSheet(order: order));

        await tester.enterText(
          find.byKey(const Key('cancel-reason-field')),
          'wrong order',
        );
        await tester.tap(find.byKey(const Key('cancel-confirm-button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('cancel-confirm-button')), findsNothing);
        expect(
          find.byKey(const Key('cancel-conflict-close-button')),
          findsOneWidget,
        );
        expect(voids.calls, 1);
      },
    );

    testWidgets(
      'a PERMISSION denial does NOT retire the cancel sheet — it stays '
      'deliberately retryable',
      (tester) async {
        final voids = _PermissionDeniedVoidRepo();
        final c = harness(voids: voids);

        final order = PosRecentOrder(
          order: view(),
          submittedAt: t0,
          snapshot: snap(revision: 3),
        );
        await pump(tester, c, CancelOrderSheet(order: order));

        await tester.enterText(
          find.byKey(const Key('cancel-reason-field')),
          'wrong order',
        );
        await tester.tap(find.byKey(const Key('cancel-confirm-button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('cancel-confirm-button')),
          findsOneWidget,
          reason: 'the order is exactly as we thought — a manager can retry',
        );
        expect(
          find.byKey(const Key('cancel-conflict-close-button')),
          findsNothing,
        );
      },
    );
  });

  // ===========================================================================
  group('HYBRID SCOPE — a session from another pairing names no scope', () {
    test('session.deviceId != pairing.deviceId -> scope is REFUSED (null), so no '
        'pull, no cache, no cross-branch hybrid', () async {
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          // The PIN session established under the PREVIOUS pairing — never
          // ended, because the unpair's server revoke is best-effort and
          // nothing client-side kills the in-memory session.
          posSyncSessionProvider.overrideWithValue(
            const SyncSession(pinSessionId: 'pin-A', deviceId: 'OLD-DEVICE'),
          ),
        ],
      );
      addTearDown(c.dispose);

      // The till is now paired as a NEW device in another branch.
      c
          .read(posDeviceContextProvider.notifier)
          .set(
            const DeviceContext(
              organizationId: 'org1',
              restaurantId: 'r1',
              branchId: 'branch-B',
              deviceId: 'NEW-DEVICE',
            ),
          );
      await Future<void>.delayed(Duration.zero);

      expect(
        c.read(posSyncScopeProvider),
        isNull,
        reason:
            'a HYBRID scope (new branch + old session device) would run every '
            "pull on the OLD branch's server session and file its orders here",
      );

      // And the sync layer treats it exactly like an unpaired till: nothing is
      // cached, nothing is persisted.
      final ok = await c
          .read(posRecentOrdersControllerProvider.notifier)
          .applySnapshots([snap()]);
      expect(ok, isFalse, reason: 'scopeless: nothing may be stored');
    });

    test('a MATCHING session still names the scope normally', () async {
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posSyncSessionProvider.overrideWithValue(
            const SyncSession(pinSessionId: 'pin', deviceId: 'DEV-1'),
          ),
        ],
      );
      addTearDown(c.dispose);
      c
          .read(posDeviceContextProvider.notifier)
          .set(
            const DeviceContext(
              organizationId: 'org1',
              restaurantId: 'r1',
              branchId: 'branch-A',
              deviceId: 'DEV-1',
            ),
          );
      await Future<void>.delayed(Duration.zero);
      expect(c.read(posSyncScopeProvider)?.deviceId, 'DEV-1');
      expect(c.read(posSyncScopeProvider)?.branchId, 'branch-A');
    });
  });

  // ===========================================================================
  group('PERSISTENCE — an empty page is not an amnesty for an owed write', () {
    const branchA = DeviceContext(
      organizationId: 'org1',
      restaurantId: 'r1',
      branchId: 'branch-A',
      deviceId: 'DEV-1',
    );

    ProviderContainer harness(PosRecentOrdersStore store) {
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posSyncSessionProvider.overrideWithValue(
            const SyncSession(pinSessionId: 'pin', deviceId: 'DEV-1'),
          ),
          posRecentOrdersStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(c.dispose);
      c.read(posDeviceContextProvider.notifier).set(branchA);
      return c;
    }

    test(
      'a failed write followed by an EMPTY page re-attempts the write instead '
      'of declaring success over a divergent disk',
      () async {
        final store = _FlakyStore(failuresBeforeSuccess: 1);
        final c = harness(store);
        final orders = c.read(posRecentOrdersControllerProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        // Page 1: reconcile succeeds in memory, the durable write FAILS.
        final ok1 = await orders.applySnapshots([snap()]);
        expect(ok1, isFalse, reason: 'the write failed and was reported');
        expect(orders.lastPersistFailed, isTrue);

        // The server has nothing new: an EMPTY page arrives. The owed write must
        // be re-attempted — "nothing changed" was only ever true of the server.
        final ok2 = await orders.applySnapshots(const []);
        expect(ok2, isTrue);
        expect(
          orders.lastPersistFailed,
          isFalse,
          reason: 'the retry wrote the day to disk',
        );
        expect(
          store.persisted,
          isNotEmpty,
          reason: 'the rows actually reached the store on the retry',
        );
      },
    );
  });

  // ===========================================================================
  group('RECOVERY MERGE — a raced first pull cannot strip the day', () {
    const branchA = DeviceContext(
      organizationId: 'org1',
      restaurantId: 'r1',
      branchId: 'branch-A',
      deviceId: 'DEV-1',
    );

    test(
      'applySnapshots landing BEFORE recovery completes must not let the '
      'lineless discovered shells clobber the stored device-owned day',
      () async {
        final store = _GatedLoadStore();
        final c = ProviderContainer(
          overrides: [
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: false),
            ),
            posSyncSessionProvider.overrideWithValue(
              const SyncSession(pinSessionId: 'pin', deviceId: 'DEV-1'),
            ),
            posRecentOrdersStoreProvider.overrideWithValue(store),
          ],
        );
        addTearDown(c.dispose);
        c.read(posDeviceContextProvider.notifier).set(branchA);

        // build() starts _recover(), which blocks on the gated load.
        final orders = c.read(posRecentOrdersControllerProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        // THE RACE: the first pull lands while recovery is still loading. With
        // state=[] the snapshot is adopted as a lineless DISCOVERED shell.
        await orders.applySnapshots([snap()]);
        expect(
          c.read(posRecentOrdersControllerProvider).single.order,
          isNull,
          reason: 'precondition: the raced adoption is a lineless shell',
        );

        // NOW the stored day arrives: the device-owned row with its lines and
        // its payment marker.
        store.gate.complete([
          PosRecentOrder(
            order: view(),
            submittedAt: t0,
            payment: payment(amount: 4000),
          ),
        ]);
        for (var i = 0; i < 6; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        final rows = c.read(posRecentOrdersControllerProvider);
        expect(rows, hasLength(1), reason: 'one order, not two');
        final row = rows.single;
        expect(
          row.order,
          isNotNull,
          reason: 'the ORDER-TIME lines survived — receipts remain reprintable',
        );
        expect(row.payment, isNotNull, reason: 'the payment marker survived');
        expect(
          row.origin,
          PosOrderOrigin.deviceOwned,
          reason: 'this till took the order and still owns it',
        );
        expect(
          row.snapshot,
          isNotNull,
          reason:
              "the raced pull's AUTHORITATIVE snapshot was merged in through "
              'the one reconciler rule, not discarded',
        );
        expect(row.revision, 3);
      },
    );
  });
}

// =============================================================================
// Fakes — they control timing and refusals, never the answer under test.
// =============================================================================

class _EmptyRepo implements OrderSnapshotRepository {
  @override
  Future<PosSnapshotPage> fetchChanges({
    PosSyncCursor? cursor,
    int limit = 50,
    int windowDays = 2,
  }) async => PosSnapshotPage.empty;

  @override
  Future<PosSnapshotPage> fetchWindow({
    PosSyncCursor? before,
    int limit = 50,
    int windowDays = 2,
  }) async => PosSnapshotPage.empty;

  @override
  Future<PosSnapshotPage> fetchOrders(List<String> orderIds) async =>
      PosSnapshotPage.empty;
}

class _ConflictPaymentRepo implements PaymentRepository {
  final List<int?> sentRevisions = <int?>[];
  final DemoPaymentStore _shift = DemoPaymentStore();

  @override
  Future<CashPayment> recordCashPayment({
    required String orderId,
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    PaymentMethod method = PaymentMethod.cash,
    int? expectedRevision,
  }) async {
    sentRevisions.add(expectedRevision);
    throw const PaymentException('conflict', conflict: true);
  }

  @override
  ShiftContext shiftContext() => _shift.shiftContext();

  @override
  CashPayment? paymentFor(PosOrderIdentity identity) => null;
}

class _ConflictVoidRepo implements VoidRepository {
  final List<int?> sentRevisions = <int?>[];

  @override
  Future<void> voidOrder({
    required String orderId,
    required String reason,
    int? expectedRevision,
  }) async {
    sentRevisions.add(expectedRevision);
    throw const VoidException('conflict', conflict: true);
  }
}

class _NotVoidableRepo implements VoidRepository {
  int calls = 0;

  @override
  Future<void> voidOrder({
    required String orderId,
    required String reason,
    int? expectedRevision,
  }) async {
    calls++;
    throw const VoidException('order_not_voidable', notVoidable: true);
  }
}

class _PermissionDeniedVoidRepo implements VoidRepository {
  @override
  Future<void> voidOrder({
    required String orderId,
    required String reason,
    int? expectedRevision,
  }) async {
    throw const VoidException('permission_denied', permissionDenied: true);
  }
}

/// Fails the first [failuresBeforeSuccess] writes, then accepts — the shape a
/// briefly-full disk takes.
class _FlakyStore implements PosRecentOrdersStore {
  _FlakyStore({required this.failuresBeforeSuccess});

  int failuresBeforeSuccess;
  final Map<String, List<PosRecentOrder>> persisted = {};

  @override
  Future<List<PosRecentOrder>> load(String scopeKey) async =>
      const <PosRecentOrder>[];

  @override
  Future<void> persist(String scopeKey, List<PosRecentOrder> orders) async {
    if (failuresBeforeSuccess > 0) {
      failuresBeforeSuccess--;
      throw const PosPersistenceException('write refused');
    }
    persisted[scopeKey] = List.of(orders);
  }
}

/// Holds the recovery load open until the test releases it.
class _GatedLoadStore implements PosRecentOrdersStore {
  final Completer<List<PosRecentOrder>> gate =
      Completer<List<PosRecentOrder>>();
  final Map<String, List<PosRecentOrder>> persisted = {};

  @override
  Future<List<PosRecentOrder>> load(String scopeKey) => gate.future;

  @override
  Future<void> persist(String scopeKey, List<PosRecentOrder> orders) async {
    persisted[scopeKey] = List.of(orders);
  }
}
