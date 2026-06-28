/// The REAL platform-admin repository (RF-120 / RF-091) - STUB, blocked on
/// Agent A. Selected ONLY in real mode; demo mode keeps the default demo repo.
///
/// Platform admin is a READ-ONLY surface (DECISION D-026). The real overview is
/// sourced from the RF-091 platform-admin RPCs
/// (`app.platform_admin_organization_overview` / `get_organization` /
/// `recent_audit`). Those are PRIVATE `app.*` functions with NO `public.*`
/// wrapper yet, and clients may only call `public.*` wrappers / RLS-scoped
/// public views - never the `app` schema directly. Until Agent A ships the
/// wrapper this repository is a HARD STUB: [RealPlatformAdminRepository.loadOverview]
/// ALWAYS throws and NEVER contacts a backend, so the surface can never make a
/// false live-data claim and never silently falls back to demo.
library;

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show SupabaseBootstrapConfig;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'platform_admin_repository.dart';
import 'platform_overview.dart';

/// Real-mode platform-admin repository - STUB, blocked on Agent A.
///
/// Accepts the validated [SupabaseBootstrapConfig] (anon key only; may be null
/// when real-mode config failed closed) so the wiring shape is ready, but it
/// does NOT build a client or call any RPC. [loadOverview] ALWAYS throws the
/// shared [RealRepoNotWiredError]: the RF-091 RPCs are private `app.*` functions
/// with no `public.*` wrapper yet (D-026 read-only path), and the `app` schema
/// is never client-exposed.
class RealPlatformAdminRepository implements PlatformAdminRepository {
  const RealPlatformAdminRepository(this.config);

  /// The validated anon-key Supabase config, or null when real-mode config was
  /// missing/invalid (fail-closed). Held only to keep the constructor shape
  /// ready; never used to contact a backend while stubbed.
  final SupabaseBootstrapConfig? config;

  @override
  Future<PlatformOverview> loadOverview() async {
    throw const RealRepoNotWiredError(
      'platform-admin public wrapper not shipped: the RF-091 '
      'app.platform_admin_* RPCs have no public.* wrapper yet (blocked on '
      'Agent A). Real mode must not call the app schema directly (D-026 '
      'read-only).',
    );
  }
}
