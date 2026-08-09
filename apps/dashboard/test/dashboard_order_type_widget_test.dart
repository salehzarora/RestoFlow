import 'package:restoflow_dashboard/src/analytics/dashboard_analytics_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_range.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_destination.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_drilldown.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/data/owner_sales_series.dart';
import 'package:restoflow_dashboard/src/data/owner_sales_series_repository.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart';
import 'package:restoflow_dashboard/src/widgets/section_card.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_window.dart';

/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-D) — the Overview order-type card.
///
/// Two contracts are defended here. The card must never invent a dine-in or
/// takeaway figure — not while loading, not on a server without SERVER-A, not
/// on a range that has no series. And it must not change the page's request
/// model: today and yesterday still issue ZERO `owner_sales_series` calls, and
/// a multi-day range still issues exactly ONE for the whole page.

class _FixedRepository implements OwnerReportsRepository {
  _FixedRepository(this.report);

  final DashboardReport report;

  @override
  Future<DashboardReport> loadReport({
    ReportRange range = ReportRange.today,
    DashboardAnalyticsScope? analyticsScope,
    CustomAnalyticsWindow? customWindow,
  }) async => report;
}

class _CountingSeriesRepository implements OwnerSalesSeriesRepository {
  _CountingSeriesRepository({this.series, this.unavailable = false});

  final OwnerSalesSeries? series;
  final bool unavailable;
  final List<AnalyticsRange> calls = <AnalyticsRange>[];

  @override
  Future<OwnerSalesSeries> loadSeries({
    required AnalyticsRange range,
    DashboardAnalyticsScope? analyticsScope,
    CustomAnalyticsWindow? customWindow,
  }) async {
    calls.add(range);
    if (unavailable) return OwnerSalesSeries.unavailable(range.wire);
    return series ?? _typedSeries;
  }
}

OwnerSalesSeriesBucket _bucket(
  String day, {
  required List<OwnerSalesSeriesOrderType> types,
}) => OwnerSalesSeriesBucket(
  day: BusinessDay.tryParse(day)!,
  orderCount: types.fold<int>(0, (s, t) => s + t.orderCount),
  grossMinor: 0,
  discountMinor: 0,
  netMinor: types.fold<int>(0, (s, t) => s + t.netMinor),
  voidCount: 0,
  voidTotalMinor: 0,
  collectedMinor: 0,
  cashMinor: 0,
  byMethod: const [
    OwnerSalesSeriesPaymentMethod(method: 'cash', count: 1, totalMinor: 1000),
  ],
  byOrderType: types,
);

/// dine_in 12 orders / ₪845.00 ; takeaway 4 orders / ₪155.00 => 75.0% / 25.0%.
final OwnerSalesSeries _typedSeries = OwnerSalesSeries(
  currencyCode: 'ILS',
  rangeWire: 'last7',
  buckets: [
    _bucket(
      '2026-08-06',
      types: const [
        OwnerSalesSeriesOrderType(
          orderType: 'dine_in',
          orderCount: 4,
          netMinor: 30000,
        ),
        OwnerSalesSeriesOrderType(
          orderType: 'takeaway',
          orderCount: 2,
          netMinor: 8000,
        ),
      ],
    ),
    _bucket(
      '2026-08-07',
      types: const [
        OwnerSalesSeriesOrderType(
          orderType: 'dine_in',
          orderCount: 5,
          netMinor: 41000,
        ),
        OwnerSalesSeriesOrderType(
          orderType: 'takeaway',
          orderCount: 1,
          netMinor: 3500,
        ),
      ],
    ),
    _bucket(
      '2026-08-08',
      types: const [
        OwnerSalesSeriesOrderType(
          orderType: 'dine_in',
          orderCount: 3,
          netMinor: 13500,
        ),
        OwnerSalesSeriesOrderType(
          orderType: 'takeaway',
          orderCount: 1,
          netMinor: 4000,
        ),
      ],
    ),
  ],
);

DashboardReport _report() => const DashboardReport(
  currencyCode: 'ILS',
  businessDateLabel: '2026-08-08',
  grossSalesMinor: 105000,
  netSalesMinor: 100000,
  discountTotalMinor: 5000,
  collectedMinor: 90000,
  cashSalesMinor: 60000,
  lastCashPaymentMinor: 3000,
  orderCount: 16,
  completedOrderCount: 14,
  openOrderCount: 2,
  unpaidOrderCount: 1,
  voidCount: 0,
  voidTotalMinor: 0,
  openingFloatMinor: 0,
  expectedCashMinor: 0,
  countedCashMinor: 0,
  shiftStatus: 'none',
  branches: [],
  topItems: [],
  recentOrders: [],
  paymentMethods: [
    PaymentMethodLine(
      method: 'cash',
      count: 10,
      totalMinor: 60000,
      currencyCode: 'ILS',
    ),
  ],
  comparison: ReportComparison(
    grossSalesMinor: 90000,
    netSalesMinor: 85000,
    orderCount: 14,
    cashSalesMinor: 50000,
    completedOrderCount: 12,
    discountTotalMinor: 4000,
  ),
);

Widget _wrap({
  Locale locale = const Locale('en'),
  OwnerSalesSeriesRepository? seriesRepo,
  void Function(DashboardDestination)? onNavigate,
  bool withNavigation = true,
}) => ProviderScope(
  overrides: [
    ownerReportsRepositoryProvider.overrideWithValue(
      _FixedRepository(_report()),
    ),
    if (seriesRepo != null)
      ownerSalesSeriesRepositoryProvider.overrideWithValue(seriesRepo),
  ],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    theme: restoflowBaseTheme(),
    home: withNavigation
        ? DashboardHomeScreen(onNavigate: onNavigate ?? (_) {})
        : const DashboardHomeScreen(),
  ),
);

void _size(WidgetTester tester, [Size size = const Size(1320, 4200)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _selectRange(WidgetTester tester, String wire) async {
  await tester.tap(find.byKey(Key('range-chip-$wire')));
  await tester.pumpAndSettle();
}

/// The pre-built secondary line of one order-type row.
String _secondary(WidgetTester tester, String type) => tester
    .widget<SectionRow>(
      find.descendant(
        of: find.byKey(Key('order-type-row-$type')),
        matching: find.byType(SectionRow),
      ),
    )
    .secondary!;

String _trailing(WidgetTester tester, String type) => tester
    .widget<SectionRow>(
      find.descendant(
        of: find.byKey(Key('order-type-row-$type')),
        matching: find.byType(SectionRow),
      ),
    )
    .trailingValue;

bool _isRowTappable(WidgetTester tester, String type) => tester
    .widgetList<InkWell>(
      find.descendant(
        of: find.byKey(Key('order-type-row-$type')),
        matching: find.byType(InkWell),
      ),
    )
    .any((w) => w.onTap != null);

void main() {
  group('presentation', () {
    testWidgets('last7 shows both types with exact counts, shares and net', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(_wrap(seriesRepo: _CountingSeriesRepository()));
      await tester.pumpAndSettle();
      await _selectRange(tester, 'last7');

      expect(find.byKey(const Key('order-type-card')), findsOneWidget);
      expect(find.text('Sales by order type'), findsOneWidget);

      // Localized labels — never the raw wire token.
      expect(find.text('Dine-in'), findsWidgets);
      expect(find.text('Takeaway'), findsWidgets);
      expect(find.text('dine_in'), findsNothing);
      expect(find.text('takeaway'), findsNothing);

      expect(_secondary(tester, 'dine_in'), '12 · Orders · 75.0% of orders');
      expect(_secondary(tester, 'takeaway'), '4 · Orders · 25.0% of orders');
      expect(_trailing(tester, 'dine_in'), '₪845.00');
      expect(_trailing(tester, 'takeaway'), '₪155.00');
    });

    testWidgets('the share is labelled as a share of ORDERS, never of sales', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(_wrap(seriesRepo: _CountingSeriesRepository()));
      await tester.pumpAndSettle();
      await _selectRange(tester, 'last7');

      expect(_secondary(tester, 'dine_in'), contains('of orders'));
      expect(_secondary(tester, 'dine_in'), isNot(contains('of sales')));
      expect(_secondary(tester, 'dine_in'), isNot(contains('of collected')));
    });

    testWidgets('an UNKNOWN future type stays visible and display-only', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(
        _wrap(
          seriesRepo: _CountingSeriesRepository(
            series: OwnerSalesSeries(
              currencyCode: 'ILS',
              rangeWire: 'last7',
              buckets: [
                _bucket(
                  '2026-08-08',
                  types: const [
                    OwnerSalesSeriesOrderType(
                      orderType: 'dine_in',
                      orderCount: 6,
                      netMinor: 60000,
                    ),
                    OwnerSalesSeriesOrderType(
                      orderType: 'delivery',
                      orderCount: 2,
                      netMinor: 20000,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _selectRange(tester, 'last7');

      // Present, with truthful figures and the honest raw-token fallback label.
      expect(find.byKey(const Key('order-type-row-delivery')), findsOneWidget);
      expect(_secondary(tester, 'delivery'), '2 · Orders · 25.0% of orders');
      expect(_trailing(tester, 'delivery'), '₪200.00');
      // ...and never clickable: the history filter has no value for it.
      expect(_isRowTappable(tester, 'delivery'), isFalse);
      expect(_isRowTappable(tester, 'dine_in'), isTrue);
    });

    testWidgets('a window with no typed rows shows NO card — not two zero '
        'rows', (tester) async {
      _size(tester);
      await tester.pumpWidget(
        _wrap(
          seriesRepo: _CountingSeriesRepository(
            series: OwnerSalesSeries(
              currencyCode: 'ILS',
              rangeWire: 'last7',
              buckets: [_bucket('2026-08-08', types: const [])],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _selectRange(tester, 'last7');

      expect(find.byKey(const Key('order-type-card')), findsNothing);
    });
  });

  group('range behaviour and request counts', () {
    testWidgets('today shows NO order-type card and issues ZERO series calls', (
      tester,
    ) async {
      _size(tester);
      final repo = _CountingSeriesRepository();
      await tester.pumpWidget(_wrap(seriesRepo: repo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('order-type-card')), findsNothing);
      expect(repo.calls, isEmpty);
      // The rest of the Overview is unaffected.
      expect(find.byKey(const Key('kpi-net-sales')), findsOneWidget);
      expect(find.byKey(const Key('payment-mix-card')), findsOneWidget);
    });

    testWidgets('yesterday shows NO order-type card and issues ZERO series '
        'calls', (tester) async {
      _size(tester);
      final repo = _CountingSeriesRepository();
      await tester.pumpWidget(_wrap(seriesRepo: repo));
      await tester.pumpAndSettle();
      await _selectRange(tester, 'yesterday');

      expect(find.byKey(const Key('order-type-card')), findsNothing);
      expect(repo.calls, isEmpty);
      expect(find.byKey(const Key('payment-mix-card')), findsOneWidget);
    });

    testWidgets('last7 costs exactly ONE series call for the whole page — the '
        'daily trend, the tender strip and the order-type card share it', (
      tester,
    ) async {
      _size(tester);
      final repo = _CountingSeriesRepository();
      await tester.pumpWidget(_wrap(seriesRepo: repo));
      await tester.pumpAndSettle();
      await _selectRange(tester, 'last7');

      // All three series consumers are on screen...
      expect(find.byKey(const Key('sales-by-day-chart')), findsOneWidget);
      expect(
        find.byKey(const Key('payment-method-trend-chart')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('order-type-card')), findsOneWidget);
      // ...and together they cost one request.
      expect(repo.calls, [AnalyticsRange.last7]);
    });

    testWidgets('last30 likewise costs exactly one', (tester) async {
      _size(tester);
      final repo = _CountingSeriesRepository();
      await tester.pumpWidget(_wrap(seriesRepo: repo));
      await tester.pumpAndSettle();
      await _selectRange(tester, 'last30');

      expect(find.byKey(const Key('order-type-card')), findsOneWidget);
      expect(repo.calls, [AnalyticsRange.last30]);
    });

    testWidgets('last7 -> today adds no call, and returning reuses the '
        'retained entry', (tester) async {
      _size(tester);
      final repo = _CountingSeriesRepository();
      await tester.pumpWidget(_wrap(seriesRepo: repo));
      await tester.pumpAndSettle();

      await _selectRange(tester, 'last7');
      expect(repo.calls, [AnalyticsRange.last7]);

      await _selectRange(tester, 'today');
      expect(find.byKey(const Key('order-type-card')), findsNothing);
      expect(repo.calls, [AnalyticsRange.last7], reason: 'today asks nothing');

      await _selectRange(tester, 'last7');
      expect(find.byKey(const Key('order-type-card')), findsOneWidget);
      expect(repo.calls, [
        AnalyticsRange.last7,
      ], reason: 'the retained entry is reused, not refetched');
    });
  });

  group('old hosted / unavailable series', () {
    testWidgets('an UNAVAILABLE series renders no order-type card and no fake '
        'zeros, leaving the rest of the Overview intact', (tester) async {
      _size(tester);
      await tester.pumpWidget(
        _wrap(seriesRepo: _CountingSeriesRepository(unavailable: true)),
      );
      await tester.pumpAndSettle();
      await _selectRange(tester, 'last7');

      expect(find.byKey(const Key('order-type-card')), findsNothing);
      // No typed row exists at all — not a zeroed one. (A global ₪0.00 search
      // would be the wrong assertion here: the report's own void and float
      // fields legitimately render zeros elsewhere on the page.)
      expect(find.byKey(const Key('order-type-row-dine_in')), findsNothing);
      expect(find.byKey(const Key('order-type-row-takeaway')), findsNothing);
      expect(find.text('Dine-in'), findsNothing);
      expect(find.text('Takeaway'), findsNothing);

      // The payment analytics and the KPIs come from a different call and stay.
      expect(find.byKey(const Key('payment-mix-card')), findsOneWidget);
      expect(find.byKey(const Key('kpi-net-sales')), findsOneWidget);
      expect(find.byKey(const Key('reports-error')), findsNothing);
    });

    testWidgets('a FAILED series stays section-local — no order-type card, the '
        'report itself unharmed', (tester) async {
      _size(tester);
      await tester.pumpWidget(_wrap(seriesRepo: _FailingSeriesRepository()));
      await tester.pumpAndSettle();
      await _selectRange(tester, 'last7');

      expect(find.byKey(const Key('order-type-card')), findsNothing);
      expect(find.byKey(const Key('sales-by-day-error')), findsOneWidget);
      expect(find.byKey(const Key('payment-mix-card')), findsOneWidget);
      expect(find.byKey(const Key('kpi-net-sales')), findsOneWidget);
    });
  });

  group('drill-down', () {
    for (final (type, filter) in const [
      ('dine_in', OrderTypeFilter.dineIn),
      ('takeaway', OrderTypeFilter.takeaway),
    ]) {
      testWidgets('tapping $type opens Orders history filtered to $type', (
        tester,
      ) async {
        _size(tester);
        DashboardDestination? landed;
        late ProviderContainer container;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ownerReportsRepositoryProvider.overrideWithValue(
                _FixedRepository(_report()),
              ),
              ownerSalesSeriesRepositoryProvider.overrideWithValue(
                _CountingSeriesRepository(),
              ),
            ],
            child: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return MaterialApp(
                  locale: const Locale('en'),
                  localizationsDelegates: restoflowLocalizationsDelegates,
                  supportedLocales: kSupportedLocales,
                  theme: restoflowBaseTheme(),
                  home: DashboardHomeScreen(onNavigate: (d) => landed = d),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _selectRange(tester, 'last7');

        // A stale, conflicting filter set the drill-down must clear.
        container
            .read(orderHistoryQueryProvider.notifier)
            .state = const OrderHistoryQuery(
          status: OrderStatusFilter.voided,
          search: 'leftover',
          payment: PaymentFilter.cash,
          orderType: OrderTypeFilter.dineIn,
        );

        await tester.tap(find.byKey(Key('order-type-row-$type')));
        await tester.pumpAndSettle();

        expect(landed, DashboardDestination.orders);
        expect(container.read(ordersInitialTabProvider), OrdersTab.history);

        final query = container.read(orderHistoryQueryProvider);
        expect(query.orderType, filter);
        expect(query.orderType.wire, type);
        // A FRESH query per the F0 contract: the leftovers are gone.
        expect(query.status, OrderStatusFilter.all);
        expect(query.payment, PaymentFilter.all);
        expect(query.searchOrNull, isNull);
      });
    }

    testWidgets('with no navigation destination every row is display-only', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(
        _wrap(seriesRepo: _CountingSeriesRepository(), withNavigation: false),
      );
      await tester.pumpAndSettle();
      await _selectRange(tester, 'last7');

      expect(_isRowTappable(tester, 'dine_in'), isFalse);
      expect(_isRowTappable(tester, 'takeaway'), isFalse);
    });

    test('the typed drill-downs carry business filters only — no scope', () {
      const dineIn = OrdersHistoryDrillDown.dineIn();
      const takeaway = OrdersHistoryDrillDown.takeaway();
      expect(dineIn.orderType, OrderTypeFilter.dineIn);
      expect(takeaway.orderType, OrderTypeFilter.takeaway);
      for (final d in const [dineIn, takeaway]) {
        expect(d.destination, DashboardDestination.orders);
        expect(d.payment, PaymentFilter.all);
        expect(d.status, OrderStatusFilter.all);
      }
    });

    test('the existing drill-downs still reset order type to all', () {
      for (final d in const [
        OrdersHistoryDrillDown.unpaid(),
        OrdersHistoryDrillDown.cash(),
        OrdersHistoryDrillDown.card(),
        OrdersHistoryDrillDown.voided(),
      ]) {
        expect(d.orderType, OrderTypeFilter.all);
      }
    });
  });

  group('layout safety', () {
    testWidgets('renders at phone width without overflow', (tester) async {
      _size(tester, const Size(390, 5200));
      await tester.pumpWidget(_wrap(seriesRepo: _CountingSeriesRepository()));
      await tester.pumpAndSettle();
      await _selectRange(tester, 'last7');

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('order-type-card')), findsOneWidget);
    });

    testWidgets('survives a 2x text scale at phone width', (tester) async {
      _size(tester, const Size(390, 6600));
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(_wrap(seriesRepo: _CountingSeriesRepository()));
      await tester.pumpAndSettle();
      await _selectRange(tester, 'last7');

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('order-type-card')), findsOneWidget);
    });

    for (final locale in const [Locale('ar'), Locale('he')]) {
      testWidgets('renders RTL (${locale.languageCode}) without overflow', (
        tester,
      ) async {
        _size(tester, const Size(390, 5200));
        await tester.pumpWidget(
          _wrap(locale: locale, seriesRepo: _CountingSeriesRepository()),
        );
        await tester.pumpAndSettle();
        await _selectRange(tester, 'last7');

        expect(tester.takeException(), isNull);
        expect(
          Directionality.of(
            tester.element(find.byKey(const Key('order-type-card'))),
          ),
          TextDirection.rtl,
        );
        // Money is the same integer-minor figure in every locale.
        expect(_trailing(tester, 'dine_in'), '₪845.00');
      });
    }
  });
}

/// A series repository that always fails, to prove the error stays local.
class _FailingSeriesRepository implements OwnerSalesSeriesRepository {
  @override
  Future<OwnerSalesSeries> loadSeries({
    required AnalyticsRange range,
    DashboardAnalyticsScope? analyticsScope,
    CustomAnalyticsWindow? customWindow,
  }) async {
    throw const OwnerSalesSeriesException('boom');
  }
}
