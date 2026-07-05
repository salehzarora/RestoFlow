/// RestoFlow feature_admin package — owner/manager Settings, Users/Roles, and
/// Devices provisioning UI (RF-113) over the RF-112 backend contracts (D-033 /
/// D-034).
///
/// Composes domain models, a client repository SEAM ([AdminRepository]), Riverpod
/// state, and a polished Material 3 dashboard surface. It adds NO backend. Today
/// the seam resolves to a clearly-labelled in-memory [DemoAdminStore] that mirrors
/// the RF-112 role-rank guard, the device lifecycle (approve = pending→paired,
/// activate = paired→active; pending→active forbidden; a session requires active),
/// and return-once secrets (enrollment code + session token shown exactly once).
/// The real RPC wiring is deferred to the auth/org-context bridge.
library;

// Models.
export 'src/models/admin_failure.dart';
export 'src/models/admin_scope.dart';
export 'src/models/admin_user.dart';
export 'src/models/device_models.dart';
export 'src/models/role_rank.dart';
export 'src/models/settings_models.dart';

// Data layer (the repository seam + demo store).
export 'src/data/admin_repository.dart';
export 'src/data/demo_admin_store.dart';

// State (Riverpod providers + the write controller + overrides).
export 'src/state/admin_providers.dart';
export 'src/state/device_pairing_panel.dart';

// UI (the three owner admin surfaces + reusable building blocks: the demo
// banner, the page header/section/state/pill primitives, and the failure/role
// label mappers — shared with the dashboard's Printers/Staff surfaces).
export 'src/screens/devices_screen.dart';
export 'src/screens/settings_screen.dart';
export 'src/screens/users_screen.dart';
export 'src/widgets/admin_common.dart'
    show
        AdminDemoBanner,
        AdminPageHeader,
        AdminPill,
        AdminSectionCard,
        AdminStateView,
        adminFailureMessage,
        adminRoleLabel;
