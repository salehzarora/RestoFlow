import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'order_submission.dart';

/// Thrown when an order submission cannot be built or enqueued.
class OrderSubmissionException implements Exception {
  const OrderSubmissionException(this.message);
  final String message;
  @override
  String toString() => 'OrderSubmissionException: $message';
}

/// The client OUTBOX seam (RF-115). Each method maps 1:1 to the production
/// outbox + push engine:
///  * [enqueue]      → `LocalDatabase.enqueueOperation` (an `OutboxOperations`
///                     row keyed by `(deviceId, localOperationId)`, DECISION D-022).
///  * [recentEntries]→ a query of the most recent outbox rows for the UI.
///  * [push]         → the RF-056 push engine calling `app.submit_order` (RF-052).
///  * [retry]        → re-queue a failed (rejected/dead) entry for another push.
///
/// Implemented here ONLY by the in-memory [DemoOutboxStore]; the real
/// `data_local`-backed implementation lands with the device/PIN-session auth
/// bridge. Nothing here contacts a backend.
abstract class OutboxRepository {
  /// Enqueues [entry] (idempotent on `(deviceId, localOperationId)`), returning
  /// the stored entry — `pending`/`created` until pushed.
  Future<OutboxEntry> enqueue(OutboxEntry entry);

  /// The outbox entries, most recent first.
  Future<List<OutboxEntry>> recentEntries();

  /// Attempts to deliver the entry. DEMO ONLY — simulates the push outcome; it
  /// does NOT contact a backend.
  Future<OutboxEntry> push(String entryId);

  /// Re-queues a failed entry back to `pending` so it can be pushed again.
  Future<OutboxEntry> retry(String entryId);
}

/// In-memory, clearly-labelled DEMO outbox (RF-115). Holds enqueued order
/// submissions and simulates the sync lifecycle (pending → in-flight →
/// applied / rejected). NO backend, NO persistence — the order body is the real
/// `submit_order`-shaped JSON, but it is never sent anywhere.
class DemoOutboxStore implements OutboxRepository {
  DemoOutboxStore({
    Future<void> Function(Duration)? delay,
    this.pushDelay = const Duration(milliseconds: 600),
    this.enqueueFails = false,
  }) : _delay = delay ?? Future<void>.delayed;

  final Future<void> Function(Duration) _delay;
  final Duration pushDelay;

  /// When true, [enqueue] throws — used to exercise the "enqueue failed, keep
  /// the cart" path. (No real backend can fail here.)
  final bool enqueueFails;

  /// When true, the NEXT [push] simulates a transient delivery failure, then
  /// resets. Lets a demo/test show the failed → retry → synced lifecycle.
  bool nextPushFails = false;

  final List<OutboxEntry> _entries = <OutboxEntry>[];

  @override
  Future<OutboxEntry> enqueue(OutboxEntry entry) async {
    if (enqueueFails) {
      throw const OrderSubmissionException('demo enqueue failed');
    }
    // Idempotency: at most one row per (deviceId, localOperationId) — mirrors the
    // production UNIQUE constraint (DECISION D-022). A duplicate returns the
    // already-stored entry instead of adding a second.
    for (final e in _entries) {
      if (e.deviceId == entry.deviceId &&
          e.localOperationId == entry.localOperationId) {
        return e;
      }
    }
    _entries.add(entry);
    return entry;
  }

  @override
  Future<List<OutboxEntry>> recentEntries() async =>
      List.unmodifiable(_entries.reversed);

  @override
  Future<OutboxEntry> push(String entryId) async {
    final idx = _indexOf(entryId);
    await _delay(pushDelay);
    final current = _entries[idx];
    final fail = nextPushFails;
    nextPushFails = false;
    final updated = fail
        ? current.copyWith(
            syncState: OutboxSyncState.rejected,
            attemptCount: current.attemptCount + 1,
            lastErrorCode: 'demo_transient',
          )
        : current.copyWith(
            syncState: OutboxSyncState.applied,
            attemptCount: current.attemptCount + 1,
            clearError: true,
          );
    _entries[idx] = updated;
    return updated;
  }

  @override
  Future<OutboxEntry> retry(String entryId) async {
    final idx = _indexOf(entryId);
    final current = _entries[idx];
    if (!current.syncState.isFailed) return current;
    final updated = current.copyWith(
      syncState: OutboxSyncState.pending,
      clearError: true,
    );
    _entries[idx] = updated;
    return updated;
  }

  int _indexOf(String entryId) {
    for (var i = 0; i < _entries.length; i++) {
      if (_entries[i].id == entryId) return i;
    }
    throw OrderSubmissionException('unknown outbox entry: $entryId');
  }
}

/// REAL client outbox repository skeleton (M7). Selected by `runtimeConfigProvider`
/// in real mode. NOT YET WIRED: the production path persists each operation in
/// `data_local` (Drift `OutboxOperations`, keyed by `(deviceId, localOperationId)`
/// - DECISION D-022) and the RF-056 push engine delivers it via `sync_push` to
/// `app.submit_order` (RF-052). That transport seam and the device/PIN-session
/// auth bridge do not exist yet, so every method throws [RealRepoNotWiredError];
/// no backend is contacted. The idempotency key must be honored when wired.
class RealOutboxRepository implements OutboxRepository {
  const RealOutboxRepository(this.config);

  /// The validated anon-key Supabase config (or null - fail-closed). Held for the
  /// future push transport; no client is constructed yet.
  final SupabaseBootstrapConfig? config;

  static const String _reason =
      'outbox: sync_push -> app.submit_order not wired yet';

  @override
  Future<OutboxEntry> enqueue(OutboxEntry entry) async =>
      throw const RealRepoNotWiredError(_reason);

  @override
  Future<List<OutboxEntry>> recentEntries() async =>
      throw const RealRepoNotWiredError(_reason);

  @override
  Future<OutboxEntry> push(String entryId) async =>
      throw const RealRepoNotWiredError(_reason);

  @override
  Future<OutboxEntry> retry(String entryId) async =>
      throw const RealRepoNotWiredError(_reason);
}
