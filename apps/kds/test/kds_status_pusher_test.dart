import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/state/kds_status_pusher.dart';

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport({this.throwOnInvoke = false});
  final bool throwOnInvoke;
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    if (throwOnInvoke) {
      throw const SyncTransportException(SyncTransportErrorKind.transient);
    }
    return {'ok': true, 'results': []};
  }
}

KdsTicketView _liveTicket() => KdsTicketView(
  kitchenTicketId: 'order-1:station-1',
  stationId: 'station-1',
  items: const [KdsItemView(name: 'Falafel', quantity: 2)],
  status: KitchenTicketStatus.newTicket,
  orderId: 'order-1',
);

void main() {
  const session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

  test('maps board statuses to the frozen order statuses (D-018 §1.1)', () {
    expect(
      KdsStatusPusher.orderStatusFor(KitchenTicketStatus.acknowledged),
      'accepted',
    );
    expect(
      KdsStatusPusher.orderStatusFor(KitchenTicketStatus.inPreparation),
      'preparing',
    );
    expect(KdsStatusPusher.orderStatusFor(KitchenTicketStatus.ready), 'ready');
    expect(
      KdsStatusPusher.orderStatusFor(KitchenTicketStatus.bumped),
      'served',
    );
    expect(
      KdsStatusPusher.orderStatusFor(KitchenTicketStatus.newTicket),
      isNull,
    );
  });

  test(
    'pushes an order.status op through sync_push (no money in payload)',
    () async {
      final transport = _FakeTransport();
      final pusher = KdsStatusPusher(
        transport: transport,
        session: session,
        generateOperationId: () => 'op-1',
      );
      await pusher.push(_liveTicket(), KitchenTicketStatus.acknowledged);

      final call = transport.calls.single;
      expect(call.$1, 'sync_push');
      expect(call.$2['p_pin_session_id'], 'pin-1');
      expect(call.$2['p_device_id'], 'dev-1');
      final op = (call.$2['p_operations'] as List).single as Map;
      expect(op['operation_type'], 'order.status');
      expect(op['local_operation_id'], 'op-1');
      expect(op['target_id'], 'order-1');
      final payload = op['payload'] as Map;
      expect(payload, {'order_id': 'order-1', 'new_status': 'accepted'});
      // Kitchen push carries NO money key of any kind (SECURITY T-003).
      expect('$payload'.contains('minor'), isFalse);
    },
  );

  test('a DEMO ticket (no orderId) is never pushed', () async {
    final transport = _FakeTransport();
    final pusher = KdsStatusPusher(transport: transport, session: session);
    await pusher.push(
      KdsTicketView(
        kitchenTicketId: 'demo-1',
        stationId: 's',
        items: const [],
        status: KitchenTicketStatus.newTicket,
      ),
      KitchenTicketStatus.acknowledged,
    );
    expect(transport.calls, isEmpty);
  });

  test('a transport failure is swallowed (the next poll re-syncs)', () async {
    final transport = _FakeTransport(throwOnInvoke: true);
    final pusher = KdsStatusPusher(transport: transport, session: session);
    // Must not throw.
    await pusher.push(_liveTicket(), KitchenTicketStatus.ready);
    expect(transport.calls, hasLength(1));
  });
}
