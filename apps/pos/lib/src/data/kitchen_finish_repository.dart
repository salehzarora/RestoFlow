import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// KITCHEN-PRINT-DUAL-001D — the outcome of advancing ONE order to `served`.
///
/// `finished` means the order is off the active kitchen board for a legitimate
/// reason: we drove it to `served` (auto-completing if paid), OR another device
/// resolved it concurrently (served/completed), OR it was cancelled/voided while
/// we worked. `failed` means it is still active (or unreadable) and stays
/// visible + retryable — never a corruption, never a false claim of completion.
enum KitchenFinishStatus { finished, failed }

class KitchenFinishResult {
  const KitchenFinishResult(this.orderId, this.status, {this.error});

  final String orderId;
  final KitchenFinishStatus status;

  /// The stable server code (or a transport/shape code) when [status] is failed.
  final String? error;

  bool get isFinished => status == KitchenFinishStatus.finished;
}

/// The canonical single-step KITCHEN advance chain (domain `OrderStateMachine`):
/// the server (`app.update_order_status`) admits ONLY these one-hop forward
/// edges, so a bulk finish drives an active order to `served` by sending each
/// next step in order — never one multi-step jump.
const List<String> kKitchenAdvanceChain = [
  'submitted',
  'accepted',
  'preparing',
  'ready',
  'served',
];

/// The ACTIVE kitchen statuses a bulk finish targets. `served` (already off the
/// kitchen board) and every terminal status are NOT active and never targeted.
const Set<String> kActiveKitchenStatuses = {
  'submitted',
  'accepted',
  'preparing',
  'ready',
};

/// Statuses that mean the order is OFF the active kitchen board for a legitimate
/// reason — reaching any of these (by us or concurrently by another device) is a
/// `finished` outcome, NOT a failure.
const Set<String> _kResolvedStatuses = {
  'served',
  'completed',
  'cancelled',
  'voided',
};

/// Every order status this finisher recognizes as authoritative (active +
/// resolved + `draft`). A `from` that is absent, malformed, or outside this set
/// is NOT trusted as authoritative — the loop re-reads the real status instead.
const Set<String> _kKnownStatuses = {
  'submitted',
  'accepted',
  'preparing',
  'ready',
  'served',
  'completed',
  'cancelled',
  'voided',
  'draft',
};

/// The ordered `new_status` steps to take [from] up to `served` (exclusive of
/// [from]). E.g. submitted -> [accepted, preparing, ready, served]; ready ->
/// [served]. Empty when [from] is not an active-advanceable status. Retained for
/// callers/tests that reason about the whole chain; the real finisher advances
/// ONE authoritative step at a time (see [kitchenNextStatus]).
List<String> kitchenStepsToServed(String from) {
  final i = kKitchenAdvanceChain.indexOf(from);
  if (i < 0 || i >= kKitchenAdvanceChain.length - 1) return const [];
  return kKitchenAdvanceChain.sublist(i + 1);
}

/// The SINGLE next `new_status` for an active order at [from] (one forward hop
/// toward `served`), or null when [from] is not an active-advanceable status.
String? kitchenNextStatus(String from) {
  final i = kKitchenAdvanceChain.indexOf(from);
  if (i < 0 || i >= kKitchenAdvanceChain.length - 1) return null;
  return kKitchenAdvanceChain[i + 1];
}

/// Advances active kitchen orders to `served` using the EXISTING `order.status`
/// sync_push op + the existing state machine (no new RPC/migration, no new
/// permission model — the server re-authorizes every push). It NEVER cancels,
/// voids, deletes, or completes an order and NEVER creates a payment or bypasses
/// settlement: reaching `served` auto-completes a PAID order through the existing
/// served+settled rule and leaves an UNPAID one at `served` (payable in history).
abstract class KitchenFinishRepository {
  /// Drives [orderId] (last known to be [fromStatus]) up to `served` via a
  /// BOUNDED authoritative-progress loop: each single-step `order.status` op is
  /// re-authorized + re-derived by the server from the LOCKED order row, so a
  /// step another device already made comes back as `invalid_transition`
  /// carrying the order's real current status — which we reclassify from,
  /// NEVER continuing from the stale locally-captured status.
  ///
  /// [batchRunId] scopes the idempotency keys for this batch: each op id is
  /// `batchRunId:orderId:targetStatus`, so retrying the SAME logical transition
  /// reuses the key (the server's ledger replays the stored result) while a new
  /// target gets a new key. [refreshStatus] re-reads the authoritative current
  /// status for the rare result that carries none (a serialization conflict);
  /// it returns null when the order can no longer be read.
  Future<KitchenFinishResult> advanceToServed({
    required String orderId,
    required String fromStatus,
    required String batchRunId,
    required Future<String?> Function(String orderId) refreshStatus,
  });

  /// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap B): the explicit printer-only
  /// COMPLETE safety net — advance a SERVED, fully-settled order to `completed`
  /// with ONE `order.status` op (the SAME transport + idempotency contract as
  /// [advanceToServed]). IDEMPOTENT: a server-already-completed order returns
  /// `finished` (never an error, never a double-complete); it never records a
  /// payment, never resubmits, never prints. [localOperationId] is the stable
  /// idempotency key for THIS completion attempt.
  Future<KitchenFinishResult> completeServedOrder({
    required String orderId,
    required String localOperationId,
  });
}

/// A hard upper bound on per-order attempts: the 4 canonical transitions plus a
/// small margin for concurrency re-reads/retries. A loop that cannot resolve an
/// order within this bound reports it failed (retryable) rather than spinning.
const int _kMaxAttemptsPerOrder = 12;

/// In-memory DEMO finisher: validates the step chain and succeeds locally with no
/// backend (mirrors [DemoVoidStore]). Never reached when the button is real-mode
/// gated, but kept so the provider is total.
class DemoKitchenFinishRepository implements KitchenFinishRepository {
  const DemoKitchenFinishRepository();

  @override
  Future<KitchenFinishResult> advanceToServed({
    required String orderId,
    required String fromStatus,
    required String batchRunId,
    required Future<String?> Function(String orderId) refreshStatus,
  }) async {
    if (kitchenNextStatus(fromStatus) == null) {
      return KitchenFinishResult(
        orderId,
        _kResolvedStatuses.contains(fromStatus)
            ? KitchenFinishStatus.finished
            : KitchenFinishStatus.failed,
        error: _kResolvedStatuses.contains(fromStatus) ? null : 'not_active',
      );
    }
    return KitchenFinishResult(orderId, KitchenFinishStatus.finished);
  }

  @override
  Future<KitchenFinishResult> completeServedOrder({
    required String orderId,
    required String localOperationId,
  }) async => KitchenFinishResult(orderId, KitchenFinishStatus.finished);
}

/// REAL finisher. Sends `order.status` ops to `public.sync_push` (dispatched to
/// `app.update_order_status`) over the SAME shared [SyncRpcTransport] +
/// [SyncSession] as the outbox/void/payment paths (anon key + the PIN/device
/// session; never the `app` schema, never a service-role key).
///
/// The server re-derives the current status from the LOCKED order row and admits
/// only the exact single-step edge. So concurrent KDS advancement never corrupts
/// or misreports the result: a step the KDS already made returns
/// `invalid_transition` with `from` = the order's REAL current status, which we
/// reclassify from and continue toward `served`; an order the KDS/settlement
/// already carried to served/completed (or a cashier cancelled/voided) resolves
/// as `finished`, not failed.
class RealKitchenFinishRepository implements KitchenFinishRepository {
  const RealKitchenFinishRepository(this._transport, this._session);

  final SyncRpcTransport? _transport;
  final SyncSession? _session;

  @override
  Future<KitchenFinishResult> advanceToServed({
    required String orderId,
    required String fromStatus,
    required String batchRunId,
    required Future<String?> Function(String orderId) refreshStatus,
  }) async {
    final transport = _transport;
    final session = _session;
    if (transport == null || session == null || orderId.trim().isEmpty) {
      return KitchenFinishResult(
        orderId,
        KitchenFinishStatus.failed,
        error: 'unavailable',
      );
    }

    var status = fromStatus;
    String? lastError;
    for (var attempt = 0; attempt < _kMaxAttemptsPerOrder; attempt++) {
      // (1) Classify the CURRENT (authoritative-or-captured) status first.
      if (_kResolvedStatuses.contains(status)) {
        // Off the active board — by us or concurrently. NOT a failure.
        return KitchenFinishResult(orderId, KitchenFinishStatus.finished);
      }
      final target = kitchenNextStatus(status);
      if (target == null) {
        // draft / unknown / unreadable — cannot be finished by advancing.
        return KitchenFinishResult(
          orderId,
          KitchenFinishStatus.failed,
          error: lastError ?? 'not_active',
        );
      }

      // (2) Send exactly ONE forward step. The idempotency key is STABLE per
      //     (batch, order, target): a retry of this same logical transition
      //     reuses it, so an op that already applied replays its stored result
      //     instead of double-advancing.
      final localOp = '$batchRunId:$orderId:$target';
      final op = <String, dynamic>{
        'local_operation_id': localOp,
        'operation_type': 'order.status',
        'target_entity': 'order',
        'target_id': orderId,
        'client_created_at': DateTime.now().toIso8601String(),
        // The server derives actor/org/branch/current-status from the PIN session
        // + the locked order row; the client sends ONLY the order + next status.
        // (This payload is IDENTICAL across retries of this op id, so the server
        // fingerprint matches and the retry replays rather than conflicting.)
        'payload': <String, dynamic>{'order_id': orderId, 'new_status': target},
      };

      final Object? raw;
      try {
        raw = await transport.invoke('sync_push', <String, dynamic>{
          'p_pin_session_id': session.pinSessionId,
          'p_device_id': session.deviceId,
          'p_operations': <dynamic>[op],
        });
      } on SyncTransportException catch (e) {
        // Ambiguous — the op MAY have reached the server and applied. Retry the
        // SAME target with the SAME idempotency key on the next bounded attempt:
        // if it applied, the replay reports it; if it never ran, it runs now.
        lastError = e.code ?? e.kind.name;
        continue;
      }

      final outcome = _opOutcome(raw, localOp);
      switch (outcome.kind) {
        case _OpKind.applied:
          // Confirmed advance. Reaching served (or an order that auto-completed
          // on this step) is terminal for the kitchen — done.
          if (target == 'served' || outcome.autoCompleted) {
            return KitchenFinishResult(orderId, KitchenFinishStatus.finished);
          }
          status = target;
        case _OpKind.staleStatus:
          // invalid_transition: the order is no longer at `status`. Normally the
          // server returns its AUTHORITATIVE current status in `from` — reclassify
          // from it, NEVER from the stale local status. When `from` is absent,
          // malformed, or an unrecognized status, DO NOT fail: re-read the real
          // status through the same refreshStatus path and continue from THAT
          // (still this one bounded loop — no second retry loop). Another KDS
          // device may already have advanced the order.
          final from = outcome.currentStatus;
          final String reclassifyFrom;
          if (from != null && _kKnownStatuses.contains(from)) {
            // (A) A valid authoritative `from` — reclassify from it directly.
            reclassifyFrom = from;
          } else {
            // (B) No usable `from` — re-read the authoritative current status.
            final refreshed = await refreshStatus(orderId);
            if (refreshed == null) {
              // missing / unreadable order — fail honestly (no silent success).
              return KitchenFinishResult(
                orderId,
                KitchenFinishStatus.failed,
                error: outcome.error ?? 'invalid_transition',
              );
            }
            reclassifyFrom = refreshed;
          }
          // The next loop iteration classifies `reclassifyFrom`: resolved
          // (served/completed/cancelled/voided) -> finished; active -> continue
          // toward served; draft/unrecognized -> failed (never advanced).
          lastError = outcome.error;
          status = reclassifyFrom;
        case _OpKind.conflict:
          // A serialization conflict carries no status — re-read the authoritative
          // one so a concurrently-served order is reported finished, not failed.
          final refreshed = await refreshStatus(orderId);
          if (refreshed == null) {
            return KitchenFinishResult(
              orderId,
              KitchenFinishStatus.failed,
              error: outcome.error ?? 'conflict',
            );
          }
          lastError = outcome.error;
          status = refreshed;
        case _OpKind.denied:
          // permission_denied / revoked — a real authorization failure; retrying
          // cannot help.
          return KitchenFinishResult(
            orderId,
            KitchenFinishStatus.failed,
            error: outcome.error ?? 'permission_denied',
          );
        case _OpKind.rejected:
        case _OpKind.malformed:
          // A raised validation/scope/not-found rejection, or an unclassifiable
          // response — a genuine failure (the order stays retryable).
          return KitchenFinishResult(
            orderId,
            KitchenFinishStatus.failed,
            error: outcome.error ?? outcome.rawStatus ?? 'rejected',
          );
      }
    }
    // Bound reached without resolving (persistent transport/conflict churn).
    return KitchenFinishResult(
      orderId,
      KitchenFinishStatus.failed,
      error: lastError ?? 'unresolved',
    );
  }

  @override
  Future<KitchenFinishResult> completeServedOrder({
    required String orderId,
    required String localOperationId,
  }) async {
    final transport = _transport;
    final session = _session;
    if (transport == null || session == null || orderId.trim().isEmpty) {
      return KitchenFinishResult(
        orderId,
        KitchenFinishStatus.failed,
        error: 'unavailable',
      );
    }
    // ONE forward step served -> completed. The server re-authorizes + re-derives
    // the transition from the LOCKED order row (settlement enforced by the
    // served+paid rule), so the client sends ONLY {order_id, new_status}. The
    // payload is IDENTICAL across retries of this id -> the server replays rather
    // than double-completing. Never a payment, never a resubmit, never a print.
    final op = <String, dynamic>{
      'local_operation_id': localOperationId,
      'operation_type': 'order.status',
      'target_entity': 'order',
      'target_id': orderId,
      'client_created_at': DateTime.now().toIso8601String(),
      'payload': <String, dynamic>{
        'order_id': orderId,
        'new_status': 'completed',
      },
    };
    final Object? raw;
    try {
      raw = await transport.invoke('sync_push', <String, dynamic>{
        'p_pin_session_id': session.pinSessionId,
        'p_device_id': session.deviceId,
        'p_operations': <dynamic>[op],
      });
    } on SyncTransportException catch (e) {
      // Ambiguous — the op MAY have applied; the order/table stay consistent (a
      // replay of the same id is a no-op) and the caller can retry.
      return KitchenFinishResult(
        orderId,
        KitchenFinishStatus.failed,
        error: e.code ?? e.kind.name,
      );
    }
    final outcome = _opOutcome(raw, localOperationId);
    switch (outcome.kind) {
      case _OpKind.applied:
        return KitchenFinishResult(orderId, KitchenFinishStatus.finished);
      case _OpKind.staleStatus:
        // invalid_transition: the order already moved. If it is ALREADY completed
        // (this or another till closed it), report finished IDEMPOTENTLY; any
        // other state is an honest failure (never a silent success).
        return outcome.currentStatus == 'completed'
            ? KitchenFinishResult(orderId, KitchenFinishStatus.finished)
            : KitchenFinishResult(
                orderId,
                KitchenFinishStatus.failed,
                error: outcome.error ?? 'invalid_transition',
              );
      case _OpKind.denied:
      case _OpKind.conflict:
      case _OpKind.rejected:
      case _OpKind.malformed:
        return KitchenFinishResult(
          orderId,
          KitchenFinishStatus.failed,
          error: outcome.error ?? outcome.rawStatus ?? 'failed',
        );
    }
  }

  _OpOutcome _opOutcome(Object? raw, String localOp) {
    if (raw is! Map) {
      return const _OpOutcome(_OpKind.malformed, error: 'malformed_response');
    }
    final results = raw['results'];
    if (results is! List) {
      return const _OpOutcome(_OpKind.malformed, error: 'missing_results');
    }
    for (final r in results) {
      if (r is Map && r['local_operation_id'] == localOp) {
        final m = r.cast<String, dynamic>();
        final status = m['status'] is String ? m['status'] as String : null;
        final error = m['error'] is String ? m['error'] as String : null;
        // `from` is the order's authoritative current status on invalid_transition.
        final from = m['from'] is String ? m['from'] as String : null;
        final autoCompleted =
            m['auto_completed'] == true || m['order_status'] == 'completed';
        if (status == 'applied' || m['ok'] == true) {
          return _OpOutcome(_OpKind.applied, autoCompleted: autoCompleted);
        }
        switch (error) {
          case 'invalid_transition':
            return _OpOutcome(
              _OpKind.staleStatus,
              error: error,
              currentStatus: from,
            );
          case 'permission_denied':
          case 'revoked_device':
            return _OpOutcome(_OpKind.denied, error: error);
          case 'conflict':
            return _OpOutcome(_OpKind.conflict, error: error);
          default:
            if (status == 'conflict') {
              return _OpOutcome(_OpKind.conflict, error: error ?? 'conflict');
            }
            return _OpOutcome(
              _OpKind.rejected,
              error: error,
              rawStatus: status,
            );
        }
      }
    }
    // The batch echoed no result for our op — anomalous. Fail (retryable) rather
    // than assume anything about the order's state.
    return const _OpOutcome(_OpKind.malformed, error: 'no_matching_operation');
  }
}

/// How a single `order.status` op result classifies for the progress loop.
enum _OpKind {
  /// The step applied (or replayed as applied) — advance.
  applied,

  /// invalid_transition — the order moved on; [_OpOutcome.currentStatus] holds
  /// its authoritative status to reclassify from.
  staleStatus,

  /// A serialization conflict (carries no status) — re-read + reclassify.
  conflict,

  /// permission_denied / revoked_device — a real authorization failure.
  denied,

  /// A raised validation/scope/not-found rejection — a genuine failure.
  rejected,

  /// An unparseable / missing result — treated as a genuine failure.
  malformed,
}

class _OpOutcome {
  const _OpOutcome(
    this.kind, {
    this.error,
    this.currentStatus,
    this.autoCompleted = false,
    this.rawStatus,
  });
  final _OpKind kind;
  final String? error;

  /// The order's authoritative current status, when the server supplied it
  /// (the `from` of an invalid_transition).
  final String? currentStatus;
  final bool autoCompleted;
  final String? rawStatus;
}
