import 'package:restoflow_core/restoflow_core.dart';

import 'app_surface.dart';
import 'auth_failure.dart';
import 'membership_context.dart';
import 'membership_role.dart';
import 'membership_selection.dart';
import 'my_context.dart';
import 'role_entry_policy.dart';

/// The pure-Dart view-model the shared auth gate renders (RF-108 Stage 3).
///
/// A sealed set derived from the auth-context load result + the current
/// membership selection + the per-surface [RoleEntryPolicy]. It holds NO Flutter
/// types, so it is unit-testable with `dart test`; the widgets that render it
/// live in `packages/feature_auth`. There is no global role (D-004) and
/// platform-admin is a separate concept (D-026).
sealed class AuthGateState {
  const AuthGateState();
}

/// The auth context is still loading (no result yet).
class AuthGateLoading extends AuthGateState {
  const AuthGateLoading();
}

/// No authenticated session - the client must show sign-in.
class AuthGateUnauthenticated extends AuthGateState {
  const AuthGateUnauthenticated();
}

/// `get_my_context` was denied (SQLSTATE 42501: unauthenticated/unlinked/
/// inactive). The client must sign out and re-authenticate; never retry-loop.
class AuthGateAuthDenied extends AuthGateState {
  const AuthGateAuthDenied();
}

/// The backend response was malformed / a generic auth error occurred.
class AuthGateInvalidResponse extends AuthGateState {
  const AuthGateInvalidResponse();
}

/// The user has no active tenant memberships (and is not a platform admin).
class AuthGateNoMemberships extends AuthGateState {
  const AuthGateNoMemberships();
}

/// The user is a platform admin with no tenant membership for this surface
/// (D-026: no tenant scope is derived from the platform-admin flag).
class AuthGatePlatformAdminNoMemberships extends AuthGateState {
  const AuthGatePlatformAdminNoMemberships();
}

/// A platform admin entering the admin surface (gated ONLY by the platform-admin
/// flag, D-026; no tenant membership required or used).
class AuthGatePlatformAdminReady extends AuthGateState {
  const AuthGatePlatformAdminReady();
}

/// More than one membership and none is validly selected - show the picker.
class AuthGatePickerNeeded extends AuthGateState {
  const AuthGatePickerNeeded(this.memberships);

  /// The memberships to choose from (a LIST; never a single global role).
  final List<MembershipContext> memberships;
}

/// A membership is selected and its role may enter this surface. The app renders
/// its real screen scoped to [membership].
class AuthGateReady extends AuthGateState {
  const AuthGateReady(this.membership);

  /// The active membership (carries org/restaurant/branch scope + role).
  final MembershipContext membership;
}

/// The active role cannot use this surface (or a non-platform-admin opened the
/// admin surface, in which case [role] is null).
class AuthGateWrongRole extends AuthGateState {
  const AuthGateWrongRole(this.role);

  /// The denied role, or null when the surface is admin and the caller is not a
  /// platform admin.
  final MembershipRole? role;
}

/// A known but DEFERRED role for RF-108 (currently `accountant`, Q-017): a
/// "coming soon" state - never a crash, never a silent grant.
class AuthGateDeferredRole extends AuthGateState {
  const AuthGateDeferredRole(this.role);

  /// The deferred role.
  final MembershipRole role;
}

/// Resolves the [AuthGateState] for [surface] from the auth-context load result.
///
/// [contextResult] is the result of calling `get_my_context`, or `null` while it
/// is still loading. [selectedMembershipId] is the user's chosen membership (for
/// multi-membership). The decision is fail-closed: a denied/invalid result or an
/// unknown/unsupported role never grants entry.
AuthGateState resolveAuthGateState({
  required AppSurface surface,
  required Result<MyContext, AuthFailure>? contextResult,
  String? selectedMembershipId,
  RoleEntryPolicy policy = const RoleEntryPolicy(),
}) {
  if (contextResult == null) return const AuthGateLoading();

  return contextResult.fold(
    (context) => _resolveLoaded(
      surface: surface,
      context: context,
      selectedMembershipId: selectedMembershipId,
      policy: policy,
    ),
    _mapFailure,
  );
}

AuthGateState _mapFailure(AuthFailure failure) => switch (failure) {
  AuthUnauthenticatedFailure() => const AuthGateUnauthenticated(),
  AuthDeniedFailure() => const AuthGateAuthDenied(),
  // Everything else (malformed response, unknown role from the backend, network,
  // unexpected PIN failures, unclassified) is a generic backend/auth error.
  AuthInvalidResponseFailure() ||
  AuthUnknownRoleFailure() ||
  AuthWrongPinFailure() ||
  AuthLockedOrPreconditionFailure() ||
  AuthNetworkFailure() ||
  AuthUnknownFailure() => const AuthGateInvalidResponse(),
};

AuthGateState _resolveLoaded({
  required AppSurface surface,
  required MyContext context,
  required String? selectedMembershipId,
  required RoleEntryPolicy policy,
}) {
  // The admin surface is gated ONLY by the platform-admin flag (D-026);
  // memberships are irrelevant there.
  if (surface == AppSurface.admin) {
    return context.isPlatformAdmin
        ? const AuthGatePlatformAdminReady()
        : const AuthGateWrongRole(null);
  }

  // Tenant surfaces (pos/kds/dashboard) need a selected membership.
  final selection = MembershipSelection.fromContext(
    context,
    selectedMembershipId: selectedMembershipId,
  );
  switch (selection.status) {
    case MembershipSelectionStatus.noMemberships:
      return const AuthGateNoMemberships();
    case MembershipSelectionStatus.platformAdminNoMemberships:
      return const AuthGatePlatformAdminNoMemberships();
    case MembershipSelectionStatus.pickerNeeded:
      return AuthGatePickerNeeded(context.memberships);
    case MembershipSelectionStatus.autoSelected:
    case MembershipSelectionStatus.selected:
      final membership = selection.activeMembership!;
      final decision = policy.evaluate(
        surface: surface,
        role: membership.role,
        isPlatformAdmin: context.isPlatformAdmin,
      );
      return switch (decision) {
        EntryDecision.allowed => AuthGateReady(membership),
        EntryDecision.denied => AuthGateWrongRole(membership.role),
        EntryDecision.deferred => AuthGateDeferredRole(membership.role),
      };
  }
}
