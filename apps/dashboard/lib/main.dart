import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:supabase/supabase.dart';

import 'src/auth/dashboard_auth_flow.dart';
import 'src/auth/dashboard_auth_repository.dart';
import 'src/auth/onboarding_repository.dart';
import 'src/auth/supabase_dashboard_auth.dart';
import 'src/dashboard_shell.dart';

/// Composition root (RF-151). In DEMO mode (`RESTOFLOW_DEMO_MODE` default true)
/// the app renders the existing in-memory demo shell. In REAL mode it builds ONE
/// anon-key [SupabaseClient] (DECISION D-011 — no service-role key) and wires the
/// real auth + onboarding flow; a missing/invalid config fails closed to an honest
/// "unconfigured" state (never a crash, never a fake-live screen).
void main() {
  final config = RuntimeConfig.fromEnvironment();
  if (config.isDemoMode) {
    runApp(const ProviderScope(child: DashboardApp(demoMode: true)));
    return;
  }

  final supabase = config.supabase;
  if (supabase == null) {
    // Real mode but the anon-key config is missing/invalid/service-role: an honest
    // unconfigured state. Real* repos never contact a backend without valid config.
    runApp(
      const ProviderScope(
        child: DashboardApp(demoMode: false, realModeUnconfigured: true),
      ),
    );
    return;
  }

  final client = SupabaseClient(supabase.url, supabase.anonKey);
  final real = buildDashboardRealAuth(client);
  runApp(
    ProviderScope(
      child: DashboardApp(
        demoMode: false,
        authRepository: real.auth,
        onboardingRepository: real.onboarding,
        fetchContext: real.fetchContext,
      ),
    ),
  );
}

/// RestoFlow owner/manager dashboard app (RF-104 / RF-108 / RF-151).
///
/// DEMO mode renders the existing in-memory [DashboardShell]. REAL mode routes
/// through [DashboardAuthFlow]: sign in / sign up -> restaurant onboarding ->
/// the role-gated real dashboard. Money is integer minor units (DECISION D-007).
class DashboardApp extends StatelessWidget {
  const DashboardApp({
    this.demoMode,
    this.fetchContext,
    this.authRepository,
    this.onboardingRepository,
    this.realModeUnconfigured = false,
    super.key,
  });

  /// Test-only override of the demo/real mode (null => `RESTOFLOW_DEMO_MODE`).
  final bool? demoMode;

  /// The `get_my_context` fetcher (real impl in production; a fake in tests).
  final AuthContextFetcher? fetchContext;

  /// The real-auth seam (null => legacy role-gate path assumes a session).
  final DashboardAuthRepository? authRepository;

  /// The onboarding seam.
  final OnboardingRepository? onboardingRepository;

  /// True in real mode when the Supabase anon-key config was missing/invalid.
  final bool realModeUnconfigured;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) =>
          AppLocalizations.of(context).dashboardAppTitle,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      localeResolutionCallback: restoflowResolveLocale,
      debugShowCheckedModeBanner: false,
      theme: restoflowBaseTheme(),
      home: _home(),
    );
  }

  Widget _home() {
    final demo = demoMode ?? authDemoModeEnabled();
    if (demo) return const DashboardShell();
    if (realModeUnconfigured || fetchContext == null) {
      // Real mode without a usable context fetcher: honest generic error state
      // (mirrors the prior real-mode-unconfigured behaviour).
      return const Scaffold(body: AuthErrorView());
    }
    return DashboardAuthFlow(
      authRepository: authRepository,
      onboardingRepository: onboardingRepository,
      fetchContext: fetchContext!,
      onReady: (context, membership) => DashboardShell(membership: membership),
    );
  }
}
