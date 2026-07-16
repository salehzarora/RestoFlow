import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';

/// PILOT-OPERATIONS-CORRECTIONS-001 — A4: the ONE canonical linked-table group
/// aggregation. Precedence: out_of_service > occupied > reserved > available; count is
/// the SUM across members (never double-counted).

({String effectiveState, int activeOrderCount}) _m(String state, int count) =>
    (effectiveState: state, activeOrderCount: count);

void main() {
  group('aggregateTableGroup', () {
    test('1. occupied member + available member -> group Occupied', () {
      final agg = aggregateTableGroup([_m('occupied', 1), _m('available', 0)]);
      expect(agg.effectiveState, 'occupied');
      expect(agg.isAvailable, isFalse);
    });

    test('2. active-order count is the SUM across members', () {
      final agg = aggregateTableGroup([_m('occupied', 1), _m('occupied', 2)]);
      expect(agg.activeOrderCount, 3);
    });

    test('3. reserved member + available member -> group Reserved', () {
      final agg = aggregateTableGroup([_m('reserved', 0), _m('available', 0)]);
      expect(agg.effectiveState, 'reserved');
    });

    test('4. an out-of-service member is never hidden (top precedence)', () {
      final agg = aggregateTableGroup([
        _m('out_of_service', 0),
        _m('reserved', 0),
        _m('available', 0),
      ]);
      expect(agg.effectiveState, 'out_of_service');
    });

    test(
      '5. manual occupied on one member prevents another being available',
      () {
        final agg = aggregateTableGroup([
          _m('occupied', 0),
          _m('available', 0),
        ]);
        expect(agg.effectiveState, 'occupied');
        expect(agg.isAvailable, isFalse);
      },
    );

    test('all-available -> group Available', () {
      final agg = aggregateTableGroup([_m('available', 0), _m('available', 0)]);
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
        // Unknown fails to the lowest rank (never masks a real hold).
        expect(
          tableEffectiveStateRank('???'),
          tableEffectiveStateRank('available'),
        );
      },
    );
  });
}
