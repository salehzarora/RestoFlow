import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/draft_recovery_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';

/// PILOT-OPERATIONS-CORRECTIONS-001 — Finding 3: a successfully applied/accepted submit
/// must not retain a rejected-draft recovery. Cleanup lives in the recovery CONTROLLER
/// (it watches the outbox), covering BOTH timing orders (capture-then-applied AND
/// applied-then-capture), and never touches a pending / retryable-failed / permanently
/// rejected recovery.

/// A mutable fake outbox so a test can transition an entry through its lifecycle.
class _MutableOutbox extends OutboxController {
  _MutableOutbox(this._initial);
  final List<OutboxEntry> _initial;
  @override
  List<OutboxEntry> build() => _initial;
  void setEntries(List<OutboxEntry> entries) => state = entries;
}

OutboxEntry _entry(String id, OutboxSyncState state, {String? code}) =>
    OutboxEntry(
      id: id,
      deviceId: 'dev-1',
      localOperationId: 'op-$id',
      operationType: 'order.submit',
      targetEntity: 'order',
      targetId: 'order-$id',
      payloadJson: '{}',
      summary: OrderSummary(
        orderNumber: 'DEMO-$id',
        orderType: OrderType.takeaway,
        tableLabel: null,
        itemCount: 1,
        subtotalMinor: 4200,
        currencyCode: 'ILS',
        customerName: null,
      ),
      syncState: state,
      clientCreatedAt: DateTime.utc(2026, 7, 16),
      lastErrorCode: code,
    );

PosDraftRecovery _rec(String entryId) => PosDraftRecovery(
  draft: const CartDraftSnapshot(currencyCode: 'ILS', lines: []),
  orderType: OrderType.takeaway,
  outboxEntryId: entryId,
  binding: const PosRecoveryBinding(),
);

ProviderContainer _container(List<OutboxEntry> entries) {
  final c = ProviderContainer(
    overrides: [
      outboxControllerProvider.overrideWith(() => _MutableOutbox(entries)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('Finding 3: applied recoveries are cleared at the controller seam', () {
    test('1. captured while PENDING, then applied -> recovery cleared', () {
      final c = _container([_entry('e1', OutboxSyncState.created)]);
      final drafts = c.read(posDraftRecoveryProvider.notifier);
      // Register the controller (its outbox listener) then capture.
      c.read(posDraftRecoveryProvider);
      drafts.capture(_rec('e1'));
      expect(c.read(posDraftRecoveryProvider).containsKey('e1'), isTrue);
      // The submit is accepted.
      (c.read(outboxControllerProvider.notifier) as _MutableOutbox).setEntries([
        _entry('e1', OutboxSyncState.applied),
      ]);
      expect(c.read(posDraftRecoveryProvider).containsKey('e1'), isFalse);
    });

    test('2. already APPLIED before capture -> never stored', () {
      final c = _container([_entry('e1', OutboxSyncState.applied)]);
      final drafts = c.read(posDraftRecoveryProvider.notifier);
      c.read(posDraftRecoveryProvider);
      drafts.capture(
        _rec('e1'),
      ); // capture returns after the entry already applied
      expect(c.read(posDraftRecoveryProvider), isEmpty);
    });

    test('4. duplicate applied delivery is idempotent', () {
      final c = _container([_entry('e1', OutboxSyncState.created)]);
      c.read(posDraftRecoveryProvider.notifier).capture(_rec('e1'));
      final outbox =
          c.read(outboxControllerProvider.notifier) as _MutableOutbox;
      outbox.setEntries([_entry('e1', OutboxSyncState.applied)]);
      outbox.setEntries([_entry('e1', OutboxSyncState.applied)]); // again
      expect(c.read(posDraftRecoveryProvider), isEmpty);
    });

    test('5. a permanent item_unavailable rejection RETAINS the recovery', () {
      final c = _container([_entry('e1', OutboxSyncState.created)]);
      c.read(posDraftRecoveryProvider.notifier).capture(_rec('e1'));
      (c.read(outboxControllerProvider.notifier) as _MutableOutbox).setEntries([
        _entry('e1', OutboxSyncState.rejected, code: 'item_unavailable'),
      ]);
      expect(c.read(posDraftRecoveryProvider).containsKey('e1'), isTrue);
    });

    test('6. a retryable transport failure RETAINS the recovery', () {
      final c = _container([_entry('e1', OutboxSyncState.created)]);
      c.read(posDraftRecoveryProvider.notifier).capture(_rec('e1'));
      (c.read(outboxControllerProvider.notifier) as _MutableOutbox).setEntries([
        _entry('e1', OutboxSyncState.pending),
      ]);
      expect(c.read(posDraftRecoveryProvider).containsKey('e1'), isTrue);
    });

    test('7. cleanup affects only the matching entry', () {
      final c = _container([
        _entry('e1', OutboxSyncState.created),
        _entry('e2', OutboxSyncState.created),
      ]);
      final drafts = c.read(posDraftRecoveryProvider.notifier);
      drafts.capture(_rec('e1'));
      drafts.capture(_rec('e2'));
      // Only e1 becomes applied.
      (c.read(outboxControllerProvider.notifier) as _MutableOutbox).setEntries([
        _entry('e1', OutboxSyncState.applied),
        _entry('e2', OutboxSyncState.created),
      ]);
      final map = c.read(posDraftRecoveryProvider);
      expect(map.containsKey('e1'), isFalse);
      expect(map.containsKey('e2'), isTrue); // untouched
    });

    test('8. nothing is retained after accepted cleanup (no leaked draft)', () {
      final c = _container([_entry('e1', OutboxSyncState.created)]);
      c.read(posDraftRecoveryProvider.notifier).capture(_rec('e1'));
      (c.read(outboxControllerProvider.notifier) as _MutableOutbox).setEntries([
        _entry('e1', OutboxSyncState.applied),
      ]);
      // No record -> no customer name / notes retained for the accepted order.
      expect(c.read(posDraftRecoveryProvider), isEmpty);
    });
  });
}
