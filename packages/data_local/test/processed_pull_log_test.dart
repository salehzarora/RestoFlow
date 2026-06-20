import 'package:drift/native.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:test/test.dart';

final _t = DateTime.utc(2026, 1, 1, 12);

ProcessedPullLogCompanion _entry({
  required String id,
  required String deviceId,
  required String localOperationId,
}) {
  return ProcessedPullLogCompanion.insert(
    id: id,
    deviceId: deviceId,
    localOperationId: localOperationId,
    appliedAt: _t,
  );
}

void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('Processed-pull / inbox ledger dedupe (DECISION D-022)', () {
    test('duplicate (device_id, local_operation_id) is rejected '
        'and only one row exists', () async {
      await db.recordProcessedPull(
        _entry(id: 'a', deviceId: 'D1', localOperationId: 'L1'),
      );

      await expectLater(
        db.recordProcessedPull(
          _entry(id: 'b', deviceId: 'D1', localOperationId: 'L1'),
        ),
        throwsA(isA<SqliteException>()),
      );

      final rows = await db.select(db.processedPullLog).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, 'a');
    });

    test('distinct idempotency pairs are all recorded', () async {
      await db.recordProcessedPull(
        _entry(id: 'a', deviceId: 'D1', localOperationId: 'L1'),
      );
      await db.recordProcessedPull(
        _entry(id: 'b', deviceId: 'D1', localOperationId: 'L2'),
      );
      await db.recordProcessedPull(
        _entry(id: 'c', deviceId: 'D2', localOperationId: 'L1'),
      );
      expect(await db.select(db.processedPullLog).get(), hasLength(3));
    });
  });
}
