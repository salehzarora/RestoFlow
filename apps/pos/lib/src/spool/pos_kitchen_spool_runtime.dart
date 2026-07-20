import 'package:crypto/crypto.dart' show sha256;
import 'dart:convert' show utf8;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory;
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart'
    show SecretValue, SecureKeyStore;
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show
        FlutterSecureDeviceSessionStore,
        KitchenModePrinterOnlyWithRevision,
        KitchenModeRevisionUnavailable,
        KitchenModeResult,
        KitchenModeVerifiedKds,
        SupabaseDeviceKitchenModeRepository,
        SupabaseDevicePrinterAssignmentsRepository,
        SupabaseKitchenDispatchAckRepository,
        SupabaseKitchenDispatchPullRepository,
        runtimeConfigProvider;

import '../data/ids.dart' show clientIdGeneratorProvider;
import '../state/pos_bluetooth_printer_config.dart'
    show posKitchenBluetoothPrinterConfigProvider;
import '../state/pos_device_context.dart' show posDeviceContextProvider;
import '../state/pos_network_printer_config.dart'
    show posKitchenNetworkPrinterConfigProvider;
import '../state/pos_printer_transport.dart'
    show posKitchenSelectedPrinterTransportProvider;
import '../state/pos_session.dart' show posAuthTransportProvider;
import 'flutter_secure_kitchen_spool_key_store.dart';
import 'kitchen_destination_resolver.dart';
import 'kitchen_dispatch_drain_coordinator.dart';
import 'kitchen_dispatch_import_coordinator.dart';
import 'pending_kitchen_ack_coordinator.dart';
import 'pos_kitchen_spool_key_flow.dart';
import 'pos_kitchen_spool_platform.dart';
import 'pos_secure_kitchen_mode_cache.dart';

/// KITCHEN-MODE-001C2B — the bounded native runtime coordinator.
///
/// LOCKED CADENCE (D4): runs ONLY on startup post-frame, app resume, and
/// explicit context refresh — no periodic timer, no worker, no print
/// transport, no submit gate, no UI.
///
/// Production behavior today:
///  * web / unsupported platform → typed no-op (fail closed);
///  * no paired device context / missing scope → no-op;
///  * verified KDS with NO existing spool file → ZERO footprint (no
///    directory, no database, no key);
///  * verified KDS with an existing spool file → open for SAFE
///    RECONCILIATION only (flush pending acks; never pull);
///  * printer_only → [KitchenModeRevisionUnavailable] under the current
///    server getter (D1) → fail closed, no pull;
///  * a trusted printer-only-with-revision state cannot arise in production
///    until 001C3 — and the server independently refuses pulls without a
///    readiness report, which nothing files until 001C3.
sealed class PosKitchenSpoolRunReport {
  const PosKitchenSpoolRunReport(this.detail);

  final String detail;
}

final class KitchenSpoolRunSkipped extends PosKitchenSpoolRunReport {
  const KitchenSpoolRunSkipped(super.detail);
}

final class KitchenSpoolRunReconciled extends PosKitchenSpoolRunReport {
  const KitchenSpoolRunReconciled(
    super.detail, {
    required this.acked,
    required this.retriesScheduled,
    required this.terminal,
  });

  final int acked;
  final int retriesScheduled;
  final int terminal;
}

final class KitchenSpoolRunBlocked extends PosKitchenSpoolRunReport {
  const KitchenSpoolRunBlocked(super.detail);
}

/// CORRECTION-001: the trusted printer-only run report — the full dormant
/// drain executed (pull → durable import → ack → next cursor) plus the
/// pending-acknowledgement flushes around it. Safe scalars only.
final class KitchenSpoolRunDrained extends PosKitchenSpoolRunReport {
  const KitchenSpoolRunDrained(
    super.detail, {
    required this.drain,
    required this.acked,
    required this.retriesScheduled,
    required this.terminal,
  });

  final KitchenDispatchDrainReport drain;

  /// Pending-ack flush totals (owed-from-before + newly-due), NOT the
  /// immediate in-import acknowledgements (those are inside [drain]).
  final int acked;
  final int retriesScheduled;
  final int terminal;
}

/// The kitchen destination could not be DETERMINED (assignments unreachable,
/// providers unavailable) — distinct from a definitive blocked resolution.
/// The drain fails closed instead of importing rows as blocked on a guess.
final class KitchenSpoolDestinationUnresolvableException implements Exception {
  const KitchenSpoolDestinationUnresolvableException();
}

final class PosKitchenSpoolRuntime {
  PosKitchenSpoolRuntime({
    required PosKitchenSpoolPlatform platform,
    required DeviceContext? Function() deviceContext,
    required DeviceSessionSecretStore? secretStore,
    required SupabaseDeviceKitchenModeRepository? modeRepository,
    required SupabaseKitchenDispatchAckRepository? ackRepository,
    required KitchenSpoolDatabaseFactory Function() databaseFactoryBuilder,
    SupabaseKitchenDispatchPullRepository? pullRepository,
    Future<KitchenModeResult> Function()? fetchMode,
    Future<KitchenDestinationResolution> Function()? destinationResolver,
    String Function()? localJobIdGenerator,
    PosSecureKitchenModeCache? modeCache,
    SecureKeyStore? keyStore,
    DateTime Function()? now,
  }) : _platform = platform,
       _deviceContext = deviceContext,
       _secretStore = secretStore,
       _modeRepository = modeRepository,
       _ackRepository = ackRepository,
       _databaseFactoryBuilder = databaseFactoryBuilder,
       _pullRepository = pullRepository,
       _fetchModeOverride = fetchMode,
       _destinationResolver = destinationResolver,
       _localJobIdGenerator = localJobIdGenerator,
       _modeCache = modeCache,
       _keyStore = keyStore,
       _now = now ?? DateTime.now;

  final PosKitchenSpoolPlatform _platform;
  final DeviceContext? Function() _deviceContext;
  final DeviceSessionSecretStore? _secretStore;
  final SupabaseDeviceKitchenModeRepository? _modeRepository;
  final SupabaseKitchenDispatchAckRepository? _ackRepository;
  final KitchenSpoolDatabaseFactory Function() _databaseFactoryBuilder;
  final SupabaseKitchenDispatchPullRepository? _pullRepository;

  /// Test seam ONLY for the mode decision: production wiring never sets it,
  /// so the mode always comes from the typed device-token repository — which
  /// can never construct a trusted printer-only-with-revision state (D1).
  final Future<KitchenModeResult> Function()? _fetchModeOverride;
  final Future<KitchenDestinationResolution> Function()? _destinationResolver;
  final String Function()? _localJobIdGenerator;
  final PosSecureKitchenModeCache? _modeCache;
  final SecureKeyStore? _keyStore;
  final DateTime Function() _now;

  KitchenSpoolDatabase? _db;
  bool _running = false;

  /// Startup post-frame hook (D4).
  Future<PosKitchenSpoolRunReport> onStartup() => _run();

  /// App-resume hook (D4).
  Future<PosKitchenSpoolRunReport> onResume() => _run();

  Future<PosKitchenSpoolRunReport> _run() async {
    if (_running) return const KitchenSpoolRunSkipped('already_running');
    _running = true;
    try {
      return await _runOnce();
    } on Object {
      // CORRECTION-001 (lifecycle async safety): the startup/resume hooks are
      // fire-and-forget, so NOTHING may escape as an unhandled async error.
      // The report is typed and REDACTED — never the raw error, an endpoint,
      // a payload, or a token — and it is a Blocked (never a silent success).
      return const KitchenSpoolRunBlocked('unexpected_failure');
    } finally {
      _running = false;
    }
  }

  Future<PosKitchenSpoolRunReport> _runOnce() async {
    // 1–2: platform + restored device scope (fail closed on anything less
    // than a complete tuple; the AAD requires every field).
    if (!_platform.supportsSecureSpool) {
      return const KitchenSpoolRunSkipped('web_unsupported');
    }
    final context = _deviceContext();
    final restaurantId = context?.restaurantId;
    final deviceId = context?.deviceId;
    if (context == null || restaurantId == null || deviceId == null) {
      return const KitchenSpoolRunSkipped('no_device_scope');
    }
    final modeRepository = _modeRepository;
    final ackRepository = _ackRepository;
    final secretStore = _secretStore;
    if (modeRepository == null ||
        ackRepository == null ||
        secretStore == null) {
      return const KitchenSpoolRunSkipped('real_backend_not_wired');
    }

    // 3: authoritative mode (typed; no silent kds fallback anywhere). The
    // override is a TEST seam; production always asks the repository.
    final KitchenModeResult mode =
        await (_fetchModeOverride ?? modeRepository.fetchMode)();
    await _cacheMode(mode, context, restaurantId, deviceId, secretStore);

    // CORRECTION-001: the TRUSTED printer-only path — the complete dormant
    // drain seam. Unreachable in production today (the mode repository can
    // never construct this state under D1, and the server independently
    // refuses pulls without a readiness report); tests inject it.
    if (mode is KitchenModePrinterOnlyWithRevision) {
      return _drainTrusted(context, restaurantId, deviceId, ackRepository);
    }

    final factory = _databaseFactoryBuilder();
    final spoolExists = await factory.spoolFileExists();

    if (mode is KitchenModeVerifiedKds && !spoolExists) {
      // 4: verified kds with no spool — ZERO footprint, nothing to do.
      return const KitchenSpoolRunSkipped('kds_no_spool_footprint');
    }
    if (mode is! KitchenModeVerifiedKds &&
        mode is! KitchenModeRevisionUnavailable) {
      // Session/transport/server failures: fail closed, touch nothing new.
      if (!spoolExists) {
        return const KitchenSpoolRunSkipped('mode_unknown_no_spool');
      }
    }

    // 5–7: an EXISTING spool reconciles safely (pending acks only). Pull is
    // impossible here in production: D1 blocks a trusted printer-only state
    // and the server additionally requires a readiness report (001C3).
    if (!spoolExists) {
      return const KitchenSpoolRunSkipped('printer_only_unavailable');
    }
    final KitchenSpoolDatabase db;
    try {
      db = _db ??= await factory.open();
    } on KitchenSpoolDatabaseUnavailableException catch (e) {
      return KitchenSpoolRunBlocked(e.reason);
    }
    final store = DriftKitchenSpoolStore(db);
    final keyFlow = PosKitchenSpoolKeyFlow(
      keyManager: KitchenSpoolKeyManager(
        _keyStore ?? FlutterSecureKitchenSpoolKeyStore(platform: _platform),
      ),
      store: store,
    );
    final capability = await keyFlow.evaluate();
    if (capability is! KitchenSpoolKeyReady &&
        capability is! KitchenSpoolKeyMissingProvisionable) {
      // BLOCKED states (missing-with-rows / corrupted / unavailable): keep
      // rows, keep key state, surface typed. Never wipe, never regenerate.
      return KitchenSpoolRunBlocked(capability.runtimeType.toString());
    }
    final acks = PendingKitchenAckCoordinator(
      store: store,
      ackRepository: ackRepository,
      now: _now,
    );
    final (acked, retries, terminal) = await acks.flush(
      deviceId: deviceId,
      branchId: context.branchId,
    );
    return KitchenSpoolRunReconciled(
      'reconciled',
      acked: acked,
      retriesScheduled: retries,
      terminal: terminal,
    );
  }

  /// CORRECTION-001: the bounded trusted printer-only sequence —
  /// 1. open the dedicated spool (existing or new) under policy;
  /// 2. inspect the key; provision ONLY in the missing-over-zero-rows state;
  /// 3. flush acknowledgements owed from previous runs;
  /// 4. pin the destination ONCE, fail closed if it cannot be determined;
  /// 5. drain: pull → durable import → ack → exact next cursor;
  /// 6. flush anything newly due;
  /// 7. return the typed report. NEVER prints.
  Future<PosKitchenSpoolRunReport> _drainTrusted(
    DeviceContext context,
    String restaurantId,
    String deviceId,
    SupabaseKitchenDispatchAckRepository ackRepository,
  ) async {
    final pullRepository = _pullRepository;
    final resolveDestination = _destinationResolver;
    final newLocalJobId = _localJobIdGenerator;
    if (pullRepository == null ||
        resolveDestination == null ||
        newLocalJobId == null) {
      return const KitchenSpoolRunSkipped('real_backend_not_wired');
    }
    final factory = _databaseFactoryBuilder();
    final KitchenSpoolDatabase db;
    try {
      db = _db ??= await factory.open();
    } on KitchenSpoolDatabaseUnavailableException catch (e) {
      return KitchenSpoolRunBlocked(e.reason);
    }
    final store = DriftKitchenSpoolStore(db);
    final keyManager = KitchenSpoolKeyManager(
      _keyStore ?? FlutterSecureKitchenSpoolKeyStore(platform: _platform),
    );
    final keyFlow = PosKitchenSpoolKeyFlow(
      keyManager: keyManager,
      store: store,
    );
    var capability = await keyFlow.evaluate();
    if (capability is KitchenSpoolKeyMissingProvisionable) {
      // D3: explicit provisioning, eligible ONLY over zero rows.
      capability = await keyFlow.provisionIfEligible();
    }
    if (capability is! KitchenSpoolKeyReady) {
      // BLOCKED (missing-with-rows / corrupted / unavailable): rows and key
      // state preserved; never wiped, never regenerated.
      return KitchenSpoolRunBlocked(capability.runtimeType.toString());
    }
    final SecretValue? key;
    try {
      key = await keyManager.readKey();
    } on Exception {
      return const KitchenSpoolRunBlocked('KitchenSpoolKeyUnavailable');
    }
    if (key == null) {
      return const KitchenSpoolRunBlocked('KitchenSpoolKeyUnavailable');
    }

    final acks = PendingKitchenAckCoordinator(
      store: store,
      ackRepository: ackRepository,
      now: _now,
    );
    // Acknowledgements owed from PREVIOUS runs flush before new work.
    final (preAcked, preRetries, preTerminal) = await acks.flush(
      deviceId: deviceId,
      branchId: context.branchId,
    );

    // The destination pins ONCE per run. A typed BLOCKED resolution is a
    // definitive configuration verdict (rows import as blockedConfiguration
    // and the server is told so); an UNDETERMINABLE state fails closed
    // instead of freezing a guess into durable rows.
    final KitchenDestinationResolution destination;
    try {
      destination = await resolveDestination();
    } on Exception {
      return const KitchenSpoolRunBlocked('kitchen_destination_unresolvable');
    }

    final drainReport = await KitchenDispatchDrainCoordinator(
      pullRepository: pullRepository,
      importCoordinator: KitchenDispatchImportCoordinator(
        store: store,
        cipher: AesGcmKitchenSpoolCipher(),
        key: key,
        scope: KitchenImportScope(
          organizationId: context.organizationId,
          restaurantId: restaurantId,
          branchId: context.branchId,
          deviceId: deviceId,
        ),
        destination: destination,
        ackRepository: ackRepository,
        localJobIdGenerator: newLocalJobId,
        now: _now,
      ),
    ).drain();

    // Anything newly pending that is already due flushes before returning.
    final (postAcked, postRetries, postTerminal) = await acks.flush(
      deviceId: deviceId,
      branchId: context.branchId,
    );
    return KitchenSpoolRunDrained(
      'drained',
      drain: drainReport,
      acked: preAcked + postAcked,
      retriesScheduled: preRetries + postRetries,
      terminal: preTerminal + postTerminal,
    );
  }

  Future<void> _cacheMode(
    KitchenModeResult mode,
    DeviceContext context,
    String restaurantId,
    String deviceId,
    DeviceSessionSecretStore secretStore,
  ) async {
    final cache = _modeCache;
    if (cache == null) return;
    // RevisionUnavailable caches printer_only WITHOUT a revision — an
    // UNTRUSTED record under D1 (importing stays impossible while the
    // revision is null). Only a trusted mode result carries one.
    final (String? wire, int? revision) = switch (mode) {
      KitchenModeVerifiedKds() => ('kds', null),
      KitchenModePrinterOnlyWithRevision(:final revision) => (
        'printer_only',
        revision,
      ),
      KitchenModeRevisionUnavailable() => ('printer_only', null),
      _ => (null, null), // failures never overwrite the cache
    };
    if (wire == null) return;
    final DeviceSessionCredential? cred;
    try {
      cred = await secretStore.read();
    } on Exception {
      return;
    }
    if (cred == null) return;
    try {
      await cache.write(
        KitchenModeCacheRecord(
          organizationId: context.organizationId,
          restaurantId: restaurantId,
          branchId: context.branchId,
          deviceId: deviceId,
          sessionFingerprint: sessionFingerprint(cred.sessionToken),
          mode: wire,
          // D1: null (untrusted) unless the mode result itself carried a
          // trusted revision — impossible from production before 001C3.
          modeRevision: revision,
          verifiedAt: _now(),
        ),
      );
    } on Exception {
      // Cache write failure is non-fatal; the cache stays UNKNOWN.
    }
  }

  /// Disposes runtime handles on logout/scope change (rows and key are
  /// deliberately preserved — scope-bound, never wiped automatically).
  Future<void> dispose() async {
    await _db?.close();
    _db = null;
  }
}

/// Deterministic NON-SECRET digest of the device-session token (the secure
/// mode-cache binding; never the token itself).
String sessionFingerprint(String sessionToken) =>
    sha256.convert(utf8.encode(sessionToken)).toString();

/// The composition seam: self-assembles from existing providers; inert on
/// web (platform seam), in demo mode, and whenever the real transport is
/// absent. `main.dart` stays untouched — the ONLY caller is the
/// [PosSyncLifecycle] startup/resume hook (D4).
final posKitchenSpoolRuntimeProvider = Provider<PosKitchenSpoolRuntime?>((ref) {
  const platform = PosKitchenSpoolPlatform();
  if (!platform.supportsSecureSpool) return null;
  if (ref.watch(runtimeConfigProvider).isDemoMode) return null;
  final transport = ref.watch(posAuthTransportProvider);
  if (transport == null) return null;
  final secretStore = FlutterSecureDeviceSessionStoreProvider.of();
  return PosKitchenSpoolRuntime(
    platform: platform,
    deviceContext: () => ref.read(posDeviceContextProvider),
    secretStore: secretStore,
    modeRepository: SupabaseDeviceKitchenModeRepository(
      transport: transport,
      secretStore: secretStore,
    ),
    ackRepository: SupabaseKitchenDispatchAckRepository(
      transport: transport,
      secretStore: secretStore,
    ),
    databaseFactoryBuilder: () => KitchenSpoolDatabaseFactory(
      documentsDirectoryProvider: getApplicationDocumentsDirectory,
    ),
    // CORRECTION-001: the dormant drain seam is FULLY wired — but it can
    // only ever run for a trusted printer-only-with-revision mode result,
    // which the production mode repository can never construct (D1), and
    // the server independently refuses pulls without a readiness report.
    pullRepository: SupabaseKitchenDispatchPullRepository(
      transport: transport,
      secretStore: secretStore,
    ),
    localJobIdGenerator: () => ref.read(clientIdGeneratorProvider).newId(),
    destinationResolver: () async {
      // ACCEPTED LIMITATION (correction pass): the assignment contract has
      // no stable local↔server printer identity — the D2 binding (enabled +
      // kitchen purpose + matching transport + 80mm) is the one-printer
      // pilot's contract; a stable assignment id is a 001C3+ additive
      // extension.
      final assignments = await SupabaseDevicePrinterAssignmentsRepository(
        transport: transport,
        secretStore: secretStore,
      ).load();
      final snapshot = assignments.fold<DevicePrinterAssignments?>(
        (value) => value,
        (_) => null,
      );
      if (snapshot == null) {
        // Could not DETERMINE the assignment state — fail closed rather
        // than importing rows as blocked on a guess.
        throw const KitchenSpoolDestinationUnresolvableException();
      }
      final selected = await ref.read(
        posKitchenSelectedPrinterTransportProvider.future,
      );
      final network = await ref.read(
        posKitchenNetworkPrinterConfigProvider.future,
      );
      final bluetooth = await ref.read(
        posKitchenBluetoothPrinterConfigProvider.future,
      );
      return const KitchenDestinationResolver().resolve(
        selectedTransport: selected,
        networkConfig: network,
        bluetoothConfig: bluetooth,
        assignments: snapshot,
      );
    },
    modeCache: PosSecureKitchenModeCache(platform: platform),
  );
});

/// Small indirection so tests can see exactly which secret store the
/// composition uses (the SAME Keystore-backed store as device pairing).
abstract final class FlutterSecureDeviceSessionStoreProvider {
  static DeviceSessionSecretStore of() => FlutterSecureDeviceSessionStore();
}
