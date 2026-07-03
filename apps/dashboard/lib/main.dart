import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport;
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminRepository, AdminScope;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart'
    show MenuImageStorage, MenuReadSource, MenuWriter;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/auth/dashboard_auth_flow.dart';
import 'src/auth/dashboard_auth_repository.dart';
import 'src/auth/onboarding_repository.dart';
import 'src/auth/supabase_dashboard_auth.dart';
import 'src/context/device_context.dart';
import 'src/context/selected_context_store.dart';
import 'src/context/tenant_context_resolver.dart';
import 'src/dashboard_shell.dart';
import 'src/printers/printers_repository.dart';
import 'src/staff/staff_repository.dart';
import 'src/state/locale_controller.dart';
import 'src/tables/tables_repository.dart';

/// Composition root (RF-151 + RF-152). In DEMO mode (`RESTOFLOW_DEMO_MODE`
/// default true) the app renders the existing in-memory demo shell. In REAL mode
/// it initializes the OFFICIAL Supabase/Flutter session persistence (survives
/// browser refresh / app restart; anon key only — DECISION D-011, no service-role
/// key) and wires the real auth + onboarding + selected-context flow; a
/// missing/invalid config fails closed to an honest "unconfigured" state.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = RuntimeConfig.fromEnvironment();
  // Language before first frame: the persisted per-device choice wins; the
  // FIRST-LAUNCH default is ARABIC (the official language — sprint).
  final localeOverride = initialLocaleProvider.overrideWithValue(
    await readPersistedLocale() ?? const Locale('ar'),
  );

  if (config.isDemoMode) {
    runApp(
      ProviderScope(
        overrides: [localeOverride],
        child: const DashboardApp(demoMode: true),
      ),
    );
    return;
  }

  final supabase = config.supabase;
  if (supabase == null) {
    // Real mode but the anon-key config is missing/invalid/service-role: an honest
    // unconfigured state. Real* repos never contact a backend without valid config.
    runApp(
      ProviderScope(
        overrides: [localeOverride],
        child: const DashboardApp(demoMode: false, realModeUnconfigured: true),
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
  try {
    await Supabase.initialize(
      url: supabase.url,
      publishableKey: supabase.anonKey,
    );
  } catch (_) {
    // Fail-closed: a backend bootstrap failure (malformed URL, storage error)
    // must never crash or blank the dashboard — show the honest config help
    // page instead. Never echo the offending value.
    runApp(
      ProviderScope(
        overrides: [localeOverride],
        child: const DashboardApp(demoMode: false, realModeUnconfigured: true),
      ),
    );
    return;
  }
  final real = buildDashboardRealAuth(Supabase.instance.client);
  runApp(
    ProviderScope(
      overrides: [localeOverride],
      child: DashboardApp(
        demoMode: false,
        authRepository: real.auth,
        onboardingRepository: real.onboarding,
        fetchContext: real.fetchContext,
        deviceRepositoryFor: real.deviceRepositoryFor,
        menuReadSource: real.menuReadSource,
        menuWriter: real.menuWriter,
        menuImageStorage: real.menuImageStorage,
        printersRepositoryFor: real.printersRepositoryFor,
        staffRepositoryFor: real.staffRepositoryFor,
        tablesRepositoryFor: real.tablesRepositoryFor,
        reportsTransport: real.transport,
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
class DashboardApp extends ConsumerWidget {
  const DashboardApp({
    this.demoMode,
    this.fetchContext,
    this.authRepository,
    this.onboardingRepository,
    this.selectedContextStore,
    this.deviceContext,
    this.deviceRepositoryFor,
    this.menuReadSource,
    this.menuWriter,
    this.menuImageStorage,
    this.printersRepositoryFor,
    this.staffRepositoryFor,
    this.tablesRepositoryFor,
    this.reportsTransport,
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

  /// The REAL menu seams (sprint): `list_menu` read + `menu_upsert_*` writer.
  /// Null in demo mode / tests => the Menu tab keeps its labelled demo store.
  final MenuReadSource? menuReadSource;
  final MenuWriter? menuWriter;

  /// The REAL item image storage (menu/media sprint — RF-110 bucket over the
  /// authenticated client). Null in demo mode / tests => the image panel shows
  /// its honest demo/unavailable state.
  final MenuImageStorage? menuImageStorage;

  /// Builds the REAL printers repository (RF-150 backend) per admin scope.
  final PrintersRepository Function(AdminScope scope)? printersRepositoryFor;

  /// Builds the REAL staff/PIN repository per admin scope.
  final StaffRepository Function(AdminScope scope)? staffRepositoryFor;

  /// Builds the REAL dining-tables repository per admin scope.
  final TablesAdminRepository Function(AdminScope scope)? tablesRepositoryFor;

  /// The authenticated dashboard transport for the Overview's real
  /// sales-summary read (sprint). Null in demo mode / tests.
  final SyncRpcTransport? reportsTransport;

  /// True in real mode when the Supabase anon-key config was missing/invalid.
  final bool realModeUnconfigured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      onGenerateTitle: (context) =>
          AppLocalizations.of(context).dashboardAppTitle,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      // Sprint (I): the persisted user-selected language drives the app.
      locale: ref.watch(localeControllerProvider),
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
      // Real mode without a usable backend: an honest help page that explains
      // exactly which --dart-define values real mode needs (never a crash, never
      // a silent demo fallback).
      return const RealModeUnconfiguredView();
    }
    return DashboardAuthFlow(
      authRepository: authRepository,
      onboardingRepository: onboardingRepository,
      fetchContext: fetchContext!,
      selectedContextStore: selectedContextStore,
      deviceContext: deviceContext,
      // Resolve the EFFECTIVE tenant context first (sprint): an org-wide
      // owner membership gets a concrete restaurant/branch + the real
      // currency from `list_org_structure`, so the menu/printers/staff
      // surfaces work instead of showing scope-blocked states.
      onReady: (context, membership) => TenantContextLoader(
        membership: membership,
        transport: reportsTransport,
        builder: (context, resolved) {
          final scope = dashboardAdminScopeFor(
            resolved.membership,
            currencyCode: resolved.currencyCode,
          );
          return DashboardShell(
            membership: resolved.membership,
            currencyCode: resolved.currencyCode,
            deviceRepositoryFor: deviceRepositoryFor,
            menuReadSource: menuReadSource,
            menuWriter: menuWriter,
            menuImageStorage: menuImageStorage,
            printersRepository: printersRepositoryFor?.call(scope),
            staffRepository: staffRepositoryFor?.call(scope),
            tablesRepository: tablesRepositoryFor?.call(scope),
            reportsTransport: reportsTransport,
            // Sign-out from the shell header; the auth flow's session stream
            // drives the transition + context clearing.
            onSignOut: authRepository == null ? null : authRepository!.signOut,
          );
        },
      ),
    );
  }
}
