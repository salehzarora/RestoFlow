// RF-132 — REVIEW-ONLY visual-QA harness. NOT part of the shipped app:
// nothing under review/ is imported by lib/, and no production build target
// references this file. It exists solely so the Real/live-limited Overview
// composition can be captured for the visual review gate.
//
// It renders the REAL `DashboardHomeScreen` in real (non-demo) mode over a
// fixture repository shaped exactly like the LIVE-UX-001 `sales_summary`
// fallback (mirroring the `_LimitedRepo` widget-test fixture): structurally
// non-empty KPI values + a prior-day comparison, with NO hourly series, NO
// branch analytics, NO top items, NO recent orders, NO payment methods — so
// nothing (chart, donut, readiness) can be fabricated. Demo/Real provider
// behavior, repositories, models, and calculations are untouched: the fixture
// is injected through the SAME ProviderScope override seam the widget tests
// use.
//
// Build (review only, from apps/dashboard):
//   flutter build web --release -t review/limited_state_preview.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// The LIVE-UX-001 live-limited report shape (same figures as the widget-test
/// `_LimitedRepo`): real-looking KPIs + comparison, no richer analytics.
class _ReviewLimitedRepo implements OwnerReportsRepository {
  const _ReviewLimitedRepo();
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

void main() {
  runApp(
    ProviderScope(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        ownerReportsRepositoryProvider.overrideWithValue(
          const _ReviewLimitedRepo(),
        ),
      ],
      child: MaterialApp(
        title: 'RF-132 review — live-limited Overview',
        theme: restoflowBaseTheme(),
        locale: const Locale('ar'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const DashboardHomeScreen(),
      ),
    ),
  );
}
