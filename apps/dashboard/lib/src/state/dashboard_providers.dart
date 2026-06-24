import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/demo_report.dart';

/// Provides the (in-memory, demo) owner dashboard report (RF-104).
///
/// Read-only: the dashboard renders this snapshot. The provider body is the
/// single swap point if a real, role-scoped report source is wired in a later
/// backend ticket — RF-104 stays UI-only with no backend/Supabase/RPC.
final dashboardReportProvider = Provider<DashboardReport>(
  (ref) => demoDashboardReport(),
);
