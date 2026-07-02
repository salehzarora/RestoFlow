import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_sync/restoflow_sync.dart';

import 'src/kds_pairing_gate.dart';
import 'src/kds_pin_gate.dart';
import 'src/kds_synced_home.dart';
import 'src/kitchen_orders_home.dart';
import 'src/state/kds_session.dart';
import 'src/state/locale_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final real = await _realDeviceAuth();
  final seams = real.seams;
  runApp(
    KdsApp(
      devicePairingRepository: seams?.pairing,
      deviceStaffRepository: seams?.staff,
      authTransport: seams?.transport,
      realAuthProblem: real.problem,
    ),
  );
}

typedef _RealDeviceSeams = ({
  DevicePairingRepository pairing,
  DeviceStaffRepository staff,
  SyncRpcTransport transport,
});

/// RF-161 + sprint: the REAL device-auth seams for production KDS. In real mode
/// with a valid Supabase config it signs the device in anonymously (an
/// authenticated, membership-less principal — DECISION D-011, no service-role
/// key) and returns the backend-backed pairing repository, the token-proven
/// staff directory for the PIN pad, and the shared transport (the SAME
/// authenticated transport carries `start_pin_session` + `sync_pull`/`sync_push`).
/// When the seams cannot be built, `problem` says WHY, so the app can show an
/// honest state instead of the legacy account gate (which used to surface a
/// misleading "Account access denied" on devices) — NEVER a fake pairing.
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
    final transport = await SupabaseAuthBootstrap(
      config: config,
    ).createAnonymousDeviceTransport();
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
      ),
      problem: null,
    );
  } catch (_) {
    // Fail closed (e.g. anonymous sign-ins disabled on the project): no fake
    // pairing — the app renders DeviceSignInUnavailableView with the fix.
    return (seams: null, problem: RealDeviceAuthProblem.signInUnavailable);
  }
}

/// Localized KDS app (RF-063 + RF-108 + RF-117 board + RF-136 real sync).
///
/// The root ALWAYS provides a [ProviderScope]. It renders the provider-backed
/// live data path ([KdsSyncedHome] — polling-first `sync_pull` via
/// `feature_kitchen`, no realtime; DECISION D-010) when EITHER a [KdsSyncSource]
/// is injected (tests) OR a real `--dart-define`-configured session has been
/// established ([kdsSyncSessionProvider] non-null, RF-136). Otherwise: in DEMO
/// mode (the DEFAULT) it shows the RF-117 kitchen order board; in auth mode it
/// routes through the kitchen_staff/owner/manager role gate (`AppSurface.kds`).
///
/// RF-136 fail-closed: real mode only activates with a valid Supabase anon
/// config AND a complete operator-supplied device/PIN context AND a successful
/// `start_pin_session`. Any missing/failed piece -> null session -> demo/auth
/// board (no backend touch, no fake live feed). The live path is DORMANT until
/// GoTrue sign-in + device provisioning land (both still deferred). RF-118: the
/// UI language is user-selectable (RTL for ar/he).
class KdsApp extends StatelessWidget {
  const KdsApp({
    this.source,
    this.invalidationSource,
    this.demoMode,
    this.fetchContext,
    this.devicePairingRepository,
    this.deviceStaffRepository,
    this.authTransport,
    this.realAuthProblem,
    this.initialDevice,
    super.key,
  });

  /// The injected sync source (authenticated). Null -> demo/auth-gate path.
  final KdsSyncSource? source;

  /// RF-153 device-pairing seam. Null => the pairing gate is dormant (current
  /// behaviour); non-null => real (non-live) mode requires a paired KDS device.
  final DevicePairingRepository? devicePairingRepository;

  /// The PIN-pad staff directory (sprint). Null with a pairing repo present
  /// => the PIN gate fails closed (honest unavailable state).
  final DeviceStaffRepository? deviceStaffRepository;

  /// The authenticated (anonymous) transport shared by pairing + PIN + sync
  /// (sprint). Null => [kdsAuthTransportProvider] keeps its default.
  final SyncRpcTransport? authTransport;

  /// Why the real device-auth bootstrap produced no seams (real mode only).
  /// Non-null with no pairing repo => the matching honest help page renders
  /// instead of the legacy account gate. Null => prior behaviour.
  final RealDeviceAuthProblem? realAuthProblem;

  /// A pre-existing paired device context, or null.
  final DeviceContext? initialDevice;

  /// RF-058: an OPTIONAL realtime invalidation source. When provided (and a sync
  /// [source] is too), realtime hints are bridged to refresh() on top of
  /// polling. Null -> polling-only (realtime is never required).
  final InvalidationSource? invalidationSource;

  /// Test-only override of the demo/auth mode (null => `RESTOFLOW_DEMO_MODE`).
  final bool? demoMode;

  /// Test-only override of the auth-context fetcher (null => env config).
  final AuthContextFetcher? fetchContext;

  @override
  Widget build(BuildContext context) {
    final injected = source;
    final invSource = invalidationSource;
    return ProviderScope(
      overrides: [
        // Sprint: the PIN/session + sync calls ride the SAME authenticated
        // (anonymous) transport as the pairing repo (D-011/RF-161).
        if (authTransport case final transport?)
          kdsAuthTransportProvider.overrideWithValue(transport),
        if (injected != null)
          kdsSyncSourceProvider.overrideWithValue(injected)
        else
          // RF-136 production wiring: build the real polling-first sync_pull
          // coordinator from the established (--dart-define) session + transport.
          // Lazy: only read when KdsSyncedHome is mounted, which is itself
          // route-gated on a non-null session (below), so the demo/auth path
          // never evaluates this and never touches a backend.
          kdsSyncSourceProvider.overrideWith((ref) {
            final realSource = ref.watch(kdsRealSyncSourceProvider);
            if (realSource == null) {
              // Unreachable in practice (route-gated on a non-null session). The
              // guard keeps the non-null provider contract honest and fails
              // closed loudly rather than ever fabricating a source.
              throw StateError(
                'kdsSyncSourceProvider read without an established real session.',
              );
            }
            return realSource;
          }),
        if (injected != null && invSource != null)
          kdsInvalidationSourceProvider.overrideWithValue(invSource),
      ],
      child: _KdsMaterialApp(
        injected: injected,
        demoMode: demoMode,
        fetchContext: fetchContext,
        devicePairingRepository: devicePairingRepository,
        deviceStaffRepository: deviceStaffRepository,
        realAuthProblem: realAuthProblem,
        initialDevice: initialDevice,
      ),
    );
  }
}

/// The MaterialApp, inside the ProviderScope so it can watch the selected locale
/// (RF-118 fix B) — switching the app, and to RTL for Arabic/Hebrew.
class _KdsMaterialApp extends ConsumerWidget {
  const _KdsMaterialApp({
    required this.injected,
    required this.demoMode,
    required this.fetchContext,
    required this.devicePairingRepository,
    required this.deviceStaffRepository,
    required this.realAuthProblem,
    required this.initialDevice,
  });

  final KdsSyncSource? injected;
  final bool? demoMode;
  final AuthContextFetcher? fetchContext;
  final DevicePairingRepository? devicePairingRepository;
  final DeviceStaffRepository? deviceStaffRepository;
  final RealDeviceAuthProblem? realAuthProblem;
  final DeviceContext? initialDevice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // RF-136: mount the live board when a source is injected (tests) OR a real
    // session has been established from --dart-define config. A null session
    // (demo, unconfigured, or a failed/anon start_pin_session) keeps the
    // demo/auth board - fail-closed, never a fake live feed.
    final hasRealSession = ref.watch(kdsSyncSessionProvider) != null;
    final live = injected != null || hasRealSession;

    final gate = AuthGatedHome(
      surface: AppSurface.kds,
      // RF-117: the visible kitchen order board (demo feed).
      demoHome: const KitchenOrdersHome(),
      onReady: (context, state) => const KitchenOrdersHome(),
      demoMode: demoMode,
      fetchContext: fetchContext,
    );
    // RF-153 + sprint: in real (non-live-yet) mode with a wired pairing repo,
    // the honest production chain is paired KDS device -> staff PIN session ->
    // (the app root mounts the LIVE board off that session, above). Money-FREE
    // throughout (kitchen — SECURITY T-003). Dormant when unconfigured; no fake
    // pairing, no fake session, no fake feed.
    final demo = demoMode ?? authDemoModeEnabled();
    final pairingRepo = devicePairingRepository;
    final problem = realAuthProblem;
    final nonLiveHome = (!demo && pairingRepo != null)
        ? KdsPairingGate(
            repository: pairingRepo,
            initialDevice: initialDevice,
            signedInBuilder: (context, device) => KdsPinGate(
              device: device,
              staffRepository: deviceStaffRepository,
              child: gate,
            ),
          )
        : (!demo && problem != null)
        // A KDS device never has an owner account, so the legacy gate's
        // "Account access denied" would be a lie here — say what is wrong.
        ? switch (problem) {
            RealDeviceAuthProblem.unconfigured =>
              const RealModeUnconfiguredView(),
            RealDeviceAuthProblem.signInUnavailable =>
              const DeviceSignInUnavailableView(),
          }
        : gate;

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).kdsAppTitle,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      locale: ref.watch(localeControllerProvider),
      localeResolutionCallback: restoflowResolveLocale,
      debugShowCheckedModeBanner: false,
      theme: restoflowBaseTheme(),
      home: live ? const KdsSyncedHome() : nonLiveHome,
    );
  }
}
