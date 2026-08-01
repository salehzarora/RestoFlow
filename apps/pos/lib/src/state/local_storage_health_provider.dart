import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_storage_health.dart';
import 'draft_recovery_controller.dart' show posDraftRecoveryStoreProvider;
import 'outbox_controller.dart' show durableOutboxStoreProvider;
import 'pos_session.dart' show posSyncSessionProvider;

/// MONEY-DURABLE-STORES-003B: what the POS knows about the health of its OWN
/// local storage, aggregated across the durable stores that can report.
class PosLocalStorageHealth {
  const PosLocalStorageHealth({
    this.writeRefused = false,
    this.unreadableRecords = 0,
  });

  /// A durable write has been REFUSED since the app started, so storage is
  /// behind what the app believes. The order that failed was NOT sent — the
  /// stores fail closed — but a result recorded after a dispatch may not
  /// survive a restart.
  final bool writeRefused;

  /// Local records this build cannot decode, plus whole envelopes it had to set
  /// aside. They are PRESERVED, not discarded, but they will not sync and no
  /// action here can reach them.
  final int unreadableRecords;

  bool get isHealthy => !writeRefused && unreadableRecords == 0;

  @override
  bool operator ==(Object other) =>
      other is PosLocalStorageHealth &&
      other.writeRefused == writeRefused &&
      other.unreadableRecords == unreadableRecords;

  @override
  int get hashCode => Object.hash(writeRefused, unreadableRecords);
}

/// The aggregate local-storage health of this till.
///
/// Reads through the [PosDurableStoreHealth] capability, so a store that keeps
/// nothing durable (demo mode, tests, the in-memory defaults) contributes
/// nothing rather than a made-up "healthy". Read live rather than cached: the
/// counts come from what is on disk RIGHT NOW, and a store that starts
/// reporting a refusal must not be masked by a stale snapshot.
final posLocalStorageHealthProvider = Provider<PosLocalStorageHealth>((ref) {
  // Watched, not read: a re-created store (a new session, a new device) must
  // re-evaluate rather than keep the previous device's verdict.
  final outbox = ref.watch(durableOutboxStoreProvider);
  final recovery = ref.watch(posDraftRecoveryStoreProvider);
  final scopeKey = ref.watch(posSyncSessionProvider)?.deviceId ?? '';

  var refused = false;
  var unreadable = 0;
  for (final store in <Object?>[outbox, recovery]) {
    if (store is! PosDurableStoreHealth) continue;
    if (store.isDegraded) refused = true;
    // A store keyed per device cannot answer without a scope; with no session
    // there is no durable queue to be unhealthy about yet.
    if (scopeKey.isNotEmpty || identical(store, recovery)) {
      unreadable += store.unreadableRecordCount(scopeKey);
    }
  }
  return PosLocalStorageHealth(
    writeRefused: refused,
    unreadableRecords: unreadable,
  );
});
