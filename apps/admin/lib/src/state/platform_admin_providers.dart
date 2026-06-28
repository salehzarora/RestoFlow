import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/platform_admin_repository.dart';
import '../data/platform_overview.dart';
import '../data/real_platform_admin_repository.dart';

/// The platform-admin data seam (RF-120 / RF-128).
///
/// This is the SINGLE swap point. The demo vs real choice is taken purely from
/// [runtimeConfigProvider] (composed from the one audited RESTOFLOW_DEMO_MODE
/// read): demo mode is the DEFAULT and keeps [DemoPlatformAdminRepository]; real
/// mode is opt-in and selects [RealPlatformAdminRepository], which reads the
/// RF-091 platform panel through the RF-125 `public.platform_admin_*` wrappers,
/// READ-ONLY (D-026). The real repo uses the shared public-schema
/// [SyncRpcTransport] built from the validated anon-key Supabase config (never a
/// service-role key, D-011; never the `app` schema). When real mode is selected
/// but the Supabase config is missing/invalid the transport is null and the real
/// repo fails closed (no backend contact). Auth entry stays gated by
/// `is_platform_admin` + aal2 (D-026).
final platformAdminRepositoryProvider = Provider<PlatformAdminRepository>((
  ref,
) {
  final config = ref.watch(runtimeConfigProvider);
  if (config.isDemoMode) {
    return const DemoPlatformAdminRepository();
  }
  final supabase = config.supabase;
  final transport = supabase == null
      ? null
      : SupabaseAuthBootstrap(config: supabase).createRpcTransport();
  return RealPlatformAdminRepository(transport);
});

/// The platform overview, loaded asynchronously through the repository so the UI
/// has loading / error / empty states. Refresh by invalidating it
/// (`ref.invalidate(platformOverviewProvider)`), which re-runs `loadOverview`.
final platformOverviewProvider = FutureProvider<PlatformOverview>(
  (ref) => ref.watch(platformAdminRepositoryProvider).loadOverview(),
);
