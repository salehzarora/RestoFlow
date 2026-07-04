import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';

/// RF-117: non-cash tenders (card/bit/external) are externally recorded — the
/// server (and the demo store) stamp amount = tendered = order total, change = 0,
/// and close_shift/the demo drawer count ONLY cash so non-cash never inflates
/// expected cash. Integer minor units only (no floating-point).
class _RecordingTransport implements SyncRpcTransport {
  _RecordingTransport(this._handler);
  final Future<Object?> Function(String, Map<String, dynamic>) _handler;
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> p) async {
    params.add(p);
    return _handler(function, p);
  }
}

void main() {
  group('DemoPaymentStore non-cash tender (RF-117)', () {
    for (final method in const [
      PaymentMethod.card,
      PaymentMethod.bit,
      PaymentMethod.externalTender,
    ]) {
      test(
        '${method.wire}: records the tender with change 0, tendered=total',
        () async {
          final store = DemoPaymentStore();
          final p = await store.recordCashPayment(
            orderId: '',
            orderNumber: 'DEMO-0001',
            amountMinor: 4200,
            tenderedMinor: 4200,
            currencyCode: 'ILS',
            method: method,
          );
          expect(p.method, method);
          expect(p.amountMinor, 4200);
          expect(p.tenderedMinor, 4200);
          expect(p.changeMinor, 0);
          // Non-cash never rolls into the drawer (only cash does).
          final ctx = store.shiftContext();
          expect(ctx.cashInDrawerMinor, ctx.openingFloatMinor);
        },
      );
    }

    test('a cash payment DOES roll into the drawer (contrast)', () async {
      final store = DemoPaymentStore();
      await store.recordCashPayment(
        orderId: '',
        orderNumber: 'DEMO-0002',
        amountMinor: 4200,
        tenderedMinor: 5000,
        currencyCode: 'ILS',
        // default method: cash
      );
      final ctx = store.shiftContext();
      expect(ctx.cashInDrawerMinor, ctx.openingFloatMinor + 4200);
    });
  });

  group('RealPaymentRepository non-cash tender -> sync_push (RF-117)', () {
    test('sends the selected tender_type and reads the method back', () async {
      final transport = _RecordingTransport(
        (_, _) async => <String, dynamic>{
          'ok': true,
          'results': <dynamic>[
            <String, dynamic>{
              'local_operation_id': 'op-pay-1',
              'operation_type': 'payment.create',
              'ok': true,
              'status': 'applied',
              'payment_id': 'srv-pay-1',
              'order_id': 'order-uuid-1',
              'method': 'card',
              'receipt_number': '42',
              'change_due_minor': 0,
            },
          ],
          'server_ts': '2026-07-04T09:00:00Z',
        },
      );
      final repo = RealPaymentRepository(
        transport,
        const SyncSession(pinSessionId: 'pin-1', deviceId: 'device-1'),
        FixedClientIdGenerator(const ['op-pay-1', 'client-pay-1']),
      );

      final payment = await repo.recordCashPayment(
        orderId: 'order-uuid-1',
        orderNumber: 'DEMO-0001',
        amountMinor: 4200,
        tenderedMinor: 4200,
        currencyCode: 'ILS',
        method: PaymentMethod.card,
      );

      final payload =
          (transport.params.single['p_operations'] as List).single
              as Map<String, dynamic>;
      final body = payload['payload'] as Map<String, dynamic>;
      expect(body['tender_type'], 'card');
      expect(body['amount_tendered_minor'], isA<int>());
      expect(body['amount_tendered_minor'], 4200);

      expect(payment.method, PaymentMethod.card);
      expect(payment.changeMinor, 0);
      expect(payment.tenderedMinor, 4200);
      expect(payment.receiptNumber, '42');
    });
  });
}
