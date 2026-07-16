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

/// PILOT-OPERATIONS-CORRECTIONS-001 — Finding 1A: a permanently-rejected shell exposes
/// its recovery actions (Restore + Discard) FROM Recent Orders — and NEVER any
/// accepted-order action (payment / discount / void / receipt).
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
}
