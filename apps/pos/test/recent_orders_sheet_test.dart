import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/recent_orders_sheet.dart';

/// POS-ORDERS-AND-PAYMENT-001 (C/D): the recent/unpaid orders surface — an
/// unpaid order offers "Take payment"; a paid order offers "Reprint receipt" +
/// "View receipt"; filters narrow the list; and reprint with no printer is an
/// honest fallback (no new order/payment).
Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

SubmittedOrderView _view(String number) => SubmittedOrderView(
  orderNumber: number,
  orderType: OrderType.takeaway,
  currencyCode: 'ILS',
  subtotalMinor: 4200,
  orderId: 'oid-$number',
  lines: [
    SubmittedLineView(
      name: 'Burger',
      quantity: 1,
      lineTotalMinor: 4200,
      currencyCode: 'ILS',
    ),
  ],
);

CashPayment _payment(String number) => CashPayment(
  paymentId: 'pay-$number',
  orderNumber: number,
  deviceId: 'd1',
  localOperationId: 'op-$number',
  method: PaymentMethod.cash,
  status: PaymentStatus.completed,
  amountMinor: 4200,
  tenderedMinor: 4200,
  changeMinor: 0,
  currencyCode: 'ILS',
  receiptNumber: 'R-1',
  paidAt: DateTime.now(),
);

Future<InMemoryRecentOrdersStore> _seededStore() async {
  final store = InMemoryRecentOrdersStore();
  final now = DateTime.now();
  await store.persist('demo-device', [
    PosRecentOrder(order: _view('#U1'), submittedAt: now),
    PosRecentOrder(
      order: _view('#P1'),
      submittedAt: now.subtract(const Duration(minutes: 5)),
      payment: _payment('#P1'),
    ),
  ]);
  return store;
}

Widget _wrap(
  InMemoryRecentOrdersStore store, {
  Locale locale = const Locale('en'),
}) => ProviderScope(
  overrides: [posRecentOrdersStoreProvider.overrideWithValue(store)],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: const Scaffold(body: RecentOrdersSheet()),
  ),
);

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('unpaid offers Take payment; paid offers Reprint + View', (
    tester,
  ) async {
    _wide(tester);
    await tester.pumpWidget(_wrap(await _seededStore()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recent-order-#U1')), findsOneWidget);
    expect(find.byKey(const Key('recent-order-#P1')), findsOneWidget);
    // Unpaid -> Take payment.
    expect(find.byKey(const Key('recent-pay-#U1')), findsOneWidget);
    expect(find.byKey(const Key('recent-reprint-#U1')), findsNothing);
    // Paid -> Reprint + View, no pay action.
    expect(find.byKey(const Key('recent-reprint-#P1')), findsOneWidget);
    expect(find.byKey(const Key('recent-view-#P1')), findsOneWidget);
    expect(find.byKey(const Key('recent-pay-#P1')), findsNothing);
  });

  // POS-OPERATIONS-SYNC-001 (Commit 3): the settlement filter is now EXACT --
  // "Paid" means paid, and it does NOT quietly include a comped order.
  testWidgets('the settlement filter narrows to unpaid / paid EXACTLY', (
    tester,
  ) async {
    _wide(tester);
    await tester.pumpWidget(_wrap(await _seededStore()));
    await tester.pumpAndSettle();

    // Look across every section, so the filter is what is being tested.
    await tester.tap(find.byKey(const Key('orders-section-all')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('orders-settlement-needsPayment')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recent-order-#U1')), findsOneWidget);
    expect(find.byKey(const Key('recent-order-#P1')), findsNothing);

    await tester.tap(find.byKey(const Key('orders-settlement-paid')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recent-order-#U1')), findsNothing);
    expect(find.byKey(const Key('recent-order-#P1')), findsOneWidget);
  });

  testWidgets('empty state when no orders', (tester) async {
    _wide(tester);
    final l10n = await _en();
    await tester.pumpWidget(_wrap(InMemoryRecentOrdersStore()));
    await tester.pumpAndSettle();
    // The centre now LANDS on Open, so the empty state is section-specific rather
    // than a single generic "no recent orders".
    expect(find.byKey(const Key('recent-orders-empty')), findsOneWidget);
    expect(find.text(l10n.posOrdersEmptyOpen), findsOneWidget);
  });

  testWidgets(
    'reprint with no printer configured shows an honest fallback message',
    (tester) async {
      _wide(tester);
      final l10n = await _en();
      await tester.pumpWidget(_wrap(await _seededStore()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recent-reprint-#P1')));
      await tester.pumpAndSettle();
      // No native/loopback bridge in a test -> honest "no printer" snackbar,
      // and NOTHING mutates the order/payment.
      expect(find.text(l10n.printStatusNotConfigured), findsOneWidget);
    },
  );

  testWidgets('renders in Arabic (RTL) without crashing', (tester) async {
    _wide(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
    await tester.pumpWidget(
      _wrap(await _seededStore(), locale: const Locale('ar')),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.posOrdersCenterTitle), findsOneWidget);
    expect(find.byKey(const Key('recent-order-#U1')), findsOneWidget);
  });
}
