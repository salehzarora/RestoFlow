import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncSession;
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
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
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';

/// POS-OPERATIONS-SYNC-001 (Commit 3) — the operational centre, on screen.
void main() {
  // PILOT-OPERATIONS-CORRECTIONS-001 (stabilization): anchor the fixture to the
  // real clock — the recent-orders view windows to `real-today − 1 day`, so a
  // hardcoded date silently falls out of the window as the calendar advances.
  final t0 = DateTime.now().toUtc().subtract(const Duration(hours: 2));

  PosOrderSnapshot snap({
    required String id,
    String status = 'submitted',
    PosSettlement settlement = PosSettlement.unpaid,
    int grand = 4000,
    int minutesAgo = 0,
  }) {
    final at = t0.subtract(Duration(minutes: minutesAgo));
    return PosOrderSnapshot(
      orderId: id,
      orderCode: '#$id',
      revision: 2,
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

  PosRecentOrder owned(PosOrderSnapshot s) => PosRecentOrder(
    order: SubmittedOrderView(
      orderNumber: s.orderCode,
      orderType: OrderType.dineIn,
      currencyCode: 'ILS',
      subtotalMinor: s.subtotalMinor,
      lines: const <SubmittedLineView>[],
      orderId: s.orderId,
    ),
    submittedAt: s.createdAt,
    snapshot: s,
  );

  void sized(WidgetTester tester, double w) {
    tester.view.physicalSize = Size(w, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<AppLocalizations> l10nFor(String code) =>
      AppLocalizations.delegate.load(Locale(code));

  Future<Widget> harness({
    required List<PosRecentOrder> seed,
    OrderSnapshotRepository? repo,
    String locale = 'en',
    PosSyncError? forceError,
  }) async {
    final store = InMemoryRecentOrdersStore();
    // In demo mode the controller keys its store on the demo device id, so the seed
    // must be written under exactly that scope.
    await store.persist(kDemoSyncScope.key, seed);
    return ProviderScope(
      overrides: [
        // A real device/PIN scope: without one the coordinator correctly no-ops, and
        // the offline/refresh paths would never run at all.
        posSyncSessionProvider.overrideWithValue(
          const SyncSession(pinSessionId: 'pin1', deviceId: 'dev1'),
        ),
        posRecentOrdersStoreProvider.overrideWithValue(store),
        posSyncCursorStoreProvider.overrideWithValue(InMemorySyncCursorStore()),
        posSyncClockProvider.overrideWithValue(() => t0),
        // NULL interval: a live repeating Timer makes pumpAndSettle hang forever.
        posSyncPollIntervalProvider.overrideWithValue(null),
        orderSnapshotRepositoryProvider.overrideWithValue(
          repo ??
              (DemoOrderSnapshotRepository()
                ..clock = t0
                ..nextFailure = forceError == PosSyncError.offline
                    ? const PosSnapshotException(PosSnapshotFailure.transport)
                    : null),
        ),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const Scaffold(body: _Seeded()),
      ),
    );
  }

  group('A. sections on screen', () {
    testWidgets('A1 the centre LANDS on Open and shows live work only', (
      tester,
    ) async {
      sized(tester, 1000);
      await tester.pumpWidget(
        await harness(
          seed: <PosRecentOrder>[
            owned(snap(id: 'live', status: 'ready')),
            owned(
              snap(
                id: 'done',
                status: 'completed',
                settlement: PosSettlement.paid,
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recent-order-#live')), findsOneWidget);
      expect(
        find.byKey(const Key('recent-order-#done')),
        findsNothing,
        reason: 'a completed order is not open work',
      );

      await tester.tap(
        find.byKey(const Key('orders-section-completedRecently')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recent-order-#done')), findsOneWidget);
    });

    testWidgets('A2 Needs payment excludes paid, comped and terminal', (
      tester,
    ) async {
      sized(tester, 1000);
      await tester.pumpWidget(
        await harness(
          seed: <PosRecentOrder>[
            owned(snap(id: 'owes', status: 'served')),
            owned(snap(id: 'paid', settlement: PosSettlement.paid)),
            owned(
              snap(
                id: 'comp',
                grand: 0,
                settlement: PosSettlement.notChargeable,
              ),
            ),
            owned(snap(id: 'gone', status: 'cancelled')),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('orders-section-needsPayment')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recent-order-#owes')), findsOneWidget);
      expect(find.byKey(const Key('recent-order-#paid')), findsNothing);
      expect(find.byKey(const Key('recent-order-#comp')), findsNothing);
      expect(find.byKey(const Key('recent-order-#gone')), findsNothing);
    });
  });

  group('B. actions are authoritative', () {
    testWidgets('B1 a COMPLETED order offers no payment and no cancel', (
      tester,
    ) async {
      sized(tester, 1000);
      await tester.pumpWidget(
        await harness(
          seed: <PosRecentOrder>[
            owned(
              snap(
                id: 'done',
                status: 'completed',
                settlement: PosSettlement.paid,
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('orders-section-completedRecently')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recent-pay-#done')), findsNothing);
      expect(find.byKey(const Key('recent-cancel-#done')), findsNothing);
      expect(find.byKey(const Key('recent-discount-#done')), findsNothing);
    });

    testWidgets('B2 a comped order shows No charge and offers no payment', (
      tester,
    ) async {
      sized(tester, 1000);
      final l10n = await l10nFor('en');
      await tester.pumpWidget(
        await harness(
          seed: <PosRecentOrder>[
            owned(
              snap(
                id: 'comp',
                status: 'served',
                grand: 0,
                settlement: PosSettlement.notChargeable,
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recent-pay-#comp')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('order-settlement-#comp')),
          matching: find.text(l10n.posNoChargeChip),
        ),
        findsOneWidget,
      );
      // A missing control is explained, not just missing.
      expect(
        find.byKey(const Key('recent-nocharge-note-#comp')),
        findsOneWidget,
      );
    });
  });

  group('C. search, filters, sort', () {
    testWidgets('C1 search by order code narrows, and clearing restores', (
      tester,
    ) async {
      sized(tester, 1000);
      await tester.pumpWidget(
        await harness(
          seed: <PosRecentOrder>[
            owned(snap(id: 'aaa', status: 'ready')),
            owned(snap(id: 'bbb', status: 'ready')),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('orders-search-field')),
        'aaa',
      );
      // Debounced: settle past the timer rather than asserting mid-flight.
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('recent-order-#aaa')), findsOneWidget);
      expect(find.byKey(const Key('recent-order-#bbb')), findsNothing);

      await tester.tap(find.byKey(const Key('orders-search-clear')));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('recent-order-#bbb')), findsOneWidget);
    });

    testWidgets('C2 an empty search shows the search-specific empty state', (
      tester,
    ) async {
      sized(tester, 1000);
      final l10n = await l10nFor('en');
      await tester.pumpWidget(
        await harness(
          seed: <PosRecentOrder>[owned(snap(id: 'aaa', status: 'ready'))],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('orders-search-field')),
        'zzz',
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text(l10n.posOrdersSearchEmpty), findsOneWidget);
    });

    testWidgets('C3 newest first by default; the sort toggle flips it', (
      tester,
    ) async {
      sized(tester, 1000);
      await tester.pumpWidget(
        await harness(
          seed: <PosRecentOrder>[
            owned(snap(id: 'old', status: 'ready', minutesAgo: 60)),
            owned(snap(id: 'new', status: 'ready', minutesAgo: 1)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final firstNewest = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.key != null)
          .map((c) => c.key.toString())
          .firstWhere((k) => k.contains('recent-order-'));
      expect(firstNewest.contains('#new'), isTrue);

      await tester.tap(find.byKey(const Key('orders-sort-toggle')));
      await tester.pumpAndSettle();
      final firstOldest = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.key != null)
          .map((c) => c.key.toString())
          .firstWhere((k) => k.contains('recent-order-'));
      expect(firstOldest.contains('#old'), isTrue);
    });
  });

  group('D. sync UX', () {
    testWidgets('D1 offline KEEPS the rows and says so', (tester) async {
      sized(tester, 1000);
      await tester.pumpWidget(
        await harness(
          seed: <PosRecentOrder>[owned(snap(id: 'keep', status: 'ready'))],
          forceError: PosSyncError.offline,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('recent-order-#keep')),
        findsOneWidget,
        reason: 'a failed refresh must NEVER blank the till',
      );
      expect(find.byKey(const Key('orders-offline-banner')), findsOneWidget);
    });

    testWidgets(
      'D2 a manual refresh control exists, and no auto-refresh toggle',
      (tester) async {
        sized(tester, 1000);
        await tester.pumpWidget(
          await harness(
            seed: <PosRecentOrder>[owned(snap(id: 'x', status: 'ready'))],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('orders-refresh-button')), findsOneWidget);
        // Refreshing is our job, not a setting to be misconfigured.
        expect(find.byType(Switch), findsNothing);
        await tester.tap(find.byKey(const Key('orders-refresh-button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('recent-order-#x')), findsOneWidget);
      },
    );

    testWidgets('D3 the sync status line never claims to be live', (
      tester,
    ) async {
      sized(tester, 1000);
      await tester.pumpWidget(
        await harness(
          seed: <PosRecentOrder>[owned(snap(id: 'x', status: 'ready'))],
        ),
      );
      await tester.pumpAndSettle();

      final text = tester
          .widget<Text>(find.byKey(const Key('orders-sync-status')))
          .data!
          .toLowerCase();
      expect(text.contains('live'), isFalse);
      expect(text.contains('real-time'), isFalse);
    });
  });

  group('E. i18n + responsive', () {
    for (final code in <String>['ar', 'he', 'en']) {
      testWidgets('E1 renders in $code without overflow (phone 390)', (
        tester,
      ) async {
        sized(tester, 390);
        await tester.pumpWidget(
          await harness(
            seed: <PosRecentOrder>[owned(snap(id: 'x', status: 'ready'))],
            locale: code,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('recent-orders-sheet')), findsOneWidget);
      });
    }

    for (final w in <double>[700, 940, 1320]) {
      testWidgets('E2 renders at ${w.toInt()}px without overflow', (
        tester,
      ) async {
        sized(tester, w);
        await tester.pumpWidget(
          await harness(
            seed: <PosRecentOrder>[owned(snap(id: 'x', status: 'ready'))],
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('E3 status and settlement are never colour-ONLY', (
      tester,
    ) async {
      sized(tester, 1000);
      final l10n = await l10nFor('en');
      await tester.pumpWidget(
        await harness(
          seed: <PosRecentOrder>[owned(snap(id: 'x', status: 'ready'))],
        ),
      );
      await tester.pumpAndSettle();

      // Both carry TEXT. Colour is not a label, and a cashier with a colour-vision
      // deficiency is still a cashier.
      expect(
        find.descendant(
          of: find.byKey(const Key('order-status-#x')),
          matching: find.text(l10n.posOrdersStatusReady),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('order-settlement-#x')),
          matching: find.text(l10n.posUnpaidChip),
        ),
        findsOneWidget,
      );
    });
  });

  group('F. branch-discovered rows', () {
    testWidgets('F1 an order another till took appears, labelled honestly', (
      tester,
    ) async {
      sized(tester, 1000);
      final l10n = await l10nFor('en');
      await tester.pumpWidget(
        await harness(
          seed: <PosRecentOrder>[
            PosRecentOrder.discovered(snap(id: 'other', status: 'ready')),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recent-order-#other')), findsOneWidget);
      expect(find.text(l10n.posOrdersOtherTill), findsOneWidget);
      // No lines were ever seen here, so there is no receipt to print.
      expect(find.byKey(const Key('recent-reprint-#other')), findsNothing);
      // ...but it is a real order on this branch and can still be acted on.
      expect(find.byKey(const Key('recent-pay-#other')), findsOneWidget);
    });
  });
}

/// Publishes the paired DeviceContext (a NotifierProvider, so it is seeded through
/// its own API) and then shows the centre.
class _Seeded extends ConsumerStatefulWidget {
  const _Seeded();

  @override
  ConsumerState<_Seeded> createState() => _SeededState();
}

class _SeededState extends ConsumerState<_Seeded> {
  @override
  void initState() {
    super.initState();
    // Riverpod forbids MUTATING a provider during initState (the tree is mid-build),
    // so publish the paired device on the next frame — which is also when the real
    // pairing gate does it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(posDeviceContextProvider.notifier)
          .set(
            const DeviceContext(
              organizationId: 'org1',
              branchId: 'branch-A',
              restaurantId: 'r1',
              deviceId: 'dev1',
            ),
          );
    });
  }

  @override
  Widget build(BuildContext context) => const RecentOrdersSheet();
}
