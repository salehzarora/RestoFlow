import 'package:flutter/material.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

void main() => runApp(const DashboardApp());

/// Minimal localized dashboard shell (RF-020). Real owner/manager dashboard UI
/// and features land in later tickets; this only proves locale resolution +
/// RTL/LTR via the shared `packages/l10n` wiring. No business logic, no
/// navigation, no hardcoded user-facing strings.
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
      home: const _DashboardHome(),
    );
  }
}

class _DashboardHome extends StatelessWidget {
  const _DashboardHome();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dashboardAppTitle)),
      body: Center(child: Text(l10n.welcomeMessage)),
    );
  }
}
