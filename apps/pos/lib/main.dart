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

import 'src/data/draft_recovery_store.dart';
import 'src/data/durable_outbox_store.dart';
import 'src/state/addition_controller.dart' show additionJournalStoreProvider;
import 'src/data/parked_carts_store.dart';
import 'src/data/ready_notifications_store.dart';
import 'src/data/addition_journal_store.dart';
import 'src/data/recent_orders_store.dart';
import 'src/data/round_print_claim_store.dart';
import 'src/print/pos_kitchen_ticket_printer.dart'
    show posRoundPrintClaimStoreProvider;
import 'src/data/sync_cursor_store.dart';
import 'src/print/print_bridge.dart';
import 'src/pos_menu_screen.dart';
import 'src/pos_pairing_gate.dart';
import 'src/pos_pin_gate.dart';
import 'src/state/locale_controller.dart';
import 'src/state/order_sync_controller.dart';
import 'src/state/outbox_controller.dart';
import 'src/state/pos_branch_tax.dart';
import 'src/state/pos_device_context.dart';
import 'src/state/pos_printer_assignments.dart';
import 'src/state/pos_receipt_logo.dart' show posReceiptLogoReaderProvider;
import 'src/state/pos_session.dart';
import 'src/state/pos_shift_close_policy.dart';
import 'src/state/draft_recovery_controller.dart';
import 'src/state/ready_notifications_controller.dart';
import 'src/state/recent_orders_controller.dart';
import 'src/widgets/pos_sync_lifecycle.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Language before first frame: the persisted per-device choice wins; the
  // FIRST-LAUNCH default is ARABIC (the official language — sprint).
  final persistedLocale = await readPersistedLocale();
  // RF-114: the durable outbox persists to shared_preferences (localStorage on
  // web), so orders queued while offline survive a refresh / tab close / restart.
  final prefs = await SharedPreferences.getInstance();
  final locale = persistedLocale ?? const Locale('ar');
  // PILOT-OFFLINE-BOOT-001 + [POS-OFFLINE-OPERATIONS-002] Pass A: run the real
  // device-auth bootstrap behind a retryable boot gate. If the venue Wi‑Fi /
  // Supabase is unreachable at launch (or after a tablet reboot) the gate
  // either mounts the DEGRADED offline composition (when durable pairing
  // evidence exists — see [PosBootCoordinator]) or shows a friendly, localized
  // offline screen with a working Retry. Every non-offline result (success,
  // unconfigured, sign-in-disabled) flows to the app exactly as before.
  runApp(
    buildPosBootRoot(
      prefs: prefs,
      locale: locale,
      autoRetryInterval: const Duration(seconds: 6),
    ),
  );
}

/// Builds the REAL POS boot root: [DeviceBootGate] over a [PosBootCoordinator].
///
/// Public and parameterized so the offline cold-boot suite can pump the SAME
/// composition `main()` runs (with injected sign-in/store seams and test-safe
/// timer settings) instead of a parallel approximation that could drift.
/// Production callers pass only [prefs], [locale] and [autoRetryInterval].
Widget buildPosBootRoot({
  required SharedPreferences prefs,
  required Locale locale,
  PosBootCoordinator? coordinator,
  Duration? autoRetryInterval,
  bool? demoModeOverride,
  bool includePeriodicWork = true,
  List<Override> extraOverrides = const [],
}) {
  final boot =
      coordinator ??
      PosBootCoordinator(prefs: prefs, demoMode: demoModeOverride);
  // Pass A: the ProviderScope override LIST is memoized PER SEAMS IDENTITY.
  // The gate re-invokes [builder] on every retry transition (degraded →
  // degraded → upgraded), and `ProviderContainer.updateOverrides` must then
  // receive the IDENTICAL override objects, or the scope would treat the
  // rebuild as an override change. Identical seams => identical list.
  List<Override>? cachedOverrides;
  PosDeviceSeams? cachedSeams;
  return DeviceBootGate<PosBootResult>(
    locale: locale,
    autoRetryInterval: autoRetryInterval,
    bootstrap: boot.bootstrap,
    isOffline: (real) => real.problem == RealDeviceAuthProblem.offline,
    // Pass A: an offline result WITH seams is the degraded hold-mode
    // composition over durable pairing evidence — mount the app and keep the
    // gate's retry loop running (the later success upgrades in place).
    mountsWhileOffline: (real) => real.seams != null,
    builder: (real) {
      var overrides = cachedOverrides;
      if (overrides == null || !identical(cachedSeams, real.seams)) {
        overrides = _posOverrides(
          prefs,
          locale,
          real.seams,
          includePeriodicWork: includePeriodicWork,
          extraOverrides: extraOverrides,
        );
        cachedOverrides = overrides;
        cachedSeams = real.seams;
      }
      return _posApp(overrides, real, demoModeOverride: demoModeOverride);
    },
  );
}

/// The POS ProviderScope override list for [seams] (real, degraded, or null).
/// Built ONCE per seams identity by [buildPosBootRoot] and reused verbatim on
/// every gate rebuild — see the memoization note there.
///
/// [includePeriodicWork] and [extraOverrides] are test seams threaded from
/// [buildPosBootRoot] (production passes defaults). They are FIXED per root,
/// so the override list keeps an identical shape across the gate's rebuilds —
/// which is what lets a degraded tree survive its in-place transport upgrade
/// without a remount.
List<Override> _posOverrides(
  SharedPreferences prefs,
  Locale locale,
  PosDeviceSeams? seams, {
  bool includePeriodicWork = true,
  List<Override> extraOverrides = const [],
}) => [
  initialLocaleProvider.overrideWithValue(locale),
  // PRINT-RTL-001: render Arabic/Hebrew (+ ₪/×) receipts as a raster image
  // on the native Android printer path so they print correctly instead of
  // "?????". Web/loopback stays ESC/POS text (the native path is Android-only).
  nativePrintRasterizerProvider.overrideWithValue(
    const FlutterReceiptRasterizer(),
  ),
  // RF-114: durable outbox + a periodic sweep so queued orders re-deliver
  // once the backend recovers (idempotent retries, D-022; no duplicates).
  durableOutboxStoreProvider.overrideWithValue(SharedPrefsOutboxStore(prefs)),
  if (includePeriodicWork)
    outboxAutoSweepIntervalProvider.overrideWithValue(
      const Duration(seconds: 25),
    ),
  // MONEY-DURABLE-ADDITIONS-003C: the durable amendment journal. One frozen
  // identity + one byte-identical payload survive process death, so an
  // uncertain Add-items operation is REPLAYED under its own
  // local_operation_id (which app.add_order_items answers with the same
  // round) instead of being re-keyed as a second round.
  additionJournalStoreProvider.overrideWithValue(
    SharedPrefsAdditionJournalStore(prefs),
  ),
  // The DURABLE automatic-kitchen-print claim, scoped to this device's
  // session. Without it the exactly-once guard is session-only, so a process
  // that dies after an amendment was applied comes back, replays the
  // operation (which correctly returns the SAME round) and prints the
  // kitchen a second ticket for food it is already cooking. Scoped like the
  // outbox: one device never reads another's claims.
  posRoundPrintClaimStoreProvider.overrideWith((ref) {
    final store = SharedPrefsRoundPrintClaimStore(prefs);
    store.scopeKey = ref.watch(posSyncSessionProvider)?.deviceId ?? '';
    return store;
  }),
  // POS-ORDERS-AND-PAYMENT-001: the recent/unpaid-orders list persists to
  // shared_preferences too, so a "today + yesterday" window + each order's
  // paid/unpaid state survive a refresh / restart (per-device key).
  posRecentOrdersStoreProvider.overrideWithValue(
    SharedPrefsRecentOrdersStore(prefs),
  ),
  // MENU-ORDER-001 (Codex #8/#9): a permanently-rejected order's recovery —
  // its draft with the Dashboard menu ranks, order type, table, customer name
  // — persists too, so Back to cart survives a refresh / restart and the
  // corrected resubmit still prints in menu order.
  posDraftRecoveryStoreProvider.overrideWithValue(
    SharedPrefsDraftRecoveryStore(prefs),
  ),
  // PARKED-CARTS-001: held (parked) carts are durable and SCOPE-PARTITIONED,
  // so a cart set aside to serve another customer survives an ordinary
  // restart, a force-stop and a logout — and is never inherited by another
  // branch or device. Purely local: never synced, never a server order.
  parkedCartsStoreProvider.overrideWithValue(
    SharedPrefsParkedCartsStore(prefs),
  ),
  // POS-OPERATIONS-SYNC-001: the incremental pull cursor is durable and
  // SCOPE-PARTITIONED (org/restaurant/branch/device). Replaying one branch's
  // cursor against another would skip that branch's whole history and present
  // an empty, confident, completely wrong board.
  posSyncCursorStoreProvider.overrideWithValue(
    SharedPrefsSyncCursorStore(prefs),
  ),
  // The ~30s re-pull, armed ONLY while an orders surface is on screen (the
  // coordinator stops it when the last one closes). Null in tests.
  if (includePeriodicWork)
    posSyncPollIntervalProvider.overrideWithValue(
      PosOrderSyncController.defaultPeriodicInterval,
    ),
  // PSC-001A: the persisted ready-notification envelope (cursor + records
  // + read state, one atomic write per scope key) and the ~7s foreground
  // ready-feed tick + ~8s banner auto-dismiss. All null/in-memory in tests.
  readyNotificationsStoreProvider.overrideWithValue(
    SharedPrefsReadyNotificationsStore(prefs),
  ),
  if (includePeriodicWork)
    posReadyFeedPollIntervalProvider.overrideWithValue(
      PosReadyNotificationsController.defaultPollInterval,
    ),
  if (includePeriodicWork)
    posReadyAlertAutoDismissProvider.overrideWithValue(
      const Duration(seconds: 8),
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
  // PRINT-BRANDING-LOGO-001: the token-proven per-device restaurant-logo
  // downloader (fail-soft — a missing reader keeps receipts text-only).
  if (seams != null)
    posReceiptLogoReaderProvider.overrideWithValue(seams.receiptLogo),
  // RF-113: the token-proven per-branch shift-close visibility policy
  // (owner-controlled from the Dashboard; default-true if unread).
  if (seams != null)
    posShiftClosePolicyReaderProvider.overrideWithValue(seams.shiftClosePolicy),
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
  // Test seam (Pass A): the cold-boot suite forces real mode + short
  // watchdogs INSIDE this scope. Empty in production; fixed per root.
  ...extraOverrides,
];

/// Builds the POS app (ProviderScope + [PosApp]) from a settled device-auth
/// result — the normal online seams, an honest problem page, or (Pass A) the
/// DEGRADED hold-mode seams over durable pairing evidence. Unchanged online
/// behaviour: the same overrides and the same [PosApp] as before.
Widget _posApp(
  List<Override> overrides,
  PosBootResult real, {
  bool? demoModeOverride,
}) {
  final seams = real.seams;
  return ProviderScope(
    overrides: overrides,
    child: PosApp(
      demoMode: demoModeOverride,
      devicePairingRepository: seams?.pairing,
      deviceStaffRepository: seams?.staff,
      realAuthProblem: real.problem,
      // Pass A: non-null ONLY for a degraded offline boot — lets the pairing
      // gate re-verify server-side the moment the boot retry reconnects.
      upgradableTransport: seams?.upgradable,
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

/// The REAL device-auth seams for production POS (RF-161 + sprint).
///
/// [POS-OFFLINE-OPERATIONS-002] Pass A: the record gains [upgradable] — the
/// shared hold-mode transport handle, non-null ONLY when these are the
/// DEGRADED offline-boot seams (every transport-backed repo above rides it).
typedef PosDeviceSeams = ({
  DevicePairingRepository pairing,
  DeviceStaffRepository staff,
  SyncRpcTransport transport,
  DeviceImageUrlResolver imageResolver,
  DevicePrinterAssignmentsReader printerAssignments,
  DeviceReceiptLogoReader receiptLogo,
  DeviceShiftClosePolicyReader shiftClosePolicy,
  DeviceBranchTaxReader branchTax,
  UpgradableSyncTransport? upgradable,
});

/// A settled POS boot result: seams (real or degraded) and/or the honest
/// reason none could be built.
typedef PosBootResult = ({
  PosDeviceSeams? seams,
  RealDeviceAuthProblem? problem,
});

/// What [SupabaseAuthBootstrap.createAnonymousDeviceSession] answers —
/// structural typedef so the cold-boot suite can inject a scripted session.
typedef PosAnonymousDeviceSession = ({
  SyncRpcTransport transport,
  DeviceImageUrlResolver imageUrlResolver,
  DeviceReceiptLogoReader receiptLogoReader,
});

/// RF-161 + sprint + [POS-OFFLINE-OPERATIONS-002] Pass A: the POS device-auth
/// boot coordinator.
///
/// In real mode with a valid Supabase config it signs the device in
/// anonymously (an authenticated, membership-less principal — DECISION D-011,
/// no service-role key) and returns the backend-backed pairing repository, the
/// token-proven staff directory for the PIN pad, and the shared transport.
/// When the seams cannot be built, `problem` says WHY, so the app can show an
/// honest state — NEVER a fake pairing or staff list.
///
/// Pass A adds the DEGRADED OFFLINE BOOT: when sign-in fails at the NETWORK
/// level AND durable local pairing evidence exists (a stored device secret
/// plus a valid cached pairing scope minted by a prior server-verified
/// pairing), the coordinator composes the same seam shape over ONE shared
/// [UpgradableSyncTransport] in hold mode — every call fails transient with
/// ZERO network IO, so the degraded tree can never reach the server (an
/// unauthenticated call would 42501 and poison the outbox with a false
/// AUTH_HOLD). The boot gate mounts the app over these seams while its retry
/// loop keeps running; the first successful retry UPGRADES the transport in
/// place (`upgrade(realTransport)`), keeping the seams object — and therefore
/// the whole widget tree and any in-progress cart — identity-stable. With NO
/// pairing evidence, behaviour is byte-identical to before (OfflineBootView).
///
/// Client-bound extras that genuinely need an authenticated SupabaseClient
/// (storage signed URLs, the receipt-logo download, realtime) stay ABSENT in a
/// degraded boot — even after the upgrade, until the next full boot. That is
/// the same fail-soft absence the web/demo compositions already render
/// (imageless cards, text-only receipts); realtime is an enhancement, never
/// the source of truth (D-010).
class PosBootCoordinator {
  PosBootCoordinator({
    required SharedPreferences prefs,
    Future<PosAnonymousDeviceSession> Function()? createSession,
    DeviceSessionSecretStore? secretStore,
    bool? demoMode,
  }) : _createSession = createSession ?? _defaultCreateSession,
       _secretStore = secretStore ?? _defaultSecretStore(prefs),
       _demoMode = demoMode ?? authDemoModeEnabled();

  final Future<PosAnonymousDeviceSession> Function() _createSession;
  final DeviceSessionSecretStore _secretStore;
  final bool _demoMode;

  /// The memoized DEGRADED seams (identity-stable across retries), or null.
  PosDeviceSeams? _degradedSeams;

  /// The post-upgrade settled result: once set, retries stop (non-offline).
  PosBootResult? _settled;

  /// The shared hold-mode transport of the degraded boot, or null (tests).
  UpgradableSyncTransport? get upgradableTransport =>
      _degradedSeams?.upgradable;

  /// LIVE-DEVICE-001: on WEB the paired-device credential must survive an F5 /
  /// browser restart. flutter_secure_storage's web backing is not reliably
  /// durable in the hosted build, so on web persist it via shared_preferences
  /// (the same localStorage the RF-114 outbox uses); NATIVE keeps the OS
  /// keychain. restore_device_session is token-proven server-side (no principal
  /// binding), so persisting {deviceId, token} is all a restore needs.
  /// POS-specific web prefix: /pos and /kds share one origin's localStorage, so
  /// each surface MUST use its own key (else KDS reads+clears POS's credential).
  static DeviceSessionSecretStore _defaultSecretStore(
    SharedPreferences prefs,
  ) => kIsWeb
      ? SharedPreferencesDeviceSessionSecretStore(
          prefs,
          keyPrefix: kPosDeviceSessionPrefix,
        )
      : FlutterSecureDeviceSessionStore();

  static Future<PosAnonymousDeviceSession> _defaultCreateSession() async {
    // Throws SupabaseConfigException when unconfigured (mapped in bootstrap).
    final config = SupabaseBootstrapConfig.fromEnvironment();
    return SupabaseAuthBootstrap(config: config).createAnonymousDeviceSession();
  }

  /// Runs one boot attempt. Called by [DeviceBootGate] at launch and again on
  /// every retry while the result stays offline.
  Future<PosBootResult> bootstrap() async {
    final settled = _settled;
    if (settled != null) return settled;
    if (_demoMode) return (seams: null, problem: null);
    final PosAnonymousDeviceSession session;
    try {
      session = await _createSession();
    } on SupabaseConfigException {
      return (seams: null, problem: RealDeviceAuthProblem.unconfigured);
    } catch (e) {
      // PILOT-OFFLINE-BOOT-001: distinguish a NETWORK/offline failure (venue
      // Wi‑Fi down/slow) from a genuine auth rejection like anonymous
      // sign-ins disabled (a config the operator must fix). Never mask a real
      // config problem as "just offline"… UNLESS a degraded tree is already
      // mounted: tearing it down mid-shift would destroy in-progress work, so
      // it stays up (still retrying) and the honest help page waits for the
      // next cold boot. Fail closed either way: no fake pairing.
      if (isDeviceAuthNetworkError(e) || _degradedSeams != null) {
        return _offlineResult();
      }
      return (seams: null, problem: RealDeviceAuthProblem.signInUnavailable);
    }
    final degraded = _degradedSeams;
    if (degraded != null) {
      // Pass A: the retry succeeded AFTER a degraded mount — DO NOT rebuild
      // the subtree. Upgrade the shared transport in place (fires the pairing
      // gate's server re-verification) and settle on the SAME seams object.
      degraded.upgradable?.upgrade(session.transport);
      final result = (seams: degraded, problem: null);
      _settled = result;
      return result;
    }
    return (seams: _realSeams(session), problem: null);
  }

  /// The offline result: the memoized degraded seams when pairing evidence
  /// exists (built at most once), else the seam-less blocked-offline result.
  Future<PosBootResult> _offlineResult() async {
    final seams = _degradedSeams ?? await _tryBuildDegradedSeams();
    return (seams: seams, problem: RealDeviceAuthProblem.offline);
  }

  /// Builds the DEGRADED seams iff durable pairing evidence exists: a stored
  /// device secret AND a valid cached POS pairing scope for the SAME device
  /// id. Fail closed on anything less — unreadable stores, a missing cache, a
  /// scope of another surface — by returning null (blocked OfflineBootView,
  /// byte-identical to today). Never performs network IO.
  Future<PosDeviceSeams?> _tryBuildDegradedSeams() async {
    final store = _secretStore;
    DeviceSessionCredential? cred;
    try {
      cred = await store.read();
    } catch (_) {
      cred = null;
    }
    if (cred == null || cred.deviceId.isEmpty) return null;
    // Typed as Object so the `is` check PROMOTES (the cache facet is
    // co-implemented by the stores, not part of the secret-store interface).
    final Object cacheStore = store;
    if (cacheStore is! DeviceContextCacheStore) return null;
    DeviceContext? cached;
    try {
      cached = await cacheStore.readCachedContext(
        expectedDeviceId: cred.deviceId,
      );
    } catch (_) {
      cached = null;
    }
    if (cached == null || !cached.isPaired || cached.deviceType != 'pos') {
      return null;
    }
    final upgradable = UpgradableSyncTransport();
    return _degradedSeams = (
      pairing: SupabaseDevicePairingRepository(
        transport: upgradable,
        secretStore: store,
      ),
      staff: SupabaseDeviceStaffRepository(
        transport: upgradable,
        secretStore: store,
      ),
      transport: upgradable,
      // No authenticated client exists: images are absent (imageless cards)…
      imageResolver: const _AbsentDeviceImageUrlResolver(),
      printerAssignments: SupabaseDevicePrinterAssignmentsRepository(
        transport: upgradable,
        secretStore: store,
      ),
      // …and the receipt logo is absent (text-only receipts). Both fail-soft.
      receiptLogo: const _AbsentDeviceReceiptLogoReader(),
      shiftClosePolicy: SupabaseDeviceShiftClosePolicyRepository(
        transport: upgradable,
        secretStore: store,
      ),
      branchTax: SupabaseDeviceBranchTaxRepository(
        transport: upgradable,
        secretStore: store,
      ),
      upgradable: upgradable,
    );
  }

  /// The normal ONLINE seams — unchanged wiring from before Pass A.
  PosDeviceSeams _realSeams(PosAnonymousDeviceSession session) {
    final transport = session.transport;
    final store = _secretStore;
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
      // Read-only menu-image signed URLs on the same anonymous session
      // (server-gated by the POS device storage policy — T-014 keeps KDS out).
      imageResolver: session.imageUrlResolver,
      printerAssignments: SupabaseDevicePrinterAssignmentsRepository(
        transport: transport,
        secretStore: store,
      ),
      // PRINT-BRANDING-LOGO-001: the device's read-only restaurant-logo
      // downloader on the SAME anonymous session (restaurant-logos bucket,
      // server-gated device SELECT policy; KDS excluded).
      receiptLogo: session.receiptLogoReader,
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
      upgradable: null,
    );
  }
}

/// Pass A: the degraded boot's absent storage capability — signed URLs never
/// resolve, so every card renders imageless (fail-soft; images are an
/// enhancement, never load-bearing). Stays absent until the next full boot.
class _AbsentDeviceImageUrlResolver implements DeviceImageUrlResolver {
  const _AbsentDeviceImageUrlResolver();

  @override
  Future<Map<String, String>> signedUrlsFor(
    List<String> objectKeys, {
    Duration expiresIn = const Duration(minutes: 30),
  }) async => const {};
}

/// Pass A: the degraded boot's absent logo capability — receipts print
/// text-only, exactly as when no logo is configured.
class _AbsentDeviceReceiptLogoReader implements DeviceReceiptLogoReader {
  const _AbsentDeviceReceiptLogoReader();

  @override
  Future<ReceiptLogoBytes?> load(String objectPath) async => null;
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
    this.upgradableTransport,
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

  /// [POS-OFFLINE-OPERATIONS-002] Pass A: the shared hold-mode transport of a
  /// DEGRADED offline boot, or null (normal online boot, demo, tests). The
  /// pairing gate subscribes to its single upgrade event to re-verify the
  /// cached pairing against the server the moment connectivity returns.
  final UpgradableSyncTransport? upgradableTransport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = AuthGatedHome(
      surface: AppSurface.pos,
      demoHome: const PosSyncLifecycle(child: PosMenuScreen()),
      onReady: (context, state) =>
          const PosSyncLifecycle(child: PosMenuScreen()),
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
            upgradeSignal: upgradableTransport,
            // Paired -> staff PIN session -> the POS surface (D-006). The PIN
            // session IS the operator identity on a paired device; no GoTrue
            // human login happens on the POS itself.
            signedInBuilder: (context, device) => PosPinGate(
              device: device,
              staffRepository: deviceStaffRepository,
              child: const PosSyncLifecycle(child: PosMenuScreen()),
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
