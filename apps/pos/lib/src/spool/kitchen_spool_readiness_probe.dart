import 'package:restoflow_data_local/restoflow_data_local.dart'
    show
        DriftKitchenSpoolStore,
        KitchenSpoolDatabaseFactory,
        KitchenSpoolKeyManager,
        KitchenSpoolKeyState;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show KitchenSpoolCountState;

import 'pos_kitchen_spool_platform.dart';

/// KITCHEN-MODE-001C3A/001C3B1A2 — NON-MUTATING secure-spool capability probe.
///
/// Answers "could this device run the encrypted kitchen spool right now, and is
/// its unresolved-job count AUTHORITATIVE?" WITHOUT changing anything:
///  * the spool database file is NEVER created (absent file = a PROVEN-EMPTY
///    count of 0, not an error — a verified-kds device must not grow a spool
///    footprint merely because readiness is being reported);
///  * the key is NEVER provisioned, rotated, or wiped (read/inspect only);
///  * an existing database is opened read-style purely to count unresolved
///    jobs, then closed. Corruption reports `false` with a typed safe
///    blocker code — no destructive recovery, ever.
///
/// KITCHEN-MODE-001C3B1A2 — COUNT CERTAINTY. The count state is decided by the
/// DATABASE path ALONE (absent file → `absent`/0; open+count succeeds →
/// `counted`/N; open or count fails → `unknown`), and is INDEPENDENT of the
/// key / secure-storage inspection. A key or secure-storage inspection failure
/// still yields `secureSpoolAvailable = false` (unprintable) but MUST NOT
/// downgrade a successfully-counted database to `unknown` — the future
/// `printer_only -> kds` escape gate needs a truthful "0 means proven empty"
/// signal that a mere key hiccup can never erase.
final class KitchenSpoolReadinessProbeResult {
  const KitchenSpoolReadinessProbeResult({
    required this.secureSpoolAvailable,
    required this.unresolvedLocalJobs,
    required this.spoolCountState,
    this.blockerCode,
  });

  /// True ONLY when an existing usable database (`spoolCountState == counted`)
  /// AND an existing usable key are both present. A fresh device that never ran
  /// the spool is `false` (spool provisioning is an explicit later activation
  /// step, not a probe side effect).
  final bool secureSpoolAvailable;

  /// Scope-specific durable count; 0 whenever no spool exists or the count
  /// could not be taken. AUTHORITATIVE only when [spoolCountState] is `counted`
  /// or `absent`.
  final int unresolvedLocalJobs;

  /// KITCHEN-MODE-001C3B1A2 — whether [unresolvedLocalJobs] is authoritative:
  ///  * `counted` — the DB opened and the count is exact;
  ///  * `absent`  — no DB file, so the count is a proven 0;
  ///  * `unknown` — the DB could not be opened/counted, so 0 is NOT a claim.
  final KitchenSpoolCountState spoolCountState;

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
      // Web has no encrypted spool at all; it never participates in the escape
      // gate, so its count is structurally non-authoritative (fail closed).
      return const KitchenSpoolReadinessProbeResult(
        secureSpoolAvailable: false,
        unresolvedLocalJobs: 0,
        spoolCountState: KitchenSpoolCountState.unknown,
        blockerCode: 'web_unsupported',
      );
    }

    // (1)-(3) COUNT STATE from the DATABASE path ALONE — never gated by the key.
    final factory = _databaseFactoryBuilder();
    final KitchenSpoolCountState countState;
    final int unresolved;
    if (!await factory.spoolFileExists()) {
      // (2) No footprint: proven empty, nothing to open, nothing to create.
      countState = KitchenSpoolCountState.absent;
      unresolved = 0;
    } else {
      // (3) An existing database: open (never creates rows), count, close.
      int? counted;
      try {
        final db = await factory.open();
        try {
          counted = await DriftKitchenSpoolStore(
            db,
          ).countUnresolved(deviceId: deviceId, branchId: branchId);
        } finally {
          await db.close();
        }
      } on Exception {
        counted = null;
      }
      if (counted == null) {
        // Open/count failed: the count is NOT a claim (never asserted as 0).
        countState = KitchenSpoolCountState.unknown;
        unresolved = 0;
      } else {
        countState = KitchenSpoolCountState.counted;
        unresolved = counted;
      }
    }

    // (4) Key / secure-storage inspected INDEPENDENTLY for printability. A
    // failure here yields an unavailable key (unprintable) but NEVER touches the
    // count state decided above.
    KitchenSpoolKeyState keyState;
    try {
      keyState = await _keyManagerBuilder().inspectState();
    } on Exception {
      keyState = KitchenSpoolKeyState.unavailable;
    }

    // secure_spool_available = an existing usable DB (counted) AND a usable key.
    final bool secureSpoolAvailable =
        countState == KitchenSpoolCountState.counted &&
        keyState == KitchenSpoolKeyState.present;

    return KitchenSpoolReadinessProbeResult(
      secureSpoolAvailable: secureSpoolAvailable,
      unresolvedLocalJobs: unresolved,
      spoolCountState: countState,
      blockerCode: _blockerFor(countState, keyState),
    );
  }

  /// Typed diagnostic, endpoint-free. An unreadable DB dominates (that is the
  /// salient failure); otherwise surface the key/secure-storage issue, but only
  /// a MISSING key when a database actually exists to be unlocked.
  static String? _blockerFor(
    KitchenSpoolCountState countState,
    KitchenSpoolKeyState keyState,
  ) {
    if (countState == KitchenSpoolCountState.unknown) {
      return 'spool_database_unavailable';
    }
    return switch (keyState) {
      KitchenSpoolKeyState.present => null,
      KitchenSpoolKeyState.missing =>
        countState == KitchenSpoolCountState.counted
            ? 'kitchen_spool_key_missing'
            : null,
      KitchenSpoolKeyState.corrupted => 'kitchen_spool_key_corrupted',
      KitchenSpoolKeyState.unavailable => 'secure_storage_unavailable',
    };
  }
}
