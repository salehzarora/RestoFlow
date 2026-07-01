import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../context/device_context.dart';
import '../context/selected_context_store.dart';
import 'dashboard_auth_repository.dart';
import 'login_signup_screen.dart';
import 'onboarding_repository.dart';
import 'onboarding_screen.dart';

/// The dashboard real-mode entry (RF-151 + RF-152): a session layer (login /
/// sign-up) in front of the RF-108 membership gate, with onboarding for an owner
/// who has no organization yet, and a persisted-but-VALIDATED selected
/// organization/branch context.
///
/// Order of resolution (real mode only — demo mode never reaches here):
///  1. no session            -> [LoginSignupScreen]
///  2. session, no org       -> [OnboardingScreen] (NoMemberships / AuthDenied)
///  3. session + 1 org       -> auto-selected -> [onReady] (the real dashboard)
///  4. session + many orgs   -> [MembershipPickerView] (persisted on pick)
///  5. wrong role / deferred -> the shared RF-108 state views (+ sign out)
///
/// RF-152 additions: on load the persisted selected membership id is RE-VALIDATED
/// against the live memberships and cleared if it is no longer allowed
/// (fail-closed — never shows a scope the user may not access). Sign-out clears
/// ALL session-derived context (selected org/branch + the device context).
/// Session persistence itself is provided by the official Supabase/Flutter
/// mechanism at the composition root (`main`), not here.
///
/// Fail-closed: it only renders the dashboard for a resolved, role-allowed
/// membership. When [authRepository] is null the session layer is skipped (the
/// legacy RF-108 role-gate tests inject only a context fetcher); production always
/// injects a real repository.
class DashboardAuthFlow extends StatefulWidget {
  const DashboardAuthFlow({
    required this.fetchContext,
    required this.onReady,
    this.authRepository,
    this.onboardingRepository,
    this.selectedContextStore,
    this.deviceContext,
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

  /// Persists/restores the selected membership (RF-152). Null => in-memory.
  final SelectedContextStore? selectedContextStore;

  /// The org/branch-scoped device context, cleared on sign-out (RF-152
  /// foundation). Null => an internal controller (absent by default).
  final DeviceContextController? deviceContext;

  @override
  State<DashboardAuthFlow> createState() => _DashboardAuthFlowState();
}

class _DashboardAuthFlowState extends State<DashboardAuthFlow> {
  late final SelectedContextStore _store;
  late final DeviceContextController _deviceContext;
  late AuthSessionStatus _status;
  StreamSubscription<AuthSessionStatus>? _sub;

  Result<MyContext, AuthFailure>? _contextResult; // null = loading
  String? _selectedMembershipId;

  String? _pendingRestaurantName;
  String? _pendingBranchName;

  @override
  void initState() {
    super.initState();
    _store = widget.selectedContextStore ?? InMemorySelectedContextStore();
    _deviceContext = widget.deviceContext ?? DeviceContextController();
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
    // Only dispose a controller WE created; an injected one is caller-owned.
    if (widget.deviceContext == null) _deviceContext.dispose();
    super.dispose();
  }

  void _onStatusChanged(AuthSessionStatus status) {
    if (!mounted) return;
    if (status == AuthSessionStatus.signedIn) {
      setState(() => _status = status);
      _loadContext();
    } else {
      // Signed out / session lost: clear ALL session-derived context.
      unawaited(_store.clear());
      _deviceContext.clear();
      setState(() {
        _status = status;
        _contextResult = null;
        _selectedMembershipId = null;
        _pendingRestaurantName = null;
        _pendingBranchName = null;
      });
    }
  }

  Future<void> _loadContext() async {
    setState(() => _contextResult = null);
    final result = await widget.fetchContext();
    if (!mounted) return;
    // Restore the persisted selection and RE-VALIDATE it against the live
    // memberships (fail-closed): a stale/unknown id is dropped so the user lands
    // on the picker instead of a scope they may no longer access.
    final restored = await _restoreValidatedSelection(result);
    if (!mounted) return;
    setState(() {
      _contextResult = result;
      _selectedMembershipId = restored;
    });
  }

  Future<String?> _restoreValidatedSelection(
    Result<MyContext, AuthFailure> result,
  ) async {
    final saved = await _store.readSelectedMembershipId();
    if (saved == null) return null;
    final memberships = switch (result) {
      Success<MyContext, AuthFailure>(:final value) => value.memberships,
      Failure<MyContext, AuthFailure>() => const <MembershipContext>[],
    };
    if (memberships.any((m) => m.id == saved)) return saved;
    await _store.clear(); // no longer allowed -> drop it.
    return null;
  }

  void _select(String membershipId) {
    unawaited(_store.writeSelectedMembershipId(membershipId));
    setState(() => _selectedMembershipId = membershipId);
  }

  Future<void> _signOut() async {
    await widget.authRepository?.signOut();
    // The session stream drives the transition + context clearing.
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
        onSelect: _select,
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
