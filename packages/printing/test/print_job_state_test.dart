import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// RF-071: the print-job state machine — legal/forbidden transitions, terminals,
/// and crash recovery to `possiblyPrinted` (STATE_MACHINES §8).
void main() {
  group('PrintJobState transitions', () {
    test('the happy path is legal', () {
      expect(
        PrintJobState.created.canTransitionTo(PrintJobState.queued),
        isTrue,
      );
      expect(
        PrintJobState.queued.canTransitionTo(PrintJobState.printing),
        isTrue,
      );
      expect(
        PrintJobState.printing.canTransitionTo(PrintJobState.printed),
        isTrue,
      );
    });

    test('failure/retry path is legal', () {
      expect(
        PrintJobState.printing.canTransitionTo(PrintJobState.failed),
        isTrue,
      );
      expect(
        PrintJobState.failed.canTransitionTo(PrintJobState.retrying),
        isTrue,
      );
      expect(
        PrintJobState.retrying.canTransitionTo(PrintJobState.printing),
        isTrue,
      );
      expect(
        PrintJobState.failed.canTransitionTo(PrintJobState.abandoned),
        isTrue,
      );
    });

    test('forbidden transitions', () {
      // cannot cancel mid-print
      expect(
        PrintJobState.printing.canTransitionTo(PrintJobState.cancelled),
        isFalse,
      );
      // failed -> printed directly is forbidden (must go through retrying)
      expect(
        PrintJobState.failed.canTransitionTo(PrintJobState.printed),
        isFalse,
      );
      // created cannot jump straight to printing (the logical lifecycle goes
      // through queued; the spool CLAIM performs the atomic dispatch at the
      // store layer, not via canTransition).
      expect(
        PrintJobState.created.canTransitionTo(PrintJobState.printing),
        isFalse,
      );
    });

    test('terminal states have no outgoing transitions', () {
      for (final t in PrintJobState.terminals) {
        expect(t.isTerminal, isTrue);
        for (final to in PrintJobState.values) {
          expect(
            t.canTransitionTo(to),
            isFalse,
            reason: '$t -> $to must be forbidden',
          );
        }
      }
      expect(PrintJobState.terminals, {
        PrintJobState.printed,
        PrintJobState.cancelled,
        PrintJobState.abandoned,
      });
    });

    test('possiblyPrinted is not terminal but has no automatic transition', () {
      expect(PrintJobState.possiblyPrinted.isTerminal, isFalse);
      for (final to in PrintJobState.values) {
        expect(PrintJobState.possiblyPrinted.canTransitionTo(to), isFalse);
      }
    });

    test(
      'crash recovery maps printing -> possiblyPrinted, others unchanged',
      () {
        expect(
          PrintJobState.recoverInterrupted(PrintJobState.printing),
          PrintJobState.possiblyPrinted,
        );
        expect(
          PrintJobState.recoverInterrupted(PrintJobState.queued),
          PrintJobState.queued,
        );
        expect(
          PrintJobState.recoverInterrupted(PrintJobState.printed),
          PrintJobState.printed,
        );
      },
    );

    test('wire round-trip', () {
      for (final s in PrintJobState.values) {
        expect(PrintJobState.fromWire(s.wireName), s);
      }
      expect(() => PrintJobState.fromWire('bogus'), throwsArgumentError);
    });
  });
}
