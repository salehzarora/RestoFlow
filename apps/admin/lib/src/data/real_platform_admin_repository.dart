/// The REAL platform-admin repository (RF-120 / RF-091 / RF-125) - real client
/// wiring intentionally DEFERRED in this M7 foundation. Selected ONLY in real
/// mode; demo mode keeps the default demo repo.
///
/// Platform admin is a READ-ONLY surface (DECISION D-026). The real overview is
/// sourced from the RF-091 platform-admin RPCs
/// (`app.platform_admin_organization_overview` / `get_organization` /
/// `recent_audit`). The narrow, authenticated-only `public.*` wrappers over
/// those RPCs NOW EXIST (RF-125: `public.platform_admin_organization_overview` /
/// `get_organization` / `recent_audit`, SECURITY INVOKER) - clients may call
/// them directly while the `app` schema stays unexposed. This foundation does
/// NOT wire to them yet: connecting the client (with aal2 MFA, an active
/// platform_admin_grant, and a mandatory audit reason) is left to a later,
/// localized client ticket. Until then this repository stays FAIL-CLOSED:
/// [RealPlatformAdminRepository.loadOverview] ALWAYS throws and NEVER contacts a
/// backend, so real platform-admin data is NOT wired now - the surface can make
/// no false live-data claim and never silently falls back to demo.
library;

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show SupabaseBootstrapConfig;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'platform_admin_repository.dart';
import 'platform_overview.dart';

/// Real-mode platform-admin repository - real wiring intentionally DEFERRED
/// (not wired in this foundation).
///
/// Accepts the validated [SupabaseBootstrapConfig] (anon key only; may be null
/// when real-mode config failed closed) so the wiring shape is ready, but it
/// does NOT build a client or call any RPC. The RF-125 `public.platform_admin_*`
/// wrappers exist now, but wiring this repo to them - with aal2 MFA, an active
/// platform_admin_grant, and a mandatory audit reason (D-026 read-only) - is a
/// later, localized client ticket. For now [loadOverview] ALWAYS throws the
/// shared [RealRepoNotWiredError] and the `app` schema is never client-exposed.
class RealPlatformAdminRepository implements PlatformAdminRepository {
  const RealPlatformAdminRepository(this.config);

  /// The validated anon-key Supabase config, or null when real-mode config was
  /// missing/invalid (fail-closed). Held only to keep the constructor shape
  /// ready; never used to contact a backend while stubbed.
  final SupabaseBootstrapConfig? config;

  @override
  Future<PlatformOverview> loadOverview() async {
    throw const RealRepoNotWiredError(
      'platform-admin real wiring intentionally deferred: the RF-125 '
      'public.platform_admin_* wrappers exist, but connecting the client '
      '(aal2 MFA + platform_admin_grant + audit reason, D-026 read-only) is a '
      'later localized ticket - real data is not wired in this foundation.',
    );
  }
}
