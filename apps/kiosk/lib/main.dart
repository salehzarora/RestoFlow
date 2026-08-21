import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/data/kiosk_live_data.dart';
import 'src/data/kiosk_menu_data.dart';
import 'src/design/kiosk_theme.dart';
import 'src/screens/kiosk_activation.dart';
import 'src/screens/kiosk_shell.dart';
import 'src/state/kiosk_flow_controller.dart';
import 'src/state/kiosk_live_runtime.dart';

/// KIOSK-001 Phase 3 — RestoFlow customer self-service kiosk.
///
/// DEMO mode (the default, `RESTOFLOW_DEMO_MODE` unset/true): exactly the
/// Phase-1 fixture shell — no backend of any kind.
///
/// REAL mode (`RESTOFLOW_DEMO_MODE=false` + the standard
/// `RESTOFLOW_SUPABASE_URL`/`RESTOFLOW_SUPABASE_ANON_KEY` defines): the kiosk
/// becomes a PAIRED, REVOCABLE DEVICE on the existing POS/KDS session model —
/// anonymous device principal → staff activation by enrollment code
/// (device type hardcoded `kiosk`) → token-proven `kiosk_menu` /
/// `kiosk_tables` live reads driving the approved V2 UI. ONLINE-REQUIRED: no
/// offline order queue, no stale floor truth. Order submit is deliberately
/// NOT wired in this phase (the submit RPC is never referenced) — the
/// known dine-in-without-a-table server contract mismatch blocks the submit
/// phase, so real mode shows an honest "ordering unavailable" notice instead
/// of a fake confirmation.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Kiosk posture: portrait only, immersive fullscreen. Keep-screen-on is
  // applied on Android in MainActivity (FLAG_KEEP_SCREEN_ON).
  unawaited(
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
  );
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));

  final demo = authDemoModeEnabled();
  // RF-LIVE-002: a RELEASE build carrying real backend config while still in
  // demo mode is an accidental production demo — fail closed, honestly.
  if (demo && kReleaseMode && SupabaseBootstrapConfig.isPresentAndValid()) {
    runApp(
      const _KioskGateApp(
        home: RealModeUnconfiguredView(
          issue: RealModeConfigIssue.demoModeInProduction,
        ),
      ),
    );
    return;
  }
  if (demo) {
    runApp(const ProviderScope(child: KioskApp()));
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  runApp(buildKioskBootRoot(prefs: prefs));
}

/// The real-mode composition root (public so tests can pump the exact tree).
Widget buildKioskBootRoot({
  required SharedPreferences prefs,
  Future<KioskBootResult> Function()? bootstrap,
}) => DeviceBootGate<KioskBootResult>(
  // The staff boot shell speaks the kiosk's default language (settings-driven
  // language arrives with the customer shell inside the gate).
  locale: const Locale('ar'),
  brightness: Brightness.dark,
  autoRetryInterval: const Duration(seconds: 6),
  bootstrap: bootstrap ?? () => kioskBootstrap(prefs),
  isOffline: (r) => r.problem == RealDeviceAuthProblem.offline,
  builder: (result) {
    final seams = result.seams;
    if (seams == null) {
      return _KioskGateApp(
        home: switch (result.problem!) {
          RealDeviceAuthProblem.unconfigured =>
            const RealModeUnconfiguredView(),
          RealDeviceAuthProblem.signInUnavailable =>
            const DeviceSignInUnavailableView(),
          RealDeviceAuthProblem.offline => const OfflineBootView(),
        },
      );
    }
    return ProviderScope(
      overrides: kioskRealOverrides(seams),
      child: KioskApp(
        home: KioskTicker(
          child: KioskPairingGate(
            outcomes: seams.pairing,
            pairing: seams.pairing,
            onActivated: (_) {},
            shellBuilder: (_) => const _KioskLiveShell(),
          ),
        ),
      ),
    );
  },
);

/// The real device seams: one anonymous transport, one secret store, the
/// shared pairing repository, and the kiosk read client over both.
typedef KioskSeams = ({
  SupabaseDevicePairingRepository pairing,
  KioskLiveReads reads,
});

typedef KioskBootResult = ({KioskSeams? seams, RealDeviceAuthProblem? problem});

Future<KioskBootResult> kioskBootstrap(SharedPreferences prefs) async {
  final SupabaseBootstrapConfig config;
  try {
    config = SupabaseBootstrapConfig.fromEnvironment();
  } on SupabaseConfigException {
    return (seams: null, problem: RealDeviceAuthProblem.unconfigured);
  }
  final SyncRpcTransport transport;
  try {
    transport = await SupabaseAuthBootstrap(
      config: config,
    ).createAnonymousDeviceTransport();
  } catch (e) {
    return (
      seams: null,
      problem: isDeviceAuthNetworkError(e)
          ? RealDeviceAuthProblem.offline
          : RealDeviceAuthProblem.signInUnavailable,
    );
  }
  final DeviceSessionSecretStore store = kIsWeb
      ? SharedPreferencesDeviceSessionSecretStore(
          prefs,
          keyPrefix: kKioskDeviceSessionPrefix,
        )
      : FlutterSecureDeviceSessionStore();
  return (
    seams: (
      pairing: SupabaseDevicePairingRepository(
        transport: transport,
        secretStore: store,
      ),
      reads: KioskLiveReads(transport: transport, secretStore: store),
    ),
    problem: null,
  );
}

/// Real-mode provider seams: the live reads client, the live-published menu
/// (never the fixtures — an unloaded live menu renders the honest states),
/// the live tables view, and the Phase-3 ordering gate (OFF: no submit path
/// exists yet, so no fake confirmation either).
List<Override> kioskRealOverrides(KioskSeams seams) => [
  kioskLiveReadsProvider.overrideWithValue(seams.reads),
  kioskOrderingEnabledProvider.overrideWithValue(false),
  kioskMenuDataProvider.overrideWith((ref) {
    final live = ref.watch(kioskLiveProvider.select((s) => s.menu));
    return live ?? const KioskMenuData.empty();
  }),
  kioskMenuStatusProvider.overrideWith((ref) {
    final s = ref.watch(kioskLiveProvider);
    if (s.menu != null) {
      return s.menu!.isEmpty ? KioskMenuStatus.empty : KioskMenuStatus.ready;
    }
    if (s.menuLoading) return KioskMenuStatus.loading;
    return switch (s.menuError) {
      KioskReadFailureKind.network => KioskMenuStatus.reconnect,
      null => KioskMenuStatus.loading,
      _ => KioskMenuStatus.unavailable,
    };
  }),
  kioskTablesViewProvider.overrideWith((ref) {
    final s = ref.watch(kioskLiveProvider);
    final status = s.tablesLoading
        ? KioskTablesStatus.loading
        : switch (s.tablesError) {
            KioskReadFailureKind.network => KioskTablesStatus.reconnect,
            null when s.zones != null => KioskTablesStatus.ready,
            null => KioskTablesStatus.loading,
            _ => KioskTablesStatus.unavailable,
          };
    return (zones: s.zones ?? const [], status: status, live: true);
  }),
];

/// The customer shell in real mode: kicks the first live menu read on mount
/// and re-validates the device session after a long background gap.
class _KioskLiveShell extends ConsumerStatefulWidget {
  const _KioskLiveShell();

  @override
  ConsumerState<_KioskLiveShell> createState() => _KioskLiveShellState();
}

class _KioskLiveShellState extends ConsumerState<_KioskLiveShell>
    with WidgetsBindingObserver {
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(kioskLiveProvider.notifier).loadMenu();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = ref.read(kioskClockProvider)();
    } else if (state == AppLifecycleState.resumed) {
      final pausedAt = _pausedAt;
      _pausedAt = null;
      // Meaningful inactivity only — no per-resume network churn.
      if (pausedAt != null &&
          ref.read(kioskClockProvider)().difference(pausedAt) >
              const Duration(minutes: 5)) {
        ref.read(kioskLiveProvider.notifier).loadMenu();
      }
    }
  }

  @override
  Widget build(BuildContext context) => const KioskShell();
}

/// Minimal MaterialApp shell for gate-level problem views (outside the
/// customer ProviderScope, mirroring the POS boot-gate posture).
class _KioskGateApp extends StatelessWidget {
  const _KioskGateApp({required this.home});
  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: kioskTheme(),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    localeResolutionCallback: restoflowResolveLocale,
    home: home,
  );
}

class KioskApp extends ConsumerWidget {
  const KioskApp({super.key, this.home});

  /// Real mode injects the gated tree; null = the Phase-1 fixture shell.
  final Widget? home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(kioskFlowProvider.select((s) => s.lang));
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).kioskStart,
      debugShowCheckedModeBanner: false,
      theme: kioskTheme(),
      locale: Locale(lang),
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      localeResolutionCallback: restoflowResolveLocale,
      home: home ?? const KioskTicker(child: KioskShell()),
    );
  }
}

/// Production clock: forwards one [KioskFlowController.tick] per second. All
/// timer behavior lives in the controller so tests drive time by calling
/// tick() directly — this widget is the only wall-clock coupling.
class KioskTicker extends ConsumerStatefulWidget {
  const KioskTicker({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<KioskTicker> createState() => _KioskTickerState();
}

class _KioskTickerState extends ConsumerState<KioskTicker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      ref.read(kioskFlowProvider.notifier).tick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
