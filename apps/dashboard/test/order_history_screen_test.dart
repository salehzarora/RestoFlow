import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/order_history_repository.dart';
import 'package:restoflow_dashboard/src/orders/order_history_screen.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// ORDERS-HISTORY-001 — the Orders history surface: rows / empty / error /
/// loading states, range + search filtering, "load more" pagination, and the
/// detail sheet with the receipt (money) + money-free kitchen previews.
Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

DemoOrder _order(
  String id, {
  String? customer,
  int total = 1000,
  bool paid = true,
  bool withMeat = false,
  int daysAgo = 0,
  String status = 'completed',
  String type = 'dine_in',
}) => DemoOrder(
  daysAgo: daysAgo,
  detail: OrderDetail(
    orderId: id,
    orderCode: '#$id',
    status: status,
    orderType: type,
    currencyCode: 'ILS',
    subtotalMinor: total,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: total,
    createdAtLabel: '10:00',
    customerName: customer,
    items: [
      OrderDetailItem(
        name: 'Burger',
        quantity: 1,
        lineTotalMinor: total,
        modifiers: withMeat
            ? const [
                OrderDetailModifier(
                  optionName: 'Double',
                  meatQuantity: 2,
                  meatUnit: 'patties',
                ),
              ]
            : const [],
      ),
    ],
    payments: paid
        ? [
            OrderPayment(
              method: 'cash',
              status: 'completed',
              amountMinor: total,
            ),
          ]
        : const [],
  ),
);

Widget _wrap(OrderHistoryRepository repo, {bool demo = true}) => ProviderScope(
  overrides: [
    runtimeConfigProvider.overrideWithValue(
      RuntimeConfig.test(isDemoMode: demo),
    ),
    orderHistoryRepositoryProvider.overrideWithValue(repo),
  ],
  child: const MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: Scaffold(body: OrderHistoryScreen()),
  ),
);

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('renders the demo rows and the demo banner', (tester) async {
    _wide(tester);
    final l10n = await _en();
    await tester.pumpWidget(_wrap(DemoOrderHistoryRepository()));
    await tester.pumpAndSettle();

    expect(find.text(l10n.ordersDemoNotice), findsOneWidget);
    expect(find.byKey(const Key('order-card-demo-ord-1001')), findsOneWidget);
    expect(find.byKey(const Key('order-card-demo-ord-1002')), findsOneWidget);
    expect(find.byKey(const Key('orders-empty')), findsNothing);
  });

  testWidgets('empty state when no orders match', (tester) async {
    _wide(tester);
    final l10n = await _en();
    await tester.pumpWidget(
      _wrap(DemoOrderHistoryRepository(orders: const [])),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('orders-empty')), findsOneWidget);
    expect(find.text(l10n.ordersEmpty), findsOneWidget);
  });

  testWidgets('error state on a failing repository', (tester) async {
    _wide(tester);
    await tester.pumpWidget(
      _wrap(DemoOrderHistoryRepository(failureMessage: 'boom')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('orders-error')), findsOneWidget);
  });

  testWidgets('range chip switches the window (yesterday hides today)', (
    tester,
  ) async {
    _wide(tester);
    await tester.pumpWidget(_wrap(DemoOrderHistoryRepository()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('order-card-demo-ord-1001')), findsOneWidget);

    await tester.tap(find.byKey(const Key('orders-range-yesterday')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('order-card-demo-ord-0991')), findsOneWidget);
    expect(find.byKey(const Key('order-card-demo-ord-1001')), findsNothing);
  });

  testWidgets('search filters the list', (tester) async {
    _wide(tester);
    await tester.pumpWidget(_wrap(DemoOrderHistoryRepository()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('orders-search-field')),
      'Layla',
    );
    await tester.tap(find.byKey(const Key('orders-search-apply')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('order-card-demo-ord-1001')), findsOneWidget);
    expect(find.byKey(const Key('order-card-demo-ord-1002')), findsNothing);
  });

  testWidgets('load more appends the next keyset page', (tester) async {
    _wide(tester);
    final repo = DemoOrderHistoryRepository(
      orders: [for (var i = 0; i < 5; i++) _order('t$i')],
      pageSize: 2,
    );
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('order-card-t0')), findsOneWidget);
    expect(find.byKey(const Key('order-card-t2')), findsNothing);
    expect(find.byKey(const Key('orders-load-more')), findsOneWidget);

    await tester.tap(find.byKey(const Key('orders-load-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('order-card-t2')), findsOneWidget);
  });

  testWidgets('opening an order shows the detail sheet; the kitchen preview is '
      'money-free', (tester) async {
    _wide(tester);
    final repo = DemoOrderHistoryRepository(
      orders: [_order('k1', customer: 'Layla', total: 8400, withMeat: true)],
    );
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('order-card-k1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('order-detail-content')), findsOneWidget);

    await tester.tap(find.byKey(const Key('order-kitchen-preview-button')));
    await tester.pumpAndSettle();

    // The kitchen preview subtree carries NO money.
    final preview = find.byKey(const Key('order-kitchen-preview'));
    expect(preview, findsOneWidget);
    expect(
      find.descendant(of: preview, matching: find.textContaining('₪')),
      findsNothing,
    );
    expect(
      find.descendant(of: preview, matching: find.textContaining('84.00')),
      findsNothing,
    );
  });

  testWidgets('the receipt preview shows the stored total (money)', (
    tester,
  ) async {
    _wide(tester);
    final repo = DemoOrderHistoryRepository(
      orders: [_order('r1', customer: 'Layla', total: 8400)],
    );
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('order-card-r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('order-receipt-preview-button')));
    await tester.pumpAndSettle();

    final preview = find.byKey(const Key('order-receipt-preview'));
    expect(preview, findsOneWidget);
    expect(
      find.descendant(of: preview, matching: find.textContaining('₪84.00')),
      findsWidgets,
    );
  });
}
