import 'package:drift/drift.dart' show DriftSqlType, TableInfo;
import 'package:drift/native.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:test/test.dart';

/// Money is integer minor units only — never floating point, anywhere
/// (DECISION D-007). RF-030 menu tables introduce money columns, so this guard
/// evolved from "no money columns exist" to: no float column anywhere, every
/// money-AMOUNT column is an INTEGER suffixed `_minor`, and the currency
/// reference is a 3-char text code on `menu_items`.
///
/// `currency` is intentionally excluded here — it is an ISO 4217 CODE, not an
/// amount — and is checked separately as text.
const _amountTerms = <String>[
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

    test('every money-amount column is an INTEGER suffixed _minor (D-007)', () {
      for (final table in allTables()) {
        for (final col in table.$columns) {
          final name = col.name.toLowerCase();
          if (_amountTerms.any(name.contains)) {
            expect(
              col.type,
              DriftSqlType.int,
              reason:
                  '${table.actualTableName}.${col.name} is a money amount -> '
                  'must be an integer (D-007), not ${col.type}',
            );
            expect(
              name.endsWith('_minor'),
              isTrue,
              reason:
                  '${table.actualTableName}.${col.name} is a money amount -> '
                  'must be suffixed _minor (D-007 / D-017)',
            );
          }
        }
      }
    });

    test(
      'currency reference lives on menu_items as a 3-char text code (D-007)',
      () {
        final byName = {for (final c in db.menuItems.$columns) c.name: c};
        expect(byName.containsKey('currency_code'), isTrue);
        expect(byName['currency_code']!.type, DriftSqlType.string);
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
