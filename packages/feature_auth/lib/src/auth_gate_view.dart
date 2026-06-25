import 'package:flutter/widgets.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

import 'auth_state_views.dart';
import 'membership_picker_view.dart';

/// Renders an [AuthGateState] (from `auth_identity`) into the matching shared
/// auth UI (RF-108 Stage 3).
///
/// For the "ready" states ([AuthGateReady], [AuthGatePlatformAdminReady]) it
/// delegates to [onReady] - the app provides the real screen. Stage 3 has NO
/// Supabase session lifecycle and NO per-app wiring; this widget only renders +
/// is testable.
class AuthGateView extends StatelessWidget {
  const AuthGateView({
    required this.state,
    required this.onReady,
    this.onSignIn,
    this.onSignOut,
    this.onRetry,
    this.onSelectMembership,
    super.key,
  });

  /// The resolved gate state.
  final AuthGateState state;

  /// Builds the real app screen for a "ready" state (the app owns this).
  final Widget Function(BuildContext context, AuthGateState readyState) onReady;

  /// Proceed to sign-in (placeholder action in Stage 3).
  final VoidCallback? onSignIn;

  /// Sign the user out (clears session/selection - app-owned).
  final VoidCallback? onSignOut;

  /// Retry loading the auth context.
  final VoidCallback? onRetry;

  /// Called with the chosen membership id from the picker.
  final ValueChanged<String>? onSelectMembership;

  @override
  Widget build(BuildContext context) {
    final s = state;
    return switch (s) {
      AuthGateLoading() => const AuthLoadingView(),
      AuthGateUnauthenticated() => AuthSignInRequiredView(onContinue: onSignIn),
      AuthGateAuthDenied() => AuthDeniedView(
        onRetry: onRetry,
        onSignOut: onSignOut,
      ),
      AuthGateInvalidResponse() => AuthErrorView(onRetry: onRetry),
      AuthGateNoMemberships() => AuthNoAccessView(onSignOut: onSignOut),
      AuthGatePlatformAdminNoMemberships() => AuthPlatformAdminView(
        onSignOut: onSignOut,
      ),
      AuthGatePlatformAdminReady() => onReady(context, s),
      AuthGatePickerNeeded(:final memberships) => MembershipPickerView(
        memberships: memberships,
        onSelect: onSelectMembership ?? (_) {},
      ),
      AuthGateReady() => onReady(context, s),
      AuthGateWrongRole() => AuthWrongRoleView(onSignOut: onSignOut),
      AuthGateDeferredRole() => AuthDeferredRoleView(onSignOut: onSignOut),
    };
  }
}
