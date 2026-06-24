import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'src/pos_menu_screen.dart';

void main() => runApp(const ProviderScope(child: PosApp()));

/// RestoFlow POS app (RF-100): a visible, polished demo menu + cart screen.
///
/// In-memory demo only — no Supabase, no auth, no order submission, no payments,
/// no persistence. Localization/RTL come from the shared `packages/l10n` wiring;
/// the theme (seeded Material 3 + tokens) comes from `packages/design_system`;
/// state is Riverpod.
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
      theme: restoflowBaseTheme(),
      home: const PosMenuScreen(),
    );
  }
}
