import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show nativePrintRasterizerProvider;
import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/data/durable_outbox_store.dart';
import 'src/data/recent_orders_store.dart';
import 'src/print/print_bridge.dart';
import 'src/pos_menu_screen.dart';
import 'src/pos_pairing_gate.dart';
import 'src/pos_pin_gate.dart';
import 'src/state/locale_controller.dart';
import 'src/state/outbox_controller.dart';
import 'src/state/pos_branch_tax.dart';
import 'src/state/pos_device_context.dart';
import 'src/state/pos_printer_assignments.dart';
import 'src/state/pos_session.dart';
import 'src/state/pos_shift_close_policy.dart';
import 'src/state/recent_orders_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Language before first frame: the persisted per-device choice wins; the
  // FIRST-LAUNCH default is ARABIC (the official language — sprint).
  final persistedLocale = await readPersistedLocale();
  // RF-114: the durable outbox persists to shared_preferences (localStorage on
  // web), so orders queued while offline survive a refresh / tab close / restart.
  final prefs = await SharedPreferences.getInstance();
  final locale = persistedLocale ?? const Locale('ar');
  // PILOT-OFFLINE-BOOT-001: run the real device-auth bootstrap behind a
  // retryable boot gate. If the venue Wi‑Fi / Supabase is unreachable at launch
  // (or after a tablet reboot) the gate shows a friendly, localized offline
  // screen with a working Retry that re-runs the bootstrap in place — no restart
  // and no developer help page. Every non-offline result (success, unconfigured,
  // sign-in-disabled) flows to [builder] exactly as before, and a successful
  // retry rebuilds the ProviderScope below with the fresh seams.
  runApp(
    DeviceBootGate(
      locale: locale,
      autoRetryInterval: const Duration(seconds: 6),
      bootstrap: () => _realDeviceAuth(prefs),
      isOffline: (real) => real.problem == RealDeviceAuthProblem.offline,
      builder: (real) => _posApp(prefs, locale, real),
    ),
  );
}

/// Builds the POS app (ProviderScope + [PosApp]) from a settled, NON-offline
/// device-auth result. Unchanged online behaviour: the same overrides and the
/// same [PosApp] as before — only reached once the boot gate has a result.
Widget _posApp(
  SharedPreferences prefs,
  Locale locale,
  ({_RealDeviceSeams? seams, RealDeviceAuthProblem? problem}) real,
) {
  final seams = real.seams;
  return ProviderScope(
    overrides: [
      initialLocaleProvider.overrideWithValue(locale),
      // PRINT-RTL-001: render Arabic/Hebrew (+ ₪/×) receipts as a raster image
      // on the native Android printer path so they print correctly instead of
      // "?????". Web/loopback stays ESC/POS text (the native path is Android-only).
      nativePrintRasterizerProvider.overrideWithValue(
        const FlutterReceiptRasterizer(),
      ),
      // RF-114: durable outbox + a periodic sweep so queued orders re-deliver
      // once the backend recovers (idempotent retries, D-022; no duplicates).
      durableOutboxStoreProvider.overrideWithValue(
        SharedPrefsOutboxStore(prefs),
      ),
      outboxAutoSweepIntervalProvider.overrideWithValue(
        const Duration(seconds: 25),
      ),
      // POS-ORDERS-AND-PAYMENT-001: the recent/unpaid-orders list persists to
      // shared_preferences too, so a "today + yesterday" window + each order's
      // paid/unpaid state survive a refresh / restart (per-device key).
      posRecentOrdersStoreProvider.overrideWithValue(
        SharedPrefsRecentOrdersStore(prefs),
      ),
      // RF-118: the client PIN-attempt lockout counter persists to
      // shared_preferences too, so a too-many-attempts cooldown survives a
      // refresh (a count + timestamp only — never a PIN; server is authoritative).
      pinAttemptStoreProvider.overrideWithValue(
        SharedPreferencesPinAttemptStore(prefs),
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
      // RF-113: the token-proven per-branch shift-close visibility policy
      // (owner-controlled from the Dashboard; default-true if unread).
      if (seams != null)
        posShiftClosePolicyReaderProvider.overrideWithValue(
          seams.shiftClosePolicy,
        ),
      // RF-117: the token-proven per-branch tax setting (owner-controlled;
      // default-OFF if unread — never invents a tax the owner did not set).
      if (seams != null)
        posBranchTaxReaderProvider.overrideWithValue(seams.branchTax),
      // Device settings sprint (Part G): the pairing repo IS the device
      // session manager (unpair = best-effort server self-revoke + local
      // clear) — exposed to the settings sheet's Unpair control.
      if (seams?.pairing case final DeviceSessionManager manager)
        posDeviceSessionManagerProvider.overrideWithValue(manager),
      // RF-115: a LOCAL print bridge, ONLY when a loopback URL is provided
      // (`--dart-define=RESTOFLOW_PRINT_BRIDGE_URL=http://127.0.0.1:8787`).
      // Off by default (dormant) so demo/tests are unaffected; a non-loopback
      // or unparseable URL is rejected fail-soft (stays dormant, no crash).
      if (_buildReceiptBridge() case final PosPrintBridge bridge)
        posPrintBridgeProvider.overrideWithValue(bridge),
    ],
    child: PosApp(
      devicePairingRepository: seams?.pairing,
      deviceStaffRepository: seams?.staff,
      realAuthProblem: real.problem,
    ),
  );
}

/// RF-115: builds the POS receipt print bridge from the compile-time loopback
/// URL, or null when unset/invalid. Loopback is ENFORCED by the client's guard
/// (`assertLoopbackBridgeUrl`); a non-loopback or malformed value fails soft
/// (dormant, no crash) so a misconfig never points the app at the network.
PosPrintBridge? _buildReceiptBridge() {
  const url = String.fromEnvironment('RESTOFLOW_PRINT_BRIDGE_URL');
  if (url.isEmpty) return null;
  try {
    final client = PrintBridgeClient(
      baseUrl: url,
      httpClient: HttpBridgeHttpClient(),
      role: 'receipt',
    );
    return EscPosReceiptBridge(
      dispatcher: PrintBridgeDispatcher(client: client),
    );
  } catch (_) {
    return null; // non-loopback / malformed URL -> dormant
  }
}

typedef _RealDeviceSeams = ({
  DevicePairingRepository pairing,
  DeviceStaffRepository staff,
  SyncRpcTransport transport,
  DeviceImageUrlResolver imageResolver,
  DevicePrinterAssignmentsReader printerAssignments,
  DeviceShiftClosePolicyReader shiftClosePolicy,
  DeviceBranchTaxReader branchTax,
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
_realDeviceAuth(SharedPreferences prefs) async {
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
    // LIVE-DEVICE-001: on WEB the paired-device credential must survive an F5 /
    // browser restart. flutter_secure_storage's web backing is not reliably
    // durable in the hosted build, so on web persist it via shared_preferences
    // (the same localStorage the RF-114 outbox uses); NATIVE keeps the OS
    // keychain. restore_device_session is token-proven server-side (no principal
    // binding), so persisting {deviceId, token} is all a restore needs.
    // POS-specific web prefix: /pos and /kds share one origin's localStorage, so
    // each surface MUST use its own key (else KDS reads+clears POS's credential).
    final DeviceSessionSecretStore store = kIsWeb
        ? SharedPreferencesDeviceSessionSecretStore(
            prefs,
            keyPrefix: kPosDeviceSessionPrefix,
          )
        : FlutterSecureDeviceSessionStore();
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
        // RF-113: same token-proven anonymous session reads the branch's
        // shift-close visibility policy.
        shiftClosePolicy: SupabaseDeviceShiftClosePolicyRepository(
          transport: transport,
          secretStore: store,
        ),
        // RF-117: same token-proven session reads the branch's tax setting.
        branchTax: SupabaseDeviceBranchTaxRepository(
          transport: transport,
          secretStore: store,
        ),
      ),
      problem: null,
    );
  } catch (e) {
    // PILOT-OFFLINE-BOOT-001: distinguish a NETWORK/offline failure (venue
    // Wi‑Fi down/slow — the retryable OfflineBootView) from a genuine auth
    // rejection like anonymous sign-ins disabled (a config the operator must
    // fix — keep the honest DeviceSignInUnavailableView). Never mask a real
    // config problem as "just offline". Fail closed either way: no fake pairing.
    return (
      seams: null,
      problem: isDeviceAuthNetworkError(e)
          ? RealDeviceAuthProblem.offline
          : RealDeviceAuthProblem.signInUnavailable,
    );
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
            // PILOT-OFFLINE-BOOT-001: the boot gate (main) intercepts `offline`
            // and shows the RETRYABLE OfflineBootView; this is only a defensive
            // fallback if it ever reaches here (no in-place retry available).
            RealDeviceAuthProblem.offline => const OfflineBootView(),
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
