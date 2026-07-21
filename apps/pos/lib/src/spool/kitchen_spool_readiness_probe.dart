import 'package:restoflow_data_local/restoflow_data_local.dart'
    show
        DriftKitchenSpoolStore,
        KitchenSpoolDatabaseFactory,
        KitchenSpoolKeyManager,
        KitchenSpoolKeyState;

import 'pos_kitchen_spool_platform.dart';

/// KITCHEN-MODE-001C3A — NON-MUTATING secure-spool capability probe.
///
/// Answers "could this device run the encrypted kitchen spool right now?"
/// WITHOUT changing anything:
///  * the spool database file is NEVER created (absent file = plain `false`,
///    not an error — a verified-kds device must not grow a spool footprint
///    merely because readiness is being reported);
///  * the key is NEVER provisioned, rotated, or wiped (read/inspect only);
///  * an existing database is opened read-style purely to count unresolved
///    jobs, then closed. Corruption reports `false` with a typed safe
///    blocker code — no destructive recovery, ever.
final class KitchenSpoolReadinessProbeResult {
  const KitchenSpoolReadinessProbeResult({
    required this.secureSpoolAvailable,
    required this.unresolvedLocalJobs,
    this.blockerCode,
  });

  /// True ONLY when an existing usable database AND an existing usable key
  /// are both present. A fresh device that never ran the spool is `false`
  /// (spool provisioning is an explicit later activation step, not a probe
  /// side effect).
  final bool secureSpoolAvailable;

  /// Scope-specific durable count; 0 whenever no spool exists.
  final int unresolvedLocalJobs;

  /// Typed, endpoint-free local blocker (`spool_database_unavailable` /
  /// `kitchen_spool_key_missing` / `kitchen_spool_key_corrupted` /
  /// `secure_storage_unavailable` / `web_unsupported`), or null.
  final String? blockerCode;
}

final class KitchenSpoolReadinessProbe {
  const KitchenSpoolReadinessProbe({
    required PosKitchenSpoolPlatform platform,
    required KitchenSpoolDatabaseFactory Function() databaseFactoryBuilder,
    required KitchenSpoolKeyManager Function() keyManagerBuilder,
  }) : _platform = platform,
       _databaseFactoryBuilder = databaseFactoryBuilder,
       _keyManagerBuilder = keyManagerBuilder;

  final PosKitchenSpoolPlatform _platform;
  final KitchenSpoolDatabaseFactory Function() _databaseFactoryBuilder;
  final KitchenSpoolKeyManager Function() _keyManagerBuilder;

  Future<KitchenSpoolReadinessProbeResult> probe({
    required String deviceId,
    required String branchId,
  }) async {
    if (!_platform.supportsSecureSpool) {
      return const KitchenSpoolReadinessProbeResult(
        secureSpoolAvailable: false,
        unresolvedLocalJobs: 0,
        blockerCode: 'web_unsupported',
      );
    }

    final KitchenSpoolKeyState keyState;
    try {
      keyState = await _keyManagerBuilder().inspectState();
    } on Exception {
      return const KitchenSpoolReadinessProbeResult(
        secureSpoolAvailable: false,
        unresolvedLocalJobs: 0,
        blockerCode: 'secure_storage_unavailable',
      );
    }

    final factory = _databaseFactoryBuilder();
    final bool fileExists = await factory.spoolFileExists();
    if (!fileExists) {
      // No footprint, nothing to count, nothing to create.
      return KitchenSpoolReadinessProbeResult(
        secureSpoolAvailable: false,
        unresolvedLocalJobs: 0,
        blockerCode: switch (keyState) {
          KitchenSpoolKeyState.corrupted => 'kitchen_spool_key_corrupted',
          KitchenSpoolKeyState.unavailable => 'secure_storage_unavailable',
          _ => null,
        },
      );
    }

    // An existing database: open (never creates rows), count, close.
    final int unresolved;
    try {
      final db = await factory.open();
      try {
        unresolved = await DriftKitchenSpoolStore(
          db,
        ).countUnresolved(deviceId: deviceId, branchId: branchId);
      } finally {
        await db.close();
      }
    } on Exception {
      return const KitchenSpoolReadinessProbeResult(
        secureSpoolAvailable: false,
        unresolvedLocalJobs: 0,
        blockerCode: 'spool_database_unavailable',
      );
    }

    return switch (keyState) {
      KitchenSpoolKeyState.present => KitchenSpoolReadinessProbeResult(
        secureSpoolAvailable: true,
        unresolvedLocalJobs: unresolved,
      ),
      KitchenSpoolKeyState.missing => KitchenSpoolReadinessProbeResult(
        secureSpoolAvailable: false,
        unresolvedLocalJobs: unresolved,
        blockerCode: 'kitchen_spool_key_missing',
      ),
      KitchenSpoolKeyState.corrupted => KitchenSpoolReadinessProbeResult(
        secureSpoolAvailable: false,
        unresolvedLocalJobs: unresolved,
        blockerCode: 'kitchen_spool_key_corrupted',
      ),
      KitchenSpoolKeyState.unavailable => KitchenSpoolReadinessProbeResult(
        secureSpoolAvailable: false,
        unresolvedLocalJobs: unresolved,
        blockerCode: 'secure_storage_unavailable',
      ),
    };
  }
}
