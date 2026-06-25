import 'package:flutter/widgets.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';

import 'auth_context_fetcher.dart';
import 'auth_gate_view.dart';

/// Drives the shared auth gate for one app surface (RF-108 Stage 4).
///
/// On mount it calls [fetchContext] (`get_my_context` through the Stage 2
/// transport, or an injected fake in tests), holds the result + the selected
/// membership, resolves the [AuthGateState] via `resolveAuthGateState`, and
/// renders [AuthGateView]. No Supabase session lifecycle and no real PIN-entry
/// UX here (deferred). It is a plain StatefulWidget (no Riverpod) so it stays
/// testable with an injected fetcher and never makes a network call in tests.
class AuthGateHost extends StatefulWidget {
  const AuthGateHost({
    required this.surface,
    required this.fetchContext,
    required this.onReady,
    this.onSignOut,
    super.key,
  });

  final AppSurface surface;

  /// Loads the caller's context (server-derived identity; no user id input).
  final AuthContextFetcher fetchContext;

  /// Builds the real app screen for a "ready" state (the app owns this).
  final Widget Function(BuildContext context, AuthGateState readyState) onReady;

  /// Signs out / clears sensitive state (app-owned).
  final VoidCallback? onSignOut;

  @override
  State<AuthGateHost> createState() => _AuthGateHostState();
}

class _AuthGateHostState extends State<AuthGateHost> {
  Result<MyContext, AuthFailure>? _result; // null = loading
  String? _selectedMembershipId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _result = null);
    final result = await widget.fetchContext();
    if (!mounted) return;
    setState(() {
      _result = result;
      _selectedMembershipId = null; // reset any stale selection on (re)load
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = resolveAuthGateState(
      surface: widget.surface,
      contextResult: _result,
      selectedMembershipId: _selectedMembershipId,
    );
    return AuthGateView(
      state: state,
      onReady: widget.onReady,
      onRetry: _load,
      // Stage 4 placeholder: real GoTrue email/password sign-in is deferred;
      // "continue" simply re-attempts the context load.
      onSignIn: _load,
      onSignOut: widget.onSignOut,
      onSelectMembership: (id) => setState(() => _selectedMembershipId = id),
    );
  }
}
