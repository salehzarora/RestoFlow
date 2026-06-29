import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';

/// RF-130: RealPaymentRepository delivers a `payment.create` op to the RF-126
/// `public.sync_push` wrapper (never `app.*`), sends ONLY the tendered cash + the
/// order id, and reads the server-authoritative receipt number (D-021) + change
/// (D-007) back from the per-op result. Everything else - no session/transport,
/// no order id, a non-`applied` result (incl. the RF-055 no-open-shift
/// precondition), or a malformed envelope - fails closed with a [PaymentException]
/// (no fake payment). House style: a hand-written recording transport, no network.
class _RecordingTransport implements SyncRpcTransport {
  _RecordingTransport(this._handler);

  final Future<Object?> Function(String function, Map<String, dynamic> params)
  _handler;

  final List<String> functions = <String>[];
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> p) async {
    functions.add(function);
    params.add(p);
    return _handler(function, p);
  }
}

const SyncSession _session = SyncSession(
  pinSessionId: 'pin-123',
  deviceId: 'device-abc',
);

/// The id generator mints, in order, the op `local_operation_id` then the client
/// `payment_id` (the server returns the authoritative one).
RealPaymentRepository _repo(SyncRpcTransport transport) =>
    RealPaymentRepository(
      transport,
      _session,
      FixedClientIdGenerator(const ['op-pay-1', 'client-pay-1']),
    );

Map<String, dynamic> _envelope(Map<String, dynamic> opResult) =>
    <String, dynamic>{
      'ok': true,
      'results': <dynamic>[opResult],
      'server_ts': '2026-06-29T09:00:01Z',
    };

Future<CashPayment> _record(RealPaymentRepository repo) =>
    repo.recordCashPayment(
      orderId: 'order-uuid-1',
      orderNumber: 'DEMO-0001',
      amountMinor: 4200,
      tenderedMinor: 5000,
      currencyCode: 'ILS',
    );

void main() {
  group('RealPaymentRepository -> public.sync_push (RF-130)', () {
    test('pushes a payment.create op (never app.*) and maps the applied server '
        'result into a CashPayment with the server receipt + change', () async {
      final transport = _RecordingTransport(
        (_, _) async => _envelope(<String, dynamic>{
          'local_operation_id': 'op-pay-1',
          'operation_type': 'payment.create',
          'ok': true,
          'status': 'applied',
          'payment_id': 'srv-pay-9',
          'order_id': 'order-uuid-1',
          'receipt_number': '17',
          'change_due_minor': 800,
          'idempotency_replay': false,
        }),
      );

      final payment = await _record(_repo(transport));

      // exactly one call, to the PUBLIC wrapper - never the app schema.
      expect(transport.functions, <String>['sync_push']);
      expect(transport.functions.any((f) => f.contains('app.')), isFalse);

      // envelope: session-scoped, a single payment.create op.
      final params = transport.params.single;
      expect(params['p_pin_session_id'], 'pin-123');
      expect(params['p_device_id'], 'device-abc');
      final ops = params['p_operations'] as List;
      expect(ops, hasLength(1));
      final op = ops.single as Map<String, dynamic>;
      expect(op['local_operation_id'], 'op-pay-1');
      expect(op['operation_type'], 'payment.create');
      expect(op['target_entity'], 'payment');
      expect(op['target_id'], 'client-pay-1');

      final payload = op['payload'] as Map<String, dynamic>;
      expect(payload['order_id'], 'order-uuid-1');
      expect(payload['tender_type'], 'cash');
      // the client sends ONLY the tendered amount - integer minor, no float.
      expect(payload['amount_tendered_minor'], isA<int>());
      expect(payload['amount_tendered_minor'], 5000);
      // the order total, change, receipt, method, and shift/drawer are server-
      // owned and never sent by the client.
      expect(payload.containsKey('amount_minor'), isFalse);
      expect(payload.containsKey('change_minor'), isFalse);
      expect(payload.containsKey('method'), isFalse);
      expect(payload.containsKey('shift_id'), isFalse);
      expect(payload.containsKey('cash_drawer_session_id'), isFalse);

      // the server is authoritative for the receipt number (D-021) + change.
      expect(payment.status, PaymentStatus.completed);
      expect(payment.method, PaymentMethod.cash);
      expect(payment.paymentId, 'srv-pay-9');
      expect(payment.receiptNumber, '17');
      expect(payment.changeMinor, 800);
      expect(payment.amountMinor, 4200);
      expect(payment.tenderedMinor, 5000);
      expect(payment.deviceId, 'device-abc');
      expect(payment.localOperationId, 'op-pay-1');
    });

    test(
      'an applied result MISSING payment_id fails closed (never a client id)',
      () async {
        // payment_id is server-authoritative: the client id used for the op
        // target_id must NEVER stand in for a real recorded payment.
        final transport = _RecordingTransport(
          (_, _) async => _envelope(<String, dynamic>{
            'local_operation_id': 'op-pay-1',
            'status': 'applied',
            'receipt_number': '18',
            'change_due_minor': 0,
          }),
        );
        await expectLater(
          _record(_repo(transport)),
          throwsA(isA<PaymentException>()),
        );
      },
    );

    test('an applied result with a BLANK payment_id fails closed', () async {
      final transport = _RecordingTransport(
        (_, _) async => _envelope(<String, dynamic>{
          'local_operation_id': 'op-pay-1',
          'status': 'applied',
          'payment_id': '',
          'receipt_number': '18',
          'change_due_minor': 0,
        }),
      );
      await expectLater(
        _record(_repo(transport)),
        throwsA(isA<PaymentException>()),
      );
    });

    test(
      'an applied result with a WRONG-TYPE payment_id fails closed',
      () async {
        final transport = _RecordingTransport(
          (_, _) async => _envelope(<String, dynamic>{
            'local_operation_id': 'op-pay-1',
            'status': 'applied',
            'payment_id': 12345, // not a string
            'receipt_number': '18',
            'change_due_minor': 0,
          }),
        );
        await expectLater(
          _record(_repo(transport)),
          throwsA(isA<PaymentException>()),
        );
      },
    );

    test(
      'a no-open-shift precondition (rejected/42501) fails closed',
      () async {
        final transport = _RecordingTransport(
          (_, _) async => _envelope(<String, dynamic>{
            'local_operation_id': 'op-pay-1',
            'status': 'rejected',
            'error': 'rejected',
            'sqlstate': '42501',
          }),
        );
        await expectLater(
          _record(_repo(transport)),
          throwsA(isA<PaymentException>()),
        );
      },
    );

    test('a conflict (40001) fails closed', () async {
      final transport = _RecordingTransport(
        (_, _) async => _envelope(<String, dynamic>{
          'local_operation_id': 'op-pay-1',
          'status': 'conflict',
          'error': 'conflict',
        }),
      );
      await expectLater(
        _record(_repo(transport)),
        throwsA(isA<PaymentException>()),
      );
    });

    test('a 42501 whole-batch transport failure fails closed', () async {
      final transport = _RecordingTransport(
        (_, _) async => throw const SyncTransportException(
          SyncTransportErrorKind.auth,
          code: '42501',
          message: 'revoked device / expired session',
        ),
      );
      await expectLater(
        _record(_repo(transport)),
        throwsA(isA<PaymentException>()),
      );
    });
  });

  group('RealPaymentRepository result parsing fails closed (RF-130)', () {
    Future<CashPayment> recordWith(Object? envelope) {
      final transport = _RecordingTransport((_, _) async => envelope);
      return _record(_repo(transport));
    }

    test('a malformed (non-Map) envelope -> PaymentException', () async {
      await expectLater(
        recordWith('not-a-map'),
        throwsA(isA<PaymentException>()),
      );
    });

    test('a missing results array -> PaymentException', () async {
      await expectLater(
        recordWith(<String, dynamic>{'ok': true}),
        throwsA(isA<PaymentException>()),
      );
    });

    test('an empty results array -> PaymentException', () async {
      await expectLater(
        recordWith(<String, dynamic>{
          'ok': true,
          'results': <dynamic>[],
          'server_ts': '2026-06-29T09:00:01Z',
        }),
        throwsA(isA<PaymentException>()),
      );
    });

    test(
      'a matched result with a MISSING status -> PaymentException',
      () async {
        await expectLater(
          recordWith(
            _envelope(<String, dynamic>{
              'local_operation_id': 'op-pay-1',
              'payment_id': 'srv-pay-1',
              'receipt_number': '1',
              'change_due_minor': 0,
            }),
          ),
          throwsA(isA<PaymentException>()),
        );
      },
    );

    test(
      'a matched result with an UNKNOWN status -> PaymentException',
      () async {
        await expectLater(
          recordWith(
            _envelope(<String, dynamic>{
              'local_operation_id': 'op-pay-1',
              'status': 'teleported',
              'payment_id': 'srv-pay-1',
              'receipt_number': '1',
              'change_due_minor': 0,
            }),
          ),
          throwsA(isA<PaymentException>()),
        );
      },
    );

    test('no result matching this op -> PaymentException', () async {
      await expectLater(
        recordWith(
          _envelope(<String, dynamic>{
            'local_operation_id': 'some-other-op',
            'status': 'applied',
            'receipt_number': '1',
            'change_due_minor': 0,
          }),
        ),
        throwsA(isA<PaymentException>()),
      );
    });

    test(
      'an applied result missing the receipt number -> PaymentException',
      () async {
        await expectLater(
          recordWith(
            _envelope(<String, dynamic>{
              'local_operation_id': 'op-pay-1',
              'status': 'applied',
              'change_due_minor': 0,
            }),
          ),
          throwsA(isA<PaymentException>()),
        );
      },
    );

    test(
      'an applied result with a non-integer change -> PaymentException',
      () async {
        await expectLater(
          recordWith(
            _envelope(<String, dynamic>{
              'local_operation_id': 'op-pay-1',
              'status': 'applied',
              'payment_id': 'srv-pay-1',
              'receipt_number': '1',
              'change_due_minor': 8.5, // money must be integer minor units
            }),
          ),
          throwsA(isA<PaymentException>()),
        );
      },
    );

    test(
      'an applied result contradicted by ok:false -> PaymentException',
      () async {
        await expectLater(
          recordWith(
            _envelope(<String, dynamic>{
              'local_operation_id': 'op-pay-1',
              'status': 'applied',
              'ok': false,
              'receipt_number': '1',
              'change_due_minor': 0,
            }),
          ),
          throwsA(isA<PaymentException>()),
        );
      },
    );
  });

  group(
    'RealPaymentRepository fail-closed without a session/transport/order',
    () {
      test('no transport -> PaymentException', () async {
        final repo = RealPaymentRepository(
          null,
          _session,
          FixedClientIdGenerator(const ['a', 'b']),
        );
        await expectLater(_record(repo), throwsA(isA<PaymentException>()));
      });

      test('no session -> PaymentException, no backend call', () async {
        final transport = _RecordingTransport(
          (_, _) async => fail('must not contact a backend'),
        );
        final repo = RealPaymentRepository(
          transport,
          null,
          FixedClientIdGenerator(const ['a', 'b']),
        );
        await expectLater(_record(repo), throwsA(isA<PaymentException>()));
        expect(transport.functions, isEmpty);
      });

      test('an empty order id -> PaymentException, no backend call', () async {
        final transport = _RecordingTransport(
          (_, _) async => fail('must not contact a backend'),
        );
        final repo = _repo(transport);
        await expectLater(
          repo.recordCashPayment(
            orderId: '   ',
            orderNumber: 'DEMO-0001',
            amountMinor: 4200,
            tenderedMinor: 5000,
            currencyCode: 'ILS',
          ),
          throwsA(isA<PaymentException>()),
        );
        expect(transport.functions, isEmpty);
      });

      test('shiftContext() returns a neutral placeholder (never throws)', () {
        final repo = RealPaymentRepository(
          null,
          null,
          FixedClientIdGenerator(const ['a', 'b']),
        );
        final ctx = repo.shiftContext();
        expect(ctx.shiftOpen, isFalse);
        expect(ctx.drawerOpen, isFalse);
        expect(ctx.cashInDrawerMinor, 0);
        expect(repo.paymentFor('DEMO-0001'), isNull);
      });
    },
  );
}
