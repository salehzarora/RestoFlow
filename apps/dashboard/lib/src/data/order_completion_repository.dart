/// The ORDER-COMPLETION data seam (ORDER-COMPLETION-001).
///
/// ONE write: move an eligible `served` order to the canonical terminal state
/// `completed`. Nothing else. There is no payment, refund, void, discount,
/// reopen or arbitrary-status entry point here, by construction — the target
/// status is not even a parameter.
///
/// The demo implementation mutates the shared [DemoOrderStore] (so the order
/// really leaves Active Orders and appears in History); the real implementation
/// calls `public.owner_complete_order`, the JWT front of the single canonical
/// state machine. Both apply the SAME rules and surface the SAME typed outcomes,
/// so the UI never branches on the source and the demo never lies about policy.
library;

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'demo_order_store.dart';

/// Why a completion did not succeed. Each maps to a STABLE server domain error;
/// none of them is a raw technical message, and each has its own localized copy.
enum OrderCompletionError {
  /// D-025: the order carries no completed payment, so fulfillment may not close.
  /// (`order_not_paid`)
  notPaid,

  /// The order is not in the one eligible source state, or is already terminal.
  /// (`invalid_transition`)
  invalidState,

  /// The caller may not settle orders in this scope. (`permission_denied`)
  permissionDenied,

  /// Someone else changed the order first; the client's view is stale.
  /// (`revision_mismatch`)
  conflict,

  /// The order is not visible in this scope. (`not_found`)
  notFound,

  /// Network / transport failure — the ONLY safely retryable outcome.
  transient,
}

/// The outcome of a completion attempt.
sealed class OrderCompletionResult {
  const OrderCompletionResult();
}

/// The order is now `completed`. [alreadyCompleted] means the server found it was
/// ALREADY completed and did nothing — an idempotent retry, still a success.
class OrderCompleted extends OrderCompletionResult {
  const OrderCompleted({this.alreadyCompleted = false, this.revision});

  final bool alreadyCompleted;
  final int? revision;
}

/// The completion was refused. The order is unchanged.
class OrderCompletionFailed extends OrderCompletionResult {
  const OrderCompletionFailed(this.error);

  final OrderCompletionError error;

  /// Retrying is only safe for a transport failure — a domain refusal would just
  /// be refused again, and blind retry of a write is never offered.
  bool get isRetryable => error == OrderCompletionError.transient;
}

/// Completes an eligible order.
abstract class OrderCompletionRepository {
  /// Moves [orderId] from `served` to `completed`. [expectedRevision] (when the
  /// caller knows it) gives stale-client protection: the server refuses if the
  /// order moved underneath us.
  Future<OrderCompletionResult> complete(
    String orderId, {
    int? expectedRevision,
  });
}

/// Demo completion against the SHARED demo store — deterministic, and honest
/// about policy: it enforces the same eligibility and the same D-025 payment rule
/// the server does, and it fabricates no payment and no money.
class DemoOrderCompletionRepository implements OrderCompletionRepository {
  DemoOrderCompletionRepository(this._store, {this.failureError});

  final DemoOrderStore _store;

  /// When set, every attempt fails with this error (drives/tests the failure
  /// states, including the retryable transport one).
  final OrderCompletionError? failureError;

  @override
  Future<OrderCompletionResult> complete(
    String orderId, {
    int? expectedRevision,
  }) async {
    final forced = failureError;
    if (forced != null) return OrderCompletionFailed(forced);

    final refusal = _store.complete(orderId);
    return switch (refusal) {
      null => const OrderCompleted(),
      DemoCompleteRefusal.notFound => const OrderCompletionFailed(
        OrderCompletionError.notFound,
      ),
      DemoCompleteRefusal.notPaid => const OrderCompletionFailed(
        OrderCompletionError.notPaid,
      ),
      DemoCompleteRefusal.invalidTransition => const OrderCompletionFailed(
        OrderCompletionError.invalidState,
      ),
    };
  }
}

/// Real completion through `public.owner_complete_order` — the JWT front of the
/// canonical state machine. The actor, the scope and the target status are all
/// SERVER-derived: this client sends only the organization and the order id.
///
/// FAIL-CLOSED: with no transport/scope it throws [RealRepoNotWiredError]; it
/// never falls back to demo, and it never reports success it did not receive.
class RealOrderCompletionRepository implements OrderCompletionRepository {
  const RealOrderCompletionRepository(
    this.config, {
    this.scope,
    this.transport,
  });

  final SupabaseBootstrapConfig? config;
  final MembershipContext? scope;
  final SyncRpcTransport? transport;

  @override
  Future<OrderCompletionResult> complete(
    String orderId, {
    int? expectedRevision,
  }) async {
    final t = transport;
    final m = scope;
    if (t == null || m == null) {
      throw const RealRepoNotWiredError(
        'order-completion: no authenticated transport/scope - real write not wired',
      );
    }

    final Object? raw;
    try {
      raw = await t.invoke('owner_complete_order', <String, dynamic>{
        'p_organization_id': m.organizationId,
        'p_order_id': orderId,
        'p_expected_revision': expectedRevision,
      });
    } on SyncTransportException {
      // The ONLY retryable outcome: we do not know whether the write landed, and
      // the server call is idempotent, so a retry is safe.
      return const OrderCompletionFailed(OrderCompletionError.transient);
    } catch (_) {
      return const OrderCompletionFailed(OrderCompletionError.transient);
    }

    // A malformed body fails CLOSED — never optimistically reported as success.
    if (raw is! Map) {
      return const OrderCompletionFailed(OrderCompletionError.transient);
    }
    if (raw['ok'] == true) {
      return OrderCompleted(
        alreadyCompleted: raw['already_completed'] == true,
        revision: raw['revision'] is int ? raw['revision'] as int : null,
      );
    }
    return OrderCompletionFailed(_mapError(raw['error']));
  }

  /// The server's STABLE domain errors -> typed outcomes. An unrecognised error is
  /// NOT treated as retryable (we do not blind-retry a write we do not understand).
  static OrderCompletionError _mapError(Object? code) => switch ('$code') {
    'order_not_paid' => OrderCompletionError.notPaid,
    'invalid_transition' => OrderCompletionError.invalidState,
    'permission_denied' => OrderCompletionError.permissionDenied,
    'revision_mismatch' => OrderCompletionError.conflict,
    'not_found' => OrderCompletionError.notFound,
    _ => OrderCompletionError.invalidState,
  };
}
