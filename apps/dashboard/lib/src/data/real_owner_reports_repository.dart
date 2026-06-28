/// Real-mode owner-reports repository SKELETON (M7, RF-119).
///
/// This is the auth-mode counterpart to [DemoOwnerReportsRepository]. Its real
/// source is the RLS-scoped report views public.daily_branch_sales_report
/// (RF-075) and public.dashboard_org_daily_sales (RF-092). Those views are
/// stated callable, but their exact output shape + RLS scope are NOT yet
/// ratified by the backend, so this skeleton deliberately does NOT contact any
/// backend: it FAILS CLOSED by throwing [RealRepoNotWiredError]. It already
/// accepts the validated [SupabaseBootstrapConfig] (anon key only) and the
/// active [MembershipContext] scope, so it can be upgraded to a thin view read
/// once the columns are ratified - without changing the seam or the UI. Money
/// stays integer minor units when wired (the [DashboardReport] model enforces
/// `_minor`); no float is ever introduced.
library;

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'demo_report.dart';
import 'owner_reports_repository.dart';

/// Reads the owner [DashboardReport] from the real RF-075/RF-092 report views.
///
/// Pending backend ratification of the view shape + RLS scope, every call fails
/// closed with the shared [RealRepoNotWiredError] rather than fabricating data
/// or silently falling back to demo. The constructor already takes the runtime
/// [config] (anon key only; null when real mode was selected but config was
/// missing/invalid) and the active membership [scope], so wiring a thin `SELECT`
/// later is a localized change.
class RealOwnerReportsRepository implements OwnerReportsRepository {
  const RealOwnerReportsRepository(this.config, {this.scope});

  /// The validated client runtime config (anon key only). Null when real mode
  /// was selected but the Supabase config was missing/invalid (fail-closed
  /// upstream in `RuntimeConfig`).
  final SupabaseBootstrapConfig? config;

  /// The active membership (org/restaurant/branch) the report is scoped to.
  /// Null in demo mode or before a membership is selected.
  final MembershipContext? scope;

  @override
  Future<DashboardReport> loadReport() async {
    throw const RealRepoNotWiredError(
      'owner-reports: public.daily_branch_sales_report / '
      'public.dashboard_org_daily_sales output shape + RLS scope not ratified '
      'yet (RF-075/RF-092) - real read not wired',
    );
  }
}
