import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// Independent re-statement of the legal SHIFT edges (NOT derived from the SUT).
const Set<(ShiftStatus, ShiftStatus)> _legalShiftEdges = {
  (ShiftStatus.opening, ShiftStatus.open),
  (ShiftStatus.open, ShiftStatus.closing),
  (ShiftStatus.closing, ShiftStatus.closed),
  (ShiftStatus.closing, ShiftStatus.open), // reopen
  (ShiftStatus.closed, ShiftStatus.reconciled),
};

Shift _shift() => Shift(
  shiftId: 's1',
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
);

void main() {
  group('exhaustive shift transition matrix (RF-037, D-018)', () {
    for (final from in ShiftStatus.values) {
      for (final to in ShiftStatus.values) {
        final expected = _legalShiftEdges.contains((from, to));
        test(
          '${from.name} -> ${to.name} ${expected ? "allowed" : "rejected"}',
          () {
            expect(ShiftStateMachine.isLegal(from, to), expected);
            if (expected) {
              expect(ShiftStateMachine.transition(from, to), to);
            } else {
              expect(
                () => ShiftStateMachine.transition(from, to),
                throwsA(isA<IllegalShiftTransitionException>()),
              );
            }
          },
        );
      }
    }
  });

  group('shift terminal + named illegal (RF-037)', () {
    test('reconciled is terminal and rejects every transition', () {
      expect(ShiftStatus.reconciled.isTerminal, isTrue);
      for (final to in ShiftStatus.values) {
        expect(ShiftStateMachine.isLegal(ShiftStatus.reconciled, to), isFalse);
      }
    });

    test('open -> closed (skipping closing) is rejected', () {
      expect(
        () =>
            ShiftStateMachine.transition(ShiftStatus.open, ShiftStatus.closed),
        throwsA(isA<IllegalShiftTransitionException>()),
      );
    });

    test('opening -> closing (skipping open) is rejected', () {
      expect(
        () => ShiftStateMachine.transition(
          ShiftStatus.opening,
          ShiftStatus.closing,
        ),
        throwsA(isA<IllegalShiftTransitionException>()),
      );
    });

    test('closed -> open is rejected', () {
      expect(
        () =>
            ShiftStateMachine.transition(ShiftStatus.closed, ShiftStatus.open),
        throwsA(isA<IllegalShiftTransitionException>()),
      );
    });
  });

  group('Shift aggregate (RF-037)', () {
    test('happy path opening -> open -> closing -> closed -> reconciled', () {
      final shift = _shift();
      expect(shift.status, ShiftStatus.opening);
      shift.open();
      expect(shift.status, ShiftStatus.open);
      shift.startClosing();
      expect(shift.status, ShiftStatus.closing);
      shift.closeAndCount(expectedTotalMinor: 1000, countedTotalMinor: 1000);
      expect(shift.status, ShiftStatus.closed);
      shift.reconcile();
      expect(shift.status, ShiftStatus.reconciled);
      expect(shift.isTerminal, isTrue);
      expect(shift.open, throwsA(isA<IllegalShiftTransitionException>()));
    });

    test('reopen(reason) is legal from closing', () {
      final shift = _shift()
        ..open()
        ..startClosing();
      shift.reopen('manager correction');
      expect(shift.status, ShiftStatus.open);
    });

    test('reopen requires a non-empty reason', () {
      final shift = _shift()
        ..open()
        ..startClosing();
      expect(
        () => shift.reopen('  '),
        throwsA(isA<MissingShiftReasonException>()),
      );
    });

    test('closeAndCount is only legal from closing', () {
      final shift = _shift()..open(); // status open, not closing
      expect(
        () => shift.closeAndCount(expectedTotalMinor: 0, countedTotalMinor: 0),
        throwsA(isA<IllegalShiftTransitionException>()),
      );
    });
  });
}
