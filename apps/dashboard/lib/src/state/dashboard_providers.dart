import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/demo_report.dart';
import '../data/owner_reports_repository.dart';

/// The owner-reports data seam (RF-119).
///
/// This is the SINGLE swap point: override it with a Supabase-backed
/// implementation (reading the real RF-075/RF-092 report views) to go live,
/// without touching the UI. Today it computes from a structured demo dataset.
final ownerReportsRepositoryProvider = Provider<OwnerReportsRepository>(
  (ref) => const DemoOwnerReportsRepository(),
);

/// The owner dashboard report, loaded asynchronously through the repository so
/// the UI has loading / error / empty states. Refresh by invalidating it
/// (`ref.invalidate(dashboardReportProvider)`), which re-runs `loadReport`.
final dashboardReportProvider = FutureProvider<DashboardReport>(
  (ref) => ref.watch(ownerReportsRepositoryProvider).loadReport(),
);
