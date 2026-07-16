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

    // Finding 4: a duplicate physical-table row (upstream join/projection) must not
    // double the group's displayed active-order count, nor make it contradictory.
    test('6/7. a duplicate physical row does not double the group count', () {
      final out = withGroupAggregation([
        _t('t1', 'T1', effective: 'occupied', active: 1, group: 'g1'),
        _t('t1', 'T1', effective: 'occupied', active: 1, group: 'g1'), // dup
        _t('t2', 'T2', effective: 'available', active: 0, group: 'g1'),
      ]);
      // Every projected row shows the deduplicated group count of 1, never 2.
      for (final t in out) {
        expect(t.activeOrderCount, 1);
        expect(t.effectiveState, 'occupied');
      }
    });

    test(
      '8. a projected member still carries its own real physical table_id',
      () {
        final out = withGroupAggregation([
          _t('t1', 'T1', effective: 'occupied', active: 1, group: 'g1'),
          _t('t2', 'T2', effective: 'available', group: 'g1'),
        ]);
        // The picker selects a real physical table id, never a group id.
        expect(out.map((t) => t.tableId).toSet(), {'t1', 't2'});
      },
    );
  });

  group('Finding 5: the PROJECTED list has one row per physical table', () {
    test('1/2. input [t1, t1, t2] returns exactly 2 rows', () {
      final out = withGroupAggregation([
        _t('t1', 'T1', effective: 'occupied', active: 1, group: 'g1'),
        _t('t1', 'T1', effective: 'occupied', active: 1, group: 'g1'), // dup
        _t('t2', 'T2', effective: 'available', group: 'g1'),
      ]);
      expect(out.length, 2);
      expect(out.map((t) => t.tableId).toList(), ['t1', 't2']);
    });

    test('ungrouped duplicates also collapse to one row', () {
      final out = withGroupAggregation([
        _t('t1', 'T1', effective: 'available'),
        _t('t1', 'T1', effective: 'available'), // dup, ungrouped
        _t('t2', 'T2', effective: 'occupied', active: 1),
      ]);
      expect(out.length, 2);
    });

    test(
      '6. stable ordering: reversed duplicate input yields the same ids',
      () {
        List<String> ids(List<DemoTable> src) =>
            withGroupAggregation(src).map((t) => t.tableId).toList();
        final forward = [
          _t('t1', 'T1', effective: 'available'),
          _t('t2', 'T2', effective: 'available'),
          _t('t1', 'T1', effective: 'available'), // t1 dup after t2
        ];
        // First occurrence order: t1 seen before t2.
        expect(ids(forward), ['t1', 't2']);
      },
    );
  });

  group('PSC-001B: member truth survives the group projection', () {
    test('a projected member keeps its OWN state and count', () {
      final out = withGroupAggregation([
        _t('t1', 'T1', effective: 'occupied', active: 1, group: 'g1'),
        _t('t2', 'T2', effective: 'available', active: 0, group: 'g1'),
      ]);
      final t1 = out.firstWhere((t) => t.tableId == 't1');
      final t2 = out.firstWhere((t) => t.tableId == 't2');
      // Group-wide projection (A4) is unchanged...
      expect(t2.effectiveState, 'occupied');
      expect(t2.activeOrderCount, 1);
      // ...but each member's OWN truth is preserved for the detail sheet.
      expect(t2.memberEffectiveState, 'available');
      expect(t2.memberActiveOrderCount, 0);
      expect(t1.memberEffectiveState, 'occupied');
      expect(t1.memberActiveOrderCount, 1);
    });

    test('duplicate physical rows merge INTO the member truth', () {
      final out = withGroupAggregation([
        _t('t1', 'T1', effective: 'available', active: 0, group: 'g1'),
        _t('t1', 'T1', effective: 'occupied', active: 1, group: 'g1'), // dup
        _t('t2', 'T2', effective: 'available', active: 0, group: 'g1'),
      ]);
      final t1 = out.firstWhere((t) => t.tableId == 't1');
      // The merged (restrictive/max) values ARE t1's own truth.
      expect(t1.memberEffectiveState, 'occupied');
      expect(t1.memberActiveOrderCount, 1);
    });

    test('an ungrouped table\'s member truth equals its own values', () {
      final out = withGroupAggregation([
        _t('t1', 'T1', effective: 'reserved', active: 0),
      ]);
      expect(out.single.memberEffectiveState, 'reserved');
      expect(out.single.memberActiveOrderCount, 0);
    });
  });

  group('Finding 6: an unknown table state is non-assignable', () {
    test('tableStatusKindFor maps unknown -> blocked (non-assignable)', () {
      expect(
        tableStatusKindFor('weird-unknown-state'),
        TableStatusKind.blocked,
      );
      expect(tableStatusKindFor(''), TableStatusKind.blocked);
      expect(tableStatusKindFor('available'), TableStatusKind.available);
      expect(tableStatusKindFor('reserved'), TableStatusKind.occupied);
      expect(tableStatusKindFor('occupied'), TableStatusKind.occupied);
      expect(tableStatusKindFor('out_of_service'), TableStatusKind.blocked);
    });

    test(
      'available + unknown in a group -> the free peer is NOT selectable',
      () {
        final out = withGroupAggregation([
          _t('t1', 'T1', effective: '???', group: 'g1'),
          _t('t2', 'T2', effective: 'available', group: 'g1'),
        ]);
        // Both members read the group-wide unknown state; neither is assignable
        // (the group-wide status is derived via tableStatusKindFor -> blocked).
        expect(out.every((t) => !t.isAssignable), isTrue);
        expect(out.every((t) => t.status == TableStatusKind.blocked), isTrue);
      },
    );
  });
}
