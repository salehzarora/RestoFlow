/// RestoFlow feature_auth package - the shared auth-gate UI (RF-108 Stage 3).
///
/// Renders the pure-Dart [AuthGateState] (from `restoflow_auth_identity`) into
/// localized states + a membership picker, reusing `restoflow_l10n` (ar/he/en +
/// RTL) and `restoflow_design_system` (theme/tokens). NO per-app wiring and NO
/// Supabase session lifecycle live here (that is the app layer / a later stage).
library;

export 'src/auth_context_fetcher.dart';
export 'src/auth_gate_host.dart';
export 'src/device_pairing_screen.dart';
export 'src/flutter_secure_device_session_store.dart';
export 'src/auth_gate_view.dart';
export 'src/auth_gated_home.dart';
export 'src/auth_state_views.dart';
export 'src/membership_picker_view.dart';
export 'src/real_repo_not_wired.dart';
export 'src/role_label.dart';
export 'src/runtime_config.dart';
