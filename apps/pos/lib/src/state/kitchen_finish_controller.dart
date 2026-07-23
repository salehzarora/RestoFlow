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
    ref.watch(clientIdGeneratorProvider),
  );
});

/// One order to advance in a bulk finish: its id + its CURRENT status (the step
/// chain to `served` is derived from the status).
typedef KitchenFinishTarget = ({String orderId, String fromStatus});

/// The honest result of a bulk finish batch.
class KitchenFinishSummary {
  const KitchenFinishSummary({required this.finished, required this.failed});

  /// Orders removed from the active kitchen workflow (reached served/completed).
  final int finished;

  /// Orders that failed a transition (remain visible + retryable).
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
/// running is ignored), captures the target list by value, continues past a
/// per-order failure, and reports an honest [KitchenFinishSummary].
class KitchenFinishController extends Notifier<KitchenFinishState> {
  @override
  KitchenFinishState build() => const KitchenFinishState();

  /// Advances every [targets] entry up to `served`. Returns the summary, or null
  /// if a batch was already running (the caller must have blocked the press).
  Future<KitchenFinishSummary?> finishAll(
    List<KitchenFinishTarget> targets,
  ) async {
    if (state.running) return null;
    state = state.copyWith(running: true);
    final repo = ref.read(kitchenFinishRepositoryProvider);
    // Capture the list once (the caller passes the snapshot taken AFTER confirm).
    final work = List<KitchenFinishTarget>.of(targets);
    var finished = 0;
    var failed = 0;
    for (final t in work) {
      try {
        final result = await repo.advanceToServed(
          orderId: t.orderId,
          fromStatus: t.fromStatus,
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
    final summary = KitchenFinishSummary(finished: finished, failed: failed);
    state = KitchenFinishState(running: false, lastSummary: summary);
    return summary;
  }
}

final kitchenFinishControllerProvider =
    NotifierProvider<KitchenFinishController, KitchenFinishState>(
      KitchenFinishController.new,
    );
