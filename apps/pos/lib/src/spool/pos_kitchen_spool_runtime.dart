import 'package:crypto/crypto.dart' show sha256;
import 'dart:convert' show utf8;

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart'
    show SecretValue, SecureKeyStore;
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show
        KitchenModePrinterOnlyWithRevision,
        KitchenModeRevisionUnavailable,
        KitchenModeResult,
        KitchenModeVerifiedKds,
        SupabaseDeviceKitchenModeRepository,
        SupabaseKitchenDispatchAckRepository,
        SupabaseKitchenDispatchPullRepository;

import 'package:restoflow_printing/restoflow_printing.dart'
    show PrinterDestinationSendGate;

import 'flutter_secure_kitchen_spool_key_store.dart';
import 'kitchen_destination_resolver.dart';
import 'kitchen_dispatch_drain_coordinator.dart';
import 'kitchen_dispatch_import_coordinator.dart';
import 'kitchen_print_worker.dart';
import 'kitchen_ticket_renderer.dart';
import 'kitchen_void_reconciliation.dart';
import 'pending_kitchen_ack_coordinator.dart';
import 'pos_kitchen_spool_hooks.dart';
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

/// KITCHEN-MODE-001C2C PASS 2 — the trusted printer-only FULL run report:
/// stale-printing recovery, ack reconciliation, VOID sweeps, the dispatch
/// drain, and the bounded worker run. Safe scalars only.
final class KitchenSpoolRunWorked extends PosKitchenSpoolRunReport {
  const KitchenSpoolRunWorked(
    super.detail, {
    required this.drain,
    required this.worker,
    required this.recoveredStale,
    required this.voidSuperseded,
    required this.voidLinks,
    required this.acked,
    required this.retriesScheduled,
    required this.terminal,
  });

  final KitchenDispatchDrainReport drain;
  final KitchenWorkerRunReport worker;

  /// Stale printing rows recovered to possiblyPrinted at run start.
  final int recoveredStale;
  final int voidSuperseded;
  final int voidLinks;

  /// Pending-ack coordinator flush totals across the run's flush points.
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

final class PosKitchenSpoolRuntime implements PosKitchenSpoolLifecycleHooks {
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
    KitchenTicketRenderer? renderer,
    KitchenNetworkSend? networkSend,
    KitchenBluetoothSend? bluetoothSend,
    PrinterDestinationSendGate? sendGate,
    int maxWorkerJobsPerRun = 20,
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
       _renderer = renderer,
       _networkSend = networkSend,
       _bluetoothSend = bluetoothSend,
       _sendGate = sendGate,
       _maxWorkerJobsPerRun = maxWorkerJobsPerRun,
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
  final KitchenTicketRenderer? _renderer;
  final KitchenNetworkSend? _networkSend;
  final KitchenBluetoothSend? _bluetoothSend;
  final PrinterDestinationSendGate? _sendGate;
  final int _maxWorkerJobsPerRun;
  final PosSecureKitchenModeCache? _modeCache;
  final SecureKeyStore? _keyStore;
  final DateTime Function() _now;

  KitchenSpoolDatabase? _db;
  bool _running = false;
  bool _disposed = false;

  /// Startup post-frame hook (D4).
  @override
  Future<PosKitchenSpoolRunReport> onStartup() => _run();

  /// App-resume hook (D4).
  @override
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

  /// KITCHEN-MODE-001C2C PASS 2 — the LOCKED trusted printer-only run:
  /// 1. open the dedicated spool DB under the existing policy;
  /// 2. inspect/provision the key ONLY under D3;
  /// 3. recover stale printing rows (→ possiblyPrinted + pending ack);
  /// 4. flush due pending acknowledgements from previous runs;
  /// 5. reconcile local VOID evidence before any new claim;
  /// 6. drain/import new dispatches (the C2B coordinator);
  /// 7. (import acks flush inside the drain + coordinator);
  /// 8. re-run VOID reconciliation after the drain;
  /// 9. run the bounded kitchen print worker;
  /// 10. flush worker-generated pending acknowledgements;
  /// 11. return the typed safe report. No timer; disposal-safe.
  Future<PosKitchenSpoolRunReport> _drainTrusted(
    DeviceContext context,
    String restaurantId,
    String deviceId,
    SupabaseKitchenDispatchAckRepository ackRepository,
  ) async {
    final pullRepository = _pullRepository;
    final resolveDestination = _destinationResolver;
    final newLocalJobId = _localJobIdGenerator;
    final renderer = _renderer;
    final networkSend = _networkSend;
    final bluetoothSend = _bluetoothSend;
    final sendGate = _sendGate;
    if (pullRepository == null ||
        resolveDestination == null ||
        newLocalJobId == null ||
        renderer == null ||
        networkSend == null ||
        bluetoothSend == null ||
        sendGate == null) {
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

    // 3: stale-printing recovery BEFORE anything else — a crash mid-print
    // may have left paper; the row becomes possiblyPrinted with its owed
    // acknowledgement in one update. Never sent, never retried.
    final recoveredStale = await store.markPossiblyPrintedOnRecoveryWithAck(
      deviceId: deviceId,
      branchId: context.branchId,
      now: _now(),
    );

    final acks = PendingKitchenAckCoordinator(
      store: store,
      ackRepository: ackRepository,
      now: _now,
    );
    // 4: acknowledgements owed from PREVIOUS runs (including the recovery
    // sweep's) flush before new work.
    final (preAcked, preRetries, preTerminal) = await acks.flush(
      deviceId: deviceId,
      branchId: context.branchId,
    );

    // 5: local VOID evidence applies BEFORE any new claim.
    final voidsBefore = await reconcileLocalVoidEvidence(
      store,
      deviceId: deviceId,
      branchId: context.branchId,
      now: _now(),
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

    final scope = KitchenImportScope(
      organizationId: context.organizationId,
      restaurantId: restaurantId,
      branchId: context.branchId,
      deviceId: deviceId,
    );
    // 6–7: drain/import (durable-before-ack, immediate import acks inside).
    final drainReport = await KitchenDispatchDrainCoordinator(
      pullRepository: pullRepository,
      importCoordinator: KitchenDispatchImportCoordinator(
        store: store,
        cipher: AesGcmKitchenSpoolCipher(),
        key: key,
        scope: scope,
        destination: destination,
        ackRepository: ackRepository,
        localJobIdGenerator: newLocalJobId,
        now: _now,
      ),
    ).drain();

    // 8: VOID evidence again — a void imported by THIS drain must stop its
    // order's earlier jobs before the worker can claim them.
    final voidsAfter = await reconcileLocalVoidEvidence(
      store,
      deviceId: deviceId,
      branchId: context.branchId,
      now: _now(),
    );

    // 9: the bounded worker (claim → decrypt/render → gated single send →
    // atomic transition+ack). Disposal stops it before any further send.
    final workerReport = await KitchenPrintWorker(
      store: store,
      cipher: AesGcmKitchenSpoolCipher(),
      key: key,
      renderer: renderer,
      networkSend: networkSend,
      bluetoothSend: bluetoothSend,
      sendGate: sendGate,
      ackRepository: ackRepository,
      scope: scope,
      now: _now,
      maxJobsPerRun: _maxWorkerJobsPerRun,
      isDisposed: () => _disposed,
    ).run();

    // 10: anything newly pending that is already due flushes before
    // returning.
    final (postAcked, postRetries, postTerminal) = await acks.flush(
      deviceId: deviceId,
      branchId: context.branchId,
    );
    return KitchenSpoolRunWorked(
      'worked',
      drain: drainReport,
      worker: workerReport,
      recoveredStale: recoveredStale,
      voidSuperseded: voidsBefore.superseded + voidsAfter.superseded,
      voidLinks: voidsBefore.links + voidsAfter.links,
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
    // revision is null). 001C3A: a verified KDS result now carries the
    // server revision too (null only against an old server — that record
    // stays readiness-ineligible but keeps normal KDS behavior).
    final (String? wire, int? revision) = switch (mode) {
      KitchenModeVerifiedKds(:final revision) => ('kds', revision),
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

  /// Disposes runtime handles on logout/unpair/scope change (rows and key
  /// are deliberately preserved — scope-bound, never wiped automatically).
  /// The disposal flag stops any in-flight worker BEFORE its next send;
  /// once a transport attempt may already have started, its ambiguity is
  /// preserved honestly (stale printing recovers to possiblyPrinted on the
  /// next valid run).
  Future<void> dispose() async {
    _disposed = true;
    await _db?.close();
    _db = null;
  }
}

/// Deterministic NON-SECRET digest of the device-session token (the secure
/// mode-cache binding; never the token itself).
String sessionFingerprint(String sessionToken) =>
    sha256.convert(utf8.encode(sessionToken)).toString();
