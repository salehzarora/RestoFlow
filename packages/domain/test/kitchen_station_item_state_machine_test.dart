import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// Independent re-statement of the legal kitchen-station-item edges.
const Set<(KitchenStationItemStatus, KitchenStationItemStatus)>
_legalStationEdges = {
  (KitchenStationItemStatus.queued, KitchenStationItemStatus.inPreparation),
  (KitchenStationItemStatus.inPreparation, KitchenStationItemStatus.ready),
  (KitchenStationItemStatus.ready, KitchenStationItemStatus.bumped),
  (KitchenStationItemStatus.queued, KitchenStationItemStatus.voided),
  (KitchenStationItemStatus.inPreparation, KitchenStationItemStatus.voided),
  (KitchenStationItemStatus.ready, KitchenStationItemStatus.voided),
};

void main() {
  group(
    'exhaustive kitchen-station-item transition matrix (RF-034, D-018)',
    () {
      for (final from in KitchenStationItemStatus.values) {
        for (final to in KitchenStationItemStatus.values) {
          final expected = _legalStationEdges.contains((from, to));
          test('${from.canonicalName} -> ${to.canonicalName} '
              '${expected ? "allowed" : "rejected"}', () {
            expect(KitchenStationItemStateMachine.isLegal(from, to), expected);
            if (expected) {
              expect(KitchenStationItemStateMachine.transition(from, to), to);
            } else {
              expect(
                () => KitchenStationItemStateMachine.transition(from, to),
                throwsA(isA<IllegalKitchenStationItemTransitionException>()),
              );
            }
          });
        }
      }
    },
  );

  group('kitchen-station-item named cases (RF-034)', () {
    test('queued -> ready throws (skips in_preparation)', () {
      expect(
        () => KitchenStationItemStateMachine.transition(
          KitchenStationItemStatus.queued,
          KitchenStationItemStatus.ready,
        ),
        throwsA(isA<IllegalKitchenStationItemTransitionException>()),
      );
    });

    test('ready -> bumped passes', () {
      expect(
        KitchenStationItemStateMachine.transition(
          KitchenStationItemStatus.ready,
          KitchenStationItemStatus.bumped,
        ),
        KitchenStationItemStatus.bumped,
      );
    });

    test('bumped is terminal and rejects every transition', () {
      expect(KitchenStationItemStatus.bumped.isTerminal, isTrue);
      for (final to in KitchenStationItemStatus.values) {
        expect(
          KitchenStationItemStateMachine.isLegal(
            KitchenStationItemStatus.bumped,
            to,
          ),
          isFalse,
        );
      }
    });

    test('voided is terminal and rejects every transition', () {
      expect(KitchenStationItemStatus.voided.isTerminal, isTrue);
      for (final to in KitchenStationItemStatus.values) {
        expect(
          KitchenStationItemStateMachine.isLegal(
            KitchenStationItemStatus.voided,
            to,
          ),
          isFalse,
        );
      }
    });
  });
}
