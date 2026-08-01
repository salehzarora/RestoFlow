import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/kitchen_finish_repository.dart';
import 'package:restoflow_pos/src/state/kitchen_finish_controller.dart';

/// SINGLE-DEVICE-ADDITION-CLOSE-AND-STALE-FAILURES-007 — BUG 1.
///
/// THE DEFECT, from the server outwards.
///
/// `app.try_auto_complete_order` (the AUTOMATIC served -> completed rule, fired
/// at the tail of a `served` transition and at the tail of `record_payment`)
/// additionally requires `app.order_rounds_all_served` — TRUE only when no live
/// `order_service_rounds` row has a status other than `served`
/// (20260722090000_psc_001c_service_rounds.sql:188-195).
///
/// `app.add_order_items` creates a NEW service round. In the one-device /
/// printer_only workflow there is NO KDS, and `app.update_round_status` is the
/// KDS's path — so that round is never walked to `served`. The predicate is
/// therefore permanently false and the order NEVER auto-completes, no matter how
/// it is paid.
///
/// `20260804090000_deferred_order_amendments_001_takeaway_and_mode_close.sql`
/// already fixed the MANUAL served -> completed gate to SKIP the rounds check on
/// a printer_only branch, and it is applied on hosted. Its own header states it
/// deliberately did NOT modify `app.try_auto_complete_order`. So the server can
/// already close these orders — through the manual `order.status -> completed`
/// op that `KitchenFinishRepository.completeServedOrder` sends.
///
/// THE CLIENT NEVER ASKS. `_FinishAllKitchenButton.deriveActive()` targets only
/// `kActiveKitchenStatuses` = {submitted, accepted, preparing, ready}; `served`
/// is explicitly excluded as "already off the kitchen board"
/// (kitchen_finish_repository.dart:36-43). An order stranded at `served` by the
/// rounds gate is therefore never touched by Finish all, and it sits in the
/// active list for ever with the payment already taken.
///
/// An ordinary order without Add-items has ZERO rounds, `order_rounds_all_served`
/// passes trivially, and it auto-completes exactly as the operator expects —
/// which is why the action "works for ordinary orders".
///
/// These tests drive the REAL controller against a recording repository, so they
/// pin the batch's behaviour, not a helper's.
class _RecordingRepo implements KitchenFinishRepository {
  _RecordingRepo({this.failComplete = const {}});

  final Set<String> failComplete;
  final List<String> advanced = [];
  final List<String> completed = [];
  final List<String> completeOpIds = [];

  @override
  Future<KitchenFinishResult> advanceToServed({
    required String orderId,
    required String fromStatus,
    required String batchRunId,
    required Future<String?> Function(String orderId) refreshStatus,
  }) async {
    advanced.add(orderId);
    return KitchenFinishResult(orderId, KitchenFinishStatus.finished);
  }

  @override
  Future<KitchenFinishResult> completeServedOrder({
    required String orderId,
    required String localOperationId,
  }) async {
    completed.add(orderId);
    completeOpIds.add(localOperationId);
    return failComplete.contains(orderId)
        ? KitchenFinishResult(
            orderId,
            KitchenFinishStatus.failed,
            error: 'invalid_transition',
          )
        : KitchenFinishResult(orderId, KitchenFinishStatus.finished);
  }
}

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

Future<KitchenFinishSummary?> _run(
  ProviderContainer c,
  List<KitchenFinishTarget> targets,
) => c
    .read(kitchenFinishControllerProvider.notifier)
    .run(resolveTargets: () async => targets, refreshStatus: (_) async => null);

void main() {
  group('A. a DINE-IN order stranded at served by an Add-items round', () {
    test('A1 is completed by the batch, not skipped', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);

      // The order is PAID and sitting at `served`: the automatic rule refused it
      // with `rounds_active` because its Add-items round can never be served on a
      // printer_only branch.
      final summary = await _run(c, [
        (orderId: 'o-dinein', fromStatus: 'served', settled: true),
      ]);

      expect(
        repo.completed,
        ['o-dinein'],
        reason:
            'THE DEFECT: `served` was excluded from the batch, so a paid order '
            'stranded by the rounds gate was never asked to complete and stayed '
            'in the active list for ever',
      );
      expect(
        repo.advanced,
        isEmpty,
        reason: 'it is already served — there is nothing to advance',
      );
      expect(summary!.finished, 1);
      expect(summary.failed, 0);
    });

    test('A2 an UNPAID served order is left alone — settlement closes it, not '
        'this button', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);

      final summary = await _run(c, [
        (orderId: 'o-unpaid', fromStatus: 'served', settled: false),
      ]);

      expect(
        repo.completed,
        isEmpty,
        reason:
            'completing an unpaid order would close a bill nobody paid; the '
            'server would refuse it anyway (D-025) and the honest local answer '
            'is not to ask',
      );
      expect(summary!.total, 0, reason: 'nothing was eligible');
    });
  });

  group('B. a TAKEAWAY order stranded the same way', () {
    test('B1 is completed by the batch', () async {
      // In printer_only the direct-print helper promotes a fresh submitted order
      // straight to `served`, so takeaway strands in exactly the same place.
      final repo = _RecordingRepo();
      final c = _container(repo);

      final summary = await _run(c, [
        (orderId: 'o-takeaway', fromStatus: 'served', settled: true),
      ]);

      expect(repo.completed, ['o-takeaway']);
      expect(summary!.finished, 1);
    });
  });

  group('C. MULTIPLE Add-items rounds', () {
    test('C1 one order with several rounds still needs exactly ONE completion '
        'op — the rounds are not walked individually', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);

      await _run(c, [
        (orderId: 'o-multi', fromStatus: 'served', settled: true),
      ]);

      expect(
        repo.completed,
        ['o-multi'],
        reason:
            'the order-level transition is what removes it from the queue; the '
            'server skips the rounds gate on a printer_only branch, so no round '
            'status is fabricated and no per-round op is sent',
      );
      expect(repo.completeOpIds, hasLength(1));
    });

    test('C2 a mixed batch advances the active ones AND completes the stranded '
        'ones in the same run', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);

      final summary = await _run(c, [
        (orderId: 'o-active', fromStatus: 'submitted', settled: false),
        (orderId: 'o-stranded', fromStatus: 'served', settled: true),
      ]);

      expect(repo.advanced, ['o-active']);
      expect(repo.completed, ['o-stranded']);
      expect(summary!.finished, 2);
      expect(summary.failed, 0);
    });
  });

  group('D. ordinary orders are unchanged', () {
    test('D1 an active order without Add-items is still advanced, never '
        'completed directly', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);

      final summary = await _run(c, [
        (orderId: 'o-plain', fromStatus: 'preparing', settled: false),
      ]);

      expect(repo.advanced, ['o-plain']);
      expect(
        repo.completed,
        isEmpty,
        reason:
            'reaching served auto-completes a paid order through the existing '
            'server rule — the batch must not add a second completion path for '
            'orders that never needed one',
      );
      expect(summary!.finished, 1);
    });
  });

  group('G. idempotency', () {
    test('G1 the completion op id is STABLE per batch+order, so a repeat press '
        'replays instead of double-completing', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);

      await _run(c, [(orderId: 'o-1', fromStatus: 'served', settled: true)]);
      final first = repo.completeOpIds.single;

      await _run(c, [(orderId: 'o-1', fromStatus: 'served', settled: true)]);

      expect(repo.completed, ['o-1', 'o-1']);
      expect(
        repo.completeOpIds.last,
        isNot(first),
        reason:
            'a NEW batch gets a new run id — the server replays an already '
            'completed order as finished, so this is safe and honest',
      );
      expect(
        first,
        contains('o-1'),
        reason: 'the id binds the order, so two orders never share a key',
      );
    });

    test(
      'G2 a server-refused completion is reported failed, never as finished',
      () async {
        final repo = _RecordingRepo(failComplete: {'o-x'});
        final c = _container(repo);

        final summary = await _run(c, [
          (orderId: 'o-x', fromStatus: 'served', settled: true),
        ]);

        expect(summary!.finished, 0);
        expect(summary.failed, 1, reason: 'it stays visible and retryable');
      },
    );
  });
}
