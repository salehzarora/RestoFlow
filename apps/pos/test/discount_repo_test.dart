import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_pos/src/data/discount.dart';
import 'package:restoflow_pos/src/data/discount_repository.dart';
import 'package:restoflow_pos/src/data/ids.dart';

/// RF-117 part C: order-level discounts are server-authoritative + authorized.
/// The demo store mirrors the server (clamp <= subtotal, half-away %), and the
/// real repo pushes an `order.discount` op, reads the recomputed totals back, and
/// surfaces permission_denied honestly. Integer minor units, no float.
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

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'device-1');

void main() {
  group('DemoDiscountStore (RF-117)', () {
    const store = DemoDiscountStore();

    test('fixed amount reduces the grand total', () async {
      final r = await store.applyOrderDiscount(
        orderId: '',
        type: DiscountType.fixed,
        value: 1000,
        reason: 'loyalty',
        subtotalMinor: 4200,
        taxTotalMinor: 0,
      );
      expect(r.discountTotalMinor, 1000);
      expect(r.grandTotalMinor, 3200);
    });

    test('percentage uses half-away rounding on the subtotal', () async {
      final r = await store.applyOrderDiscount(
        orderId: '',
        type: DiscountType.percentage,
        value: 1000, // 10.00%
        reason: 'promo',
        subtotalMinor: 4200,
        taxTotalMinor: 0,
      );
      expect(r.discountTotalMinor, 420);
      expect(r.grandTotalMinor, 3780);
    });

    test(
      'a discount larger than the subtotal is CLAMPED (grand >= tax)',
      () async {
        final r = await store.applyOrderDiscount(
          orderId: '',
          type: DiscountType.fixed,
          value: 999999,
          reason: 'comp',
          subtotalMinor: 4200,
          taxTotalMinor: 300,
        );
        expect(r.discountTotalMinor, 4200); // clamped to subtotal
        expect(r.grandTotalMinor, 300); // subtotal - subtotal + tax
      },
    );

    test('an empty reason is rejected', () async {
      expect(
        () => store.applyOrderDiscount(
          orderId: '',
          type: DiscountType.fixed,
          value: 500,
          reason: '   ',
          subtotalMinor: 4200,
          taxTotalMinor: 0,
        ),
        throwsA(isA<DiscountException>()),
      );
    });

    test('a non-positive value is rejected', () async {
      expect(
        () => store.applyOrderDiscount(
          orderId: '',
          type: DiscountType.fixed,
          value: 0,
          reason: 'x',
          subtotalMinor: 4200,
          taxTotalMinor: 0,
        ),
        throwsA(isA<DiscountException>()),
      );
    });
  });

  group('RealDiscountRepository -> public.sync_push (RF-117)', () {
    RealDiscountRepository repo(SyncRpcTransport t) => RealDiscountRepository(
      t,
      _session,
      FixedClientIdGenerator(const ['op-disc-1']),
    );

    test(
      'pushes an order.discount op and reads the recomputed totals',
      () async {
        final transport = _RecordingTransport(
          (_, _) async => <String, dynamic>{
            'ok': true,
            'results': <dynamic>[
              <String, dynamic>{
                'local_operation_id': 'op-disc-1',
                'operation_type': 'order.discount',
                'ok': true,
                'status': 'applied',
                'order_id': 'order-1',
                'revision': 2,
                'discount_total_minor': 1000,
                'grand_total_minor': 3200,
              },
            ],
            'server_ts': '2026-07-04T09:00:00Z',
          },
        );
        final r = await repo(transport).applyOrderDiscount(
          orderId: 'order-1',
          type: DiscountType.fixed,
          value: 1000,
          reason: 'loyalty',
          subtotalMinor: 4200,
          taxTotalMinor: 0,
        );

        // exactly one call, to the PUBLIC wrapper — never app.*.
        final params = transport.params.single;
        final op =
            (params['p_operations'] as List).single as Map<String, dynamic>;
        expect(op['operation_type'], 'order.discount');
        final payload = op['payload'] as Map<String, dynamic>;
        expect(payload['scope'], 'order');
        expect(payload['discount_type'], 'fixed');
        expect(payload['value'], 1000);
        expect(payload['reason'], 'loyalty');

        // server-authoritative totals read back from the result.
        expect(r.discountTotalMinor, 1000);
        expect(r.grandTotalMinor, 3200);
      },
    );

    test(
      'permission_denied surfaces as DiscountException(permissionDenied)',
      () async {
        final transport = _RecordingTransport(
          (_, _) async => <String, dynamic>{
            'ok': true,
            'results': <dynamic>[
              <String, dynamic>{
                'local_operation_id': 'op-disc-1',
                'operation_type': 'order.discount',
                'ok': false,
                'error': 'permission_denied',
                'status': 'rejected',
              },
            ],
            'server_ts': '2026-07-04T09:00:00Z',
          },
        );
        await expectLater(
          repo(transport).applyOrderDiscount(
            orderId: 'order-1',
            type: DiscountType.percentage,
            value: 1000,
            reason: 'promo',
            subtotalMinor: 4200,
            taxTotalMinor: 0,
          ),
          throwsA(
            isA<DiscountException>().having(
              (e) => e.permissionDenied,
              'permissionDenied',
              isTrue,
            ),
          ),
        );
      },
    );

    test('no session/transport fails closed (no backend call)', () async {
      final transport = _RecordingTransport(
        (_, _) async => fail('must not contact a backend'),
      );
      final r = RealDiscountRepository(
        transport,
        null,
        FixedClientIdGenerator(const ['op-disc-1']),
      );
      await expectLater(
        r.applyOrderDiscount(
          orderId: 'order-1',
          type: DiscountType.fixed,
          value: 500,
          reason: 'x',
          subtotalMinor: 4200,
          taxTotalMinor: 0,
        ),
        throwsA(isA<DiscountException>()),
      );
      expect(transport.params, isEmpty);
    });
  });
}
