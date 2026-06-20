import 'package:flutter/material.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

void main() => runApp(const AdminApp());

/// Minimal localized platform-admin shell (RF-020). Real (isolated, audited)
/// admin UI and features land in later tickets; this only proves locale
/// resolution + RTL/LTR via the shared `packages/l10n` wiring. No business
/// logic, no navigation, no hardcoded user-facing strings.
class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).adminAppTitle,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      localeResolutionCallback: restoflowResolveLocale,
      debugShowCheckedModeBanner: false,
      home: const _AdminHome(),
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
