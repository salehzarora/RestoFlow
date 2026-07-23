import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/ids.dart';
import '../data/kitchen_finish_repository.dart';
import 'pos_session.dart';

/// KITCHEN-PRINT-DUAL-001D: the bulk kitchen-finish repository, selected by
/// runtime mode (demo vs real). Real mode posts `order.status` ops to
/// `public.sync_push` over the shared [posAuthTransportProvider] +
/// [posSyncSessionProvider]; with no transport/session it fails closed.
final kitchenFinishRepositoryProvider = Provider<KitchenFinishRepository>((
  ref,
) {
  if (ref.watch(runtimeConfigProvider).isDemoMode) {
    return const DemoKitchenFinishRepository();
  }
  return RealKitchenFinishRepository(
    ref.watch(posAuthTransportProvider),
    ref.watch(posSyncSessionProvider),
  );
});

/// One order to advance in a bulk finish: its id + its last-known status (the
/// next step toward `served` is derived from the status, then re-derived
/// authoritatively by the server on every push).
typedef KitchenFinishTarget = ({String orderId, String fromStatus});

/// The honest result of a bulk finish batch.
class KitchenFinishSummary {
  const KitchenFinishSummary({required this.finished, required this.failed});

  /// Orders removed from the active kitchen workflow — driven to served, or
  /// resolved concurrently (served/completed/cancelled/voided by another device).
  final int finished;

  /// Orders that stayed active (or unreadable) and remain visible + retryable.
  final int failed;

  int get total => finished + failed;
}

class KitchenFinishState {
  const KitchenFinishState({this.running = false, this.lastSummary});

  /// True while a batch is in flight — used to block a second press.
  final bool running;

  /// The most recent completed batch's summary (for the result message).
  final KitchenFinishSummary? lastSummary;

  KitchenFinishState copyWith({
    bool? running,
    KitchenFinishSummary? lastSummary,
  }) => KitchenFinishState(
    running: running ?? this.running,
    lastSummary: lastSummary ?? this.lastSummary,
  );
}

/// Drives the bulk kitchen-finish batch. Re-entrant-safe (a second call while
/// running is ignored). The eligible target list is resolved by [run] AFTER the
/// caller has confirmed — inside the running guard — so it reflects the branch's
/// state at execution time, never a snapshot taken before the confirmation.
class KitchenFinishController extends Notifier<KitchenFinishState> {
  @override
  KitchenFinishState build() => const KitchenFinishState();

  /// Runs one bulk finish. [resolveTargets] is invoked ONCE, under the running
  /// guard, to produce the fresh eligible list (the caller refreshes the
  /// authoritative window first, then derives the active orders). An empty list
  /// yields a zero/zero summary and sends nothing. Every target is advanced by
  /// the repository's bounded authoritative-progress loop, sharing ONE
  /// [batchRunId] so idempotency keys are stable across retries within the run.
  /// A per-order failure never aborts the batch. Returns the summary, or null if
  /// a batch was already running.
  Future<KitchenFinishSummary?> run({
    required Future<List<KitchenFinishTarget>> Function() resolveTargets,
    required Future<String?> Function(String orderId) refreshStatus,
  }) async {
    if (state.running) return null;
    state = state.copyWith(running: true);
    // One id for the whole batch; each op keys off batchRunId + order + target.
    final batchRunId = ref.read(clientIdGeneratorProvider).newId();
    var finished = 0;
    var failed = 0;
    try {
      final targets = await resolveTargets();
      // Nothing eligible after confirmation -> zero/zero, and don't even build
      // the repository (no transport is touched for an empty batch).
      if (targets.isNotEmpty) {
        final repo = ref.read(kitchenFinishRepositoryProvider);
        for (final t in targets) {
          try {
            final result = await repo.advanceToServed(
              orderId: t.orderId,
              fromStatus: t.fromStatus,
              batchRunId: batchRunId,
              refreshStatus: refreshStatus,
            );
            if (result.isFinished) {
              finished++;
            } else {
              failed++;
            }
          } catch (_) {
            // Continue processing the rest of the batch on any per-order failure.
            failed++;
          }
        }
      }
    } catch (_) {
      // A failure resolving the target list (or any unexpected error) must never
      // leave the controller stuck "running" — fall through and clear it below.
    }
    final summary = KitchenFinishSummary(finished: finished, failed: failed);
    state = KitchenFinishState(running: false, lastSummary: summary);
    return summary;
  }
}

final kitchenFinishControllerProvider =
    NotifierProvider<KitchenFinishController, KitchenFinishState>(
      KitchenFinishController.new,
    );
