import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';

/// PILOT-OPERATIONS-CORRECTIONS-001 — A4: the ONE canonical linked-table group
/// aggregation. Precedence: out_of_service > occupied > reserved > available; count is
/// the SUM across DISTINCT physical tables (Finding 4: deduplicated by table id).

TableGroupMember _m(String tableId, String state, int count) =>
    (tableId: tableId, effectiveState: state, activeOrderCount: count);

void main() {
  group('aggregateTableGroup', () {
    test('1. occupied member + available member -> group Occupied', () {
      final agg = aggregateTableGroup([
        _m('t1', 'occupied', 1),
        _m('t2', 'available', 0),
      ]);
      expect(agg.effectiveState, 'occupied');
      expect(agg.isAvailable, isFalse);
    });

    test('2. active-order count is the SUM across DISTINCT members', () {
      final agg = aggregateTableGroup([
        _m('t1', 'occupied', 1),
        _m('t2', 'occupied', 2),
      ]);
      expect(agg.activeOrderCount, 3);
    });

    test('3. reserved member + available member -> group Reserved', () {
      final agg = aggregateTableGroup([
        _m('t1', 'reserved', 0),
        _m('t2', 'available', 0),
      ]);
      expect(agg.effectiveState, 'reserved');
    });

    test('4. an out-of-service member is never hidden (top precedence)', () {
      final agg = aggregateTableGroup([
        _m('t1', 'out_of_service', 0),
        _m('t2', 'reserved', 0),
        _m('t3', 'available', 0),
      ]);
      expect(agg.effectiveState, 'out_of_service');
    });

    test(
      '5. manual occupied on one member prevents another being available',
      () {
        final agg = aggregateTableGroup([
          _m('t1', 'occupied', 0),
          _m('t2', 'available', 0),
        ]);
        expect(agg.effectiveState, 'occupied');
        expect(agg.isAvailable, isFalse);
      },
    );

    test('all-available -> group Available', () {
      final agg = aggregateTableGroup([
        _m('t1', 'available', 0),
        _m('t2', 'available', 0),
      ]);
      expect(agg.effectiveState, 'available');
      expect(agg.isAvailable, isTrue);
      expect(agg.activeOrderCount, 0);
    });

    test(
      'precedence ranks are ordered out_of_service>occupied>reserved>avail',
      () {
        expect(
          tableEffectiveStateRank('out_of_service') >
              tableEffectiveStateRank('occupied'),
          isTrue,
        );
        expect(
          tableEffectiveStateRank('occupied') >
              tableEffectiveStateRank('reserved'),
          isTrue,
        );
        expect(
          tableEffectiveStateRank('reserved') >
              tableEffectiveStateRank('available'),
          isTrue,
        );
      },
    );
  });

  group('Finding 6: unknown state is deterministic + fail-closed', () {
    test('unknown ranks MORE restrictive than available (not equal)', () {
      expect(
        tableEffectiveStateRank('???') > tableEffectiveStateRank('available'),
        isTrue,
      );
      // ...but LESS than a known hold (a known state is more informative).
      expect(
        tableEffectiveStateRank('reserved') > tableEffectiveStateRank('???'),
        isTrue,
      );
    });

    test('normalize maps any unrecognized value to unknown', () {
      expect(normalizeTableEffectiveState('foo'), 'unknown');
      expect(normalizeTableEffectiveState(''), 'unknown');
      expect(normalizeTableEffectiveState('available'), 'available');
      expect(normalizeTableEffectiveState('occupied'), 'occupied');
    });

    test(
      'available + unknown resolves to unknown REGARDLESS of input order',
      () {
        final a = aggregateTableGroup([
          _m('t1', 'available', 0),
          _m('t2', '???', 0),
        ]);
        final b = aggregateTableGroup([
          _m('t2', '???', 0),
          _m('t1', 'available', 0),
        ]);
        expect(a.effectiveState, 'unknown');
        expect(b.effectiveState, 'unknown');
        expect(a.isAvailable, isFalse);
        expect(b.isAvailable, isFalse); // never selectable
      },
    );

    test('unknown never wins over a known hold, either order', () {
      for (final known in ['occupied', 'reserved', 'out_of_service']) {
        final a = aggregateTableGroup([_m('t1', known, 0), _m('t2', '???', 0)]);
        final b = aggregateTableGroup([_m('t2', '???', 0), _m('t1', known, 0)]);
        expect(a.effectiveState, known);
        expect(b.effectiveState, known);
      }
    });

    test('a duplicate-unknown table row never becomes available', () {
      final agg = aggregateTableGroup([
        _m('t1', '???', 0),
        _m('t1', 'available', 0), // same table, conflicting
      ]);
      expect(agg.effectiveState, 'unknown'); // restrictive, order-independent
    });

    test('mostRestrictiveTableState is commutative + normalized', () {
      expect(mostRestrictiveTableState('available', '???'), 'unknown');
      expect(mostRestrictiveTableState('???', 'available'), 'unknown');
      expect(mostRestrictiveTableState('reserved', '???'), 'reserved');
      expect(mostRestrictiveTableState('???', 'reserved'), 'reserved');
    });
  });

  group('Finding 4: deduplicate physical table rows', () {
    test('1. the same table id twice (count 1 each) counts ONCE', () {
      final agg = aggregateTableGroup([
        _m('t1', 'occupied', 1),
        _m('t1', 'occupied', 1), // duplicate row for the SAME physical table
      ]);
      expect(agg.activeOrderCount, 1); // not 2
      expect(agg.effectiveState, 'occupied');
    });

    test(
      '2. duplicate rows use the MAX count for that table (not the sum)',
      () {
        final agg = aggregateTableGroup([
          _m('t1', 'occupied', 1),
          _m('t1', 'occupied', 2), // same table, conflicting count
        ]);
        expect(agg.activeOrderCount, 2); // max(1,2), never 3
      },
    );

    test('3. conflicting duplicate states resolve to the RESTRICTIVE one', () {
      final agg = aggregateTableGroup([
        _m('t1', 'available', 0),
        _m('t1', 'occupied', 1), // same table, conflicting state
      ]);
      expect(agg.effectiveState, 'occupied'); // restrictive wins
      expect(agg.activeOrderCount, 1);
    });

    test('4. distinct table ids still SUM normally', () {
      final agg = aggregateTableGroup([
        _m('t1', 'occupied', 1),
        _m('t2', 'occupied', 2),
        _m('t1', 'occupied', 1), // t1 duplicate collapses; t2 stays distinct
      ]);
      expect(agg.activeOrderCount, 3); // t1(max 1) + t2(2)
    });

    test('5. a duplicate available row cannot inflate an occupied group', () {
      final agg = aggregateTableGroup([
        _m('t1', 'occupied', 1),
        _m('t2', 'available', 0),
        _m('t2', 'available', 0), // duplicate free peer
      ]);
      expect(agg.effectiveState, 'occupied');
      expect(agg.activeOrderCount, 1); // never doubled
    });
  });
}
