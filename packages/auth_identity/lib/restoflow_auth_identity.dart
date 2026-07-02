/// RestoFlow auth_identity package - RF-108 Stage 1: typed models + services for
/// real auth and role-based entry. No app/UI integration in this stage.
///
/// Consumes the merged backend auth RPCs: `public.get_my_context()` (RF-124) and
/// `public.start_pin_session()` (RF-123). Identity is server-derived from
/// `auth.uid()` (NEVER client-supplied); roles are per-membership (D-004); the
/// platform-admin flag is a SEPARATE boolean (D-026). No service-role key, no
/// money fields, no hardcoded tenant ids, no `ok:false`, no `server_ts`.
library;

export 'src/app_surface.dart';
export 'src/app_user_context.dart';
export 'src/auth_context_repository.dart';
// RF-153: shared device/station pairing context + repository seam (reused by
// dashboard/POS/KDS).
export 'src/device_context.dart';
export 'src/device_pairing_repository.dart';
// RF-161: the device-session secret store abstraction (raw token -> secure storage).
export 'src/device_session_secret_store.dart';
export 'src/auth_gate_state.dart';
export 'src/auth_failure.dart';
export 'src/membership_context.dart';
export 'src/membership_role.dart';
export 'src/membership_selection.dart';
export 'src/my_context.dart';
export 'src/pin_session_service.dart';
export 'src/role_entry_policy.dart';
// RF-108 Stage 2: Supabase bootstrap config + transport factory (anon key only).
export 'src/supabase_auth_bootstrap.dart';
export 'src/supabase_bootstrap_config.dart';
