import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// Independent re-statement of the legal ORDER edges (NOT derived from the SUT)
/// so the exhaustive matrix tests the machine against the spec, not itself.
Set<(OrderStatus, OrderStatus)> _legalOrderEdges(OrderType type) => {
  (OrderStatus.draft, OrderStatus.submitted),
  (OrderStatus.submitted, OrderStatus.accepted),
  (OrderStatus.submitted, OrderStatus.cancelled),
  (OrderStatus.accepted, OrderStatus.preparing),
  (OrderStatus.accepted, OrderStatus.cancelled),
  (OrderStatus.preparing, OrderStatus.ready),
  (OrderStatus.served, OrderStatus.completed),
  (OrderStatus.submitted, OrderStatus.voided),
  (OrderStatus.accepted, OrderStatus.voided),
  (OrderStatus.preparing, OrderStatus.voided),
  (OrderStatus.ready, OrderStatus.voided),
  (OrderStatus.served, OrderStatus.voided),
  if (type == OrderType.dineIn) (OrderStatus.ready, OrderStatus.served),
  if (type == OrderType.takeaway) (OrderStatus.ready, OrderStatus.completed),
};

void main() {
  group('exhaustive order transition matrix (RF-032, D-018)', () {
    for (final type in OrderType.values) {
      final legal = _legalOrderEdges(type);
      for (final from in OrderStatus.values) {
        for (final to in OrderStatus.values) {
          final expected = legal.contains((from, to));
          test('${type.name}: ${from.name} -> ${to.name} '
              '${expected ? "allowed" : "rejected"}', () {
            expect(OrderStateMachine.isLegal(from, to, type), expected);
            if (expected) {
              expect(OrderStateMachine.transition(from, to, type), to);
            } else {
              expect(
                () => OrderStateMachine.transition(from, to, type),
                throwsA(isA<IllegalOrderTransitionException>()),
              );
            }
          });
        }
      }
    }
  });

  group('terminal order states are sinks (RF-032)', () {
    for (final terminal in [
      OrderStatus.completed,
      OrderStatus.cancelled,
      OrderStatus.voided,
    ]) {
      test('${terminal.name} is terminal and has no legal outgoing edge', () {
        expect(terminal.isTerminal, isTrue);
        for (final type in OrderType.values) {
          for (final to in OrderStatus.values) {
            expect(
              OrderStateMachine.isLegal(terminal, to, type),
              isFalse,
              reason: '${terminal.name} -> ${to.name} must be rejected',
            );
          }
        }
      });
    }
    test('non-terminal order states report isTerminal == false', () {
      for (final s in [
        OrderStatus.draft,
        OrderStatus.submitted,
        OrderStatus.accepted,
        OrderStatus.preparing,
        OrderStatus.ready,
        OrderStatus.served,
      ]) {
        expect(s.isTerminal, isFalse);
      }
    });
  });

  group('named illegal cases (RF-032 AC#1)', () {
    test('draft -> completed throws', () {
      expect(
        () => OrderStateMachine.transition(
          OrderStatus.draft,
          OrderStatus.completed,
          OrderType.dineIn,
        ),
        throwsA(isA<IllegalOrderTransitionException>()),
      );
    });
    test('submitted -> served throws', () {
      expect(
        () => OrderStateMachine.transition(
          OrderStatus.submitted,
          OrderStatus.served,
          OrderType.dineIn,
        ),
        throwsA(isA<IllegalOrderTransitionException>()),
      );
    });
    test('submitted -> completed throws', () {
      expect(
        () => OrderStateMachine.transition(
          OrderStatus.submitted,
          OrderStatus.completed,
          OrderType.takeaway,
        ),
        throwsA(isA<IllegalOrderTransitionException>()),
      );
    });
  });

  group('order-type fork at ready (RF-032)', () {
    test('dine-in: ready -> served allowed', () {
      expect(
        OrderStateMachine.isLegal(
          OrderStatus.ready,
          OrderStatus.served,
          OrderType.dineIn,
        ),
        isTrue,
      );
    });
    test('dine-in: ready -> completed rejected', () {
      expect(
        OrderStateMachine.isLegal(
          OrderStatus.ready,
          OrderStatus.completed,
          OrderType.dineIn,
        ),
        isFalse,
      );
    });
    test('takeaway: ready -> completed allowed', () {
      expect(
        OrderStateMachine.isLegal(
          OrderStatus.ready,
          OrderStatus.completed,
          OrderType.takeaway,
        ),
        isTrue,
      );
    });
    test('takeaway: ready -> served rejected', () {
      expect(
        OrderStateMachine.isLegal(
          OrderStatus.ready,
          OrderStatus.served,
          OrderType.takeaway,
        ),
        isFalse,
      );
    });
  });
}
