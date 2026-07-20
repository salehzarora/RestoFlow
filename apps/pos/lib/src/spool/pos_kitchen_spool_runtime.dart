import 'package:crypto/crypto.dart' show sha256;
import 'dart:convert' show utf8;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory;
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart' show SecureKeyStore;
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show
        FlutterSecureDeviceSessionStore,
        KitchenModeRevisionUnavailable,
        KitchenModeResult,
        KitchenModeVerifiedKds,
        SupabaseDeviceKitchenModeRepository,
        SupabaseKitchenDispatchAckRepository,
        runtimeConfigProvider;

import '../state/pos_device_context.dart' show posDeviceContextProvider;
import '../state/pos_session.dart' show posAuthTransportProvider;
import 'flutter_secure_kitchen_spool_key_store.dart';
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

final class PosKitchenSpoolRuntime {
  PosKitchenSpoolRuntime({
    required PosKitchenSpoolPlatform platform,
    required DeviceContext? Function() deviceContext,
    required DeviceSessionSecretStore? secretStore,
    required SupabaseDeviceKitchenModeRepository? modeRepository,
    required SupabaseKitchenDispatchAckRepository? ackRepository,
    required KitchenSpoolDatabaseFactory Function() databaseFactoryBuilder,
    PosSecureKitchenModeCache? modeCache,
    SecureKeyStore? keyStore,
    DateTime Function()? now,
  }) : _platform = platform,
       _deviceContext = deviceContext,
       _secretStore = secretStore,
       _modeRepository = modeRepository,
       _ackRepository = ackRepository,
       _databaseFactoryBuilder = databaseFactoryBuilder,
       _modeCache = modeCache,
       _keyStore = keyStore,
       _now = now ?? DateTime.now;

  final PosKitchenSpoolPlatform _platform;
  final DeviceContext? Function() _deviceContext;
  final DeviceSessionSecretStore? _secretStore;
  final SupabaseDeviceKitchenModeRepository? _modeRepository;
  final SupabaseKitchenDispatchAckRepository? _ackRepository;
  final KitchenSpoolDatabaseFactory Function() _databaseFactoryBuilder;
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

    // 3: authoritative mode (typed; no silent kds fallback anywhere).
    final KitchenModeResult mode = await modeRepository.fetchMode();
    await _cacheMode(mode, context, restaurantId, deviceId, secretStore);

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

  Future<void> _cacheMode(
    KitchenModeResult mode,
    DeviceContext context,
    String restaurantId,
    String deviceId,
    DeviceSessionSecretStore secretStore,
  ) async {
    final cache = _modeCache;
    if (cache == null) return;
    final String? wire = switch (mode) {
      KitchenModeVerifiedKds() => 'kds',
      KitchenModeRevisionUnavailable() => 'printer_only',
      _ => null, // failures never overwrite the cache
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
          modeRevision: null, // D1: no trusted revision until 001C3.
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
    modeCache: PosSecureKitchenModeCache(platform: platform),
  );
});

/// Small indirection so tests can see exactly which secret store the
/// composition uses (the SAME Keystore-backed store as device pairing).
abstract final class FlutterSecureDeviceSessionStoreProvider {
  static DeviceSessionSecretStore of() => FlutterSecureDeviceSessionStore();
}
