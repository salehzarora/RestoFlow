import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:test/test.dart';

void main() {
  group('SyncOperationState — enumeration (DECISION D-018)', () {
    test('has exactly the eight approved values with their wire names', () {
      expect(SyncOperationState.values, hasLength(8));
      expect(SyncOperationState.values.map((s) => s.wireName).toSet(), {
        'created',
        'pending',
        'in_flight',
        'applied',
        'rejected',
        'dead',
        'conflict',
        'resolved',
      });
    });

    test('wire names round-trip via fromWire', () {
      for (final s in SyncOperationState.values) {
        expect(SyncOperationState.fromWire(s.wireName), s);
      }
      expect(SyncOperationState.inFlight.wireName, 'in_flight');
    });

    test('fromWire rejects an unknown value', () {
      expect(
        () => SyncOperationState.fromWire('nonsense'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('SyncOperationState — transition guard', () {
    test('legal transitions are permitted', () {
      const legal = <List<SyncOperationState>>[
        [SyncOperationState.created, SyncOperationState.pending],
        [SyncOperationState.pending, SyncOperationState.inFlight],
        [SyncOperationState.inFlight, SyncOperationState.applied],
        [SyncOperationState.inFlight, SyncOperationState.rejected],
        [SyncOperationState.inFlight, SyncOperationState.dead],
        [SyncOperationState.inFlight, SyncOperationState.conflict],
        [SyncOperationState.conflict, SyncOperationState.resolved],
        [SyncOperationState.resolved, SyncOperationState.applied],
        [SyncOperationState.resolved, SyncOperationState.rejected],
      ];
      for (final t in legal) {
        expect(
          SyncOperationState.canTransition(t.first, t.last),
          isTrue,
          reason: '${t.first.wireName} -> ${t.last.wireName} should be legal',
        );
        expect(t.first.canTransitionTo(t.last), isTrue);
      }
    });

    test('illegal transitions are rejected', () {
      const illegal = <List<SyncOperationState>>[
        // skipping the queue
        [SyncOperationState.created, SyncOperationState.inFlight],
        [SyncOperationState.created, SyncOperationState.applied],
        [SyncOperationState.pending, SyncOperationState.applied],
        // backwards
        [SyncOperationState.inFlight, SyncOperationState.pending],
        [SyncOperationState.conflict, SyncOperationState.inFlight],
        // conflict must go through resolved
        [SyncOperationState.conflict, SyncOperationState.applied],
        // resolved cannot become dead/conflict
        [SyncOperationState.resolved, SyncOperationState.dead],
        [SyncOperationState.resolved, SyncOperationState.conflict],
      ];
      for (final t in illegal) {
        expect(
          SyncOperationState.canTransition(t.first, t.last),
          isFalse,
          reason: '${t.first.wireName} -> ${t.last.wireName} should be illegal',
        );
      }
    });

    test('canTransition matches the full legal edge set for every ordered '
        'pair (exhaustive over all 8x8 transitions)', () {
      // Independent oracle: the legal edge set, re-declared here from the spec
      // (NOT imported from the source map) so that any mutation of the guard —
      // an added illegal edge OR a dropped legal one — diverges and fails.
      const expectedLegal = <SyncOperationState, Set<SyncOperationState>>{
        SyncOperationState.created: {SyncOperationState.pending},
        SyncOperationState.pending: {SyncOperationState.inFlight},
        SyncOperationState.inFlight: {
          SyncOperationState.applied,
          SyncOperationState.rejected,
          SyncOperationState.dead,
          SyncOperationState.conflict,
        },
        SyncOperationState.conflict: {SyncOperationState.resolved},
        SyncOperationState.resolved: {
          SyncOperationState.applied,
          SyncOperationState.rejected,
        },
        SyncOperationState.applied: <SyncOperationState>{},
        SyncOperationState.rejected: <SyncOperationState>{},
        SyncOperationState.dead: <SyncOperationState>{},
      };

      for (final from in SyncOperationState.values) {
        for (final to in SyncOperationState.values) {
          final shouldBeLegal = expectedLegal[from]!.contains(to);
          expect(
            SyncOperationState.canTransition(from, to),
            shouldBeLegal,
            reason:
                '${from.wireName} -> ${to.wireName} should be '
                '${shouldBeLegal ? 'legal' : 'illegal'}',
          );
        }
      }
    });

    test('terminal states cannot transition onward', () {
      expect(SyncOperationState.terminals, {
        SyncOperationState.applied,
        SyncOperationState.rejected,
        SyncOperationState.dead,
      });
      for (final terminal in SyncOperationState.terminals) {
        expect(terminal.isTerminal, isTrue);
        for (final to in SyncOperationState.values) {
          expect(
            SyncOperationState.canTransition(terminal, to),
            isFalse,
            reason: '${terminal.wireName} is terminal: no onward transition',
          );
        }
      }
    });

    test('non-terminal states are not flagged terminal', () {
      for (final s in SyncOperationState.values) {
        if (!SyncOperationState.terminals.contains(s)) {
          expect(s.isTerminal, isFalse);
        }
      }
    });
  });
}
