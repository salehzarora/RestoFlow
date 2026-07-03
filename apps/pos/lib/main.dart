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
import 'src/state/pos_printer_assignments.dart';
import 'src/state/pos_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Language before first frame: the persisted per-device choice wins; the
  // FIRST-LAUNCH default is ARABIC (the official language — sprint).
  final persistedLocale = await readPersistedLocale();
  final real = await _realDeviceAuth();
  final seams = real.seams;
  runApp(
    ProviderScope(
      overrides: [
        initialLocaleProvider.overrideWithValue(
          persistedLocale ?? const Locale('ar'),
        ),
        // The PIN/session + sync_push calls must ride the SAME authenticated
        // (anonymous) transport as the pairing repo — the plain anon transport
        // cannot reach the authenticated-only RPC grants (D-011/RF-161).
        if (seams != null)
          posAuthTransportProvider.overrideWithValue(seams.transport),
        // Menu/media sprint: the device's read-only menu-image signed-URL
        // resolver rides the SAME anonymous session (fail-soft — a missing
        // resolver just renders imageless cards).
        if (seams != null)
          posImageUrlResolverProvider.overrideWithValue(seams.imageResolver),
        // Device settings sprint: the token-proven per-device printer read
        // (receipt printers of this station's branch; no secrets).
        if (seams != null)
          posPrinterAssignmentsReaderProvider.overrideWithValue(
            seams.printerAssignments,
          ),
      ],
      child: PosApp(
        devicePairingRepository: seams?.pairing,
        deviceStaffRepository: seams?.staff,
        realAuthProblem: real.problem,
      ),
    ),
  );
}

typedef _RealDeviceSeams = ({
  DevicePairingRepository pairing,
  DeviceStaffRepository staff,
  SyncRpcTransport transport,
  DeviceImageUrlResolver imageResolver,
  DevicePrinterAssignmentsReader printerAssignments,
});

/// RF-161 + sprint: the REAL device-auth seams for production POS. In real mode
/// with a valid Supabase config it signs the device in anonymously (an
/// authenticated, membership-less principal — DECISION D-011, no service-role
/// key) and returns the backend-backed pairing repository, the token-proven
/// staff directory for the PIN pad, and the shared transport. When the seams
/// cannot be built, `problem` says WHY, so the app can show an honest state
/// instead of the legacy account gate (which used to surface a misleading
/// "Account access denied" on devices) — NEVER a fake pairing or staff list.
Future<({_RealDeviceSeams? seams, RealDeviceAuthProblem? problem})>
_realDeviceAuth() async {
  if (authDemoModeEnabled()) return (seams: null, problem: null);
  final SupabaseBootstrapConfig config;
  try {
    config = SupabaseBootstrapConfig.fromEnvironment();
  } on SupabaseConfigException {
    return (seams: null, problem: RealDeviceAuthProblem.unconfigured);
  }
  try {
    final session = await SupabaseAuthBootstrap(
      config: config,
    ).createAnonymousDeviceSession();
    final transport = session.transport;
    final store = FlutterSecureDeviceSessionStore();
    return (
      seams: (
        pairing: SupabaseDevicePairingRepository(
          transport: transport,
          secretStore: store,
        ),
        staff: SupabaseDeviceStaffRepository(
          transport: transport,
          secretStore: store,
        ),
        transport: transport,
        // Read-only menu-image signed URLs on the same anonymous session
        // (server-gated by the POS device storage policy — T-014 keeps KDS out).
        imageResolver: session.imageUrlResolver,
        printerAssignments: SupabaseDevicePrinterAssignmentsRepository(
          transport: transport,
          secretStore: store,
        ),
      ),
      problem: null,
    );
  } catch (_) {
    // Fail closed (e.g. anonymous sign-ins disabled on the project): no fake
    // pairing — the app renders DeviceSignInUnavailableView with the fix.
    return (seams: null, problem: RealDeviceAuthProblem.signInUnavailable);
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
/// WITHOUT the seams shows the honest reason ([realAuthProblem]) — the
/// unconfigured help page or the device-sign-in-unavailable page — never the
/// legacy account gate's misleading denial, and never a fake pairing, session,
/// or menu. Localization/RTL as before.
class PosApp extends ConsumerWidget {
  const PosApp({
    this.demoMode,
    this.fetchContext,
    this.devicePairingRepository,
    this.deviceStaffRepository,
    this.realAuthProblem,
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

  /// Why the real device-auth bootstrap produced no seams (real mode only).
  /// Non-null with no pairing repo => the matching honest help page renders
  /// instead of the legacy account gate. Null => prior behaviour.
  final RealDeviceAuthProblem? realAuthProblem;

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
    final problem = realAuthProblem;
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
        : (!demo && problem != null)
        // A POS device never has an owner account, so the legacy gate's
        // "Account access denied" would be a lie here — say what is wrong.
        ? switch (problem) {
            RealDeviceAuthProblem.unconfigured =>
              const RealModeUnconfiguredView(),
            RealDeviceAuthProblem.signInUnavailable =>
              const DeviceSignInUnavailableView(),
          }
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
