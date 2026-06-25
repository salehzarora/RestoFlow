import 'package:flutter/material.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

void main() => runApp(const AdminApp());

/// Localized platform-admin shell (RF-020 + RF-108), behind the shared auth
/// gate.
///
/// In DEMO mode (`RESTOFLOW_DEMO_MODE` default true) it shows the minimal demo
/// shell. In auth mode it routes through the platform-admin gate
/// (`AppSurface.admin`): entry is allowed ONLY when `is_platform_admin == true`
/// (D-026 - never a tenant role); the platform-admin DATA surface is out of
/// RF-108 scope. RTL/LTR via the shared `packages/l10n` wiring.
class AdminApp extends StatelessWidget {
  const AdminApp({this.demoMode, this.fetchContext, super.key});

  /// Test-only override of the demo/auth mode (null => `RESTOFLOW_DEMO_MODE`).
  final bool? demoMode;

  /// Test-only override of the auth-context fetcher (null => env config).
  final AuthContextFetcher? fetchContext;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).adminAppTitle,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      localeResolutionCallback: restoflowResolveLocale,
      debugShowCheckedModeBanner: false,
      theme: restoflowBaseTheme(),
      home: AuthGatedHome(
        surface: AppSurface.admin,
        demoHome: const _AdminHome(),
        onReady: (context, state) => const _AdminHome(),
        demoMode: demoMode,
        fetchContext: fetchContext,
      ),
    );
  }
}

class _AdminHome extends StatelessWidget {
  const _AdminHome();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.adminAppTitle)),
      body: Center(child: Text(l10n.welcomeMessage)),
    );
  }
}
