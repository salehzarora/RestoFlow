import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/draft_recovery_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';

/// A session controller whose established session can be FLIPPED mid-test — used to
/// simulate a real PIN handover on the SAME till (employee A signs out, employee B signs
/// in) so `posRecoveryBindingProvider` recomputes without changing the operational scope.
class _SwitchableSession extends PosSessionController {
  _SwitchableSession(this._initial);
  final SyncSession? _initial;
  @override
  FutureOr<SyncSession?> build() => _initial;
  void switchTo(SyncSession? session) => state = AsyncData(session);
}

/// PILOT-OPERATIONS-CORRECTIONS-001 — Finding 1A: a permanently-rejected shell exposes
/// its recovery actions (Restore + Discard) FROM Recent Orders — and NEVER any
/// accepted-order action (payment / discount / void / receipt). Finding 2: a shell whose
/// recovery belongs to ANOTHER session is NOT discardable by this actor.
void main() {
  final t0 = DateTime.now().toUtc().subtract(const Duration(hours: 2));

  PosRecentOrder rejectedShell(String entryId) => PosRecentOrder(
    order: SubmittedOrderView(
      orderNumber: 'DEMO-$entryId',
      orderType: OrderType.dineIn,
      currencyCode: 'ILS',
      subtotalMinor: 4200,
      lines: const <SubmittedLineView>[],
      orderId: 'local-$entryId',
      outboxEntryId: entryId,
      localOperationId: 'op-$entryId',
    ),
    submittedAt: t0,
  ).copyWith(neverCreated: true);

  Future<ProviderContainer> seededContainer(List<PosRecentOrder> seed) async {
    final store = InMemoryRecentOrdersStore();
    await store.persist(kDemoSyncScope.key, seed);
    return ProviderContainer(
      overrides: [
        posSyncSessionProvider.overrideWithValue(
          const SyncSession(pinSessionId: 'pin1', deviceId: 'dev1'),
        ),
        posRecentOrdersStoreProvider.overrideWithValue(store),
        posSyncCursorStoreProvider.overrideWithValue(InMemorySyncCursorStore()),
        posSyncClockProvider.overrideWithValue(() => t0),
        posSyncPollIntervalProvider.overrideWithValue(null),
        orderSnapshotRepositoryProvider.overrideWithValue(
          DemoOrderSnapshotRepository()..clock = t0,
        ),
      ],
    );
  }

  Future<void> pump(WidgetTester tester, ProviderContainer c) async {
    tester.view.physicalSize = const Size(1100, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(body: RecentOrdersSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a rejected shell WITH a matching recovery shows Restore + Discard, '
    'never accepted-order actions',
    (tester) async {
      final c = await seededContainer([rejectedShell('eA')]);
      addTearDown(c.dispose);
      // A matching, scope-valid recovery for the shell.
      c
          .read(posDraftRecoveryProvider.notifier)
          .capture(
            PosDraftRecovery(
              draft: const CartDraftSnapshot(currencyCode: 'ILS', lines: []),
              orderType: OrderType.dineIn,
              outboxEntryId: 'eA',
              binding: c.read(posRecoveryBindingProvider),
            ),
          );
      await pump(tester, c);
      // Move to the "All" tab where the rejected shell is visible.
      await tester.tap(find.byKey(const Key('orders-section-all')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recent-restore-DEMO-eA')), findsOneWidget);
      expect(find.byKey(const Key('recent-discard-DEMO-eA')), findsOneWidget);
      // The shell is marked Not created and exposes NO accepted-order action.
      expect(
        find.byKey(const Key('recent-not-created-DEMO-eA')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('recent-pay-DEMO-eA')), findsNothing);
      expect(find.byKey(const Key('recent-discount-DEMO-eA')), findsNothing);
      expect(find.byKey(const Key('recent-cancel-DEMO-eA')), findsNothing);
      expect(find.byKey(const Key('recent-move-table-DEMO-eA')), findsNothing);
      expect(find.byKey(const Key('recent-reprint-DEMO-eA')), findsNothing);
    },
  );

  testWidgets('a rejected shell with NO matching recovery shows only Discard', (
    tester,
  ) async {
    // No recovery captured (e.g. after a restart — the in-memory recovery is gone).
    final c = await seededContainer([rejectedShell('eB')]);
    addTearDown(c.dispose);
    await pump(tester, c);
    await tester.tap(find.byKey(const Key('orders-section-all')));
    await tester.pumpAndSettle();
    // Restore is unavailable; a safe local Discard remains.
    expect(find.byKey(const Key('recent-restore-DEMO-eB')), findsNothing);
    expect(find.byKey(const Key('recent-discard-DEMO-eB')), findsOneWidget);
    expect(find.byKey(const Key('recent-pay-DEMO-eB')), findsNothing);
  });

  testWidgets(
    'Finding 2 (A→B→A): employee B canNOT discard employee A\'s rejected shell — '
    'it belongs to another session; the shell + recovery survive so A recovers it '
    'when they return',
    (tester) async {
      const sessionA = SyncSession(pinSessionId: 'pinA', deviceId: 'dev1');
      const sessionB = SyncSession(pinSessionId: 'pinB', deviceId: 'dev1');
      final store = InMemoryRecentOrdersStore();
      await store.persist(kDemoSyncScope.key, [rejectedShell('eX')]);
      final switchable = _SwitchableSession(sessionA);
      final c = ProviderContainer(
        overrides: [
          // A REAL session controller we can flip A→B→A (same till, new PIN).
          posSessionControllerProvider.overrideWith(() => switchable),
          posRecentOrdersStoreProvider.overrideWithValue(store),
          posSyncCursorStoreProvider.overrideWithValue(
            InMemorySyncCursorStore(),
          ),
          posSyncClockProvider.overrideWithValue(() => t0),
          posSyncPollIntervalProvider.overrideWithValue(null),
          orderSnapshotRepositoryProvider.overrideWithValue(
            DemoOrderSnapshotRepository()..clock = t0,
          ),
        ],
      );
      addTearDown(c.dispose);

      // Employee A captures a recovery for the shell under A's binding.
      final bindingA = c.read(posRecoveryBindingProvider);
      c
          .read(posDraftRecoveryProvider.notifier)
          .capture(
            PosDraftRecovery(
              draft: const CartDraftSnapshot(currencyCode: 'ILS', lines: []),
              orderType: OrderType.dineIn,
              outboxEntryId: 'eX',
              binding: bindingA,
            ),
          );
      // Sanity: under A the recovery is recoverable.
      expect(
        c.read(posDraftRecoveryProvider.notifier).recoverable('eX', bindingA),
        isNotNull,
      );

      // Employee A signs out; employee B signs in on the SAME till (new PIN session).
      switchable.switchTo(sessionB);
      await pump(tester, c);
      await tester.tap(find.byKey(const Key('orders-section-all')));
      await tester.pumpAndSettle();

      // B sees the shell honestly marked as another session's — NO Restore, and
      // CRUCIALLY NO Discard: B must not be able to retire A's shell.
      expect(
        find.byKey(const Key('recent-other-session-DEMO-eX')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('recent-restore-DEMO-eX')), findsNothing);
      expect(find.byKey(const Key('recent-discard-DEMO-eX')), findsNothing);

      // Employee A returns (signs back in): the recovery is recoverable again and the
      // shell SURVIVED B's session — Restore + Discard are back for the rightful owner.
      switchable.switchTo(sessionA);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('recent-other-session-DEMO-eX')),
        findsNothing,
      );
      expect(find.byKey(const Key('recent-restore-DEMO-eX')), findsOneWidget);
      expect(find.byKey(const Key('recent-discard-DEMO-eX')), findsOneWidget);
      // A's recovery record is intact (B never mutated it).
      expect(
        c
            .read(posDraftRecoveryProvider.notifier)
            .recoverable('eX', c.read(posRecoveryBindingProvider)),
        isNotNull,
      );
    },
  );

  testWidgets(
    'PSC-001C cart-safety: the Restore action DISABLES while a frozen '
    'addition attempt owns the cart, and restores after unlock — the shell '
    'and recovery survive throughout',
    (tester) async {
      final c = await seededContainer([rejectedShell('eL')]);
      addTearDown(c.dispose);
      c
          .read(posDraftRecoveryProvider.notifier)
          .capture(
            PosDraftRecovery(
              draft: const CartDraftSnapshot(currencyCode: 'ILS', lines: []),
              orderType: OrderType.dineIn,
              outboxEntryId: 'eL',
              binding: c.read(posRecoveryBindingProvider),
            ),
          );
      await pump(tester, c);
      await tester.tap(find.byKey(const Key('orders-section-all')));
      await tester.pumpAndSettle();
      ButtonStyleButton restoreButton() => tester.widget<ButtonStyleButton>(
        find.byKey(const Key('recent-restore-DEMO-eL')),
      );
      expect(restoreButton().onPressed, isNotNull);

      // A frozen addition attempt owns the cart.
      const owner = CartLockOwner(
        generation: 1,
        orderId: 'o-add',
        localOperationId: 'op-add',
      );
      expect(
        c.read(cartControllerProvider.notifier).lockForAddition(owner),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(restoreButton().onPressed, isNull); // disabled, not hidden

      // A legitimate release restores the SAME action for the SAME recovery.
      expect(
        c.read(cartControllerProvider.notifier).unlockForAddition(owner),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(restoreButton().onPressed, isNotNull);
      expect(
        c
            .read(posDraftRecoveryProvider.notifier)
            .recoverable('eL', c.read(posRecoveryBindingProvider)),
        isNotNull,
      );
    },
  );
}
