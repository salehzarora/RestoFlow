import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'src/pos_menu_screen.dart';
import 'src/pos_pairing_gate.dart';
import 'src/pos_pin_gate.dart';
import 'src/state/locale_controller.dart';
import 'src/state/pos_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final real = await _realDeviceAuth();
  runApp(
    ProviderScope(
      overrides: [
        // The PIN/session + sync_push calls must ride the SAME authenticated
        // (anonymous) transport as the pairing repo — the plain anon transport
        // cannot reach the authenticated-only RPC grants (D-011/RF-161).
        if (real != null)
          posAuthTransportProvider.overrideWithValue(real.transport),
      ],
      child: PosApp(
        devicePairingRepository: real?.pairing,
        deviceStaffRepository: real?.staff,
      ),
    ),
  );
}

/// RF-161 + sprint: the REAL device-auth seams for production POS. In real mode
/// with a valid Supabase config it signs the device in anonymously (an
/// authenticated, membership-less principal — DECISION D-011, no service-role
/// key) and returns the backend-backed pairing repository, the token-proven
/// staff directory for the PIN pad, and the shared transport. Returns null (the
/// gates stay dormant, prior behaviour) in demo mode, when unconfigured, or when
/// anonymous sign-in is unavailable — NEVER a fake pairing or staff list.
Future<
  ({
    DevicePairingRepository pairing,
    DeviceStaffRepository staff,
    SyncRpcTransport transport,
  })?
>
_realDeviceAuth() async {
  if (authDemoModeEnabled()) return null;
  final SupabaseBootstrapConfig config;
  try {
    config = SupabaseBootstrapConfig.fromEnvironment();
  } on SupabaseConfigException {
    return null; // unconfigured -> dormant.
  }
  try {
    final transport = await SupabaseAuthBootstrap(
      config: config,
    ).createAnonymousDeviceTransport();
    final store = FlutterSecureDeviceSessionStore();
    return (
      pairing: SupabaseDevicePairingRepository(
        transport: transport,
        secretStore: store,
      ),
      staff: SupabaseDeviceStaffRepository(
        transport: transport,
        secretStore: store,
      ),
      transport: transport,
    );
  } catch (_) {
    return null; // fail closed (e.g. anonymous sign-in disabled) -> no fake pairing.
  }
}

/// RestoFlow POS app (RF-100 + RF-108 + RF-153 + RF-161 + sprint).
///
/// DEMO mode (`RESTOFLOW_DEMO_MODE` default true) renders the in-memory demo
/// screen, unchanged. REAL mode with the device seams wired walks the honest
/// production chain: paired device (pairing gate, type-checked restore) → staff
/// PIN session (PIN gate over `start_pin_session`) → the POS surface selling
/// the REAL backend menu, submitting orders and cash payments through
/// `public.sync_push` with the session (RF-129/RF-130/RF-131). Real mode
/// WITHOUT the seams (unconfigured) falls back to the legacy auth gate — no
/// fake pairing, no fake session, no fake menu. Localization/RTL as before.
class PosApp extends ConsumerWidget {
  const PosApp({
    this.demoMode,
    this.fetchContext,
    this.devicePairingRepository,
    this.deviceStaffRepository,
    this.initialDevice,
    super.key,
  });

  /// Test-only override of the demo/auth mode (null => `RESTOFLOW_DEMO_MODE`).
  final bool? demoMode;

  /// Test-only override of the auth-context fetcher (null => env config).
  final AuthContextFetcher? fetchContext;

  /// The device-pairing seam (RF-153/RF-161). Null => the pairing gate is
  /// dormant (prior behaviour); non-null => real mode requires a paired device.
  final DevicePairingRepository? devicePairingRepository;

  /// The PIN-pad staff directory (sprint). Null with a pairing repo present
  /// => the PIN gate fails closed (honest unavailable state).
  final DeviceStaffRepository? deviceStaffRepository;

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
            // Paired -> staff PIN session -> the POS surface (D-006). The PIN
            // session IS the operator identity on a paired device; no GoTrue
            // human login happens on the POS itself.
            signedInBuilder: (context, device) => PosPinGate(
              device: device,
              staffRepository: deviceStaffRepository,
              child: const PosMenuScreen(),
            ),
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
