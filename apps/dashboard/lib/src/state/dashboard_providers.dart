import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/demo_report.dart';
import '../data/owner_reports_repository.dart';
import '../data/real_owner_reports_repository.dart';

/// The active dashboard membership scope (org/restaurant/branch), overridden by
/// the shell's Overview scope for real mode (sprint). Null in demo mode (the
/// DEFAULT) or before a membership is selected; the real repo treats null as
/// unscoped and fails closed.
final dashboardMembershipProvider = Provider<MembershipContext?>(
  (ref) => null,
  dependencies: const [],
);

/// The AUTHENTICATED dashboard RPC transport (the session-carrying
/// supabase_flutter client), overridden by the shell for real mode (sprint).
/// Null => real reads fail closed (never a fresh, session-less client).
final dashboardAuthTransportProvider = Provider<SyncRpcTransport?>(
  (ref) => null,
  dependencies: const [],
);

/// The owner-reports data seam (RF-119).
///
/// SINGLE swap point. The demo/real choice is decided by [runtimeConfigProvider]
/// (the one audited mode switch): demo mode - the DEFAULT (RESTOFLOW_DEMO_MODE
/// defaults to true) - keeps the verbatim [DemoOwnerReportsRepository] computing
/// from the structured demo dataset; real mode returns the
/// [RealOwnerReportsRepository] reading `public.sales_summary` (sprint) over the
/// authenticated transport, scoped to the active membership. With no
/// transport/scope it fails closed (see [RealRepoNotWiredError]) and the
/// existing error state surfaces it.
final ownerReportsRepositoryProvider = Provider<OwnerReportsRepository>((ref) {
  final config = ref.watch(runtimeConfigProvider);
  if (config.isDemoMode) {
    return const DemoOwnerReportsRepository();
  }
  return RealOwnerReportsRepository(
    config.supabase,
    scope: ref.watch(dashboardMembershipProvider),
    transport: ref.watch(dashboardAuthTransportProvider),
  );
}, dependencies: [dashboardMembershipProvider, dashboardAuthTransportProvider]);

/// The selected reporting date range (RF-REPORT-004). The Overview's range chips
/// write this; the report provider watches it, so changing the range re-runs
/// `loadReport` for the new window. Defaults to today.
final reportRangeProvider = StateProvider<ReportRange>(
  (ref) => ReportRange.today,
);

/// The owner dashboard report, loaded asynchronously through the repository so
/// the UI has loading / error / empty states. Reloads when the selected
/// [reportRangeProvider] changes; refresh by invalidating it
/// (`ref.invalidate(dashboardReportProvider)`), which re-runs `loadReport`.
final dashboardReportProvider = FutureProvider<DashboardReport>((ref) {
  final range = ref.watch(reportRangeProvider);
  return ref.watch(ownerReportsRepositoryProvider).loadReport(range: range);
}, dependencies: [ownerReportsRepositoryProvider, reportRangeProvider]);
