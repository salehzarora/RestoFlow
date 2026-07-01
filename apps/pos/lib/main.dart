import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'src/pos_menu_screen.dart';
import 'src/pos_pairing_gate.dart';
import 'src/state/locale_controller.dart';

void main() => runApp(const ProviderScope(child: PosApp()));

/// RestoFlow POS app (RF-100 + RF-108 + RF-153): the demo menu + cart screen,
/// behind the shared auth gate, with a real-mode device-pairing gate.
///
/// In DEMO mode (`RESTOFLOW_DEMO_MODE` default true) it renders the existing
/// in-memory demo screen. In auth mode it routes through the cashier/owner/
/// manager role gate (`AppSurface.pos`). RF-153: when a [devicePairingRepository]
/// is wired (injected), real mode first requires a paired device (the shared
/// [PosPairingGate] / [DevicePairingScreen]); production leaves it dormant until
/// the real device-session repository + secure storage land (RF-154), so no fake
/// pairing is shown and real-mode behaviour is otherwise unchanged. No order
/// submission/payments here (RF-108 wires entry only). Localization/RTL as before.
class PosApp extends ConsumerWidget {
  const PosApp({
    this.demoMode,
    this.fetchContext,
    this.devicePairingRepository,
    this.initialDevice,
    super.key,
  });

  /// Test-only override of the demo/auth mode (null => `RESTOFLOW_DEMO_MODE`).
  final bool? demoMode;

  /// Test-only override of the auth-context fetcher (null => env config).
  final AuthContextFetcher? fetchContext;

  /// The device-pairing seam (RF-153). Null => the pairing gate is dormant (the
  /// current real-mode behaviour); non-null => real mode requires a paired device.
  final DevicePairingRepository? devicePairingRepository;

  /// A pre-existing paired device context, or null.
  final DeviceContext? initialDevice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = AuthGatedHome(
      surface: AppSurface.pos,
      demoHome: const PosMenuScreen(),
      onReady: (context, state) => const PosMenuScreen(),
      demoMode: demoMode,
      fetchContext: fetchContext,
    );
    final demo = demoMode ?? authDemoModeEnabled();
    final pairingRepo = devicePairingRepository;
    final home = (!demo && pairingRepo != null)
        ? PosPairingGate(
            repository: pairingRepo,
            initialDevice: initialDevice,
            signedInChild: gate,
          )
        : gate;

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).posAppTitle,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      // RF-118 fix B: the user-selected language drives the app (RTL for ar/he).
      locale: ref.watch(localeControllerProvider),
      localeResolutionCallback: restoflowResolveLocale,
      debugShowCheckedModeBanner: false,
      theme: restoflowBaseTheme(),
      home: home,
    );
  }
}
