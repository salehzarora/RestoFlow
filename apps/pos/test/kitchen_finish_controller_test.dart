import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/data/kitchen_finish_repository.dart';
import 'package:restoflow_pos/src/state/kitchen_finish_controller.dart';

/// KITCHEN-PRINT-DUAL-001D — the batch controller: capture-once, continue past a
/// per-order failure, an honest summary, and a re-entrancy guard.
class _FakeRepo implements KitchenFinishRepository {
  _FakeRepo({this.failOrderIds = const {}, this.gate});
  final Set<String> failOrderIds;
  final Completer<void>? gate;
  final List<String> processed = [];

  @override
  Future<KitchenFinishResult> advanceToServed({
    required String orderId,
    required String fromStatus,
  }) async {
    if (gate != null) await gate!.future;
    processed.add(orderId);
    return failOrderIds.contains(orderId)
        ? KitchenFinishResult(orderId, KitchenFinishStatus.failed, error: 'x')
        : KitchenFinishResult(orderId, KitchenFinishStatus.finished);
  }
}

ProviderContainer _container(KitchenFinishRepository repo) {
  final c = ProviderContainer(
    overrides: [kitchenFinishRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

List<KitchenFinishTarget> _targets(List<String> ids) => [
  for (final id in ids) (orderId: id, fromStatus: 'submitted'),
];

void main() {
  test(
    'a partial batch continues past failures and reports an honest summary',
    () async {
      final repo = _FakeRepo(failOrderIds: {'o2'});
      final c = _container(repo);
      final summary = await c
          .read(kitchenFinishControllerProvider.notifier)
          .finishAll(_targets(['o1', 'o2', 'o3']));

      expect(summary, isNotNull);
      expect(summary!.finished, 2); // o1, o3
      expect(summary.failed, 1); // o2
      expect(summary.total, 3);
      // EVERY order was processed — a failure never aborts the batch.
      expect(repo.processed, ['o1', 'o2', 'o3']);
      // Not running afterwards; the summary is retained.
      expect(c.read(kitchenFinishControllerProvider).running, isFalse);
      expect(c.read(kitchenFinishControllerProvider).lastSummary?.failed, 1);
    },
  );

  test(
    'a second press while a batch is running is blocked (returns null)',
    () async {
      final gate = Completer<void>();
      final repo = _FakeRepo(gate: gate);
      final c = _container(repo);
      final notifier = c.read(kitchenFinishControllerProvider.notifier);

      final first = notifier.finishAll(_targets(['o1', 'o2']));
      // The controller set running=true synchronously before the first await.
      expect(c.read(kitchenFinishControllerProvider).running, isTrue);

      final second = await notifier.finishAll(_targets(['o3']));
      expect(second, isNull, reason: 'a concurrent second batch is refused');

      gate.complete();
      final summary = await first;
      expect(summary!.finished, 2);
      expect(repo.processed, [
        'o1',
        'o2',
      ], reason: 'the second batch never ran');
      expect(c.read(kitchenFinishControllerProvider).running, isFalse);
    },
  );

  test('all-success batch reports zero failures', () async {
    final c = _container(_FakeRepo());
    final summary = await c
        .read(kitchenFinishControllerProvider.notifier)
        .finishAll(_targets(['o1', 'o2']));
    expect(summary!.finished, 2);
    expect(summary.failed, 0);
  });
}
