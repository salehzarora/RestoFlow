import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'src/dashboard_home_screen.dart';

void main() => runApp(const ProviderScope(child: DashboardApp()));

/// RestoFlow owner/manager dashboard app (RF-104 + RF-108): the demo report
/// screen, behind the shared auth gate.
///
/// In DEMO mode (`RESTOFLOW_DEMO_MODE` default true) it renders the existing
/// in-memory demo screen. In auth mode it routes through the owner/manager role
/// gate (`AppSurface.dashboard`). No real report views here (RF-108 wires entry
/// only). Localization/RTL + theme + Riverpod as before; money is integer minor
/// units (DECISION D-007).
class DashboardApp extends StatelessWidget {
  const DashboardApp({this.demoMode, this.fetchContext, super.key});

  /// Test-only override of the demo/auth mode (null => `RESTOFLOW_DEMO_MODE`).
  final bool? demoMode;

  /// Test-only override of the auth-context fetcher (null => env config).
  final AuthContextFetcher? fetchContext;

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
      home: AuthGatedHome(
        surface: AppSurface.dashboard,
        demoHome: const DashboardHomeScreen(),
        onReady: (context, state) => const DashboardHomeScreen(),
        demoMode: demoMode,
        fetchContext: fetchContext,
      ),
    );
  }
}
