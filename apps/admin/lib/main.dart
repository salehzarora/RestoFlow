import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/auth/admin_auth.dart';
import 'src/auth/admin_auth_flow.dart';
import 'src/auth/supabase_admin_auth.dart';
import 'src/platform_admin_screen.dart';
import 'src/state/locale_controller.dart';
import 'src/state/platform_admin_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Language before first frame: the persisted per-device choice wins; the
  // FIRST-LAUNCH default is ARABIC (the official language — sprint).
  final persistedLocale = await readPersistedLocale();
  final localeOverride = initialLocaleProvider.overrideWithValue(
    persistedLocale ?? const Locale('ar'),
  );

  final config = RuntimeConfig.fromEnvironment();
  // RF-LIVE-002: a RELEASE build left in demo mode while valid real credentials
  // are present is an accidental production demo — fail closed with an honest
  // help page. Local demo (no real config present) is unaffected.
  if (config.isDemoModeMisconfigured) {
    runApp(
      ProviderScope(
        overrides: [localeOverride],
        child: const AdminApp(demoMode: true, demoModeMisconfigured: true),
      ),
    );
    return;
  }
  // DEMO mode (the DEFAULT): the demo-backed platform overview, no session.
  if (config.isDemoMode) {
    runApp(
      ProviderScope(
        overrides: [localeOverride],
        child: const AdminApp(demoMode: true),
      ),
    );
    return;
  }
  // Real mode but no valid anon-key config: an honest, fail-closed help page.
  final supabase = config.supabase;
  if (supabase == null) {
    runApp(
      ProviderScope(
        overrides: [localeOverride],
        child: const AdminApp(demoMode: false, realModeUnconfigured: true),
      ),
    );
    return;
  }
  // RF-119-b: initialise Supabase (session persistence) with the PUBLIC anon key
  // ONLY (DECISION D-011 — the config already rejects any service-role/secret
  // key). The SAME client carries the GoTrue session (incl. the aal claim after
  // TOTP MFA) into public.get_my_context / the platform RPCs.
  try {
    await Supabase.initialize(
      url: supabase.url,
      publishableKey: supabase.anonKey,
    );
  } catch (_) {
    // Fail-closed: a bootstrap failure shows the honest config help page, never a
    // crash or a demo fallback. Never echo the offending value.
    runApp(
      ProviderScope(
        overrides: [localeOverride],
        child: const AdminApp(demoMode: false, realModeUnconfigured: true),
      ),
    );
    return;
  }
  final client = Supabase.instance.client;
  // ONE session-carrying transport, shared by BOTH get_my_context AND the platform
  // overview reads (RF-119-b Codex fix): both must ride the SAME authenticated
  // client so the operator's aal2 session reaches app.platform_admin_guard.
  final transport = SupabaseSyncRpcTransport(client);
  runApp(
    ProviderScope(
      overrides: [
        localeOverride,
        // The overview repo reads through this SAME transport — never a fresh
        // sessionless anon-key client (which the guard would reject). Default is
        // null (fail-closed); this override is what enables real platform reads.
        platformAdminTransportProvider.overrideWithValue(transport),
      ],
      child: AdminApp(
        demoMode: false,
        authService: SupabaseAdminAuthService(client),
        // The context fetcher rides the SAME session-carrying transport, so
        // get_my_context sees auth.uid() + the assurance claim.
        fetchContext: AuthContextRepository(transport).fetchMyContext,
      ),
    ),
  );
}

/// Localized platform-admin app (RF-020 + RF-108 + RF-119 + RF-119-b).
///
/// DEMO mode (`RESTOFLOW_DEMO_MODE` default true) shows the demo platform
/// overview (no session). REAL mode runs the honest operator flow via
/// [AdminAuthFlow]: platform-operator sign-in → (if platform admin without aal2)
/// interactive TOTP MFA enrol/challenge → the overview once the SERVER confirms
/// aal2. Entry is ALWAYS gated server-side by `app.platform_admin_guard`
/// (grant + aal2 + reason); a restaurant owner/manager is never a platform admin
/// (D-026). No service-role key (D-011). RTL/LTR via the shared `packages/l10n`.
class AdminApp extends ConsumerWidget {
  const AdminApp({
    this.demoMode,
    this.authService,
    this.fetchContext,
    this.realModeUnconfigured = false,
    this.demoModeMisconfigured = false,
    super.key,
  });

  /// Test-only override of the demo/auth mode (null => `RESTOFLOW_DEMO_MODE`).
  final bool? demoMode;

  /// The real (or fake, in tests) platform-operator auth + MFA service. Null in
  /// demo mode and when real mode is unconfigured.
  final AdminAuthService? authService;

  /// The `get_my_context` fetcher (rides the same session-carrying client). Null
  /// in demo mode and when real mode is unconfigured.
  final AuthContextFetcher? fetchContext;

  /// True when real mode was selected but Supabase config was missing/invalid or
  /// the bootstrap failed → the honest unconfigured help page.
  final bool realModeUnconfigured;

  /// RF-LIVE-002: true when a RELEASE build is in DEMO mode while VALID real
  /// credentials are present (an accidental production demo) → the honest
  /// "demo mode with real credentials" help page, never demo data as production.
  final bool demoModeMisconfigured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).adminAppTitle,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      locale: ref.watch(localeControllerProvider),
      localeResolutionCallback: restoflowResolveLocale,
      debugShowCheckedModeBanner: false,
      theme: restoflowBaseTheme(),
      home: _home(),
    );
  }

  Widget _home() {
    // RF-LIVE-002: an accidental production demo (release + demo-mode + valid
    // real credentials) fails closed BEFORE the demo overview ever renders.
    if (demoModeMisconfigured) {
      return const RealModeUnconfiguredView(
        issue: RealModeConfigIssue.demoModeInProduction,
      );
    }
    final demo = demoMode ?? authDemoModeEnabled();
    // Demo shows the overview (no session). No sign-out (nothing to sign out of).
    if (demo) return const PlatformAdminScreen();
    if (realModeUnconfigured) return const RealModeUnconfiguredView();
    final service = authService;
    final fetch = fetchContext;
    if (service != null && fetch != null) {
      return AdminAuthFlow(authService: service, fetchContext: fetch);
    }
    // Real mode with no wired auth (e.g. a bare AdminApp(demoMode: false)) fails
    // closed to the honest unconfigured help page — never a bypass.
    return const RealModeUnconfiguredView();
  }
}
