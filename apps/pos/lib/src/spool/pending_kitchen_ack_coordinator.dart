import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'kitchen_dispatch_import_coordinator.dart'
    show flushAck, KitchenAckFlushOutcome;
import 'kitchen_contained_ack.dart';

/// KITCHEN-MODE-001C2B — retries the acknowledgements this device still owes
/// the server (`imported` / `blocked_configuration` only), on startup/resume.
/// Exponential backoff (2s·2ⁿ, capped at 5 minutes) persisted in the job
/// row; terminal server verdicts stop the loop permanently; failures never
/// delete, re-encrypt, reroute, or re-queue anything.
final class PendingKitchenAckCoordinator {
  PendingKitchenAckCoordinator({
    required KitchenSpoolStore store,
    required SupabaseKitchenDispatchAckRepository ackRepository,
    DateTime Function()? now,
    Future<bool> Function(KitchenSpoolJobRow job)? mayFlush,
    KitchenAckInvoke? acknowledge,
  }) : _store = store,
       _ackRepository = ackRepository,
       _now = now ?? DateTime.now,
       _mayFlush = mayFlush,
       _acknowledge = acknowledge;

  static const Duration _backoffBase = Duration(seconds: 2);
  static const Duration _backoffCap = Duration(minutes: 5);

  final KitchenSpoolStore _store;
  final SupabaseKitchenDispatchAckRepository _ackRepository;
  final DateTime Function() _now;
  final Future<bool> Function(KitchenSpoolJobRow job)? _mayFlush;
  final KitchenAckInvoke? _acknowledge;

  /// Flushes every DUE pending acknowledgement for this device/branch scope.
  /// Returns (acked, retriesScheduled, terminal).
  Future<(int, int, int)> flush({
    required String deviceId,
    required String branchId,
  }) async {
    var acked = 0, retries = 0, terminal = 0;
    var eligible = 0;
    final due = await _store.listPendingServerAcks(
      deviceId: deviceId,
      branchId: branchId,
      now: _now(),
      // Inspect the finite durable snapshot when filtering, so held rows at
      // the front do not starve unrelated authentic acknowledgements. Actual
      // network work retains the existing twenty-ack bound.
      limit: _mayFlush == null ? 20 : await _store.countTotalRows(),
    );
    for (final job in due) {
      try {
        if (!(await _mayFlush?.call(job) ?? true)) continue;
      } on Object {
        continue;
      }
      if (++eligible > 20) break;
      final outcome = await flushAck(
        _store,
        _ackRepository,
        job,
        _now(),
        backoffBase: _backoffBase,
        backoffCap: _backoffCap,
        acknowledge: _acknowledge,
      );
      switch (outcome) {
        case KitchenAckFlushOutcome.acked:
          acked++;
        case KitchenAckFlushOutcome.retryScheduled:
          retries++;
        case KitchenAckFlushOutcome.terminal:
          terminal++;
        case KitchenAckFlushOutcome.skipped:
          break;
      }
    }
    return (acked, retries, terminal);
  }
}
