import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/platform_admin_repository.dart';
import '../data/platform_overview.dart';
import '../data/real_platform_admin_repository.dart';

/// The platform-admin data seam (RF-120).
///
/// This is the SINGLE swap point. The demo vs real choice is taken purely from
/// [runtimeConfigProvider] (composed from the one audited RESTOFLOW_DEMO_MODE
/// read): demo mode is the DEFAULT and keeps [DemoPlatformAdminRepository];
/// real mode is opt-in and selects [RealPlatformAdminRepository] - a HARD STUB
/// blocked on Agent A (no `public.*` wrapper for the RF-091 platform-admin RPCs
/// yet; D-026 read-only). The stub NEVER contacts a backend, so the surface can
/// make no false live-data claim. Auth entry stays gated by `is_platform_admin`
/// (D-026).
final platformAdminRepositoryProvider = Provider<PlatformAdminRepository>((
  ref,
) {
  final config = ref.watch(runtimeConfigProvider);
  if (config.isDemoMode) {
    return const DemoPlatformAdminRepository();
  }
  return RealPlatformAdminRepository(config.supabase);
});

/// The platform overview, loaded asynchronously through the repository so the UI
/// has loading / error / empty states. Refresh by invalidating it
/// (`ref.invalidate(platformOverviewProvider)`), which re-runs `loadOverview`.
final platformOverviewProvider = FutureProvider<PlatformOverview>(
  (ref) => ref.watch(platformAdminRepositoryProvider).loadOverview(),
);
