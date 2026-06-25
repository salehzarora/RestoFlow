import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';

/// Loads the caller's own auth context (`get_my_context`). Returns a
/// `Result<MyContext, AuthFailure>`; identity is server-derived (no user id
/// input). Apps depend on this typedef so they need not import `restoflow_core`.
typedef AuthContextFetcher = Future<Result<MyContext, AuthFailure>> Function();

/// Whether the app should run in DEMO mode - the existing in-memory demo UI with
/// NO auth (RF-108 Stage 4).
///
/// Controlled by the compile-time `--dart-define=RESTOFLOW_DEMO_MODE=...`.
/// DEFAULTS TO TRUE so the existing local/dev run commands keep working without
/// any auth/Supabase config. A production-style build sets
/// `--dart-define=RESTOFLOW_DEMO_MODE=false` to enable the auth gate. The flag is
/// read ONLY here, so the demo/auth choice is auditable in one place and is never
/// a silent in-code bypass.
bool authDemoModeEnabled() =>
    const bool.fromEnvironment('RESTOFLOW_DEMO_MODE', defaultValue: true);

/// Builds the real auth-context fetcher from the Stage 2 Supabase bootstrap
/// (`RESTOFLOW_SUPABASE_URL` / `RESTOFLOW_SUPABASE_ANON_KEY`).
///
/// The fetcher calls `public.get_my_context()` via the anon-key transport (no
/// service-role; no user id sent - identity is server-side). FAIL-CLOSED: if
/// auth mode is on but the config is missing/invalid (or a service-role-looking
/// key is supplied), the returned fetcher yields an error result so the gate
/// shows a generic error - it never crashes and never bypasses auth.
AuthContextFetcher authContextFetcherFromEnvironment() {
  try {
    final config = SupabaseBootstrapConfig.fromEnvironment();
    final repository = AuthContextRepository(
      SupabaseAuthBootstrap(config: config).createRpcTransport(),
    );
    return repository.fetchMyContext;
  } on SupabaseConfigException {
    // Never echo the underlying detail; the gate renders a generic error state.
    return () async => const Failure(
      AuthInvalidResponseFailure('Supabase auth config missing or invalid'),
    );
  }
}
