import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_sync/restoflow_sync.dart';

import 'src/kds_pairing_gate.dart';
import 'src/kds_synced_home.dart';
import 'src/kitchen_orders_home.dart';
import 'src/state/kds_session.dart';
import 'src/state/locale_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(KdsApp(devicePairingRepository: await _realDevicePairing()));
}

/// RF-161: the REAL device-pairing repository for production KDS. In real mode with
/// a valid Supabase config it signs the device in anonymously (an authenticated,
/// membership-less principal — DECISION D-011, no service-role key) and returns the
/// backend-backed [SupabaseDevicePairingRepository] over OS-backed secure storage.
/// Returns null (the gate stays dormant, prior behaviour) in demo mode, when
/// unconfigured, or when anonymous sign-in is unavailable — NEVER a fake pairing.
Future<DevicePairingRepository?> _realDevicePairing() async {
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
    return SupabaseDevicePairingRepository(
      transport: transport,
      secretStore: FlutterSecureDeviceSessionStore(),
    );
  } catch (_) {
    return null; // fail closed (e.g. anonymous sign-in disabled) -> no fake pairing.
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
    this.initialDevice,
    super.key,
  });

  /// The injected sync source (authenticated). Null -> demo/auth-gate path.
  final KdsSyncSource? source;

  /// RF-153 device-pairing seam. Null => the pairing gate is dormant (current
  /// behaviour); non-null => real (non-live) mode requires a paired KDS device.
  final DevicePairingRepository? devicePairingRepository;

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
    required this.initialDevice,
  });

  final KdsSyncSource? injected;
  final bool? demoMode;
  final AuthContextFetcher? fetchContext;
  final DevicePairingRepository? devicePairingRepository;
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
    // RF-153: in real (non-demo, non-live) mode with a wired pairing repo, require
    // a paired KDS device first. Money-FREE (kitchen); dormant in production
    // (repo null), so no fake pairing and the current behaviour is preserved.
    final demo = demoMode ?? authDemoModeEnabled();
    final pairingRepo = devicePairingRepository;
    final nonLiveHome = (!demo && pairingRepo != null)
        ? KdsPairingGate(
            repository: pairingRepo,
            initialDevice: initialDevice,
            signedInChild: gate,
          )
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
