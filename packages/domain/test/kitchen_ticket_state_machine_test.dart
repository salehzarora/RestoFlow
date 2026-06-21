import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// Independent re-statement of the legal NORMAL kitchen-ticket edges (NOT
/// derived from the SUT). Excludes the recall edge `bumped -> in_preparation`,
/// which is reachable only via `KitchenTicketStateMachine.recall`.
const Set<(KitchenTicketStatus, KitchenTicketStatus)> _legalTicketEdges = {
  (KitchenTicketStatus.newTicket, KitchenTicketStatus.acknowledged),
  (KitchenTicketStatus.acknowledged, KitchenTicketStatus.inPreparation),
  (KitchenTicketStatus.inPreparation, KitchenTicketStatus.ready),
  (KitchenTicketStatus.ready, KitchenTicketStatus.bumped),
  (KitchenTicketStatus.newTicket, KitchenTicketStatus.cancelled),
  (KitchenTicketStatus.acknowledged, KitchenTicketStatus.cancelled),
  (KitchenTicketStatus.inPreparation, KitchenTicketStatus.cancelled),
  (KitchenTicketStatus.ready, KitchenTicketStatus.cancelled),
};

void main() {
  group('exhaustive kitchen-ticket transition matrix (RF-034, D-018)', () {
    for (final from in KitchenTicketStatus.values) {
      for (final to in KitchenTicketStatus.values) {
        final expected = _legalTicketEdges.contains((from, to));
        test('${from.canonicalName} -> ${to.canonicalName} '
            '${expected ? "allowed" : "rejected"}', () {
          expect(KitchenTicketStateMachine.isLegal(from, to), expected);
          if (expected) {
            expect(KitchenTicketStateMachine.transition(from, to), to);
          } else {
            expect(
              () => KitchenTicketStateMachine.transition(from, to),
              throwsA(isA<IllegalKitchenTicketTransitionException>()),
            );
          }
        });
      }
    }
  });

  group('kitchen-ticket named cases (RF-034)', () {
    test('newTicket maps to canonical "new"', () {
      expect(KitchenTicketStatus.newTicket.canonicalName, 'new');
    });

    test('newTicket -> inPreparation throws (skips acknowledged)', () {
      expect(
        () => KitchenTicketStateMachine.transition(
          KitchenTicketStatus.newTicket,
          KitchenTicketStatus.inPreparation,
        ),
        throwsA(isA<IllegalKitchenTicketTransitionException>()),
      );
    });

    test('ready -> bumped passes', () {
      expect(
        KitchenTicketStateMachine.transition(
          KitchenTicketStatus.ready,
          KitchenTicketStatus.bumped,
        ),
        KitchenTicketStatus.bumped,
      );
    });

    test('normal bumped -> inPreparation is rejected (recall-only)', () {
      expect(
        KitchenTicketStateMachine.isLegal(
          KitchenTicketStatus.bumped,
          KitchenTicketStatus.inPreparation,
        ),
        isFalse,
      );
      expect(
        () => KitchenTicketStateMachine.transition(
          KitchenTicketStatus.bumped,
          KitchenTicketStatus.inPreparation,
        ),
        throwsA(isA<IllegalKitchenTicketTransitionException>()),
      );
    });

    test('cancelled is terminal and rejects every transition', () {
      expect(KitchenTicketStatus.cancelled.isTerminal, isTrue);
      for (final to in KitchenTicketStatus.values) {
        expect(
          KitchenTicketStateMachine.isLegal(KitchenTicketStatus.cancelled, to),
          isFalse,
        );
      }
    });

    test('bumped is terminal and rejects every NORMAL transition', () {
      expect(KitchenTicketStatus.bumped.isTerminal, isTrue);
      for (final to in KitchenTicketStatus.values) {
        expect(
          KitchenTicketStateMachine.isLegal(KitchenTicketStatus.bumped, to),
          isFalse,
        );
      }
    });
  });
}
