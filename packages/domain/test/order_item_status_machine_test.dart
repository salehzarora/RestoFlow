import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// Independent re-statement of the legal ORDER-ITEM edges (NOT derived from the
/// SUT) for the exhaustive matrix.
const Set<(OrderItemStatus, OrderItemStatus)> _legalItemEdges = {
  (OrderItemStatus.pending, OrderItemStatus.queued),
  (OrderItemStatus.queued, OrderItemStatus.preparing),
  (OrderItemStatus.preparing, OrderItemStatus.ready),
  (OrderItemStatus.ready, OrderItemStatus.served),
  (OrderItemStatus.pending, OrderItemStatus.cancelled),
  (OrderItemStatus.queued, OrderItemStatus.cancelled),
  (OrderItemStatus.pending, OrderItemStatus.voided),
  (OrderItemStatus.queued, OrderItemStatus.voided),
  (OrderItemStatus.preparing, OrderItemStatus.voided),
  (OrderItemStatus.ready, OrderItemStatus.voided),
  (OrderItemStatus.served, OrderItemStatus.voided),
};

void main() {
  group('exhaustive order-item transition matrix (RF-032, D-018)', () {
    for (final from in OrderItemStatus.values) {
      for (final to in OrderItemStatus.values) {
        final expected = _legalItemEdges.contains((from, to));
        test(
          '${from.name} -> ${to.name} ${expected ? "allowed" : "rejected"}',
          () {
            expect(OrderItemStateMachine.isLegal(from, to), expected);
            if (expected) {
              expect(OrderItemStateMachine.transition(from, to), to);
            } else {
              expect(
                () => OrderItemStateMachine.transition(from, to),
                throwsA(isA<IllegalOrderItemTransitionException>()),
              );
            }
          },
        );
      }
    }
  });

  group('order-item terminal states (RF-032)', () {
    test('voided and cancelled are terminal sinks', () {
      for (final terminal in [
        OrderItemStatus.voided,
        OrderItemStatus.cancelled,
      ]) {
        expect(terminal.isTerminal, isTrue);
        for (final to in OrderItemStatus.values) {
          expect(
            OrderItemStateMachine.isLegal(terminal, to),
            isFalse,
            reason: '${terminal.name} -> ${to.name} must be rejected',
          );
        }
      }
    });

    test('served is NOT terminal (served -> voided is allowed)', () {
      expect(OrderItemStatus.served.isTerminal, isFalse);
      expect(
        OrderItemStateMachine.isLegal(
          OrderItemStatus.served,
          OrderItemStatus.voided,
        ),
        isTrue,
      );
    });
  });

  group('named illegal order-item cases (RF-032)', () {
    test('pending -> preparing (skipping queued) throws', () {
      expect(
        () => OrderItemStateMachine.transition(
          OrderItemStatus.pending,
          OrderItemStatus.preparing,
        ),
        throwsA(isA<IllegalOrderItemTransitionException>()),
      );
    });
    test('preparing -> cancelled throws (once in production, only void)', () {
      expect(
        () => OrderItemStateMachine.transition(
          OrderItemStatus.preparing,
          OrderItemStatus.cancelled,
        ),
        throwsA(isA<IllegalOrderItemTransitionException>()),
      );
    });
  });
}
