import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/order_snapshot_repository.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosPersistenceException;
import 'package:restoflow_pos/src/data/void_repository.dart';
import 'package:restoflow_pos/src/pos_pin_gate.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/draft_recovery_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/state/void_controller.dart'
    show voidRepositoryProvider;
import 'package:restoflow_pos/src/widgets/cancel_order_sheet.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart';

/// POS-OPERATIONS-SYNC-001 — the FINAL scope-lifecycle closures.
///
/// Every test drives the production seam: the real session controller, the real
/// gate, the real scope provider, the real sync coordinator, the real sheets.
void main() {
  final t0 = DateTime.now().toUtc().subtract(
    const Duration(hours: 2),
  ); // stabilization: anchor to real clock (recent-orders 1-day window)

  const ctxA = DeviceContext(
    organizationId: 'org-1',
    restaurantId: 'rest-1',
    branchId: 'branch-A',
    deviceId: 'device-1',
    deviceType: 'pos',
    deviceSessionId: 'ds-A',
  );
  // THE ATTACK SHAPE: the SAME device id, a different branch + pairing.
  const ctxB = DeviceContext(
    organizationId: 'org-1',
    restaurantId: 'rest-1',
    branchId: 'branch-B',
    deviceId: 'device-1',
    deviceType: 'pos',
    deviceSessionId: 'ds-B',
  );
  // Same org/branch/device — but a DIFFERENT pairing (new device session).
  const ctxA2 = DeviceContext(
    organizationId: 'org-1',
    restaurantId: 'rest-1',
    branchId: 'branch-A',
    deviceId: 'device-1',
    deviceType: 'pos',
    deviceSessionId: 'ds-A2',
  );

  ProviderContainer harness({
    OrderSnapshotRepository? repo,
    OutboxRepository? outbox,
    PosRecentOrdersStore? store,
    VoidRepository? voids,
  }) {
    final c = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        // The REAL session controller establishes sessions over this transport.
        posAuthTransportProvider.overrideWithValue(_FakeTransport()),
        // No dart-define auto-establish: sessions come only from sign-in.
        posRealSessionConfigProvider.overrideWithValue(null),
        posSyncClockProvider.overrideWithValue(() => t0),
        orderSnapshotRepositoryProvider.overrideWithValue(repo ?? _SpyRepo()),
        if (outbox != null) outboxRepositoryProvider.overrideWithValue(outbox),
        if (store != null)
          posRecentOrdersStoreProvider.overrideWithValue(store),
        if (voids != null) voidRepositoryProvider.overrideWithValue(voids),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  // MICROTASKS, not Future.delayed: inside a testWidgets body, a zero-duration
  // Future.delayed is a FAKE-ZONE timer that never fires without a pump, and
  // these helpers must work in both plain test() and testWidgets() bodies.
  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.microtask(() {});
    }
  }

  Future<void> signIn(ProviderContainer c, DeviceContext device) async {
    final err = await c
        .read(posSessionControllerProvider.notifier)
        .signInWithPin(
          device: device,
          deviceId: device.deviceId!,
          deviceSessionId: device.deviceSessionId!,
          employeeProfileId: 'emp-1',
          pin: '1234',
        );
    expect(err, isNull);
    await settle();
  }

  // ===========================================================================
  group('BLOCKER 1 — the PIN session is bound to the FULL pairing context', () {
    test('the normal lifecycle: sign in under A -> scope A exists', () async {
      final c = harness();
      c.read(posDeviceContextProvider.notifier).set(ctxA);
      await settle();
      await signIn(c, ctxA);

      final scope = c.read(posSyncScopeProvider);
      expect(scope, isNotNull);
      expect(scope!.branchId, 'branch-A');
      expect(scope.deviceId, 'device-1');
      final binding = c.read(posPinSessionBindingProvider);
      expect(binding, isNotNull);
      expect(binding!.matchesContext(ctxA), isTrue);
      expect(
        binding.matchesContext(ctxB),
        isFalse,
        reason: 'the SAME deviceId in another branch is NOT the same context',
      );
      expect(
        binding.matchesContext(ctxA2),
        isFalse,
        reason: 'the SAME branch under a NEW pairing is NOT the same context',
      );
    });

    test('a context transition (same deviceId, A -> B) INVALIDATES the session '
        'at the source: no session, no scope, ZERO snapshot calls', () async {
      final spy = _SpyRepo();
      final c = harness(repo: spy);
      c.read(posDeviceContextProvider.notifier).set(ctxA);
      await settle();
      await signIn(c, ctxA);
      expect(c.read(posSyncScopeProvider)?.branchId, 'branch-A');

      // The pairing moves to branch B — deviceId UNCHANGED. deviceId-only
      // matching would accept the old session here; the binding must not.
      c.read(posDeviceContextProvider.notifier).set(ctxB);
      await settle();

      expect(
        c.read(posSyncSessionProvider),
        isNull,
        reason: 'the session died with the pairing it was minted for',
      );
      expect(c.read(posPinSessionBindingProvider), isNull);
      expect(
        c.read(posSyncScopeProvider),
        isNull,
        reason: 'no session valid for THIS context -> no scope',
      );

      // And a scopeless till performs ZERO snapshot RPCs on any entry point.
      final sync = c.read(posOrderSyncControllerProvider.notifier);
      await sync.syncNow();
      await sync.refreshWindow();
      await sync.loadMore();
      await sync.refreshOrders(<String>['o-1']);
      expect(spy.calls, 0, reason: 'not "fetch and discard" — ZERO calls');
    });

    test(
      'a NEW pairing of the SAME branch and device (new device session) does '
      'not accept the old session either',
      () async {
        final c = harness();
        c.read(posDeviceContextProvider.notifier).set(ctxA);
        await settle();
        await signIn(c, ctxA);
        expect(c.read(posSyncScopeProvider), isNotNull);

        c.read(posDeviceContextProvider.notifier).set(ctxA2);
        await settle();

        expect(
          c.read(posSyncSessionProvider),
          isNull,
          reason: 'a re-pair is a NEW pairing even at the same branch',
        );
        expect(c.read(posSyncScopeProvider), isNull);
      },
    );

    test('A -> B -> A: EACH context requires a session established under it; '
        'nothing is silently reused', () async {
      final c = harness();
      c.read(posDeviceContextProvider.notifier).set(ctxA);
      await settle();
      await signIn(c, ctxA);

      c.read(posDeviceContextProvider.notifier).set(ctxB);
      await settle();
      expect(c.read(posSyncScopeProvider), isNull);
      await signIn(c, ctxB);
      expect(c.read(posSyncScopeProvider)?.branchId, 'branch-B');

      c.read(posDeviceContextProvider.notifier).set(ctxA);
      await settle();
      expect(
        c.read(posSyncScopeProvider),
        isNull,
        reason: "B's session does not survive the return to A",
      );
      await signIn(c, ctxA);
      expect(c.read(posSyncScopeProvider)?.branchId, 'branch-A');
    });

    testWidgets(
      'the GATE refuses a session whose binding does not match its pairing — '
      'even when the session somehow survived (defense in depth)',
      (tester) async {
        final c = harness();
        // Session established under A; the device-context provider deliberately
        // NOT switched, so the source-invalidation layer does not fire and the
        // gate's own binding check is what stands between the stale session and
        // the POS surface.
        c.read(posDeviceContextProvider.notifier).set(ctxA);
        await settle();
        await signIn(c, ctxA);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              localizationsDelegates: restoflowLocalizationsDelegates,
              supportedLocales: kSupportedLocales,
              home: PosPinGate(
                // The gate is now mounted for pairing B.
                device: ctxB,
                staffRepository: _FakeStaff(),
                child: const Text('POS-SURFACE', key: Key('pos-surface')),
              ),
            ),
          ),
        );
        // Bounded pumps, not pumpAndSettle: the PIN screen keeps an animation
        // ticking under this harness, and the assertion needs no settlement.
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(
          find.byKey(const Key('pos-surface')),
          findsNothing,
          reason:
              "a session bound to branch A must not unlock a till paired to B — "
              'operating under it would put orders on the wrong books',
        );
        expect(find.byType(PinLoginScreen), findsOneWidget);
      },
    );
  });

  // ===========================================================================
  group('BLOCKER 3 — the submit result respects the TRUE mutation boundary', () {
    testWidgets(
      'a submit begun in A that completes after the move to B mutates NOTHING '
      'B-visible — and the accepted operation is not deleted',
      (tester) async {
        final outbox = _GatedOutbox();
        final c = harness(outbox: outbox, store: InMemoryRecentOrdersStore());
        c.read(posDeviceContextProvider.notifier).set(ctxA);
        await settle();
        await signIn(c, ctxA);

        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        late WidgetRef capturedRef;
        late BuildContext capturedContext;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              localizationsDelegates: restoflowLocalizationsDelegates,
              supportedLocales: kSupportedLocales,
              home: Consumer(
                builder: (context, ref, _) {
                  capturedRef = ref;
                  capturedContext = context;
                  return const Scaffold(body: SizedBox());
                },
              ),
            ),
          ),
        );

        // A real cart with a real line, submitted through the REAL handler.
        final cartController = c.read(cartControllerProvider.notifier);
        cartController.addItem(
          const DemoMenuItem(
            id: 'item-1',
            name: 'Burger',
            priceMinor: 4000,
            categoryId: 'cat',
            categoryName: 'Mains',
          ),
        );
        final pending = submitOrderFromCart(
          ref: capturedRef,
          context: capturedContext,
          cart: c.read(cartControllerProvider),
          setup: c.read(orderSetupControllerProvider),
          cartController: cartController,
          setupController: c.read(orderSetupControllerProvider.notifier),
          l10n: l10n,
        );
        await tester.pump();

        // THE MOVE: the pairing switches to branch B while the enqueue is in
        // flight.
        c.read(posDeviceContextProvider.notifier).set(ctxB);
        await settle();
        await signIn(c, ctxB);

        // NOW branch A's submit completes successfully.
        outbox.gate.complete();
        await pending;
        await tester.pumpAndSettle();

        expect(
          c.read(cartControllerProvider).submittedOrder,
          isNull,
          reason:
              "branch A's confirmation (with its live payment/discount actions) "
              'must not be installed while the till stands in branch B',
        );
        expect(
          c.read(posRecentOrdersControllerProvider),
          isEmpty,
          reason: "no A recent-order row may be written under B's scope",
        );
        expect(
          outbox.enqueued,
          hasLength(1),
          reason:
              'the ACCEPTED operation is preserved — an obsolete UI result is '
              'not a failed server operation',
        );
      },
    );

    testWidgets('the same submit in a STABLE scope completes normally', (
      tester,
    ) async {
      final outbox = _GatedOutbox();
      final c = harness(outbox: outbox, store: InMemoryRecentOrdersStore());
      c.read(posDeviceContextProvider.notifier).set(ctxA);
      await settle();
      await signIn(c, ctxA);

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      late WidgetRef capturedRef;
      late BuildContext capturedContext;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                capturedContext = context;
                return const Scaffold(body: SizedBox());
              },
            ),
          ),
        ),
      );

      final cartController = c.read(cartControllerProvider.notifier);
      cartController.addItem(
        const DemoMenuItem(
          id: 'item-1',
          name: 'Burger',
          priceMinor: 4000,
          categoryId: 'cat',
          categoryName: 'Mains',
        ),
      );
      final pending = submitOrderFromCart(
        ref: capturedRef,
        context: capturedContext,
        cart: c.read(cartControllerProvider),
        setup: c.read(orderSetupControllerProvider),
        cartController: cartController,
        setupController: c.read(orderSetupControllerProvider.notifier),
        l10n: l10n,
      );
      await tester.pump();
      outbox.gate.complete();
      await pending;
      await tester.pumpAndSettle();

      expect(c.read(cartControllerProvider).submittedOrder, isNotNull);
      expect(c.read(posRecentOrdersControllerProvider), hasLength(1));
    });

    testWidgets("Finding 1 (A->B->A): a submit result that lands after a PIN handover on "
        "the SAME till never mutates B's session; A's recovery is retained under "
        "A's binding, recoverable only when A returns", (tester) async {
      final outbox = _GatedOutbox();
      final c = harness(outbox: outbox, store: InMemoryRecentOrdersStore());
      c.read(posDeviceContextProvider.notifier).set(ctxA);
      await settle();
      await signIn(c, ctxA); // employee A — PIN session 1

      // A's exact submit-attempt binding (scope + PIN session), captured up front.
      final bindingA = c.read(posRecoveryBindingProvider);
      final scopeA = c.read(posSyncScopeProvider)?.key;

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      late WidgetRef capturedRef;
      late BuildContext capturedContext;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                capturedContext = context;
                return const Scaffold(body: SizedBox());
              },
            ),
          ),
        ),
      );

      // Employee A builds a cart and submits it through the REAL handler (gated
      // in flight).
      final cartController = c.read(cartControllerProvider.notifier);
      cartController.addItem(
        const DemoMenuItem(
          id: 'item-1',
          name: 'Burger',
          priceMinor: 4000,
          categoryId: 'cat',
          categoryName: 'Mains',
        ),
      );
      final pending = submitOrderFromCart(
        ref: capturedRef,
        context: capturedContext,
        cart: c.read(cartControllerProvider),
        setup: c.read(orderSetupControllerProvider),
        cartController: cartController,
        setupController: c.read(orderSetupControllerProvider.notifier),
        l10n: l10n,
      );
      await tester.pump();

      // THE HANDOVER: employee A signs out and a NEW PIN session signs in on the
      // SAME till (same operational scope) while A's submit is still in flight.
      c.read(posSessionControllerProvider.notifier).endSession();
      await settle();
      await signIn(c, ctxA); // employee B — PIN session 2, SAME scope
      final bindingB = c.read(posRecoveryBindingProvider);
      expect(
        bindingB == bindingA,
        isFalse,
        reason: 'a new PIN session is a new session binding',
      );
      expect(
        c.read(posSyncScopeProvider)?.key,
        scopeA,
        reason: 'the operational scope is unchanged — the same till',
      );

      // NOW A's submit completes.
      outbox.gate.complete();
      await pending;
      await tester.pumpAndSettle();

      // B's session is UNTOUCHED: A's confirmation is never installed under B.
      expect(
        c.read(cartControllerProvider).submittedOrder,
        isNull,
        reason: "A's confirmation must not be shown under B's session",
      );

      final entryId = outbox.enqueued.single.id;
      final recovery = c.read(posDraftRecoveryProvider.notifier);
      // B can neither see nor restore A's draft (binding mismatch).
      expect(
        recovery.recoverable(entryId, bindingB),
        isNull,
        reason: "employee B must not be able to restore employee A's draft",
      );
      // A's recovery IS retained under A's ORIGINAL binding — recoverable when A
      // returns, and inaccessible to anyone else.
      expect(
        recovery.recoverable(entryId, bindingA),
        isNotNull,
        reason: "A's draft must survive the handover, recoverable only by A",
      );
      // The shared (same-scope) recent list holds A's row so A finds it on return.
      expect(
        c
            .read(posRecentOrdersControllerProvider)
            .where((o) => o.order?.outboxEntryId == entryId),
        hasLength(1),
      );
    });
  });

  // ===========================================================================
  group('BLOCKER 4 — the owed durable write survives A -> B -> A', () {
    test(
      "A's failed write is preserved across the round trip and re-attempted — "
      'with the D-008 lines and payment truth intact',
      () async {
        final store = _FlakyStore(failuresBeforeSuccess: 2);
        final c = harness(store: store);
        c.read(posDeviceContextProvider.notifier).set(ctxA);
        await settle();
        await signIn(c, ctxA);
        final scopeAKey = c.read(posSyncScopeProvider)!.key;

        // A rich deviceOwned order: order-time lines (a receipt can be rebuilt).
        final orders = c.read(posRecentOrdersControllerProvider.notifier);
        orders.recordSubmitted(
          const SubmittedOrderView(
            orderNumber: '#o-1',
            orderType: OrderType.takeaway,
            currencyCode: 'ILS',
            subtotalMinor: 4000,
            orderId: 'o-1',
            lines: [
              SubmittedLineView(
                name: 'Burger',
                quantity: 1,
                lineTotalMinor: 4000,
                currencyCode: 'ILS',
              ),
            ],
          ),
        );
        await settle(); // the fire-and-forget persist FAILS -> debt booked

        // The authoritative snapshot arrives; the durable write fails AGAIN.
        final ok = await orders.applySnapshots([
          PosOrderSnapshot(
            orderId: 'o-1',
            orderCode: '#o-1',
            revision: 2,
            status: 'served',
            settlement: PosSettlement.unpaid,
            subtotalMinor: 4000,
            discountTotalMinor: 0,
            taxTotalMinor: 0,
            grandTotalMinor: 4000,
            createdAt: t0,
            updatedAt: t0,
            syncAt: t0,
            currencyCode: 'ILS',
          ),
        ]);
        expect(ok, isFalse);
        expect(orders.lastPersistFailed, isTrue, reason: 'A owes a write');

        // A -> B. The debt is A's; B inherits neither rows nor debt.
        c.read(posDeviceContextProvider.notifier).set(ctxB);
        await settle();
        await signIn(c, ctxB);
        expect(c.read(posRecentOrdersControllerProvider), isEmpty);
        expect(
          orders.lastPersistFailed,
          isFalse,
          reason: "B does not inherit A's unsaved-day flag",
        );
        // A B-side success must not clear A's debt.
        final okB = await orders.applySnapshots(const []);
        expect(okB, isTrue);

        // B -> A. The owed rows participate in recovery...
        c.read(posDeviceContextProvider.notifier).set(ctxA);
        await settle();
        await signIn(c, ctxA);
        c.read(posRecentOrdersControllerProvider); // build + recover
        await settle();

        final recovered = c.read(posRecentOrdersControllerProvider);
        expect(recovered, hasLength(1));
        expect(
          recovered.single.order?.lines,
          isNotEmpty,
          reason: 'the order-time lines survived the round trip',
        );
        expect(
          recovered.single.snapshot?.revision,
          2,
          reason: 'the authoritative snapshot survived with them',
        );
        expect(orders.lastPersistFailed, isTrue, reason: 'A still owes');

        // ...and an EMPTY server page now retries the owed write (store heals).
        final okRetry = await orders.applySnapshots(const []);
        expect(okRetry, isTrue);
        expect(orders.lastPersistFailed, isFalse, reason: 'debt cleared');
        final persisted = store.persisted[scopeAKey]!;
        expect(persisted, hasLength(1));
        expect(
          persisted.single.order?.lines,
          isNotEmpty,
          reason: 'the rich row was durably REWRITTEN, lines and all',
        );
        expect(
          store.persisted.keys.where((k) => k != scopeAKey && k.isNotEmpty),
          isNot(contains(anything)),
        );
      },
    );
  });

  // ===========================================================================
  group('BLOCKER 5 — the void flow survives sheet dismissal', () {
    PosRecentOrder orderA() => PosRecentOrder(
      order: const SubmittedOrderView(
        orderNumber: '#o-1',
        orderType: OrderType.takeaway,
        currencyCode: 'ILS',
        subtotalMinor: 4000,
        orderId: 'o-1',
        lines: <SubmittedLineView>[],
      ),
      submittedAt: t0,
      snapshot: PosOrderSnapshot(
        orderId: 'o-1',
        orderCode: '#o-1',
        revision: 3,
        status: 'submitted',
        settlement: PosSettlement.unpaid,
        subtotalMinor: 4000,
        discountTotalMinor: 0,
        taxTotalMinor: 0,
        grandTotalMinor: 4000,
        createdAt: t0,
        updatedAt: t0,
        syncAt: t0,
        currencyCode: 'ILS',
      ),
    );

    Future<void> pumpSheetAndSubmit(
      WidgetTester tester,
      ProviderContainer c,
    ) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    key: const Key('open-sheet'),
                    onPressed: () =>
                        CancelOrderSheet.show(context, order: orderA()),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-sheet')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('cancel-reason-field')),
        'wrong order',
      );
      await tester.tap(find.byKey(const Key('cancel-confirm-button')));
      await tester.pump();
    }

    testWidgets(
      'dismissed before SUCCESS: no ref-after-dispose, the terminal marker and '
      'the targeted reconcile still land, the order is not left actionable',
      (tester) async {
        final voids = _GatedVoidRepo();
        final spy = _SpyRepo();
        final c = harness(
          voids: voids,
          repo: spy,
          store: InMemoryRecentOrdersStore(),
        );
        c.read(posDeviceContextProvider.notifier).set(ctxA);
        await settle();
        await signIn(c, ctxA);
        c
            .read(posRecentOrdersControllerProvider.notifier)
            .recordSubmitted(orderA().order!);
        await settle();

        await pumpSheetAndSubmit(tester, c);

        // THE DISMISSAL: the cashier drags the sheet away mid-flight.
        Navigator.of(tester.element(find.byType(CancelOrderSheet))).pop();
        await tester.pumpAndSettle();
        expect(find.byType(CancelOrderSheet), findsNothing);

        // NOW the server confirms the void.
        voids.gate.complete();
        await tester.pumpAndSettle();

        final row = c.read(posRecentOrdersControllerProvider).single;
        expect(
          row.isVoided,
          isTrue,
          reason:
              'the SERVER voided this order; a dismissed sheet must not leave '
              'it actionable on the till',
        );
        expect(row.isTerminal, isTrue);
        expect(
          spy.targeted,
          1,
          reason: 'the authoritative targeted reconcile still ran',
        );
        expect(tester.takeException(), isNull, reason: 'no ref-after-dispose');
      },
    );

    testWidgets(
      'dismissed before CONFLICT: the targeted refresh still runs, nothing '
      'auto-retries, no ref-after-dispose',
      (tester) async {
        final voids = _GatedVoidRepo(
          error: const VoidException('conflict', conflict: true),
        );
        final spy = _SpyRepo();
        final c = harness(
          voids: voids,
          repo: spy,
          store: InMemoryRecentOrdersStore(),
        );
        c.read(posDeviceContextProvider.notifier).set(ctxA);
        await settle();
        await signIn(c, ctxA);
        c
            .read(posRecentOrdersControllerProvider.notifier)
            .recordSubmitted(orderA().order!);
        await settle();

        await pumpSheetAndSubmit(tester, c);
        Navigator.of(tester.element(find.byType(CancelOrderSheet))).pop();
        await tester.pumpAndSettle();

        voids.gate.complete();
        await tester.pumpAndSettle();

        expect(voids.calls, 1, reason: 'never auto-retried');
        expect(
          spy.targeted,
          1,
          reason: 'data reconciliation does not need a mounted sheet',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'scope moves A -> B during the void: the A result is NOT merged into B',
      (tester) async {
        final voids = _GatedVoidRepo();
        final spy = _SpyRepo();
        final c = harness(
          voids: voids,
          repo: spy,
          store: InMemoryRecentOrdersStore(),
        );
        c.read(posDeviceContextProvider.notifier).set(ctxA);
        await settle();
        await signIn(c, ctxA);
        c
            .read(posRecentOrdersControllerProvider.notifier)
            .recordSubmitted(orderA().order!);
        await settle();

        await pumpSheetAndSubmit(tester, c);

        // The pairing moves mid-void.
        c.read(posDeviceContextProvider.notifier).set(ctxB);
        await settle();
        await signIn(c, ctxB);

        voids.gate.complete();
        // Bounded pumps: in the REAL app the pairing change unmounts this tree;
        // in this harness the sheet stays mounted, and full settlement is not
        // what is under test.
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(
          c.read(posRecentOrdersControllerProvider),
          isEmpty,
          reason: "the A void must write NOTHING into B's state",
        );
        expect(
          spy.targeted,
          0,
          reason:
              "no targeted fetch under B for A's order — A reconciles it on "
              'its own return',
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}

// =============================================================================
// Fakes — timing and refusals only, never the answer under test.
// =============================================================================

class _FakeTransport implements SyncRpcTransport {
  int pinSessions = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'start_pin_session') {
      pinSessions++;
      return 'pin-session-$pinSessions';
    }
    if (function == 'sync_push') {
      return <String, dynamic>{
        'ok': true,
        'results': <dynamic>[
          <String, dynamic>{
            'operation_type': 'shift.open',
            'status': 'applied',
            'ok': true,
          },
        ],
      };
    }
    return null;
  }
}

class _FakeStaff implements DeviceStaffRepository {
  @override
  Future<Result<List<DeviceStaffMember>, DeviceStaffFailure>>
  listStaff() async => const Success([
    DeviceStaffMember(
      employeeProfileId: 'emp-1',
      displayName: 'Amira K.',
      role: 'cashier',
    ),
  ]);
}

/// Counts every snapshot RPC. Zero means ZERO.
class _SpyRepo implements OrderSnapshotRepository {
  int window = 0;
  int changes = 0;
  int targeted = 0;
  int get calls => window + changes + targeted;

  @override
  Future<PosSnapshotPage> fetchWindow({
    PosSyncCursor? before,
    int limit = 50,
    int windowDays = 2,
  }) async {
    window++;
    return PosSnapshotPage.empty;
  }

  @override
  Future<PosSnapshotPage> fetchChanges({
    PosSyncCursor? cursor,
    int limit = 50,
    int windowDays = 2,
  }) async {
    changes++;
    return PosSnapshotPage.empty;
  }

  @override
  Future<PosSnapshotPage> fetchOrders(List<String> orderIds) async {
    targeted++;
    return PosSnapshotPage.empty;
  }
}

/// An outbox whose enqueue blocks until the test releases it.
class _GatedOutbox implements OutboxRepository {
  final Completer<void> gate = Completer<void>();
  final List<OutboxEntry> enqueued = <OutboxEntry>[];

  @override
  Future<OutboxEntry> enqueue(OutboxEntry entry) async {
    await gate.future;
    enqueued.add(entry);
    return entry;
  }

  @override
  Future<List<OutboxEntry>> recentEntries() async => List.of(enqueued);

  @override
  Future<OutboxEntry> push(String entryId) async =>
      enqueued.firstWhere((e) => e.id == entryId);

  @override
  Future<OutboxEntry> retry(String entryId) async =>
      enqueued.firstWhere((e) => e.id == entryId);
}

/// A void repository gated on a Completer; optionally refusing with [error].
class _GatedVoidRepo implements VoidRepository {
  _GatedVoidRepo({this.error});

  final Completer<void> gate = Completer<void>();
  final VoidException? error;
  int calls = 0;

  @override
  Future<void> voidOrder({
    required String orderId,
    required String reason,
    int? expectedRevision,
  }) async {
    calls++;
    await gate.future;
    final e = error;
    if (e != null) throw e;
  }
}

/// Fails the first N persists, then accepts.
class _FlakyStore implements PosRecentOrdersStore {
  _FlakyStore({required this.failuresBeforeSuccess});

  int failuresBeforeSuccess;
  final Map<String, List<PosRecentOrder>> persisted = {};

  @override
  Future<List<PosRecentOrder>> load(String scopeKey) async =>
      List.of(persisted[scopeKey] ?? const <PosRecentOrder>[]);

  @override
  Future<void> persist(String scopeKey, List<PosRecentOrder> orders) async {
    if (failuresBeforeSuccess > 0) {
      failuresBeforeSuccess--;
      throw const PosPersistenceException('write refused');
    }
    persisted[scopeKey] = List.of(orders);
  }
}
