import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'src/dashboard_home_screen.dart';

void main() => runApp(const ProviderScope(child: DashboardApp()));

/// RestoFlow owner/manager dashboard app (RF-104): a visible demo report-cards
/// screen.
///
/// In-memory demo only — no Supabase, no report views, no backend. Localization
/// /RTL come from the shared `packages/l10n` wiring; the theme (seeded Material
/// 3 + tokens) comes from `packages/design_system`; state is Riverpod. Money is
/// integer minor units (DECISION D-007).
class DashboardApp extends StatelessWidget {
  const DashboardApp({super.key});

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
      home: const DashboardHomeScreen(),
    );
  }
}
