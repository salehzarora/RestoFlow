import 'menu_entity_type.dart';

/// A typed failure from an RF-109 menu write (RF-111).
///
/// The RF-109 RPCs have TWO distinct failure surfaces, and the client must keep
/// them apart (the existing `classifyPostgrestCode` collapses every `42501` to
/// "auth", which would wrongly show validation errors as "access denied"):
///
///  * a member who lacks the write role gets a RETURNED envelope
///    `{ok:false, error:'permission_denied'}` -> [MenuPermissionDenied];
///  * every other failure (validation, scope/cross-org, immutable-scope,
///    not-found, unauthenticated/no-membership) is RAISED as SQLSTATE `42501`
///    with a descriptive message -> [MenuValidationRejected] (message shown).
sealed class MenuWriteFailure {
  const MenuWriteFailure();
}

/// The principal is a member of the scope but lacks a write role
/// (`org_owner` / `restaurant_owner` / `manager`). Returned envelope, not raised.
class MenuPermissionDenied extends MenuWriteFailure {
  const MenuPermissionDenied(this.entity);

  final MenuEntityType entity;
}

/// The server RAISED `42501` with a descriptive [message] — a validation,
/// scope/cross-org, immutable-scope, or not-found rejection. The message is a
/// rule description (not PII/secret) and is safe to surface to the operator.
class MenuValidationRejected extends MenuWriteFailure {
  const MenuValidationRejected(this.message);

  final String message;
}

/// A transient transport problem (network / timeout / throttle) — retryable.
class MenuTransientFailure extends MenuWriteFailure {
  const MenuTransientFailure([this.message]);

  final String? message;
}

/// A non-transient server-side error.
class MenuServerFailure extends MenuWriteFailure {
  const MenuServerFailure([this.message]);

  final String? message;
}

/// The RPC returned an unexpected / malformed body.
class MenuInvalidResponseFailure extends MenuWriteFailure {
  const MenuInvalidResponseFailure();
}
