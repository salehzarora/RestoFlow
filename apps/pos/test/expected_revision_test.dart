import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_pos/src/data/discount.dart';
import 'package:restoflow_pos/src/data/discount_repository.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/data/void_repository.dart';

/// POS-OPERATIONS-SYNC-001 (Commit 3) — `expected_revision` is actually SENT.
///
/// The POS has always ACCEPTED an `expectedRevision` parameter and never once
/// supplied one, so `app.record_payment` / `app.apply_discount` / `app.void_order`
/// could never fire their optimistic-concurrency check. The server's conflict branch
/// was, in practice, unreachable: two tills could each pay an order they both
/// believed was unpaid, and the loser found out by accident.
///
/// Commit 2 gave the POS a revision to send. These prove it now goes on the wire —
/// and that a conflict is surfaced as a TYPED refusal that is never auto-retried.
void main() {
  const session = SyncSession(pinSessionId: 'pin', deviceId: 'dev');

  group('A. the revision reaches the server', () {
    test('A1 DISCOUNT sends expected_revision', () async {
      final t = _CapturingTransport(
        _applied(<String, Object?>{
          'discount_total_minor': 500,
          'grand_total_minor': 3500,
        }),
      );
      await RealDiscountRepository(t, session, const _Ids()).applyOrderDiscount(
        orderId: 'o-1',
        type: DiscountType.fixed,
        value: 500,
        reason: 'goodwill',
        subtotalMinor: 4000,
        taxTotalMinor: 0,
        expectedRevision: 7,
      );
      expect(t.payload['expected_revision'], 7);
    });

    test('A2 PAYMENT sends expected_revision', () async {
      // S1 (PDR-002): a faithful applied payment result names its operation
      // type and the order it settled; the client no longer infers either.
      final t = _CapturingTransport(
        _applied(<String, Object?>{
          'operation_type': 'payment.create',
          'order_id': 'o-1',
          'receipt_number': 'R-1',
          'payment_id': 'p-1',
          'change_due_minor': 0,
          'method': 'cash',
        }),
      );
      await RealPaymentRepository(t, session, const _Ids()).recordCashPayment(
        orderId: 'o-1',
        orderNumber: '#O1',
        amountMinor: 4000,
        tenderedMinor: 4000,
        currencyCode: 'ILS',
        expectedRevision: 9,
      );
      expect(t.payload['expected_revision'], 9);
    });

    test('A3 VOID sends expected_revision', () async {
      final t = _CapturingTransport(
        _applied(<String, Object?>{'order_id': 'o-1'}),
      );
      await RealVoidRepository(
        t,
        session,
        const _Ids(),
      ).voidOrder(orderId: 'o-1', reason: 'wrong order', expectedRevision: 4);
      expect(t.payload['expected_revision'], 4);
    });

    test(
      'A4 with NO known revision, the key is OMITTED — never guessed',
      () async {
        // A guess is worse than nothing: it would make the server refuse a perfectly
        // good write, or (worse) accept one it should have refused.
        final t = _CapturingTransport(
          _applied(<String, Object?>{'order_id': 'o-1'}),
        );
        await RealVoidRepository(
          t,
          session,
          const _Ids(),
        ).voidOrder(orderId: 'o-1', reason: 'wrong order');
        expect(t.payload.containsKey('expected_revision'), isFalse);
      },
    );
  });

  group('B. a conflict is TYPED, and never auto-retried', () {
    test('B1 payment surfaces `conflict` as a typed refusal', () async {
      // sync_push classifies SQLSTATE 40001 as the stable token `conflict`. This is
      // a domain code — not a SQLSTATE we sniffed, not a message we parsed.
      final t = _CapturingTransport(<String, Object?>{
        // The CALL succeeded; the operation inside it was refused.
        'ok': true,
        // CHANGED IN S1-R5: a faithful `sync_push` reply also stamps its own outer
        // `server_ts` (20260905090001_..._002.sql:876).
        'server_ts': '2026-09-08T12:00:01.000Z',
        'results': <Object?>[
          <String, Object?>{
            'local_operation_id': 'id-1',
            'operation_type': 'payment.create',
            'status': 'conflict',
            'ok': false,
            'error': 'conflict',
            // CHANGED IN S1-R3: the EXACT revision-conflict tuple is
            // error 'conflict' + SQLSTATE 40001 + the replay flag
            // (20260905090001_..._002.sql:790-800). Without the SQLSTATE this
            // was not a shape the source emits, and the old classifier turned
            // every unrecognised conflict into a memoized revision refusal.
            'sqlstate': '40001',
            'idempotency_replay': false,
          },
        ],
      });
      await expectLater(
        RealPaymentRepository(t, session, const _Ids()).recordCashPayment(
          orderId: 'o-1',
          orderNumber: '#O1',
          amountMinor: 4000,
          tenderedMinor: 4000,
          currencyCode: 'ILS',
          expectedRevision: 3,
        ),
        throwsA(
          isA<PaymentException>()
              .having((e) => e.conflict, 'conflict', isTrue)
              .having((e) => e.notChargeable, 'notChargeable', isFalse),
        ),
      );
      expect(t.calls, 1, reason: 'ONE attempt — a blind retry double-charges');
    });

    test('B2 a conflict is NOT mistaken for a non-chargeable refusal', () async {
      final t = _CapturingTransport(<String, Object?>{
        'ok': true,
        // CHANGED IN S1-R5: a faithful `sync_push` reply also stamps its own outer
        // `server_ts` (20260905090001_..._002.sql:876).
        'server_ts': '2026-09-08T12:00:01.000Z',
        'results': <Object?>[
          <String, Object?>{
            'local_operation_id': 'id-1',
            'operation_type': 'payment.create',
            'status': 'rejected',
            'ok': false,
            'error': 'order_not_chargeable',
            // CHANGED IN S1-R3: `record_payment` RETURNS this refusal with
            // its own replay flag (20260716090000_...sql:256-259), and
            // sync_push merges it through verbatim.
            // CHANGED IN S1-R4: it always names the order too (:256-258), so
            // the binding is part of the tuple rather than optional.
            'order_id': 'o-1',
            'server_ts': '2026-07-04T09:00:01Z',
            'idempotency_replay': false,
          },
        ],
      });
      await expectLater(
        RealPaymentRepository(t, session, const _Ids()).recordCashPayment(
          orderId: 'o-1',
          orderNumber: '#O1',
          amountMinor: 0,
          tenderedMinor: 0,
          currencyCode: 'ILS',
        ),
        throwsA(
          isA<PaymentException>()
              .having((e) => e.notChargeable, 'notChargeable', isTrue)
              .having((e) => e.conflict, 'conflict', isFalse),
        ),
      );
    });

    test(
      'B3 a GENERIC rejection implies neither conflict nor terminality',
      () async {
        final t = _CapturingTransport(<String, Object?>{
          'ok': true,
          // CHANGED IN S1-R5: a faithful `sync_push` reply also stamps its own outer
          // `server_ts` (20260905090001_..._002.sql:876).
          'server_ts': '2026-09-08T12:00:01.000Z',
          'results': <Object?>[
            <String, Object?>{
              'local_operation_id': 'id-1',
              // Named, so this really exercises the GENERIC-rejection branch
              // rather than passing through the mismatched-result branch.
              'operation_type': 'payment.create',
              'status': 'rejected',
              'ok': false,
              'error': 'rejected',
              // CHANGED IN S1-R3: the exact caught-rejection tuple carries the
              // SQLSTATE and the replay flag
              // (20260905090001_..._002.sql:834-853).
              'sqlstate': '42501',
              'detail': null,
              'idempotency_replay': false,
            },
          ],
        });
        await expectLater(
          RealPaymentRepository(t, session, const _Ids()).recordCashPayment(
            orderId: 'o-1',
            orderNumber: '#O1',
            amountMinor: 4000,
            tenderedMinor: 4000,
            currencyCode: 'ILS',
          ),
          throwsA(
            isA<PaymentException>()
                .having((e) => e.conflict, 'conflict', isFalse)
                .having((e) => e.notChargeable, 'notChargeable', isFalse),
          ),
        );
      },
    );
  });
}

/// S1-R2: `sync_push` returns `ok: true` on its normal path even when an
/// individual operation was refused, so every faithful reply carries it.
Map<String, Object?> _applied(Map<String, Object?> extra) => <String, Object?>{
  'ok': true,
  // CHANGED IN S1-R5: a faithful `sync_push` reply also stamps its own outer
  // `server_ts` (20260905090001_..._002.sql:876).
  'server_ts': '2026-09-08T12:00:01.000Z',
  'results': <Object?>[
    <String, Object?>{
      'local_operation_id': 'id-1',
      'status': 'applied',
      'ok': true,
      // CHANGED IN S1-R3: `sync_push` stamps `idempotency_replay` on every
      // result (20260905090001_..._002.sql:861-872); a fixture without it
      // blessed a shape the deployed function never emits.
      'idempotency_replay': false,
      // CHANGED IN S1-R4: the COMPLETE tracked applied tuple. `record_payment`
      // emits every one of these on a real application
      // (20260716090000_..._contracts.sql:400-411), so a fixture without them
      // blessed a shape the deployed function never returns. A case that wants
      // one absent overrides it.
      'shift_id': 'shift-1',
      'cash_drawer_session_id': 'drawer-1',
      'payment_revision': 1,
      'order_revision': 8,
      'auto_completed': false,
      'server_ts': '2026-07-04T09:00:01Z',
      ...extra,
    },
  ],
};

/// Captures the op payload actually put on the wire. The point of these tests is
/// what the SERVER receives, so nothing less than the real payload will do.
class _CapturingTransport implements SyncRpcTransport {
  _CapturingTransport(this._response);

  final Object? _response;
  int calls = 0;
  Map<String, Object?> payload = <String, Object?>{};

  @override
  Future<Object?> invoke(String fn, Map<String, dynamic> args) async {
    calls++;
    final ops = args['p_operations'] as List<dynamic>;
    final op = ops.single as Map<String, dynamic>;
    payload = (op['payload'] as Map).cast<String, Object?>();
    return _response;
  }
}

class _Ids implements ClientIdGenerator {
  const _Ids();

  @override
  String newId() => 'id-1';
}
