/// RestoFlow feature_auth package - the shared auth-gate UI (RF-108 Stage 3).
///
/// Renders the pure-Dart [AuthGateState] (from `restoflow_auth_identity`) into
/// localized states + a membership picker, reusing `restoflow_l10n` (ar/he/en +
/// RTL) and `restoflow_design_system` (theme/tokens). NO per-app wiring and NO
/// Supabase session lifecycle live here (that is the app layer / a later stage).
library;

export 'src/auth_context_fetcher.dart';
export 'src/auth_gate_host.dart';
export 'src/auth_redirect.dart';
export 'src/device_pairing_screen.dart';
export 'src/device_sign_in_unavailable_view.dart';
export 'src/flutter_secure_device_session_store.dart';
export 'src/pairing_code_link.dart';
export 'src/shared_preferences_device_session_store.dart';
export 'src/supabase_device_pairing_repository.dart';
// Device settings sprint: the token-proven per-device printer read + the
// shared settings-sheet printers section (honest capability statuses).
export 'src/device_printer_assignments_section.dart';
// RF-115: the shared print-bridge status view-model rendered in the section.
export 'src/print_bridge_status.dart';
export 'src/supabase_device_printer_assignments_repository.dart';
// KITCHEN-MODE-001C2B: device-token kitchen clients (mode / dispatch pull /
// import-acknowledgement). Production dispatch importing stays impossible
// until 001C3 (no mode revision on the getter + no readiness reporting).
export 'src/kitchen_dispatch_ack_repository.dart';
export 'src/kitchen_dispatch_pull_repository.dart';
export 'src/kitchen_mode_repository.dart';
export 'src/supabase_device_shift_close_policy_repository.dart';
// RF-117: the token-proven per-branch tax-setting read (BranchTax over the
// device transport; default-OFF fail-soft).
export 'src/supabase_device_branch_tax_repository.dart';
export 'src/auth_gate_view.dart';
export 'src/auth_gated_home.dart';
export 'src/auth_state_views.dart';
export 'src/membership_picker_view.dart';
export 'src/pin_login_screen.dart';
// RF-118: durable (shared_preferences) client PIN-attempt lockout store.
export 'src/shared_preferences_pin_attempt_store.dart';
export 'src/real_mode_unconfigured_view.dart';
// PILOT-OFFLINE-BOOT-001: the retryable device-auth boot gate + the friendly
// offline "no connection" screen (POS/KDS launch resilience).
export 'src/device_boot_gate.dart';
export 'src/offline_boot_view.dart';
export 'src/real_repo_not_wired.dart';
export 'src/supabase_device_staff_repository.dart';
export 'src/role_label.dart';
export 'src/runtime_config.dart';
