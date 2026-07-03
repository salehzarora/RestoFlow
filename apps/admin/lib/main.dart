import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'src/admin_platform_gate.dart';
import 'src/platform_admin_screen.dart';
import 'src/state/locale_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Language before first frame: the persisted per-device choice wins; the
  // FIRST-LAUNCH default is ARABIC (the official language — sprint).
  final persistedLocale = await readPersistedLocale();
  runApp(
    ProviderScope(
      overrides: [
        initialLocaleProvider.overrideWithValue(
          persistedLocale ?? const Locale('ar'),
        ),
      ],
      child: const AdminApp(),
    ),
  );
}

/// Localized platform-admin app (RF-020 + RF-108 + RF-120), behind the shared
/// auth gate.
///
/// In DEMO mode (`RESTOFLOW_DEMO_MODE` default true) it shows the platform
/// overview (RF-120, demo-backed). In auth mode it routes through the
/// platform-admin gate (`AppSurface.admin`): entry is allowed ONLY when
/// `is_platform_admin == true` (D-026 - never a tenant role). The overview is
/// demo data behind a repository seam (real RF-091 platform-admin RPC wiring is
/// deferred). RTL/LTR via the shared `packages/l10n` wiring.
class AdminApp extends ConsumerWidget {
  const AdminApp({this.demoMode, this.fetchContext, super.key});

  /// Test-only override of the demo/auth mode (null => `RESTOFLOW_DEMO_MODE`).
  final bool? demoMode;

  /// Test-only override of the auth-context fetcher (null => env config).
  final AuthContextFetcher? fetchContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).adminAppTitle,
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

  /// Sprint (admin access clarification): the admin surface no longer rides
  /// the shared tenant gate's dead-end states. Demo renders the overview;
  /// real mode without valid config gets the honest unconfigured help page
  /// (mirrors apps/dashboard); otherwise [AdminPlatformGate] admits platform
  /// admins and explains the app to everyone else. Entry stays gated by
  /// `get_my_context.is_platform_admin` (D-026); data reads still require an
  /// active grant + MFA + reason server-side (RF-091).
  Widget _home() {
    final demo = demoMode ?? authDemoModeEnabled();
    if (demo) return const PlatformAdminScreen();
    final injected = fetchContext;
    if (injected != null) return AdminPlatformGate(fetchContext: injected);
    if (RuntimeConfig.fromEnvironment().supabase == null) {
      // Real mode but the anon-key config is missing/invalid: an honest,
      // fail-closed help page (never a generic error, never a demo fallback).
      return const RealModeUnconfiguredView();
    }
    return AdminPlatformGate(fetchContext: authContextFetcherFromEnvironment());
  }
}
