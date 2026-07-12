// Dashboard V2 — REVIEW-ONLY visual-QA harness (like limited_state_preview):
// NOT part of the shipped app; nothing under review/ is imported by lib/ and
// no production build target references this file. It renders the real
// `DashboardHomeScreen` over the live-limited report fixture together with the
// real `DashboardDeviceSummaryCard` fed by a review stub repository, so the
// device readiness card's honest states can be captured for visual review:
//
//   ?devices=all          -> every configured device active  (success tone)
//   ?devices=partial      -> some configured devices inactive (warning tone)
//   ?devices=unavailable  -> device load fails                (unavailable card)
//
// Build (review only, from apps/dashboard):
//   flutter build web --release -t review/device_states_preview.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/setup/device_summary_card.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
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

/// A review stub devices repository with a fixed device list.
class _StubDevices extends DemoAdminStore {
  _StubDevices(this._devices) : super(scope: AdminScope.demo);
  final List<AdminDevice> _devices;

  @override
  Future<AdminResult<List<AdminDevice>>> loadDevices() async =>
      Success(_devices);
}

/// A review stub devices repository whose load always fails.
class _FailingDevices extends DemoAdminStore {
  _FailingDevices() : super(scope: AdminScope.demo);

  @override
  Future<AdminResult<List<AdminDevice>>> loadDevices() async =>
      const Failure(AdminNotFound());
}

AdminDevice _device(String id, String type, DeviceLifecycleStatus status) =>
    AdminDevice(
      id: id,
      label: id,
      deviceType: type,
      branchLabel: 'Main',
      status: status,
    );

void main() {
  final variant = Uri.base.queryParameters['devices'] ?? 'all';
  final DemoAdminStore repository = switch (variant) {
    'partial' => _StubDevices([
      _device('POS 1', 'pos', DeviceLifecycleStatus.active),
      _device('KDS 1', 'kds', DeviceLifecycleStatus.codeIssued),
      _device('POS 2', 'pos', DeviceLifecycleStatus.pending),
    ]),
    'unavailable' => _FailingDevices(),
    _ => _StubDevices([
      _device('POS 1', 'pos', DeviceLifecycleStatus.active),
      _device('KDS 1', 'kds', DeviceLifecycleStatus.active),
    ]),
  };

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
        title: 'Dashboard V2 review — device readiness states',
        theme: restoflowBaseTheme(),
        locale: const Locale('ar'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: DashboardHomeScreen(
          deviceSummary: DashboardDeviceSummaryCard(repository: repository),
        ),
      ),
    ),
  );
}
