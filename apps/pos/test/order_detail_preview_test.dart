@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ORDER-DETAIL-PREVIEW-001 — B/M. opening the preview from a real Orders row,
/// and the READ-ONLY guarantee.
///
/// The preview is a window, not a lever. Opening it, scrolling it and closing it
/// must leave the order, the outbox, the printer and the payment state exactly
/// as they were. The only thing that may ever mutate anything is an explicit
/// press on one of the EXISTING action buttons.

const _code = '#PV0001';
const _orderId = 'oid-PV0001';

SubmittedOrderView _view() => const SubmittedOrderView(
  orderNumber: _code,
  orderType: OrderType.dineIn,
  tableLabel: 'T5',
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
      modifiers: ['Extra meat ×2'],
      note: 'no onion',
    ),
  ],
);

PosOrderSnapshot _snapshot({
  required PosSettlement settlement,
  String status = 'served',
  int grand = 5400,
  int revision = 2,
}) {
  final at = DateTime.utc(2026, 7, 30, 10);
  return PosOrderSnapshot(
    orderId: _orderId,
    orderCode: _code,
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
    orderType: 'dine_in',
    tableLabel: 'T5',
    currencyCode: 'ILS',
  );
}

PosRecentOrder _unpaidOrder() => PosRecentOrder(
  order: _view(),
  snapshot: _snapshot(settlement: PosSettlement.unpaid),
  submittedAt: DateTime.utc(2026, 7, 30, 10),
);

Future<InMemoryRecentOrdersStore> _store(PosRecentOrder order) async {
  final store = InMemoryRecentOrdersStore();
  await store.persist(kDemoSyncScope.key, [order]);
  return store;
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  InMemoryRecentOrdersStore store, {
  Locale locale = const Locale('en'),
}) async {
  SharedPreferences.setMockInitialValues(const {});
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [posRecentOrdersStoreProvider.overrideWithValue(store)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const Scaffold(body: RecentOrdersSheet()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder get _rowTap => find.byKey(const Key('recent-order-preview-$_code'));
Finder get _preview => find.byKey(const Key('order-detail-preview'));
Finder get _pay => find.byKey(const Key('recent-pay-$_code'));

void main() {
  test('FIXTURE CONTRACT: the fixture is a payable, non-terminal order so the '
      'Orders row really renders its action buttons', () {
    final actions = resolveOrderActions(_unpaidOrder());
    expect(actions.canPay, isTrue);
    expect(actions.isEmpty, isFalse);
  });

  group('B. opening the preview from the row', () {
    testWidgets('B1 the row body is a tappable preview target', (tester) async {
      await _pump(tester, await _store(_unpaidOrder()));
      expect(
        _rowTap,
        findsOneWidget,
        reason: 'the order card body must expose a stable preview target',
      );
    });

    testWidgets('B2 tapping the row body opens EXACTLY ONE preview', (
      tester,
    ) async {
      await _pump(tester, await _store(_unpaidOrder()));
      expect(_preview, findsNothing);

      await tester.tap(_rowTap);
      await tester.pumpAndSettle();

      expect(_preview, findsOneWidget);
      expect(find.text(_code), findsWidgets);
    });

    testWidgets('B3 a second tap does not stack a second preview', (
      tester,
    ) async {
      await _pump(tester, await _store(_unpaidOrder()));
      await tester.tap(_rowTap);
      await tester.pumpAndSettle();
      expect(_preview, findsOneWidget);

      // The Orders sheet stays mounted BENEATH the preview, so its row is still
      // in the tree; tapping it again must not open a second sheet.
      await tester.tap(_rowTap, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_preview, findsOneWidget);
    });

    testWidgets(
      'B4 SEMANTIC activation opens it too (keyboard/accessibility)',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, await _store(_unpaidOrder()));

        expect(
          tester.getSemantics(_rowTap),
          matchesSemantics(
            isButton: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );
        await tester.tap(_rowTap);
        await tester.pumpAndSettle();
        expect(_preview, findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets('B5 tapping an ACTION button does not also open the preview', (
      tester,
    ) async {
      await _pump(tester, await _store(_unpaidOrder()));
      expect(_pay, findsOneWidget);

      await tester.tap(_pay);
      await tester.pumpAndSettle();

      expect(
        _preview,
        findsNothing,
        reason: 'an action press must never double-trigger the row preview',
      );
      // The payment sheet is what a Collect-payment press opens.
      await tester.pumpAndSettle();
    });

    testWidgets('B6 the Orders sheet remains mounted beneath the preview', (
      tester,
    ) async {
      await _pump(tester, await _store(_unpaidOrder()));
      await tester.tap(_rowTap);
      await tester.pumpAndSettle();

      expect(_preview, findsOneWidget);
      expect(find.byType(RecentOrdersSheet), findsOneWidget);
      expect(
        find.byKey(const Key('recent-order-$_code')),
        findsOneWidget,
        reason: 'the existing row key is untouched',
      );
    });

    testWidgets('B7 closing the preview returns to the Orders sheet', (
      tester,
    ) async {
      await _pump(tester, await _store(_unpaidOrder()));
      await tester.tap(_rowTap);
      await tester.pumpAndSettle();
      expect(_preview, findsOneWidget);

      await tester.tap(find.byKey(const Key('order-detail-preview-close')));
      await tester.pumpAndSettle();

      expect(_preview, findsNothing);
      expect(find.byKey(const Key('recent-order-$_code')), findsOneWidget);
    });
  });

  group('M. the READ-ONLY guarantee', () {
    testWidgets('M1 opening, scrolling and closing mutates NOTHING', (
      tester,
    ) async {
      final container = await _pump(tester, await _store(_unpaidOrder()));

      await tester.tap(_rowTap);
      await tester.pumpAndSettle();
      // Scroll the preview body.
      await tester.drag(_preview, const Offset(0, -120));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('order-detail-preview-close')));
      await tester.pumpAndSettle();

      expect(
        container.read(outboxControllerProvider),
        isEmpty,
        reason: 'a preview never enqueues a sync operation',
      );
      expect(
        container.read(receiptPrintControllerProvider),
        isEmpty,
        reason: 'opening a preview is not a print trigger',
      );
    });

    testWidgets('M2 the order itself is unchanged after a preview visit', (
      tester,
    ) async {
      final store = await _store(_unpaidOrder());
      final container = await _pump(tester, store);

      await tester.tap(_rowTap);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('order-detail-preview-close')));
      await tester.pumpAndSettle();

      final after = (await store.load(kDemoSyncScope.key)).single;
      expect(after.snapshot?.status, 'served');
      expect(after.snapshot?.settlement, PosSettlement.unpaid);
      expect(after.snapshot?.revision, 2);
      expect(after.payment, isNull);
      expect(after.voidedAt, isNull);
      expect(container.read(outboxControllerProvider), isEmpty);
    });

    testWidgets('M3 the preview surfaces NO action the policy refuses', (
      tester,
    ) async {
      await _pump(tester, await _store(_unpaidOrder()));
      await tester.tap(_rowTap);
      await tester.pumpAndSettle();

      final actions = resolveOrderActions(_unpaidOrder());
      // Eligible here -> present, keyed under the preview prefix.
      expect(actions.canPay, isTrue);
      expect(find.byKey(const Key('preview-pay-$_code')), findsOneWidget);
      // NOT eligible here -> absent, exactly as in the Orders row.
      expect(actions.canOpenReceipt, isFalse);
      expect(find.byKey(const Key('preview-reprint-$_code')), findsNothing);
      expect(find.byKey(const Key('preview-view-$_code')), findsNothing);
    });
  });
}
