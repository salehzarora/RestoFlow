import 'package:flutter/material.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

void main() => runApp(const KdsApp());

/// Minimal localized KDS shell (RF-020). Real Kitchen Display UI and features
/// land in later tickets; this only proves locale resolution + RTL/LTR via the
/// shared `packages/l10n` wiring. No business logic, no navigation, no hardcoded
/// user-facing strings.
class KdsApp extends StatelessWidget {
  const KdsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).kdsAppTitle,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      localeResolutionCallback: restoflowResolveLocale,
      debugShowCheckedModeBanner: false,
      home: const _KdsHome(),
    );
  }
}

class _KdsHome extends StatelessWidget {
  const _KdsHome();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.kdsAppTitle)),
      body: Center(child: Text(l10n.welcomeMessage)),
    );
  }
}
