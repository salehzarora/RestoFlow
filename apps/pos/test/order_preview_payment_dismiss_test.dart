import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart' show PosMenuScreen;
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// POS-OPEN-ORDER-PAYMENT-DISMISS-019 — the payment-success dismissal
/// lifecycle of the order detail preview.
///
/// Business truth is untouched: [CashPaymentSheet]'s ONE authoritative success
/// edge now carries `true` out of its pop, the shared action row forwards ONLY
/// that to an optional callback, and the preview retires itself on it. Card
/// membership stays entirely with the authoritative controller + the canonical
/// Open predicate; cancel/failure/gates keep the cashier on the preview with
/// today's behavior.

const _code = '#PD0001';
const _orderId = 'oid-PD0001';

SubmittedOrderView _view() => const SubmittedOrderView(
  orderNumber: _code,
  orderType: OrderType.dineIn,
  tableLabel: 'T7',
  currencyCode: 'ILS',
  subtotalMinor: 5400,
  orderId: _orderId,
  customerName: 'Dana',
  lines: [
    SubmittedLineView(
      name: 'Classic Burger',
      quantity: 1,
      lineTotalMinor: 5400,
      currencyCode: 'ILS',
    ),
  ],
);

PosOrderSnapshot _snapshot({
  required PosSettlement settlement,
  String status = 'served',
  int revision = 2,
}) {
  // Window-safe: anchored to now (the recent-orders horizon is today+yesterday).
  final at = DateTime.now().toUtc().subtract(const Duration(hours: 2));
  return PosOrderSnapshot(
    orderId: _orderId,
    orderCode: _code,
    revision: revision,
    status: status,
    settlement: settlement,
    subtotalMinor: 5400,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: 5400,
    createdAt: at,
    updatedAt: at,
    syncAt: at,
    orderType: 'dine_in',
    tableLabel: 'T7',
    currencyCode: 'ILS',
  );
}

PosRecentOrder _unpaidServedOrder() => PosRecentOrder(
  order: _view(),
  snapshot: _snapshot(settlement: PosSettlement.unpaid),
  submittedAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
);

/// Pumps the REAL POS menu screen (strip + grid) with one seeded open order —
/// the exact surface chain the owner reported: strip card → preview → pay.
Future<(ProviderContainer, DemoOrderSnapshotRepository)> _pumpMenu(
  WidgetTester tester,
) async {
  SharedPreferences.setMockInitialValues(const {});
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final store = InMemoryRecentOrdersStore();
  await store.persist(kDemoSyncScope.key, [_unpaidServedOrder()]);
  final repo = DemoOrderSnapshotRepository();
  final container = ProviderContainer(
    overrides: [
      posRecentOrdersStoreProvider.overrideWithValue(store),
      orderSnapshotRepositoryProvider.overrideWithValue(repo),
      posSyncPollIntervalProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const PosMenuScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container, repo);
}

Finder get _stripCard => find.byKey(const Key('open-strip-order-$_code'));
Finder get _preview => find.byKey(const Key('order-detail-preview'));
Finder get _previewPay => find.byKey(const Key('preview-pay-$_code'));

Future<void> _openPreviewFromStrip(WidgetTester tester) async {
  await tester.tap(_stripCard);
  await tester.pumpAndSettle();
  expect(_preview, findsOneWidget);
}

Future<void> _payExact(WidgetTester tester) async {
  await tester.tap(_previewPay);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('quick-cash-exact')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('confirm-payment-button')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('D. payment success auto-dismisses the preview', () {
    testWidgets('D1 a successful payment closes the payment sheet AND the '
        'preview — the cashier lands back on the menu with no stale pay '
        'button anywhere', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await _pumpMenu(tester);
      await _openPreviewFromStrip(tester);
      await _payExact(tester);

      // Payment sheet gone, preview gone, menu (grid) visible again.
      expect(find.text(l10n.posPaymentTitle), findsNothing);
      expect(_preview, findsNothing);
      expect(find.byKey(const Key('pos-product-grid')), findsOneWidget);
      // No stale interactive window: the pay affordance is nowhere on screen.
      expect(_previewPay, findsNothing);
    });

    testWidgets('D2 when the authoritative refresh marks the order terminal, '
        'the strip card leaves through the controller + canonical predicate — '
        'no manual removal anywhere in the dismiss path', (tester) async {
      final (container, repo) = await _pumpMenu(tester);
      await _openPreviewFromStrip(tester);
      await _payExact(tester);
      expect(_preview, findsNothing);

      // The server's answer: payment auto-completed the served order. The
      // card must leave on the SAME authoritative update every surface reads.
      repo.upsert(
        _snapshot(
          settlement: PosSettlement.paid,
          status: 'completed',
          revision: 3,
        ),
      );
      await container
          .read(posOrderSyncControllerProvider.notifier)
          .refreshOrders(const [_orderId]);
      await tester.pumpAndSettle();
      expect(_stripCard, findsNothing);
      expect(find.byKey(const Key('open-orders-strip')), findsNothing);
    });

    testWidgets('D3 an order that stays legitimately open after payment KEEPS '
        'its card; reopening it shows the paid state and offers NO pay '
        'action', (tester) async {
      await _pumpMenu(tester);
      await _openPreviewFromStrip(tester);
      await _payExact(tester);
      expect(_preview, findsNothing);

      // Still served (open) under the canonical predicate — the card stays;
      // nothing force-hid it just to look tidy.
      expect(_stripCard, findsOneWidget);

      // Reopening resolves FRESH eligibility: paid marker, no pay button.
      await tester.tap(_stripCard);
      await tester.pumpAndSettle();
      expect(_preview, findsOneWidget);
      expect(_previewPay, findsNothing);
      expect(
        find.byKey(const Key('order-detail-preview-paid')),
        findsOneWidget,
      );
    });
  });

  group('C. cancel / dismissal never auto-closes the preview', () {
    testWidgets('C1 drag-dismissing the payment sheet keeps the preview open '
        'with the pay action intact', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await _pumpMenu(tester);
      await _openPreviewFromStrip(tester);
      await tester.tap(_previewPay);
      await tester.pumpAndSettle();
      expect(find.text(l10n.posPaymentTitle), findsOneWidget);

      // Dragging the sheet down pops it with NO result (the sheet has no
      // cancel button by design — drag/barrier are its abandon paths).
      await tester.drag(find.text(l10n.posPaymentTitle), const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(find.text(l10n.posPaymentTitle), findsNothing);
      expect(_preview, findsOneWidget);
      expect(_previewPay, findsOneWidget);
    });

    testWidgets('C2 a barrier dismissal of the payment sheet also keeps the '
        'preview open', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await _pumpMenu(tester);
      await _openPreviewFromStrip(tester);
      await tester.tap(_previewPay);
      await tester.pumpAndSettle();
      expect(find.text(l10n.posPaymentTitle), findsOneWidget);

      // Tap the modal barrier above the sheet (top-left corner is barrier).
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text(l10n.posPaymentTitle), findsNothing);
      expect(_preview, findsOneWidget);
      expect(_previewPay, findsOneWidget);
    });
  });

  group('P. Orders-center parity — rows keep their current behavior', () {
    testWidgets('P1 paying from an Orders-sheet ROW leaves the sheet mounted '
        '(no surface is popped) and the row re-resolves to paid', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(const {});
      tester.view.physicalSize = const Size(1400, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final store = InMemoryRecentOrdersStore();
      await store.persist(kDemoSyncScope.key, [_unpaidServedOrder()]);
      final container = ProviderContainer(
        overrides: [
          posRecentOrdersStoreProvider.overrideWithValue(store),
          orderSnapshotRepositoryProvider.overrideWithValue(
            DemoOrderSnapshotRepository(),
          ),
          posSyncPollIntervalProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const Scaffold(body: RecentOrdersSheet()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recent-pay-$_code')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quick-cash-exact')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-payment-button')));
      await tester.pumpAndSettle();

      // The Orders surface itself was NOT dismissed (no onPaymentSuccess
      // there), and its row re-resolved: pay is gone for a paid order.
      expect(find.byType(RecentOrdersSheet), findsOneWidget);
      expect(find.byKey(const Key('recent-pay-$_code')), findsNothing);
    });
  });
}
