import 'package:flutter/widgets.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

import 'auth_context_fetcher.dart';
import 'auth_gate_host.dart';

/// The per-app entry switch (RF-108 Stage 4): renders the existing [demoHome] in
/// DEMO mode, or the auth gate ([AuthGateHost]) in auth mode.
///
/// The demo/auth choice comes from [authDemoModeEnabled] (`RESTOFLOW_DEMO_MODE`,
/// default true) unless [demoMode] overrides it (tests). In auth mode the real
/// context fetcher is built ONCE from the Stage 2 env config unless
/// [fetchContext] is injected (tests) - so widget tests never construct a real
/// Supabase client or hit the network. There is no in-code auth bypass.
class AuthGatedHome extends StatefulWidget {
  const AuthGatedHome({
    required this.surface,
    required this.demoHome,
    required this.onReady,
    this.demoMode,
    this.fetchContext,
    this.onSignOut,
    super.key,
  });

  final AppSurface surface;

  /// The existing in-memory demo entry screen for this app.
  final Widget demoHome;

  /// Builds the real app screen for a "ready" state.
  final Widget Function(BuildContext context, AuthGateState readyState) onReady;

  /// Overrides the demo-mode flag (tests). Null => read `RESTOFLOW_DEMO_MODE`.
  final bool? demoMode;

  /// Overrides the context fetcher (tests). Null => build from the env config.
  final AuthContextFetcher? fetchContext;

  final VoidCallback? onSignOut;

  @override
  State<AuthGatedHome> createState() => _AuthGatedHomeState();
}

class _AuthGatedHomeState extends State<AuthGatedHome> {
  late final bool _demo;
  AuthContextFetcher? _fetcher;

  @override
  void initState() {
    super.initState();
    _demo = widget.demoMode ?? authDemoModeEnabled();
    if (!_demo) {
      // Built ONCE (not per build): in real auth mode this constructs the
      // Supabase client; in tests an injected fetcher is used instead.
      _fetcher = widget.fetchContext ?? authContextFetcherFromEnvironment();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_demo) return widget.demoHome;
    return AuthGateHost(
      surface: widget.surface,
      fetchContext: _fetcher!,
      onReady: widget.onReady,
      onSignOut: widget.onSignOut,
    );
  }
}
