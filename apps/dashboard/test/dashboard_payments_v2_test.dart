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
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-C) — payments analysis v2.
///
/// The load-bearing assertion is the CAPABILITY GATE. Before SERVER-B an
/// unknown `p_payment` returned an empty list rather than an error, so a card
/// row that navigated on an older database would answer "no orders" for money
/// the owner can see on the same screen. These tests pin that such a row is
/// inert until the payload proves the migration ran — and that cash, which was
/// always expressible, is never held back by that gate.

class _FixedRepository implements OwnerReportsRepository {
  _FixedRepository(this.report);

  final DashboardReport report;

  @override
  Future<DashboardReport> loadReport({
    ReportRange range = ReportRange.today,
  }) async => report;
}

/// Counts series loads so a test can prove the payment trend rides the daily
/// trend's request rather than adding one.
class _CountingSeriesRepository implements OwnerSalesSeriesRepository {
  _CountingSeriesRepository({this.unavailable = false});

  final bool unavailable;
  final List<AnalyticsRange> calls = <AnalyticsRange>[];

  @override
  Future<OwnerSalesSeries> loadSeries({required AnalyticsRange range}) async {
    calls.add(range);
    if (unavailable) return OwnerSalesSeries.unavailable(range.wire);
    return _threeDaySeries;
  }
}

OwnerSalesSeriesBucket _bucket(
  String day, {
  required int cash,
  required int card,
}) => OwnerSalesSeriesBucket(
  day: BusinessDay.tryParse(day)!,
  orderCount: 3,
  grossMinor: cash + card,
  discountMinor: 0,
  netMinor: cash + card,
  voidCount: 0,
  voidTotalMinor: 0,
  collectedMinor: cash + card,
  cashMinor: cash,
  byMethod: [
    if (cash > 0)
      OwnerSalesSeriesPaymentMethod(method: 'cash', count: 2, totalMinor: cash),
    if (card > 0)
      OwnerSalesSeriesPaymentMethod(method: 'card', count: 1, totalMinor: card),
  ],
);

final OwnerSalesSeries _threeDaySeries = OwnerSalesSeries(
  currencyCode: 'ILS',
  rangeWire: 'last7',
  buckets: [
    _bucket('2026-08-06', cash: 4000, card: 1000),
    // A day with NO cash tender at all — the strip must plot a truthful 0,
    // never interpolate across the gap.
    _bucket('2026-08-07', cash: 0, card: 3000),
    _bucket('2026-08-08', cash: 9000, card: 2000),
  ],
);

/// Four known tenders plus an unrecognised future one; collected 20000 exactly.
const _fourMethods = <PaymentMethodLine>[
  PaymentMethodLine(
    method: 'cash',
    count: 4,
    totalMinor: 12000,
    currencyCode: 'ILS',
  ),
  PaymentMethodLine(
    method: 'card',
    count: 2,
    totalMinor: 5000,
    currencyCode: 'ILS',
  ),
  PaymentMethodLine(
    method: 'bit',
    count: 1,
    totalMinor: 2000,
    currencyCode: 'ILS',
  ),
  PaymentMethodLine(
    method: 'external',
    count: 1,
    totalMinor: 1000,
    currencyCode: 'ILS',
  ),
];

const _serverBComparison = ReportComparison(
  grossSalesMinor: 18000,
  netSalesMinor: 17000,
  orderCount: 5,
  cashSalesMinor: 9000,
  completedOrderCount: 4,
  discountTotalMinor: 1200,
);

const _legacyComparison = ReportComparison(
  grossSalesMinor: 18000,
  netSalesMinor: 17000,
  orderCount: 5,
  cashSalesMinor: 9000,
);

DashboardReport _report({
  ReportComparison? comparison = _serverBComparison,
  List<PaymentMethodLine> methods = _fourMethods,
  int collectedMinor = 20000,
  ReportRange range = ReportRange.today,
}) => DashboardReport(
  currencyCode: 'ILS',
  businessDateLabel: '2026-08-08',
  grossSalesMinor: 24000,
  // Billed net deliberately differs from collected: the share denominator must
  // not follow it.
  netSalesMinor: 22500,
  discountTotalMinor: 1500,
  collectedMinor: collectedMinor,
  cashSalesMinor: 12000,
  lastCashPaymentMinor: 3000,
  orderCount: 8,
  completedOrderCount: 6,
  openOrderCount: 2,
  unpaidOrderCount: 1,
  voidCount: 0,
  voidTotalMinor: 0,
  openingFloatMinor: 0,
  expectedCashMinor: 0,
  countedCashMinor: 0,
  shiftStatus: 'none',
  branches: const [],
  topItems: const [],
  recentOrders: const [],
  paymentMethods: methods,
  comparison: comparison,
  range: range,
);

Widget _wrap(
  DashboardReport report, {
  Locale locale = const Locale('en'),
  OwnerSalesSeriesRepository? seriesRepo,
  void Function(DashboardDestination)? onNavigate,
}) => ProviderScope(
  overrides: [
    ownerReportsRepositoryProvider.overrideWithValue(_FixedRepository(report)),
    if (seriesRepo != null)
      ownerSalesSeriesRepositoryProvider.overrideWithValue(seriesRepo),
  ],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    theme: restoflowBaseTheme(),
    home: DashboardHomeScreen(onNavigate: onNavigate ?? (_) {}),
  ),
);

void _size(WidgetTester tester, [Size size = const Size(1320, 3400)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

String _meta(WidgetTester tester, String method) =>
    tester.widget<Text>(find.byKey(Key('payment-meta-$method'))).data!;

String _amount(WidgetTester tester, String method) =>
    tester.widget<Text>(find.byKey(Key('payment-amount-$method'))).data!;

/// Whether a legend row exposes button semantics (i.e. really is tappable).
bool _isRowTappable(WidgetTester tester, String method) => tester
    .widgetList<InkWell>(
      find.descendant(
        of: find.byKey(Key('payment-mix-row-$method')),
        matching: find.byType(InkWell),
      ),
    )
    .any((w) => w.onTap != null);

Future<void> _selectRange(WidgetTester tester, String wire) async {
  await tester.tap(find.byKey(Key('range-chip-$wire')));
  await tester.pumpAndSettle();
}

void main() {
  group('per-method metrics', () {
    testWidgets('every method shows amount, count, share and average', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(_wrap(_report()));
      await tester.pumpAndSettle();

      expect(_amount(tester, 'cash'), '₪120.00');
      expect(_amount(tester, 'card'), '₪50.00');
      expect(_amount(tester, 'bit'), '₪20.00');
      expect(_amount(tester, 'external'), '₪10.00');

      // 12000 of 20000 collected = 60.0%; average 12000/4 = ₪30.00.
      expect(
        _meta(tester, 'cash'),
        '4 recorded payments · 60.0% of collected · Avg. payment ₪30.00',
      );
      expect(
        _meta(tester, 'card'),
        '2 recorded payments · 25.0% of collected · Avg. payment ₪25.00',
      );
      expect(
        _meta(tester, 'bit'),
        '1 recorded payment · 10.0% of collected · Avg. payment ₪20.00',
      );
      expect(
        _meta(tester, 'external'),
        '1 recorded payment · 5.0% of collected · Avg. payment ₪10.00',
      );
    });

    testWidgets('the share denominator is COLLECTED, not billed net', (
      tester,
    ) async {
      _size(tester);
      // Billed net is 22500 while collected is 20000. Against billed, cash
      // would read 53.3%.
      await tester.pumpWidget(_wrap(_report()));
      await tester.pumpAndSettle();

      expect(_meta(tester, 'cash'), contains('60.0% of collected'));
      expect(_meta(tester, 'cash'), isNot(contains('53.3')));
    });

    testWidgets('a window that collected NOTHING shows amounts but no share '
        'and no average', (tester) async {
      _size(tester);
      await tester.pumpWidget(
        _wrap(
          _report(
            collectedMinor: 0,
            methods: const [
              PaymentMethodLine(
                method: 'cash',
                count: 0,
                totalMinor: 0,
                currencyCode: 'ILS',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final meta = _meta(tester, 'cash');
      expect(meta, '0 recorded payments'); // plural form for zero
      expect(meta, isNot(contains('%')));
      expect(meta, isNot(contains('Avg')));
    });

    testWidgets('a zero AMOUNT across real payments still averages to zero', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(
        _wrap(
          _report(
            collectedMinor: 5000,
            methods: const [
              PaymentMethodLine(
                method: 'cash',
                count: 3,
                totalMinor: 0,
                currencyCode: 'ILS',
              ),
              PaymentMethodLine(
                method: 'card',
                count: 1,
                totalMinor: 5000,
                currencyCode: 'ILS',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_meta(tester, 'cash'), contains('Avg. payment ₪0.00'));
      expect(_meta(tester, 'cash'), contains('0.0% of collected'));
    });

    testWidgets('an UNKNOWN method keeps its figures and stays display-only', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(
        _wrap(
          _report(
            collectedMinor: 20000,
            methods: const [
              PaymentMethodLine(
                method: 'cash',
                count: 5,
                totalMinor: 15000,
                currencyCode: 'ILS',
              ),
              PaymentMethodLine(
                method: 'crypto',
                count: 2,
                totalMinor: 5000,
                currencyCode: 'ILS',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_amount(tester, 'crypto'), '₪50.00');
      expect(_meta(tester, 'crypto'), contains('25.0% of collected'));
      expect(
        _isRowTappable(tester, 'crypto'),
        isFalse,
        reason: 'there is no history filter token for an unknown method',
      );
      // ...even though the SERVER-B capability is present in this report.
      expect(_isRowTappable(tester, 'cash'), isTrue);
    });
  });

  group('the SERVER-B capability gate', () {
    testWidgets('WITHOUT the capability, only cash is tappable — the analytics '
        'still render in full', (tester) async {
      _size(tester);
      await tester.pumpWidget(_wrap(_report(comparison: _legacyComparison)));
      await tester.pumpAndSettle();

      expect(_isRowTappable(tester, 'cash'), isTrue);
      for (final method in const ['card', 'bit', 'external']) {
        expect(
          _isRowTappable(tester, method),
          isFalse,
          reason:
              '$method must not navigate to a list the server cannot filter',
        );
      }
      // The numbers are unaffected by the gate — only the interaction is.
      expect(_amount(tester, 'card'), '₪50.00');
      expect(_meta(tester, 'card'), contains('25.0% of collected'));
    });

    testWidgets('WITH the capability, all four known methods are tappable', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(_wrap(_report()));
      await tester.pumpAndSettle();

      for (final method in const ['cash', 'card', 'bit', 'external']) {
        expect(_isRowTappable(tester, method), isTrue, reason: method);
      }
    });

    testWidgets('with NO drill-down destination every row is display-only, '
        'capability or not', (tester) async {
      _size(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ownerReportsRepositoryProvider.overrideWithValue(
              _FixedRepository(_report()),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            theme: restoflowBaseTheme(),
            // No onNavigate: nowhere to go.
            home: const DashboardHomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final method in const ['cash', 'card', 'bit', 'external']) {
        expect(_isRowTappable(tester, method), isFalse, reason: method);
      }
    });
  });

  group('drill-down', () {
    for (final (method, filter) in const [
      ('cash', PaymentFilter.cash),
      ('card', PaymentFilter.card),
      ('bit', PaymentFilter.bit),
      ('external', PaymentFilter.external),
    ]) {
      testWidgets('tapping $method opens Orders history filtered to $method', (
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

        // A stale, conflicting filter set the drill-down must clear.
        container
            .read(orderHistoryQueryProvider.notifier)
            .state = const OrderHistoryQuery(
          status: OrderStatusFilter.voided,
          search: 'leftover',
          payment: PaymentFilter.paid,
        );

        await tester.tap(find.byKey(Key('payment-mix-row-$method')));
        await tester.pumpAndSettle();

        expect(landed, DashboardDestination.orders);
        expect(container.read(ordersInitialTabProvider), OrdersTab.history);

        final query = container.read(orderHistoryQueryProvider);
        expect(query.payment, filter);
        expect(query.payment.wire, method);
        // A FRESH query: the leftovers are gone, not merged.
        expect(query.status, OrderStatusFilter.all);
        expect(query.searchOrNull, isNull);
      });
    }

    test('the typed drill-downs carry business filters only — no scope', () {
      for (final drill in const [
        OrdersHistoryDrillDown.cash(),
        OrdersHistoryDrillDown.card(),
        OrdersHistoryDrillDown.bit(),
        OrdersHistoryDrillDown.external(),
      ]) {
        expect(drill.destination, DashboardDestination.orders);
        expect(drill.status, OrderStatusFilter.all);
      }
      expect(const OrdersHistoryDrillDown.card().payment, PaymentFilter.card);
      expect(const OrdersHistoryDrillDown.bit().payment, PaymentFilter.bit);
      expect(
        const OrdersHistoryDrillDown.external().payment,
        PaymentFilter.external,
      );
    });

    test('the method filters are distinguishable from the settlement ones', () {
      expect(PaymentFilter.cash.isMethod, isTrue);
      expect(PaymentFilter.card.isMethod, isTrue);
      expect(PaymentFilter.bit.isMethod, isTrue);
      expect(PaymentFilter.external.isMethod, isTrue);
      expect(PaymentFilter.paid.isMethod, isFalse);
      expect(PaymentFilter.unpaid.isMethod, isFalse);
      expect(PaymentFilter.all.isMethod, isFalse);
    });
  });

  group('the per-method daily trend', () {
    testWidgets('last7 draws the cash trend from the SAME series the daily '
        'sales trend loaded — no extra request', (tester) async {
      _size(tester);
      final seriesRepo = _CountingSeriesRepository();
      await tester.pumpWidget(_wrap(_report(), seriesRepo: seriesRepo));
      await tester.pumpAndSettle();
      await _selectRange(tester, 'last7');

      expect(
        find.byKey(const Key('payment-method-trend-chart')),
        findsOneWidget,
      );
      expect(
        seriesRepo.calls,
        [AnalyticsRange.last7],
        reason: 'the payment trend rides the daily trend request',
      );

      final chart = tester.widget<RestoflowBarChart>(
        find.byKey(const Key('payment-method-trend-chart')),
      );
      // Cash per day, including the truthful ZERO on the day with no cash.
      expect(chart.bars.map((b) => b.value), [4000, 0, 9000]);
      expect(chart.peakValueLabel, '₪90.00');
      // Labels come from the server's calendar tokens, never a re-rendered date.
      expect(chart.bars.map((b) => b.label), ['06', '07', '08']);
    });

    testWidgets('the heading names the method being drawn', (tester) async {
      _size(tester);
      await tester.pumpWidget(
        _wrap(_report(), seriesRepo: _CountingSeriesRepository()),
      );
      await tester.pumpAndSettle();
      await _selectRange(tester, 'last7');

      expect(find.text('Daily recorded tender: Cash'), findsOneWidget);
    });

    testWidgets('with no cash tender the trend falls back to the LARGEST '
        'method, and says so', (tester) async {
      _size(tester);
      await tester.pumpWidget(
        _wrap(
          _report(
            collectedMinor: 7000,
            methods: const [
              PaymentMethodLine(
                method: 'card',
                count: 2,
                totalMinor: 5000,
                currencyCode: 'ILS',
              ),
              PaymentMethodLine(
                method: 'bit',
                count: 1,
                totalMinor: 2000,
                currencyCode: 'ILS',
              ),
            ],
          ),
          seriesRepo: _CountingSeriesRepository(),
        ),
      );
      await tester.pumpAndSettle();
      await _selectRange(tester, 'last7');

      expect(find.text('Daily recorded tender: Card'), findsOneWidget);
      final chart = tester.widget<RestoflowBarChart>(
        find.byKey(const Key('payment-method-trend-chart')),
      );
      expect(chart.bars.map((b) => b.value), [1000, 3000, 2000]);
    });

    testWidgets('today and yesterday show the payment mix with NO trend and NO '
        'series request', (tester) async {
      _size(tester);
      final seriesRepo = _CountingSeriesRepository();
      await tester.pumpWidget(_wrap(_report(), seriesRepo: seriesRepo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('payment-mix-card')), findsOneWidget);
      expect(find.byKey(const Key('payment-method-trend-chart')), findsNothing);
      expect(seriesRepo.calls, isEmpty);

      await _selectRange(tester, 'yesterday');
      expect(find.byKey(const Key('payment-mix-card')), findsOneWidget);
      expect(find.byKey(const Key('payment-method-trend-chart')), findsNothing);
      expect(seriesRepo.calls, isEmpty);
    });

    testWidgets('an UNAVAILABLE series (old hosted, no SERVER-A) hides the '
        'trend without collapsing the payment analytics', (tester) async {
      _size(tester);
      await tester.pumpWidget(
        _wrap(
          _report(),
          seriesRepo: _CountingSeriesRepository(unavailable: true),
        ),
      );
      await tester.pumpAndSettle();
      await _selectRange(tester, 'last7');

      expect(find.byKey(const Key('payment-method-trend-chart')), findsNothing);
      // The payment card and its figures are untouched — SERVER-A and SERVER-B
      // are separate capabilities.
      expect(find.byKey(const Key('payment-mix-card')), findsOneWidget);
      expect(_amount(tester, 'card'), '₪50.00');
      expect(_isRowTappable(tester, 'card'), isTrue);
    });
  });

  group('wording', () {
    testWidgets('the card states these are recorded tenders, and claims no '
        'settlement', (tester) async {
      _size(tester);
      await tester.pumpWidget(_wrap(_report()));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('payment-recorded-tenders-note')),
        findsOneWidget,
      );
      expect(
        find.text('Recorded tenders only — not processor settlement.'),
        findsOneWidget,
      );
      for (final forbidden in const [
        'approved',
        'settled',
        'reconcil',
        'acquirer',
        'EMV',
        'authorized',
      ]) {
        expect(
          find.textContaining(forbidden, skipOffstage: false),
          findsNothing,
          reason:
              'no acquirer integration exists — "$forbidden" cannot be claimed',
        );
      }
    });

    for (final (locale, note) in const [
      (
        Locale('ar'),
        'مبالغ مسجّلة في النظام فقط — وليست تسوية من مزوّد الدفع.',
      ),
      (Locale('he'), 'תשלומים שנרשמו במערכת בלבד — לא סליקה מול חברת האשראי.'),
    ]) {
      testWidgets('the recorded-tender note is localized in '
          '${locale.languageCode}', (tester) async {
        _size(tester);
        await tester.pumpWidget(_wrap(_report(), locale: locale));
        await tester.pumpAndSettle();

        expect(find.text(note), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('layout safety', () {
    testWidgets('renders at phone width without overflow', (tester) async {
      _size(tester, const Size(390, 4200));
      await tester.pumpWidget(_wrap(_report()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('payment-mix-card')), findsOneWidget);
    });

    testWidgets('survives a 2x text scale at phone width', (tester) async {
      _size(tester, const Size(390, 5200));
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(_wrap(_report()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('payment-mix-card')), findsOneWidget);
    });

    for (final locale in const [Locale('ar'), Locale('he')]) {
      testWidgets('renders RTL (${locale.languageCode}) without overflow', (
        tester,
      ) async {
        _size(tester, const Size(390, 4200));
        await tester.pumpWidget(_wrap(_report(), locale: locale));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          Directionality.of(
            tester.element(find.byKey(const Key('payment-mix-card'))),
          ),
          TextDirection.rtl,
        );
        // Money stays the same integer-minor figure in every locale.
        expect(_amount(tester, 'cash'), '₪120.00');
      });
    }
  });
}
