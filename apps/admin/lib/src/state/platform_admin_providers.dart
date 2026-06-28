import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/platform_admin_repository.dart';
import '../data/platform_overview.dart';

/// The platform-admin data seam (RF-120).
///
/// This is the SINGLE swap point: override it with a Supabase-backed
/// implementation (calling the real RF-091 platform-admin RPCs) to go live,
/// without touching the UI. Today it computes from a structured demo dataset.
final platformAdminRepositoryProvider = Provider<PlatformAdminRepository>(
  (ref) => const DemoPlatformAdminRepository(),
);

/// The platform overview, loaded asynchronously through the repository so the UI
/// has loading / error / empty states. Refresh by invalidating it
/// (`ref.invalidate(platformOverviewProvider)`), which re-runs `loadOverview`.
final platformOverviewProvider = FutureProvider<PlatformOverview>(
  (ref) => ref.watch(platformAdminRepositoryProvider).loadOverview(),
);
