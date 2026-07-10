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
// PILOT-OFFLINE-BOOT-001: classifies a device-auth bootstrap failure as a
// network/offline problem vs a real auth/config rejection.
export 'src/device_auth_network_error.dart';
// RF-153: shared device/station pairing context + repository seam (reused by
// dashboard/POS/KDS).
export 'src/device_context.dart';
export 'src/device_image_url_resolver.dart';
export 'src/device_pairing_repository.dart';
// Device settings sprint: the safe per-device printer-assignments projection.
export 'src/device_printer_assignments.dart';
// RF-113: the per-branch POS shift-close (reconciliation) visibility policy seam.
export 'src/device_shift_close_policy.dart';
// RF-117: the token-proven per-branch tax setting seam (BranchTax + reader).
export 'src/device_branch_tax.dart';
// RF-161: the device-session secret store abstraction (raw token -> secure storage).
export 'src/device_session_secret_store.dart';
// Sprint: the money-free device staff directory for the POS/KDS PIN pad.
export 'src/device_staff.dart';
export 'src/auth_gate_state.dart';
export 'src/auth_failure.dart';
export 'src/membership_context.dart';
export 'src/membership_role.dart';
export 'src/membership_selection.dart';
export 'src/my_context.dart';
// RF-118: client-side PIN attempt limiter + staff PIN-session expiry policy
// (pure logic; UX mirrors of the authoritative server RF-051 lockout / window).
export 'src/pin_attempt_limiter.dart';
export 'src/pin_session_expiry_policy.dart';
export 'src/pin_session_service.dart';
export 'src/role_entry_policy.dart';
// RF-108 Stage 2: Supabase bootstrap config + transport factory (anon key only).
export 'src/supabase_auth_bootstrap.dart';
export 'src/supabase_bootstrap_config.dart';
