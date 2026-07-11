import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// RF-127 — the redesigned, data-forward Overview composition (demo data): the
/// four prioritized primary KPIs, the preserved secondary operational summary,
/// the dominant sales-by-hour area chart beside the payment-mix donut, the strong
/// top-sellers/recent-orders pair, a persistent readiness/setup slot, and
/// responsive + RTL/LTR behavior at representative widths. Presentation only —
/// values come from the same demo report seam as before.

Widget _wrap({Widget? setupPanel, Locale locale = const Locale('en')}) =>
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: DashboardHomeScreen(setupPanel: setupPanel),
      ),
    );

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

String _kpi(WidgetTester tester, String key) =>
    tester.widget<RestoflowMetricCard>(find.byKey(Key(key))).value;

void main() {
  testWidgets('four primary KPIs are prioritized and carry the demo values', (
    tester,
  ) async {
    _size(tester, const Size(1320, 2600));
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // The four headline KPIs.
    expect(_kpi(tester, 'kpi-gross-sales'), '₪626.00');
    expect(_kpi(tester, 'kpi-net-sales'), '₪620.00');
    expect(_kpi(tester, 'kpi-orders'), '7');
    expect(_kpi(tester, 'kpi-avg-ticket'), '₪88.57');
  });

  testWidgets('the secondary operational summary preserves every metric', (
    tester,
  ) async {
    _size(tester, const Size(1320, 2600));
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // None of the secondary figures are dropped in the redesign.
    expect(_kpi(tester, 'kpi-cash-sales'), '₪474.00');
    expect(_kpi(tester, 'kpi-completed'), '5');
    expect(_kpi(tester, 'kpi-unpaid'), '2');
    // Open-order count is preserved as the completed card's caption.
    expect(find.textContaining('Open orders: 2'), findsOneWidget);
  });

  testWidgets('sales-by-hour is the dominant visualization beside the payment '
      'mix, with an accessible summary', (tester) async {
    final handle = tester.ensureSemantics();
    _size(tester, const Size(1320, 2600));
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sales-by-hour-card')), findsOneWidget);
    expect(find.byType(RestoflowAreaChart), findsOneWidget);
    expect(find.byKey(const Key('payment-mix-card')), findsOneWidget);

    // Dominant = wider than the secondary payment-mix analytics at wide widths.
    final chartW = tester
        .getSize(find.byKey(const Key('sales-by-hour-card')))
        .width;
    final mixW = tester
        .getSize(find.byKey(const Key('payment-mix-card')))
        .width;
    expect(chartW, greaterThan(mixW));

    // The chart exposes a MEANINGFUL summary naming the peak hour + its formatted
    // value (demo peak is 19:00 → ₪101.00). The "Peak at" phrase targets the
    // chart summary, not the section-card title.
    expect(
      find.bySemanticsLabel('Sales by hour. Peak at 19:00: ₪101.00'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets(
    'the sales-by-hour chart summary is localized (Arabic + Hebrew)',
    (tester) async {
      final handle = tester.ensureSemantics();
      _size(tester, const Size(1320, 2600));

      // Arabic: the localized peak summary (context + peak hour + amount), not
      // the English string.
      await tester.pumpWidget(_wrap(locale: const Locale('ar')));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('المبيعات حسب الساعة. الذروة عند 19:00: ₪101.00'),
        findsOneWidget,
      );

      // Hebrew: its localized peak summary.
      await tester.pumpWidget(_wrap(locale: const Locale('he')));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('מכירות לפי שעה. שיא ב-19:00: ₪101.00'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testWidgets('at phone width the payment mix stacks under the hourly chart', (
    tester,
  ) async {
    _size(tester, const Size(390, 3200));
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('sales-by-hour-card')), findsOneWidget);
    expect(find.byKey(const Key('payment-mix-card')), findsOneWidget);
    // Stacked: the chart sits above the mix.
    final chartY = tester
        .getTopLeft(find.byKey(const Key('sales-by-hour-card')))
        .dy;
    final mixY = tester
        .getTopLeft(find.byKey(const Key('payment-mix-card')))
        .dy;
    expect(chartY, lessThan(mixY));
  });

  testWidgets('top sellers and recent orders form the strong secondary pair', (
    tester,
  ) async {
    _size(tester, const Size(1320, 2600));
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('top-items-card')), findsOneWidget);
    expect(find.byKey(const Key('recent-orders-card')), findsOneWidget);
    // The daily/payment summaries remain accessible below.
    expect(find.byKey(const Key('payment-summary-card')), findsOneWidget);
    expect(find.text('Daily summary'), findsOneWidget);
  });

  testWidgets('the setup slot renders above the primary KPIs and keeps its '
      'interactions', (tester) async {
    _size(tester, const Size(1320, 2600));
    var tapped = 0;
    await tester.pumpWidget(
      _wrap(
        setupPanel: FilledButton(
          key: const Key('test-setup-panel'),
          onPressed: () => tapped++,
          child: const Text('Setup slot'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('test-setup-panel')), findsOneWidget);
    // It sits above the KPI row (right after the page chrome).
    final setupY = tester
        .getTopLeft(find.byKey(const Key('test-setup-panel')))
        .dy;
    final kpiY = tester.getTopLeft(find.byKey(const Key('kpi-gross-sales'))).dy;
    expect(setupY, lessThan(kpiY));
    // The slot does not swallow interactions (callbacks preserved).
    await tester.tap(find.byKey(const Key('test-setup-panel')));
    expect(tapped, 1);
  });

  testWidgets('refresh + range switching still work after the redesign', (
    tester,
  ) async {
    _size(tester, const Size(1320, 2600));
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reports-refresh-button')));
    await tester.pumpAndSettle();
    expect(_kpi(tester, 'kpi-net-sales'), '₪620.00');

    // Switching to a multi-day range hides the single-day hourly chart.
    await tester.tap(find.byKey(const Key('range-chip-last7')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sales-by-hour-card')), findsNothing);
  });

  for (final width in const [390.0, 700.0, 940.0, 1320.0]) {
    testWidgets('no horizontal overflow at ${width.toInt()}px', (tester) async {
      _size(tester, Size(width, 3200));
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('kpi-gross-sales')), findsOneWidget);
    });
  }

  for (final locale in const [Locale('ar'), Locale('he'), Locale('en')]) {
    testWidgets('renders ${locale.languageCode} with correct direction', (
      tester,
    ) async {
      _size(tester, const Size(1320, 2600));
      await tester.pumpWidget(_wrap(locale: locale));
      await tester.pumpAndSettle();

      final expected = locale.languageCode == 'en'
          ? TextDirection.ltr
          : TextDirection.rtl;
      expect(
        Directionality.of(
          tester.element(find.byKey(const Key('kpi-gross-sales'))),
        ),
        expected,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
