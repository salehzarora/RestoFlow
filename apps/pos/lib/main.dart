import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'src/pos_menu_screen.dart';
import 'src/state/locale_controller.dart';

void main() => runApp(const ProviderScope(child: PosApp()));

/// RestoFlow POS app (RF-100 + RF-108): the demo menu + cart screen, behind the
/// shared auth gate.
///
/// In DEMO mode (`RESTOFLOW_DEMO_MODE` default true) it renders the existing
/// in-memory demo screen. In auth mode it routes through the cashier/owner/
/// manager role gate (`AppSurface.pos`). No order submission/payments here
/// (RF-108 wires entry only); the cashier scope-aware data binding is deferred
/// to the real-data tickets. Localization/RTL + theme + Riverpod as before.
class PosApp extends ConsumerWidget {
  const PosApp({this.demoMode, this.fetchContext, super.key});

  /// Test-only override of the demo/auth mode (null => `RESTOFLOW_DEMO_MODE`).
  final bool? demoMode;

  /// Test-only override of the auth-context fetcher (null => env config).
  final AuthContextFetcher? fetchContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).posAppTitle,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      // RF-118 fix B: the user-selected language drives the app (RTL for ar/he).
      locale: ref.watch(localeControllerProvider),
      localeResolutionCallback: restoflowResolveLocale,
      debugShowCheckedModeBanner: false,
      theme: restoflowBaseTheme(),
      home: AuthGatedHome(
        surface: AppSurface.pos,
        demoHome: const PosMenuScreen(),
        onReady: (context, state) => const PosMenuScreen(),
        demoMode: demoMode,
        fetchContext: fetchContext,
      ),
    );
  }
}
