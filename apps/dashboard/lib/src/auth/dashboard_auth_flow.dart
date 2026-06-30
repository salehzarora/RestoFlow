import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'dashboard_auth_repository.dart';
import 'login_signup_screen.dart';
import 'onboarding_repository.dart';
import 'onboarding_screen.dart';

/// The dashboard real-mode entry (RF-151): a session layer (login / sign-up) in
/// front of the RF-108 membership gate, with onboarding for an authenticated
/// owner who has no organization yet.
///
/// Order of resolution (real mode only — demo mode never reaches here):
///  1. no session            -> [LoginSignupScreen]
///  2. session, no org       -> [OnboardingScreen] (NoMemberships / AuthDenied)
///  3. session + membership  -> [onReady] (the real dashboard, scoped)
///  4. wrong role / deferred -> the shared RF-108 state views (+ sign out)
///
/// Fail-closed: it only renders the dashboard for a resolved, role-allowed
/// membership; a missing session, a denied context, or a missing org never shows
/// real dashboard data. When [authRepository] is null the session layer is skipped
/// (the legacy RF-108 role-gate tests inject only a context fetcher); the
/// production composition root ALWAYS injects a real repository.
class DashboardAuthFlow extends StatefulWidget {
  const DashboardAuthFlow({
    required this.fetchContext,
    required this.onReady,
    this.authRepository,
    this.onboardingRepository,
    super.key,
  });

  /// Loads `get_my_context` for the authenticated principal.
  final AuthContextFetcher fetchContext;

  /// Builds the real dashboard for a resolved, role-allowed membership.
  final Widget Function(BuildContext context, MembershipContext membership)
  onReady;

  /// The real-auth seam (null => assume signed in; legacy role-gate tests).
  final DashboardAuthRepository? authRepository;

  /// The onboarding seam (null => onboarding shows a safe error).
  final OnboardingRepository? onboardingRepository;

  @override
  State<DashboardAuthFlow> createState() => _DashboardAuthFlowState();
}

class _DashboardAuthFlowState extends State<DashboardAuthFlow> {
  late AuthSessionStatus _status;
  StreamSubscription<AuthSessionStatus>? _sub;

  Result<MyContext, AuthFailure>? _contextResult; // null = loading
  String? _selectedMembershipId;

  // Captured from a sign-up-with-session so onboarding can pre-fill them.
  String? _pendingRestaurantName;
  String? _pendingBranchName;

  @override
  void initState() {
    super.initState();
    final repo = widget.authRepository;
    if (repo == null) {
      _status = AuthSessionStatus.signedIn;
      _loadContext();
    } else {
      _status = repo.status;
      _sub = repo.statusChanges.listen(_onStatusChanged);
      if (_status == AuthSessionStatus.signedIn) _loadContext();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onStatusChanged(AuthSessionStatus status) {
    if (!mounted) return;
    setState(() {
      _status = status;
      if (status == AuthSessionStatus.signedIn) {
        _loadContext();
      } else {
        _contextResult = null;
        _selectedMembershipId = null;
        _pendingRestaurantName = null;
        _pendingBranchName = null;
      }
    });
  }

  Future<void> _loadContext() async {
    setState(() => _contextResult = null);
    final result = await widget.fetchContext();
    if (!mounted) return;
    setState(() {
      _contextResult = result;
      _selectedMembershipId = null;
    });
  }

  Future<void> _signOut() async {
    await widget.authRepository?.signOut();
    // The session stream drives the transition back to the login screen.
  }

  void _onSignedUpWithSession(String restaurantName, String? branchName) {
    setState(() {
      _pendingRestaurantName = restaurantName;
      _pendingBranchName = branchName;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case AuthSessionStatus.unknown:
        return const AuthLoadingView();
      case AuthSessionStatus.signedOut:
        return LoginSignupScreen(
          authRepository: widget.authRepository!,
          onSignedUpWithSession: _onSignedUpWithSession,
        );
      case AuthSessionStatus.signedIn:
        return _signedInGate(context);
    }
  }

  Widget _signedInGate(BuildContext context) {
    final state = resolveAuthGateState(
      surface: AppSurface.dashboard,
      contextResult: _contextResult,
      selectedMembershipId: _selectedMembershipId,
    );
    return switch (state) {
      AuthGateLoading() => const AuthLoadingView(),
      AuthGateReady(:final membership) => widget.onReady(context, membership),
      // No organization yet (fresh sign-up is AuthDenied until create_organization
      // bootstraps the app_user; an existing user with no org is NoMemberships).
      AuthGateNoMemberships() ||
      AuthGatePlatformAdminNoMemberships() ||
      AuthGateAuthDenied() ||
      AuthGatePlatformAdminReady() => _onboarding(),
      AuthGatePickerNeeded(:final memberships) => MembershipPickerView(
        memberships: memberships,
        onSelect: (id) => setState(() => _selectedMembershipId = id),
      ),
      AuthGateWrongRole() => AuthWrongRoleView(onSignOut: _signOutAction),
      AuthGateDeferredRole() => AuthDeferredRoleView(onSignOut: _signOutAction),
      AuthGateInvalidResponse() => AuthErrorView(onRetry: _loadContext),
      // Session present but context is unauthenticated (e.g. expired token): let
      // the user retry or sign out — never silently bypass.
      AuthGateUnauthenticated() => AuthDeniedView(
        onRetry: _loadContext,
        onSignOut: _signOutAction,
      ),
    };
  }

  /// Sign-out callback, or null when there is no auth repository (legacy tests).
  VoidCallback? get _signOutAction =>
      widget.authRepository == null ? null : _signOut;

  Widget _onboarding() {
    final repo = widget.onboardingRepository;
    if (repo == null) {
      // No onboarding seam wired — honest error rather than a fake success.
      return AuthErrorView(onRetry: _loadContext);
    }
    return OnboardingScreen(
      onboardingRepository: repo,
      initialRestaurantName: _pendingRestaurantName,
      initialBranchName: _pendingBranchName,
      onCreated: _loadContext,
      onSignOut: _signOutAction,
    );
  }
}
