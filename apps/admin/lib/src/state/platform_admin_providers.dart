import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/platform_admin_repository.dart';
import '../data/platform_overview.dart';
import '../data/real_platform_admin_repository.dart';

/// RF-119-b — the authenticated RPC transport the REAL platform overview reads
/// use. It DEFAULTS TO NULL (fail-closed): real platform reads require the Admin
/// app to OVERRIDE this (in `main.dart`) with the SAME session-carrying
/// `SupabaseSyncRpcTransport(Supabase.instance.client)` it uses for
/// `get_my_context` — so the operator's signed-in aal2 session reaches the
/// RF-091/RF-119 `platform_admin_guard` (grant + aal2 + reason).
///
/// Without that override the real repo has no transport and fails CLOSED (honest
/// "not configured") — it NEVER builds a fresh sessionless anon-key client for
/// platform reads, and NEVER fakes data. No service-role key (D-011); the server
/// guard stays the authorization boundary and the client aal2 is UX only.
final platformAdminTransportProvider = Provider<SyncRpcTransport?>(
  (ref) => null,
);

/// The platform-admin data seam (RF-120 / RF-128 / RF-119-b).
///
/// The demo vs real choice is taken from [runtimeConfigProvider] (the one audited
/// RESTOFLOW_DEMO_MODE read): demo mode (the DEFAULT) keeps
/// [DemoPlatformAdminRepository]; real mode selects [RealPlatformAdminRepository],
/// reading the RF-091 panel through the RF-125 `public.platform_admin_*` wrappers
/// (READ-ONLY, D-026) over the [platformAdminTransportProvider] transport — the
/// SAME authenticated session client `get_my_context` uses (RF-119-b). Entry stays
/// gated by `is_platform_admin` + aal2 (server-side).
final platformAdminRepositoryProvider = Provider<PlatformAdminRepository>((
  ref,
) {
  final config = ref.watch(runtimeConfigProvider);
  if (config.isDemoMode) {
    return const DemoPlatformAdminRepository();
  }
  // Real mode: read through the injected session-carrying transport (null =>
  // fail-closed, an honest "not configured" state; never a sessionless read).
  return RealPlatformAdminRepository(ref.watch(platformAdminTransportProvider));
});

/// The platform overview, loaded asynchronously through the repository so the UI
/// has loading / error / empty states. Refresh by invalidating it
/// (`ref.invalidate(platformOverviewProvider)`), which re-runs `loadOverview`.
final platformOverviewProvider = FutureProvider<PlatformOverview>(
  (ref) => ref.watch(platformAdminRepositoryProvider).loadOverview(),
);
