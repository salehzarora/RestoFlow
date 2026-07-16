import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show DiningTable;
import 'package:restoflow_pos/src/data/demo_tables.dart';

/// PILOT-OPERATIONS-CORRECTIONS-001 — A4 (POS): withGroupAggregation projects the
/// group-wide effective state + count onto every grouped member, so a free-looking peer
/// of an occupied group is never selectable, while a selected member still carries its
/// own real physical table_id.

DemoTable _t(
  String id,
  String label, {
  String manual = 'available',
  String effective = 'available',
  int active = 0,
  String? group,
}) => DemoTable(
  table: DiningTable(
    tableId: id,
    label: label,
    organizationId: 'o',
    restaurantId: 'r',
    branchId: 'b',
  ),
  status: effective == 'available'
      ? TableStatusKind.available
      : (effective == 'out_of_service'
            ? TableStatusKind.blocked
            : TableStatusKind.occupied),
  manualStatus: manual,
  effectiveState: effective,
  activeOrderCount: active,
  groupId: group,
);

void main() {
  group('withGroupAggregation (POS)', () {
    test('1/8. an occupied group makes its available peer non-selectable', () {
      final out = withGroupAggregation([
        _t('t1', 'T1', effective: 'occupied', active: 1, group: 'g1'),
        _t('t2', 'T2', effective: 'available', active: 0, group: 'g1'),
      ]);
      final t2 = out.firstWhere((t) => t.tableId == 't2');
      // The free peer now shows the group-wide Occupied state...
      expect(t2.effectiveState, 'occupied');
      // ...and is NOT assignable (the picker can no longer select it).
      expect(t2.isAssignable, isFalse);
      expect(t2.status, TableStatusKind.occupied);
    });

    test('2. every member shows the group-wide SUM count', () {
      final out = withGroupAggregation([
        _t('t1', 'T1', effective: 'occupied', active: 1, group: 'g1'),
        _t('t2', 'T2', effective: 'occupied', active: 2, group: 'g1'),
      ]);
      for (final t in out) {
        expect(t.activeOrderCount, 3);
      }
    });

    test('3. reserved + available -> both reserved', () {
      final out = withGroupAggregation([
        _t('t1', 'T1', manual: 'reserved', effective: 'reserved', group: 'g1'),
        _t('t2', 'T2', effective: 'available', group: 'g1'),
      ]);
      expect(out.every((t) => t.effectiveState == 'reserved'), isTrue);
    });

    test('4. out-of-service member propagates to the whole group', () {
      final out = withGroupAggregation([
        _t('t1', 'T1', effective: 'out_of_service', group: 'g1'),
        _t('t2', 'T2', effective: 'available', group: 'g1'),
      ]);
      expect(out.every((t) => t.effectiveState == 'out_of_service'), isTrue);
      expect(out.every((t) => t.status == TableStatusKind.blocked), isTrue);
    });

    test(
      '9. group members keep their OWN real table_id (never a group id)',
      () {
        final out = withGroupAggregation([
          _t('t1', 'T1', effective: 'occupied', active: 1, group: 'g1'),
          _t('t2', 'T2', effective: 'available', group: 'g1'),
        ]);
        expect(out.map((t) => t.tableId), containsAll(<String>['t1', 't2']));
      },
    );

    test('ungrouped tables are unchanged', () {
      final out = withGroupAggregation([
        _t('t1', 'T1', effective: 'occupied', active: 1),
        _t('t2', 'T2', effective: 'available'),
      ]);
      expect(
        out.firstWhere((t) => t.tableId == 't2').effectiveState,
        'available',
      );
      expect(out.firstWhere((t) => t.tableId == 't2').isAssignable, isTrue);
    });
  });
}
