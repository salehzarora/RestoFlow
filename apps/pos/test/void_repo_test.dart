import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/void_repository.dart';

/// MONEY-VOID-001: the order-cancellation (void) repository. The demo store
/// validates the reason and succeeds locally; the real repo posts an
/// `order.void` op (money-free), reads the per-op result back, and surfaces the
/// server refusals (permission_denied / order_has_completed_payment) honestly.
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

Map<String, dynamic> _envelope(Map<String, dynamic> op) => <String, dynamic>{
  'ok': true,
  'results': <dynamic>[op],
};

void main() {
  group('DemoVoidStore', () {
    const store = DemoVoidStore();

    test('a blank reason is rejected', () {
      expect(
        () => store.voidOrder(orderId: 'o1', reason: '  '),
        throwsA(isA<VoidException>()),
      );
    });

    test('a non-empty reason succeeds locally', () async {
      await store.voidOrder(orderId: 'o1', reason: 'wrong item'); // no throw
    });
  });

  group('RealVoidRepository', () {
    RealVoidRepository repo(SyncRpcTransport t) => RealVoidRepository(
      t,
      _session,
      FixedClientIdGenerator(const ['op-v1']),
    );

    test('fails closed with no transport/session (no fake success)', () {
      final r = RealVoidRepository(
        null,
        null,
        FixedClientIdGenerator(const ['x']),
      );
      expect(
        () => r.voidOrder(orderId: 'o1', reason: 'x'),
        throwsA(isA<VoidException>()),
      );
    });

    test('fails closed with an empty order id; never contacts the backend', () {
      final t = _RecordingTransport((_, _) async => _envelope(const {}));
      expect(
        () => repo(t).voidOrder(orderId: '   ', reason: 'x'),
        throwsA(isA<VoidException>()),
      );
      expect(t.params, isEmpty);
    });

    test('a blank reason is rejected before any backend call', () {
      final t = _RecordingTransport((_, _) async => _envelope(const {}));
      expect(
        () => repo(t).voidOrder(orderId: 'o1', reason: '   '),
        throwsA(isA<VoidException>()),
      );
      expect(t.params, isEmpty);
    });

    test(
      'sends an order.void op with {order_id, reason} and NO money',
      () async {
        final t = _RecordingTransport(
          (_, _) async => _envelope(const {
            'local_operation_id': 'op-v1',
            'status': 'applied',
            'ok': true,
            'order_id': 'o1',
          }),
        );
        await repo(t).voidOrder(orderId: 'o1', reason: 'wrong table');

        expect(t.params.single['p_pin_session_id'], 'pin-1');
        expect(t.params.single['p_device_id'], 'device-1');
        final op = (t.params.single['p_operations'] as List).single as Map;
        expect(op['operation_type'], 'order.void');
        expect(op['local_operation_id'], 'op-v1');
        final payload = op['payload'] as Map;
        expect(payload['order_id'], 'o1');
        expect(payload['reason'], 'wrong table');
        // Money-free: no *_minor keys are ever sent for a void.
        expect(payload.keys.where((k) => '$k'.contains('minor')), isEmpty);
      },
    );

    test('an applied result succeeds', () async {
      final t = _RecordingTransport(
        (_, _) async => _envelope(const {
          'local_operation_id': 'op-v1',
          'status': 'applied',
          'ok': true,
        }),
      );
      await repo(t).voidOrder(orderId: 'o1', reason: 'x'); // no throw
    });

    test('permission_denied -> VoidException.permissionDenied', () {
      final t = _RecordingTransport(
        (_, _) async => _envelope(const {
          'local_operation_id': 'op-v1',
          'status': 'rejected',
          'ok': false,
          'error': 'permission_denied',
        }),
      );
      expect(
        () => repo(t).voidOrder(orderId: 'o1', reason: 'x'),
        throwsA(
          isA<VoidException>()
              .having((e) => e.permissionDenied, 'permissionDenied', isTrue)
              .having((e) => e.alreadyPaid, 'alreadyPaid', isFalse),
        ),
      );
    });

    test('order_has_completed_payment -> VoidException.alreadyPaid', () {
      final t = _RecordingTransport(
        (_, _) async => _envelope(const {
          'local_operation_id': 'op-v1',
          'status': 'rejected',
          'ok': false,
          'error': 'permission_denied',
          'detail': 'order_has_completed_payment',
        }),
      );
      expect(
        () => repo(t).voidOrder(orderId: 'o1', reason: 'x'),
        throwsA(
          isA<VoidException>().having(
            (e) => e.alreadyPaid,
            'alreadyPaid',
            isTrue,
          ),
        ),
      );
    });

    test('a generic rejection is neither permission nor paid', () {
      final t = _RecordingTransport(
        (_, _) async => _envelope(const {
          'local_operation_id': 'op-v1',
          'status': 'rejected',
          'ok': false,
          'error': 'conflict',
        }),
      );
      expect(
        () => repo(t).voidOrder(orderId: 'o1', reason: 'x'),
        throwsA(
          isA<VoidException>().having(
            (e) => e.permissionDenied || e.alreadyPaid,
            'typed',
            isFalse,
          ),
        ),
      );
    });

    test('a whole-batch transport failure throws VoidException', () {
      final t = _RecordingTransport(
        (_, _) async => throw const SyncTransportException(
          SyncTransportErrorKind.transient,
          code: '42501',
        ),
      );
      expect(
        () => repo(t).voidOrder(orderId: 'o1', reason: 'x'),
        throwsA(isA<VoidException>()),
      );
    });
  });
}
