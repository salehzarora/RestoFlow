import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/demo_report.dart';
import '../data/owner_reports_repository.dart';
import '../data/real_owner_reports_repository.dart';

/// The active dashboard membership scope (org/restaurant/branch), supplied by
/// [DashboardShell] from the RF-108 `AuthGateReady.membership`. Null in demo
/// mode (the DEFAULT) or before a membership is selected; the real repo treats
/// null as unscoped and fails closed. The wiring that overrides this from
/// DashboardShell lands with the real view read.
final dashboardMembershipProvider = Provider<MembershipContext?>((ref) => null);

/// The owner-reports data seam (RF-119).
///
/// SINGLE swap point. The demo/real choice is decided by [runtimeConfigProvider]
/// (the one audited mode switch): demo mode - the DEFAULT (RESTOFLOW_DEMO_MODE
/// defaults to true) - keeps the verbatim [DemoOwnerReportsRepository] computing
/// from the structured demo dataset; real mode returns the
/// [RealOwnerReportsRepository] skeleton, scoped to the active membership and
/// carrying the anon-key-only config. The real repo reads the RF-075/RF-092
/// report views once their shape is ratified; until then it fails closed (see
/// [RealRepoNotWiredError]) and the existing error state surfaces it.
final ownerReportsRepositoryProvider = Provider<OwnerReportsRepository>((ref) {
  final config = ref.watch(runtimeConfigProvider);
  if (config.isDemoMode) {
    return const DemoOwnerReportsRepository();
  }
  return RealOwnerReportsRepository(
    config.supabase,
    scope: ref.watch(dashboardMembershipProvider),
  );
});

/// The owner dashboard report, loaded asynchronously through the repository so
/// the UI has loading / error / empty states. Refresh by invalidating it
/// (`ref.invalidate(dashboardReportProvider)`), which re-runs `loadReport`.
final dashboardReportProvider = FutureProvider<DashboardReport>(
  (ref) => ref.watch(ownerReportsRepositoryProvider).loadReport(),
);
