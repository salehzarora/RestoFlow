import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show AuthContextFetcher;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../admin_platform_gate.dart' show AdminGateExplainer;
import '../platform_admin_screen.dart';
import '../widgets/language_selector.dart';
import 'admin_auth.dart';
import 'admin_mfa_screen.dart';
import 'admin_sign_in_screen.dart';

/// RF-119-b — the Admin app's real-mode entry orchestrator. It composes the
/// honest platform-operator flow on top of the RF-119 server enforcement:
///
///   no GoTrue session            -> [AdminSignInScreen]
///   session, get_my_context ...
///     not a platform admin        -> [AdminGateExplainer] (this is the platform
///                                    panel; sign out to try another account)
///     platform admin + aal2       -> [PlatformAdminScreen] (the overview)
///     platform admin + NO aal2    -> [AdminMfaScreen] (enrol or challenge TOTP)
///
/// After a successful TOTP verify the client holds an aal2 session; the flow
/// RE-FETCHES `get_my_context`, so the overview is entered ONLY when the SERVER
/// (`is_mfa_aal2`, backed by `app.platform_admin_guard`) confirms aal2 — never on
/// this client's own state. Sign-in/out are detected via the auth session stream.
/// The gate weakens NOTHING: every platform read is still grant + aal2 + reason
/// gated server-side; the client assurance is UX only.
class AdminAuthFlow extends StatefulWidget {
  const AdminAuthFlow({
    required this.authService,
    required this.fetchContext,
    super.key,
  });

  final AdminAuthService authService;
  final AuthContextFetcher fetchContext;

  @override
  State<AdminAuthFlow> createState() => _AdminAuthFlowState();
}

class _AdminAuthFlowState extends State<AdminAuthFlow> {
  late bool _hasSession = widget.authService.hasSession;
  StreamSubscription<bool>? _sub;
  Future<Result<MyContext, AuthFailure>>? _contextFuture;

  @override
  void initState() {
    super.initState();
    if (_hasSession) _contextFuture = widget.fetchContext();
    _sub = widget.authService.sessionChanges.listen(_onSessionChanged);
  }

  void _onSessionChanged(bool hasSession) {
    // Only act on a genuine sign-in/out TRANSITION. GoTrue emits many events
    // (tokenRefreshed, userUpdated, mfaChallengeVerified, ...) that all carry a
    // session; re-fetching context on each would needlessly reload — and could
    // bounce a working operator to the explainer/error on a transient failure.
    if (!mounted || hasSession == _hasSession) return;
    setState(() {
      _hasSession = hasSession;
      // A new session -> resolve its context; a sign-out -> back to sign-in.
      _contextFuture = hasSession ? widget.fetchContext() : null;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Re-fetch `get_my_context` (after an MFA verify or a retry) so entry is gated
  /// on the fresh SERVER-derived assurance.
  void _reloadContext() {
    if (!mounted) return;
    // Block body (not `=>`): the setState callback must return void, not the
    // Future that assigning `widget.fetchContext()` would yield.
    setState(() {
      _contextFuture = widget.fetchContext();
    });
  }

  Future<void> _signOut() async {
    await widget.authService.signOut();
    // The auth stream normally flips _hasSession to false; sync defensively in
    // case a (fake) service does not emit, so the flow always returns to sign-in.
    if (mounted && !widget.authService.hasSession) _onSessionChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!_hasSession) {
      // A successful sign-in flips the session stream -> the context resolves.
      return AdminSignInScreen(authService: widget.authService);
    }
    final future = _contextFuture ??= widget.fetchContext();
    return FutureBuilder<Result<MyContext, AuthFailure>>(
      future: future,
      builder: (context, snap) {
        // Show the spinner whenever the fetch is IN FLIGHT — including a re-fetch
        // (after an MFA verify or retry). FutureBuilder retains the previous
        // snapshot's `.data` when the future object changes, so a plain
        // `!snap.hasData` check would re-fold STALE context and reuse the old MFA
        // screen; gate on connectionState so a fresh result rebuilds cleanly.
        if (snap.connectionState != ConnectionState.done || !snap.hasData) {
          return _scaffold(
            l10n,
            RestoflowStateView(
              showSpinner: true,
              title: l10n.authLoadingAccount,
            ),
          );
        }
        return snap.data!.fold(
          (ctx) => switch ((ctx.isPlatformAdmin, ctx.hasMfaAal2)) {
            // Active grant + an MFA (aal2) session: the overview. Reads still
            // enforce grant + aal2 + reason server-side (RF-091).
            (true, true) => PlatformAdminScreen(onSignOut: _signOut),
            // Active grant but NO aal2: the interactive TOTP enrol/challenge.
            (true, false) => AdminMfaScreen(
              authService: widget.authService,
              onVerified: _reloadContext,
              onSignOut: _signOut,
            ),
            // Signed in but not a platform admin (e.g. a restaurant owner).
            (false, _) => AdminGateExplainer(
              signedIn: true,
              onRetry: _reloadContext,
              onSignOut: _signOut,
            ),
          },
          (failure) => switch (failure) {
            // Signed in, but the principal is not a linked/active app_user -> it is
            // not a platform admin here. Explain + allow sign-out (try another).
            AuthDeniedFailure() ||
            AuthUnauthenticatedFailure() => AdminGateExplainer(
              signedIn: true,
              onRetry: _reloadContext,
              onSignOut: _signOut,
            ),
            // Transport/config/parse problems: an honest, retryable error.
            _ => _scaffold(
              l10n,
              RestoflowStateView(
                icon: Icons.error_outline,
                tone: RestoflowTone.danger,
                title: l10n.authError,
                actions: [
                  FilledButton.tonal(
                    onPressed: _reloadContext,
                    child: Text(l10n.authTryAgain),
                  ),
                ],
              ),
            ),
          },
        );
      },
    );
  }

  Widget _scaffold(AppLocalizations l10n, Widget child) => Scaffold(
    appBar: AppBar(
      title: Text(l10n.adminAppTitle),
      actions: const [LanguageSelector()],
    ),
    body: SafeArea(child: child),
  );
}
