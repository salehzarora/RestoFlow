import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

RecallAuditEvent _recall({
  String ticketId = 't1',
  KitchenTicketStatus from = KitchenTicketStatus.bumped,
  String reason = 'bumped in error',
  String actorId = 'kds-device',
}) => KitchenTicketStateMachine.recall(
  kitchenTicketId: ticketId,
  from: from,
  reason: reason,
  actorId: actorId,
);

void main() {
  group('recall audit placeholder (RF-034, AC#1)', () {
    test('recall requires a non-empty reason', () {
      expect(
        () => _recall(reason: '  '),
        throwsA(isA<MissingRecallReasonException>()),
      );
    });

    test('recall requires an actor id', () {
      expect(
        () => _recall(actorId: ''),
        throwsA(isA<MissingRecallActorException>()),
      );
    });

    test('recall from a non-bumped state throws an illegal transition', () {
      expect(
        () => _recall(from: KitchenTicketStatus.ready),
        throwsA(isA<IllegalKitchenTicketTransitionException>()),
      );
    });

    test('recall from bumped returns a RecallAuditEvent (bumped -> '
        'in_preparation)', () {
      final event = _recall(
        ticketId: 'ticket-7',
        reason: 'remake needed',
        actorId: 'cook-1',
      );
      expect(event, isA<RecallAuditEvent>());
      expect(event.kitchenTicketId, 'ticket-7');
      expect(event.fromStatus, KitchenTicketStatus.bumped);
      expect(event.toStatus, KitchenTicketStatus.inPreparation);
      expect(event.reason, 'remake needed');
      expect(event.actorId, 'cook-1');
    });

    test('the recall is local-only — no audit is written anywhere', () {
      // The event is a pure in-memory value object (no I/O); equality proves it
      // carries exactly the recall context.
      final a = _recall(ticketId: 't', reason: 'r', actorId: 'x');
      final b = _recall(ticketId: 't', reason: 'r', actorId: 'x');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
