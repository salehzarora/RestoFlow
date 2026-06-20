import 'package:drift/drift.dart' show DriftSqlType, TableInfo;
import 'package:drift/native.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:test/test.dart';

/// Money is integer minor units only — never floating point, anywhere
/// (DECISION D-007). RF-018 adds NO money columns at all; this test proves the
/// shipped local schema declares no float column and no money-named column.
const _moneyTerms = <String>[
  'price',
  'amount',
  'subtotal',
  'total',
  'money',
  'minor',
  'cost',
  'balance',
  'tendered',
  'discount',
  'payment',
  'cash',
  'gross',
  'refund',
  'currency',
];

void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Iterable<TableInfo> allTables() => db.allTables;

  group('No floating-point money in the local schema (DECISION D-007)', () {
    test('no column uses a floating-point (REAL/double) SQL type', () {
      for (final table in allTables()) {
        for (final col in table.$columns) {
          expect(
            col.type,
            isNot(DriftSqlType.double),
            reason:
                '${table.actualTableName}.${col.name} must not be a float '
                '(REAL/double); money is integer minor units (D-007)',
          );
        }
      }
    });

    test(
      'no money-named column exists at all (RF-018 adds no money fields)',
      () {
        for (final table in allTables()) {
          for (final col in table.$columns) {
            final name = col.name.toLowerCase();
            for (final term in _moneyTerms) {
              expect(
                name.contains(term),
                isFalse,
                reason:
                    '${table.actualTableName}.${col.name} looks money-named '
                    '("$term"); RF-018 must add no money fields (money lives in '
                    'packages/money, RF-036, and only as integer *_minor)',
              );
            }
          }
        }
      },
    );

    test('outbox columns are present with the expected snake_case names', () {
      final names = db.outboxOperations.$columns.map((c) => c.name).toSet();
      expect(
        names,
        containsAll(<String>[
          'id',
          'device_id',
          'local_operation_id',
          'organization_id',
          'restaurant_id',
          'branch_id',
          'station_id',
          'operation_type',
          'target_entity',
          'target_id',
          'payload',
          'depends_on',
          'base_revision',
          'sync_state',
          'client_created_at',
          'client_updated_at',
          'attempt_count',
          'next_attempt_at',
          'last_error_code',
          'last_error_class',
        ]),
      );
    });
  });
}
