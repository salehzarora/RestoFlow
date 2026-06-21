import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// Independent re-statement of the legal CASH-DRAWER edges (NOT from the SUT).
const Set<(CashDrawerSessionStatus, CashDrawerSessionStatus)>
_legalDrawerEdges = {
  (CashDrawerSessionStatus.opened, CashDrawerSessionStatus.active),
  (CashDrawerSessionStatus.active, CashDrawerSessionStatus.counting),
  (CashDrawerSessionStatus.counting, CashDrawerSessionStatus.closed),
  (CashDrawerSessionStatus.counting, CashDrawerSessionStatus.active), // recount
  (CashDrawerSessionStatus.closed, CashDrawerSessionStatus.reconciled),
};

CashDrawerSession _drawer() => CashDrawerSession(
  cashDrawerSessionId: 'd1',
  shiftId: 's1',
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  openingFloatMinor: 10000,
);

void main() {
  group('exhaustive cash-drawer transition matrix (RF-037, D-018)', () {
    for (final from in CashDrawerSessionStatus.values) {
      for (final to in CashDrawerSessionStatus.values) {
        final expected = _legalDrawerEdges.contains((from, to));
        test(
          '${from.name} -> ${to.name} ${expected ? "allowed" : "rejected"}',
          () {
            expect(CashDrawerSessionStateMachine.isLegal(from, to), expected);
            if (expected) {
              expect(CashDrawerSessionStateMachine.transition(from, to), to);
            } else {
              expect(
                () => CashDrawerSessionStateMachine.transition(from, to),
                throwsA(isA<IllegalCashDrawerSessionTransitionException>()),
              );
            }
          },
        );
      }
    }
  });

  group('drawer terminal + named illegal (RF-037)', () {
    test('reconciled is terminal and rejects every transition', () {
      expect(CashDrawerSessionStatus.reconciled.isTerminal, isTrue);
      for (final to in CashDrawerSessionStatus.values) {
        expect(
          CashDrawerSessionStateMachine.isLegal(
            CashDrawerSessionStatus.reconciled,
            to,
          ),
          isFalse,
        );
      }
    });

    test('opened -> counting (skipping active) is rejected', () {
      expect(
        () => CashDrawerSessionStateMachine.transition(
          CashDrawerSessionStatus.opened,
          CashDrawerSessionStatus.counting,
        ),
        throwsA(isA<IllegalCashDrawerSessionTransitionException>()),
      );
    });

    test('opened -> closed is rejected', () {
      expect(
        () => CashDrawerSessionStateMachine.transition(
          CashDrawerSessionStatus.opened,
          CashDrawerSessionStatus.closed,
        ),
        throwsA(isA<IllegalCashDrawerSessionTransitionException>()),
      );
    });

    test('active -> reconciled is rejected', () {
      expect(
        () => CashDrawerSessionStateMachine.transition(
          CashDrawerSessionStatus.active,
          CashDrawerSessionStatus.reconciled,
        ),
        throwsA(isA<IllegalCashDrawerSessionTransitionException>()),
      );
    });

    test('closed -> active is rejected', () {
      expect(
        () => CashDrawerSessionStateMachine.transition(
          CashDrawerSessionStatus.closed,
          CashDrawerSessionStatus.active,
        ),
        throwsA(isA<IllegalCashDrawerSessionTransitionException>()),
      );
    });
  });

  group('CashDrawerSession aggregate (RF-037)', () {
    test('happy path opened -> active -> counting -> closed -> reconciled', () {
      final drawer = _drawer();
      expect(drawer.status, CashDrawerSessionStatus.opened);
      drawer.activate();
      expect(drawer.status, CashDrawerSessionStatus.active);
      drawer.startCounting();
      expect(drawer.status, CashDrawerSessionStatus.counting);
      drawer.recordCount(expectedCashMinor: 10000, countedAmountMinor: 10000);
      expect(drawer.status, CashDrawerSessionStatus.closed);
      drawer.reconcile();
      expect(drawer.status, CashDrawerSessionStatus.reconciled);
      expect(drawer.isTerminal, isTrue);
      expect(
        drawer.activate,
        throwsA(isA<IllegalCashDrawerSessionTransitionException>()),
      );
    });

    test('recount(reason) is legal from counting', () {
      final drawer = _drawer()
        ..activate()
        ..startCounting();
      drawer.recount('miscount');
      expect(drawer.status, CashDrawerSessionStatus.active);
    });

    test('recount requires a non-empty reason', () {
      final drawer = _drawer()
        ..activate()
        ..startCounting();
      expect(
        () => drawer.recount(''),
        throwsA(isA<MissingShiftReasonException>()),
      );
    });

    test('recordCount is only legal from counting', () {
      final drawer = _drawer()..activate(); // status active, not counting
      expect(
        () => drawer.recordCount(expectedCashMinor: 0, countedAmountMinor: 0),
        throwsA(isA<IllegalCashDrawerSessionTransitionException>()),
      );
    });
  });
}
