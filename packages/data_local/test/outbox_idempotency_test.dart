import 'package:drift/native.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:test/test.dart';

/// Fixed timestamp so tests stay deterministic.
final _t = DateTime.utc(2026, 1, 1, 12);

OutboxOperationsCompanion _op({
  required String id,
  required String deviceId,
  required String localOperationId,
}) {
  return OutboxOperationsCompanion.insert(
    id: id,
    deviceId: deviceId,
    localOperationId: localOperationId,
    organizationId: 'org-1',
    operationType: 'order.create',
    targetEntity: 'orders',
    targetId: 'order-1',
    payload: '{"note":"opaque payload, no money fields"}',
    baseRevision: 0,
    clientCreatedAt: _t,
    clientUpdatedAt: _t,
  );
}

void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('Outbox idempotency (DECISION D-022)', () {
    test('duplicate (device_id, local_operation_id) insert is rejected '
        'and only one row exists', () async {
      await db.enqueueOperation(
        _op(id: 'a', deviceId: 'D1', localOperationId: 'L1'),
      );

      await expectLater(
        db.enqueueOperation(
          _op(id: 'b', deviceId: 'D1', localOperationId: 'L1'),
        ),
        throwsA(isA<SqliteException>()),
      );

      final rows = await db.select(db.outboxOperations).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, 'a');
    });

    test(
      'same device with a different local_operation_id is allowed',
      () async {
        await db.enqueueOperation(
          _op(id: 'a', deviceId: 'D1', localOperationId: 'L1'),
        );
        await db.enqueueOperation(
          _op(id: 'b', deviceId: 'D1', localOperationId: 'L2'),
        );
        expect(await db.select(db.outboxOperations).get(), hasLength(2));
      },
    );

    test('same local_operation_id on a different device is allowed', () async {
      await db.enqueueOperation(
        _op(id: 'a', deviceId: 'D1', localOperationId: 'L1'),
      );
      await db.enqueueOperation(
        _op(id: 'b', deviceId: 'D2', localOperationId: 'L1'),
      );
      expect(await db.select(db.outboxOperations).get(), hasLength(2));
    });

    test('a fresh outbox row carries the expected defaults', () async {
      await db.enqueueOperation(
        _op(id: 'a', deviceId: 'D1', localOperationId: 'L1'),
      );
      final row = (await db.select(db.outboxOperations).get()).single;
      expect(row.syncState, SyncOperationState.created);
      expect(row.dependsOn, '[]');
      expect(row.attemptCount, 0);
      expect(row.nextAttemptAt, isNull);
    });
  });
}
