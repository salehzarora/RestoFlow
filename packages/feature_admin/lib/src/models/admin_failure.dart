import 'package:restoflow_core/restoflow_core.dart';

/// A typed admin operation failure (no exceptions across the layer boundary).
/// Mirrors the RF-112 error envelope: `permission_denied` (role/rank denied),
/// validation (`42501` structural/validation), conflict (state/idempotency),
/// not-found, and a transient transport class.
sealed class AdminFailure {
  const AdminFailure();
}

/// The caller is a member in scope but lacks the role/rank — RF-112 returns
/// `{ok:false, error:'permission_denied'}` (and audits the denial).
class AdminPermissionDenied extends AdminFailure {
  const AdminPermissionDenied([this.reason]);

  /// An optional machine reason key (e.g. `role_rank`, `self_grant`) for messaging.
  final String? reason;
}

/// Structural / validation rejection (RF-112 raises `42501`): bad input, bad
/// scope, a forbidden lifecycle transition, etc. Carries a human message.
class AdminValidation extends AdminFailure {
  const AdminValidation(this.message);
  final String message;
}

/// A conflict — e.g. a non-`paired` pairing cannot be activated, an already-active
/// pairing, or a duplicate. Carries a human message.
class AdminConflict extends AdminFailure {
  const AdminConflict(this.message);
  final String message;
}

/// The target row was not found in the active scope.
class AdminNotFound extends AdminFailure {
  const AdminNotFound();
}

/// A transient transport problem (retryable). Demo store never returns this; it
/// exists so the UI has a clear retry path once the real RPC wiring lands.
class AdminTransient extends AdminFailure {
  const AdminTransient();
}

/// The repository result alias used across the admin feature.
typedef AdminResult<T> = Result<T, AdminFailure>;
