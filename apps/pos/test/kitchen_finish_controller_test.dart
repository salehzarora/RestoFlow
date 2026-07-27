import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/kitchen_finish_repository.dart';
import 'package:restoflow_pos/src/state/kitchen_finish_controller.dart';

/// KITCHEN-PRINT-DUAL-001D (concurrency correction) — the batch controller:
/// resolves the eligible list AFTER confirmation (inside the running guard),
/// continues past a per-order failure, reports an honest summary, shares ONE
/// batchRunId per run, and refuses a second concurrent press.
class _FakeRepo implements KitchenFinishRepository {
  _FakeRepo({this.failOrderIds = const {}, this.gate});
  final Set<String> failOrderIds;
  final Completer<void>? gate;
  final List<String> processed = [];
  final List<String> batchIds = [];

  @override
  Future<KitchenFinishResult> advanceToServed({
    required String orderId,
    required String fromStatus,
    required String batchRunId,
    required Future<String?> Function(String orderId) refreshStatus,
  }) async {
    if (gate != null) await gate!.future;
    processed.add(orderId);
    batchIds.add(batchRunId);
    return failOrderIds.contains(orderId)
        ? KitchenFinishResult(orderId, KitchenFinishStatus.failed, error: 'x')
        : KitchenFinishResult(orderId, KitchenFinishStatus.finished);
  }
}

/// Deterministic batch ids: batch-1, batch-2, ...
class _SeqIds implements ClientIdGenerator {
  int _n = 0;
  @override
  String newId() => 'batch-${++_n}';
}

ProviderContainer _container(KitchenFinishRepository repo) {
  final c = ProviderContainer(
    overrides: [
      kitchenFinishRepositoryProvider.overrideWithValue(repo),
      clientIdGeneratorProvider.overrideWithValue(_SeqIds()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<List<KitchenFinishTarget>> Function() _fixed(List<String> ids) =>
    () async => [for (final id in ids) (orderId: id, fromStatus: 'submitted')];

Future<String?> _noRefresh(String orderId) async => null;

void main() {
  test(
    'a partial batch continues past failures and reports an honest summary',
    () async {
      final repo = _FakeRepo(failOrderIds: {'o2'});
      final c = _container(repo);
      final summary = await c
          .read(kitchenFinishControllerProvider.notifier)
          .run(
            resolveTargets: _fixed(['o1', 'o2', 'o3']),
            refreshStatus: _noRefresh,
          );

      expect(summary, isNotNull);
      expect(summary!.finished, 2); // o1, o3
      expect(summary.failed, 1); // o2
      expect(summary.total, 3);
      // EVERY order was processed — a failure never aborts the batch.
      expect(repo.processed, ['o1', 'o2', 'o3']);
      expect(c.read(kitchenFinishControllerProvider).running, isFalse);
      expect(c.read(kitchenFinishControllerProvider).lastSummary?.failed, 1);
    },
  );

  test('the eligible list is resolved AT run time (post-confirmation), not '
      'captured earlier', () async {
    final repo = _FakeRepo();
    final c = _container(repo);
    // The list the closure will return is mutated AFTER it is constructed but
    // BEFORE run() awaits it — the run must see the fresh set.
    var active = <String>['o-stale'];
    Future<List<KitchenFinishTarget>> resolve() async => [
      for (final id in active) (orderId: id, fromStatus: 'submitted'),
    ];
    active = ['o-fresh-1', 'o-fresh-2'];
    final summary = await c
        .read(kitchenFinishControllerProvider.notifier)
        .run(resolveTargets: resolve, refreshStatus: _noRefresh);
    expect(summary!.total, 2);
    expect(repo.processed, ['o-fresh-1', 'o-fresh-2']);
  });

  test(
    'an empty post-confirmation list sends nothing and reports zero/zero',
    () async {
      final repo = _FakeRepo();
      final c = _container(repo);
      final summary = await c
          .read(kitchenFinishControllerProvider.notifier)
          .run(resolveTargets: () async => const [], refreshStatus: _noRefresh);
      expect(summary, isNotNull);
      expect(summary!.finished, 0);
      expect(summary.failed, 0);
      expect(summary.total, 0);
      expect(repo.processed, isEmpty);
      expect(c.read(kitchenFinishControllerProvider).running, isFalse);
    },
  );

  test(
    'every order in ONE run shares a single batchRunId; a new run gets a new '
    'one',
    () async {
      final repo = _FakeRepo();
      final c = _container(repo);
      final notifier = c.read(kitchenFinishControllerProvider.notifier);
      await notifier.run(
        resolveTargets: _fixed(['o1', 'o2']),
        refreshStatus: _noRefresh,
      );
      await notifier.run(
        resolveTargets: _fixed(['o3']),
        refreshStatus: _noRefresh,
      );
      expect(repo.batchIds, ['batch-1', 'batch-1', 'batch-2']);
    },
  );

  test(
    'a second press while a batch is running is blocked (returns null)',
    () async {
      final gate = Completer<void>();
      final repo = _FakeRepo(gate: gate);
      final c = _container(repo);
      final notifier = c.read(kitchenFinishControllerProvider.notifier);

      final first = notifier.run(
        resolveTargets: _fixed(['o1', 'o2']),
        refreshStatus: _noRefresh,
      );
      // The controller set running=true synchronously before the first await.
      expect(c.read(kitchenFinishControllerProvider).running, isTrue);

      final second = await notifier.run(
        resolveTargets: _fixed(['o3']),
        refreshStatus: _noRefresh,
      );
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
        .run(resolveTargets: _fixed(['o1', 'o2']), refreshStatus: _noRefresh);
    expect(summary!.finished, 2);
    expect(summary.failed, 0);
  });
}
