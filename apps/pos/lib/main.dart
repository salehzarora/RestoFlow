import 'package:flutter/material.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

void main() => runApp(const PosApp());

/// Minimal localized POS shell (RF-020). Real POS UI, routing, and features land
/// in later tickets; this only proves locale resolution + RTL/LTR via the shared
/// `packages/l10n` wiring. No business logic, no navigation, no hardcoded
/// user-facing strings.
class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).posAppTitle,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      localeResolutionCallback: restoflowResolveLocale,
      debugShowCheckedModeBanner: false,
      home: const _PosHome(),
    );
  }
}

class _PosHome extends StatelessWidget {
  const _PosHome();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.posAppTitle)),
      body: Center(child: Text(l10n.welcomeMessage)),
    );
  }
}
