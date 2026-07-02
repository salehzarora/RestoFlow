import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminRepository, AdminScope;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/auth/dashboard_auth_flow.dart';
import 'src/auth/dashboard_auth_repository.dart';
import 'src/auth/onboarding_repository.dart';
import 'src/auth/supabase_dashboard_auth.dart';
import 'src/context/device_context.dart';
import 'src/context/selected_context_store.dart';
import 'src/dashboard_shell.dart';

/// Composition root (RF-151 + RF-152). In DEMO mode (`RESTOFLOW_DEMO_MODE`
/// default true) the app renders the existing in-memory demo shell. In REAL mode
/// it initializes the OFFICIAL Supabase/Flutter session persistence (survives
/// browser refresh / app restart; anon key only — DECISION D-011, no service-role
/// key) and wires the real auth + onboarding + selected-context flow; a
/// missing/invalid config fails closed to an honest "unconfigured" state.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  // Official session persistence: Supabase.initialize restores any saved session
  // at startup and auto-refreshes it, so a signed-in owner stays signed in across
  // a refresh/restart. The SAME anon-key client carries the session into the
  // public.* RPC calls (identity server-derived from auth.uid()).
  // `publishableKey` is the current name for the PUBLIC anon key (the config
  // already rejects any service-role/secret key — DECISION D-011).
  await Supabase.initialize(
    url: supabase.url,
    publishableKey: supabase.anonKey,
  );
  final real = buildDashboardRealAuth(Supabase.instance.client);
  runApp(
    ProviderScope(
      child: DashboardApp(
        demoMode: false,
        authRepository: real.auth,
        onboardingRepository: real.onboarding,
        fetchContext: real.fetchContext,
        deviceRepositoryFor: real.deviceRepositoryFor,
        selectedContextStore: SharedPreferencesSelectedContextStore(),
      ),
    ),
  );
}

/// RestoFlow owner/manager dashboard app (RF-104 / RF-108 / RF-151 / RF-152).
///
/// DEMO mode renders the existing in-memory [DashboardShell]. REAL mode routes
/// through [DashboardAuthFlow]: sign in / sign up -> restaurant onboarding ->
/// (validated) org/branch selection -> the role-gated real dashboard. Money is
/// integer minor units (DECISION D-007).
class DashboardApp extends StatelessWidget {
  const DashboardApp({
    this.demoMode,
    this.fetchContext,
    this.authRepository,
    this.onboardingRepository,
    this.selectedContextStore,
    this.deviceContext,
    this.deviceRepositoryFor,
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

  /// Persists/restores the selected membership (RF-152). Null => in-memory.
  final SelectedContextStore? selectedContextStore;

  /// The device/station context holder (RF-152 foundation). Null => internal.
  final DeviceContextController? deviceContext;

  /// Builds the REAL device repository for a given admin scope (RF-160). Non-null
  /// only in authenticated real mode; the dashboard Devices tab uses it there and
  /// falls back to the demo store otherwise (demo default preserved).
  final AdminRepository Function(AdminScope scope)? deviceRepositoryFor;

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
      selectedContextStore: selectedContextStore,
      deviceContext: deviceContext,
      onReady: (context, membership) => DashboardShell(
        membership: membership,
        deviceRepositoryFor: deviceRepositoryFor,
      ),
    );
  }
}
