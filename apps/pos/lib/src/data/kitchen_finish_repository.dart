import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'ids.dart';

/// KITCHEN-PRINT-DUAL-001D — the outcome of advancing ONE order to `served`.
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
/// the server (`app.apply_order_status_transition`) admits ONLY these one-hop
/// forward edges, so a bulk finish drives an active order to `served` by sending
/// each next step in order — never one multi-step jump.
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

/// The ordered `new_status` steps to take [from] up to `served` (exclusive of
/// [from]). E.g. submitted -> [accepted, preparing, ready, served]; ready ->
/// [served]. Empty when [from] is not an active-advanceable status.
List<String> kitchenStepsToServed(String from) {
  final i = kKitchenAdvanceChain.indexOf(from);
  if (i < 0 || i >= kKitchenAdvanceChain.length - 1) return const [];
  return kKitchenAdvanceChain.sublist(i + 1);
}

/// Advances active kitchen orders to `served` using the EXISTING `order.status`
/// sync_push op + the existing state machine (no new RPC/migration, no new
/// permission model — the server re-authorizes every push). It NEVER cancels,
/// voids, deletes, or completes an order and NEVER creates a payment or bypasses
/// settlement: reaching `served` auto-completes a PAID order through the existing
/// served+settled rule and leaves an UNPAID one at `served` (payable in history).
abstract class KitchenFinishRepository {
  /// Drives [orderId] (currently [fromStatus]) up to `served` via one or more
  /// single-step `order.status` ops. Returns finished on success, or failed with
  /// the first blocking server/transport code (the order stays retryable).
  Future<KitchenFinishResult> advanceToServed({
    required String orderId,
    required String fromStatus,
  });
}

/// In-memory DEMO finisher: validates the step chain and succeeds locally with no
/// backend (mirrors [DemoVoidStore]). Never reached when the button is real-mode
/// gated, but kept so the provider is total.
class DemoKitchenFinishRepository implements KitchenFinishRepository {
  const DemoKitchenFinishRepository();

  @override
  Future<KitchenFinishResult> advanceToServed({
    required String orderId,
    required String fromStatus,
  }) async {
    if (kitchenStepsToServed(fromStatus).isEmpty) {
      return KitchenFinishResult(
        orderId,
        KitchenFinishStatus.failed,
        error: 'not_active',
      );
    }
    return KitchenFinishResult(orderId, KitchenFinishStatus.finished);
  }
}

/// REAL finisher. Sends `order.status` ops to `public.sync_push` (dispatched to
/// `app.update_order_status`) over the SAME shared [SyncRpcTransport] +
/// [SyncSession] as the outbox/void/payment paths (anon key + the PIN/device
/// session; never the `app` schema, never a service-role key). Each op carries a
/// FRESH idempotency key; the server re-derives the current status from the
/// locked order row and admits only the exact single-step edge, so an
/// already-passed step is a harmless `invalid_transition` no-op.
class RealKitchenFinishRepository implements KitchenFinishRepository {
  const RealKitchenFinishRepository(this._transport, this._session, this._ids);

  final SyncRpcTransport? _transport;
  final SyncSession? _session;
  final ClientIdGenerator _ids;

  @override
  Future<KitchenFinishResult> advanceToServed({
    required String orderId,
    required String fromStatus,
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
    final steps = kitchenStepsToServed(fromStatus);
    if (steps.isEmpty) {
      return KitchenFinishResult(
        orderId,
        KitchenFinishStatus.failed,
        error: 'not_active',
      );
    }

    for (final newStatus in steps) {
      final localOp = _ids.newId();
      final op = <String, dynamic>{
        'local_operation_id': localOp,
        'operation_type': 'order.status',
        'target_entity': 'order',
        'target_id': orderId,
        'client_created_at': DateTime.now().toIso8601String(),
        // The server derives actor/org/branch/current-status from the PIN session
        // + the locked order row; the client sends ONLY the order + next status.
        'payload': <String, dynamic>{
          'order_id': orderId,
          'new_status': newStatus,
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
        return KitchenFinishResult(
          orderId,
          KitchenFinishStatus.failed,
          error: e.code ?? e.kind.name,
        );
      }

      final outcome = _opOutcome(raw, localOp);
      if (outcome.status != 'applied') {
        return KitchenFinishResult(
          orderId,
          KitchenFinishStatus.failed,
          error: outcome.error ?? outcome.status ?? 'unknown',
        );
      }
      // `served` (or an order that auto-completed on this step) is terminal for
      // the kitchen — stop advancing it.
      if (newStatus == 'served' || outcome.autoCompleted) break;
    }
    return KitchenFinishResult(orderId, KitchenFinishStatus.finished);
  }

  _OpOutcome _opOutcome(Object? raw, String localOp) {
    if (raw is! Map) return const _OpOutcome(status: 'malformed_response');
    final results = raw['results'];
    if (results is! List) return const _OpOutcome(status: 'missing_results');
    for (final r in results) {
      if (r is Map && r['local_operation_id'] == localOp) {
        final m = r.cast<String, dynamic>();
        return _OpOutcome(
          status: m['status'] is String ? m['status'] as String : null,
          error: m['error'] is String ? m['error'] as String : null,
          autoCompleted:
              m['auto_completed'] == true || m['order_status'] == 'completed',
        );
      }
    }
    return const _OpOutcome(status: 'no_matching_operation');
  }
}

class _OpOutcome {
  const _OpOutcome({this.status, this.error, this.autoCompleted = false});
  final String? status;
  final String? error;
  final bool autoCompleted;
}
