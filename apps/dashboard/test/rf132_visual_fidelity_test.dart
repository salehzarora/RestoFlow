import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/main.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/state/locale_controller.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminSettingsScreen;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart'
    show MenuManagementScreen;
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// RF-132 — visual-fidelity corrections against the approved Overview
/// reference: the cohesive segmented range control (stable keys + behavior
/// preserved), the KPI tile hierarchy (one consistent height, KPI style), the
/// honest live-limited analytics slot above the legacy tables, the untruncated
/// side-rail brand lockup, and increased-text-scale safety. Behavior seams
/// (providers, ranges, refresh, honesty states) are the RF-127 ones, untouched.

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

/// A live-LIMITED report like the sales_summary fallback produces
/// (LIVE-UX-001): KPIs + a safe comparison, but NO hourly / branch / top-item /
/// recent-order data (nothing fabricated).
class _LimitedRepo implements OwnerReportsRepository {
  const _LimitedRepo();
  @override
  Future<DashboardReport> loadReport({
    ReportRange range = ReportRange.today,
  }) async => const DashboardReport(
    currencyCode: 'ILS',
    businessDateLabel: '2026-07-05',
    grossSalesMinor: 12000,
    netSalesMinor: 12000,
    discountTotalMinor: 0,
    collectedMinor: 12000,
    cashSalesMinor: 12000,
    lastCashPaymentMinor: 0,
    orderCount: 5,
    completedOrderCount: 3,
    openOrderCount: 2,
    unpaidOrderCount: 2,
    voidCount: 0,
    voidTotalMinor: 0,
    openingFloatMinor: 0,
    expectedCashMinor: 0,
    countedCashMinor: 0,
    shiftStatus: 'none',
    branches: [],
    topItems: [],
    recentOrders: [],
    paymentMethods: [],
    comparison: ReportComparison(
      grossSalesMinor: 8000,
      netSalesMinor: 8000,
      orderCount: 4,
      cashSalesMinor: 8000,
    ),
  );
}

Widget _wrapLimited() => ProviderScope(
  overrides: [
    runtimeConfigProvider.overrideWithValue(
      RuntimeConfig.test(isDemoMode: false),
    ),
    ownerReportsRepositoryProvider.overrideWithValue(const _LimitedRepo()),
  ],
  child: const MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    home: DashboardHomeScreen(),
  ),
);

void main() {
  testWidgets('the range filter is ONE cohesive segmented control with the '
      'stable range-chip keys and working range behavior', (tester) async {
    _size(tester, const Size(1320, 2600));
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // One segmented control replaces the detached chips.
    expect(find.byKey(const Key('reports-range-filter')), findsOneWidget);
    expect(find.byType(RestoflowSegmentedControl<ReportRange>), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);

    // The four stable keys survive, inside the control.
    for (final wire in const ['today', 'yesterday', 'last7', 'last30']) {
      expect(
        find.descendant(
          of: find.byKey(const Key('reports-range-filter')),
          matching: find.byKey(Key('range-chip-$wire')),
        ),
        findsOneWidget,
      );
    }

    // Range behavior is untouched: multi-day range hides the hourly chart,
    // switching back restores it.
    await tester.tap(find.byKey(const Key('range-chip-last30')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sales-by-hour-card')), findsNothing);
    await tester.tap(find.byKey(const Key('range-chip-today')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sales-by-hour-card')), findsOneWidget);
  });

  testWidgets('range segments announce selection to assistive tech', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    _size(tester, const Size(1320, 2600));
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.bySemanticsLabel('Today')),
      matchesSemantics(
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        label: 'Today',
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Last 7 days')),
      matchesSemantics(
        isButton: true,
        isSelected: false,
        hasSelectedState: true,
        label: 'Last 7 days',
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('the four primary KPI tiles use the KPI style and share one '
      'height at the wide breakpoint', (tester) async {
    _size(tester, const Size(1320, 2600));
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    const primary = [
      'kpi-gross-sales',
      'kpi-net-sales',
      'kpi-orders',
      'kpi-avg-ticket',
    ];
    final heights = <double>[];
    for (final key in primary) {
      final card = tester.widget<RestoflowMetricCard>(find.byKey(Key(key)));
      expect(
        card.style,
        RestoflowMetricCardStyle.kpi,
        reason: '$key uses the reference KPI tile style',
      );
      heights.add(tester.getSize(find.byKey(Key(key))).height);
    }
    expect(
      heights.toSet().length,
      1,
      reason: 'primary KPI cards align at one height: $heights',
    );

    // Secondary tiles keep the same style (hierarchy consistency).
    for (final key in const ['kpi-cash-sales', 'kpi-completed', 'kpi-unpaid']) {
      expect(
        tester.widget<RestoflowMetricCard>(find.byKey(Key(key))).style,
        RestoflowMetricCardStyle.kpi,
      );
    }
  });

  testWidgets('data-rich wide order: primary KPIs above analytics, analytics '
      'above secondary cards, secondary cards above the detail sections', (
    tester,
  ) async {
    _size(tester, const Size(1320, 3200));
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    double topOf(String key) => tester.getTopLeft(find.byKey(Key(key))).dy;

    // Primary KPIs sit above the dominant analytics row.
    expect(topOf('kpi-gross-sales'), lessThan(topOf('sales-by-hour-card')));
    // The analytics row sits above the secondary operational cards.
    expect(topOf('sales-by-hour-card'), lessThan(topOf('kpi-cash-sales')));
    expect(topOf('payment-mix-card'), lessThan(topOf('kpi-cash-sales')));
    // The secondary cards sit above the lower detail sections.
    expect(topOf('kpi-cash-sales'), lessThan(topOf('top-items-card')));
    expect(topOf('kpi-cash-sales'), lessThan(topOf('recent-orders-card')));
    expect(topOf('kpi-cash-sales'), lessThan(topOf('payment-summary-card')));
    // Secondary values/captions preserved through the move.
    expect(
      tester
          .widget<RestoflowMetricCard>(find.byKey(const Key('kpi-cash-sales')))
          .value,
      '₪474.00',
    );
    expect(
      tester
          .widget<RestoflowMetricCard>(find.byKey(const Key('kpi-completed')))
          .value,
      '5',
    );
    expect(
      tester
          .widget<RestoflowMetricCard>(find.byKey(const Key('kpi-unpaid')))
          .value,
      '2',
    );
    expect(find.textContaining('Open orders: 2'), findsOneWidget);
  });

  testWidgets('live-limited: the honest limited-analytics panel holds the '
      'analytics slot ABOVE the legacy summary tables', (tester) async {
    _size(tester, const Size(1320, 2600));
    await tester.pumpWidget(_wrapLimited());
    await tester.pumpAndSettle();

    // The honesty chrome is intact.
    expect(find.byKey(const Key('reports-realmode-banner')), findsOneWidget);
    expect(find.byKey(const Key('reports-limited-analytics')), findsOneWidget);
    // Nothing fabricated: no chart, no analytics sections.
    expect(find.byType(RestoflowAreaChart), findsNothing);
    expect(find.byKey(const Key('sales-by-hour-card')), findsNothing);
    expect(find.byKey(const Key('top-items-card')), findsNothing);

    // The limited panel sits in the analytics position: below the primary
    // KPIs, above the secondary operational cards, and above the legacy
    // daily/payment tables — the first viewport keeps the reference hierarchy.
    final limitedY = tester
        .getTopLeft(find.byKey(const Key('reports-limited-analytics')))
        .dy;
    final primaryY = tester
        .getTopLeft(find.byKey(const Key('kpi-gross-sales')))
        .dy;
    final secondaryY = tester
        .getTopLeft(find.byKey(const Key('kpi-cash-sales')))
        .dy;
    final paymentY = tester
        .getTopLeft(find.byKey(const Key('payment-summary-card')))
        .dy;
    expect(primaryY, lessThan(limitedY));
    expect(limitedY, lessThan(secondaryY));
    expect(secondaryY, lessThan(paymentY));
  });

  testWidgets('the wide rail shows the untruncated brand lockup', (
    tester,
  ) async {
    _size(tester, const Size(1320, 1200));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialLocaleProvider.overrideWithValue(const Locale('en')),
        ],
        child: const DashboardApp(demoMode: true),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final rail = find.byKey(const Key('dashboard-side-rail'));
    expect(rail, findsOneWidget);

    // The lockup renders the short wordmark + tagline — never the long app
    // title that used to ellipsize inside the rail. (Pixel truncation itself
    // cannot be asserted under the square test font, where every word is far
    // wider than in any real font; it is covered by the RF-132 screenshot
    // review gate.)
    expect(
      find.descendant(of: rail, matching: find.text(l10n.dashboardBrandName)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: rail,
        matching: find.text(l10n.dashboardBrandTagline),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rail, matching: find.text(l10n.dashboardAppTitle)),
      findsNothing,
    );
  });

  for (final locale in const [Locale('ar'), Locale('en')]) {
    testWidgets(
      'phone bottom nav at a REAL 390x844 surface is icon-only, unclipped, '
      'fully labelled for assistive tech, and navigates '
      '(${locale.languageCode})',
      (tester) async {
        final handle = tester.ensureSemantics();
        _size(tester, const Size(390, 844));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [initialLocaleProvider.overrideWithValue(locale)],
            child: const DashboardApp(demoMode: true),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final l10n = await AppLocalizations.delegate.load(locale);
        final nav = find.byKey(const Key('dashboard-bottom-nav'));
        expect(nav, findsOneWidget);
        expect(find.byKey(const Key('dashboard-side-rail')), findsNothing);

        // Icon-only is INTENTIONAL: no label may render (and therefore none
        // can clip) — ten destinations at 390px cannot show readable text.
        expect(
          tester.widget<NavigationBar>(nav).labelBehavior,
          NavigationDestinationLabelBehavior.alwaysHide,
        );
        final labels = [
          l10n.dashboardNavOverview,
          l10n.dashboardNavMenu,
          l10n.dashboardNavDevices,
          l10n.dashboardNavPrinters,
          l10n.dashboardNavStaff,
          l10n.dashboardNavTables,
          l10n.dashboardNavUsers,
          l10n.dashboardNavOrders,
          l10n.dashboardNavActivity,
          l10n.dashboardNavSettings,
        ];
        for (final label in labels) {
          // No VISIBLE label text inside the bar: NavigationBar keeps the
          // hidden label in the tree (laid out past the bar's bottom edge)
          // and hides it through a FadeTransition — the opacity must be
          // EXACTLY zero, i.e. fully invisible, never a partially rendered /
          // clipped label like the pre-fix `onlyShowSelected` behavior.
          final labelText = find.descendant(
            of: nav,
            matching: find.text(label),
          );
          if (tester.any(labelText)) {
            final fade = tester.widget<FadeTransition>(
              find
                  .ancestor(
                    of: labelText.first,
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            );
            expect(
              fade.opacity.value,
              0.0,
              reason:
                  'label "$label" must be fully hidden, not partially visible',
            );
          }
          // …but every destination stays named for assistive tech (the node
          // label reads "<label>\nTab N of 10").
          expect(
            find.descendant(
              of: nav,
              matching: find.bySemanticsLabel(
                RegExp('^${RegExp.escape(label)}\\n'),
              ),
            ),
            findsWidgets,
            reason: 'semantic label present for "$label"',
          );
        }
        // The bar fits the surface exactly — nothing renders past the bottom.
        expect(tester.getBottomLeft(nav).dy, lessThanOrEqualTo(844.0));

        // Selection is announced (Overview is selected at boot; Menu is not).
        SemanticsNode navNode(String label) => tester.getSemantics(
          find
              .descendant(
                of: nav,
                matching: find.bySemanticsLabel(
                  RegExp('^${RegExp.escape(label)}\\n'),
                ),
              )
              .first,
        );
        // (The node label itself — "<name>\nTab N of 10" — was matched by the
        // finder above; the tab-position hint is localized, so only the flags
        // are pinned here.)
        expect(
          navNode(l10n.dashboardNavOverview),
          matchesSemantics(
            isSelected: true,
            hasSelectedState: true,
            isButton: true,
            hasTapAction: true,
            isFocusable: true,
            hasFocusAction: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        );
        expect(
          navNode(l10n.dashboardNavMenu),
          matchesSemantics(
            isSelected: false,
            hasSelectedState: true,
            isButton: true,
            hasTapAction: true,
            isFocusable: true,
            hasFocusAction: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        );

        // Representative navigation still works from the icon-only bar.
        await tester.tap(
          find.descendant(
            of: nav,
            matching: find.byIcon(Icons.restaurant_menu_outlined),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MenuManagementScreen), findsOneWidget);

        await tester.tap(
          find.descendant(of: nav, matching: find.byIcon(Icons.tune_outlined)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AdminSettingsScreen), findsOneWidget);

        handle.dispose();
      },
    );
  }

  testWidgets('increased text scale (2.0) renders the Overview without '
      'horizontal overflow at phone width', (tester) async {
    _size(tester, const Size(390, 3600));
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('reports-range-filter')), findsOneWidget);
    expect(find.byKey(const Key('kpi-gross-sales')), findsOneWidget);
  });

  for (final width in const [390.0, 700.0, 940.0, 1320.0]) {
    testWidgets(
      'the segmented control + KPI hierarchy render at ${width.toInt()}px '
      'without overflow',
      (tester) async {
        _size(tester, Size(width, 3200));
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('reports-range-filter')), findsOneWidget);
        expect(
          find.byType(RestoflowSegmentedControl<ReportRange>),
          findsOneWidget,
        );
      },
    );
  }

  for (final locale in const [Locale('ar'), Locale('he'), Locale('en')]) {
    testWidgets('the recomposed Overview keeps the correct direction for '
        '${locale.languageCode}', (tester) async {
      _size(tester, const Size(1320, 2600));
      await tester.pumpWidget(_wrap(locale: locale));
      await tester.pumpAndSettle();

      final expected = locale.languageCode == 'en'
          ? TextDirection.ltr
          : TextDirection.rtl;
      expect(
        Directionality.of(
          tester.element(find.byKey(const Key('reports-range-filter'))),
        ),
        expected,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
