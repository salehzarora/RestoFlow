import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show kdsSyncSourceProvider;
import 'package:restoflow_kds/src/state/kds_session.dart';
import 'package:restoflow_kds/src/state/kds_void_ack_controller.dart';
import 'package:restoflow_sync/restoflow_sync.dart';

/// PSC-001D — the acknowledgement controller's honest result handling: an
/// applied envelope keeps the order PENDING (removal waits for the
/// authoritative pull) and triggers the immediate canonical refresh; a typed
/// rejection or transport failure marks it failed (card stays, retryable);
/// duplicate taps while in flight are single-fire.

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> p) _handler;
  final List<(String, Map<String, dynamic>)> calls = [];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return _handler(function, params);
  }
}

class _FakeSource implements KdsSyncSource {
  int refreshCalls = 0;
  @override
  KdsSyncState get state => KdsSyncState.initial;
  @override
  Stream<KdsSyncState> get states => const Stream.empty();
  @override
  Future<void> start() async {}
  @override
  Future<void> refresh() async {
    refreshCalls++;
  }

  @override
  Future<void> resume() async {}
  @override
  Future<void> dispose() async {}
}

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

Map<String, dynamic> _result(String status, {bool ok = true, String? error}) {
  final op = <String, dynamic>{'status': status, 'ok': ok};
  if (error != null) op['error'] = error;
  return {
    'ok': true,
    'results': [op],
  };
}

(ProviderContainer, _FakeTransport, _FakeSource) _harness(
  Object? Function(String fn, Map<String, dynamic> p) handler,
) {
  final transport = _FakeTransport(handler);
  final source = _FakeSource();
  final container = ProviderContainer(
    overrides: [
      kdsAuthTransportProvider.overrideWithValue(transport),
      kdsSyncSessionProvider.overrideWithValue(_session),
      kdsSyncSourceProvider.overrideWithValue(source),
    ],
  );
  addTearDown(container.dispose);
  return (container, transport, source);
}

String? _sentLocalOp(_FakeTransport t) {
  final ops = t.calls.single.$2['p_operations'] as List;
  return (ops.single as Map)['local_operation_id'] as String?;
}

void main() {
  test(
    'an APPLIED ack stays pending and triggers the immediate pull',
    () async {
      late String localOp;
      final (container, transport, source) = _harness((fn, p) {
        final ops = p['p_operations'] as List;
        localOp = (ops.single as Map)['local_operation_id'] as String;
        return {
          'ok': true,
          'results': [
            {'local_operation_id': localOp, 'status': 'applied', 'ok': true},
          ],
        };
      });
      await container
          .read(kdsVoidAckControllerProvider.notifier)
          .acknowledge('o1');
      final state = container.read(kdsVoidAckControllerProvider);
      // Pending until the AUTHORITATIVE pull clears the card — never hidden
      // locally on the envelope alone.
      expect(state.pending, {'o1'});
      expect(state.failed, isEmpty);
      expect(source.refreshCalls, 1);
      // The envelope is the canonical single-op order.void_ack.
      final op =
          (transport.calls.single.$2['p_operations'] as List).single as Map;
      expect(op['operation_type'], 'order.void_ack');
      expect(op['target_id'], 'o1');
      expect((op['payload'] as Map)['order_id'], 'o1');
    },
  );

  test(
    'a typed REJECTION marks the order failed (card stays, retryable)',
    () async {
      final (container, transport, source) = _harness(
        (fn, p) => _result('rejected', ok: false, error: 'invalid_device_type'),
      );
      await container
          .read(kdsVoidAckControllerProvider.notifier)
          .acknowledge('o1');
      final state = container.read(kdsVoidAckControllerProvider);
      expect(state.pending, isEmpty);
      expect(state.failed, {'o1'});
      expect(source.refreshCalls, 0);
      expect(_sentLocalOp(transport), isNotNull);
    },
  );

  test(
    'a TRANSPORT failure marks the order failed and never fakes success',
    () async {
      final (container, _, source) = _harness(
        (fn, p) => throw StateError('offline'),
      );
      await container
          .read(kdsVoidAckControllerProvider.notifier)
          .acknowledge('o1');
      final state = container.read(kdsVoidAckControllerProvider);
      expect(state.pending, isEmpty);
      expect(state.failed, {'o1'});
      expect(source.refreshCalls, 0);
    },
  );

  test('duplicate acknowledgements while pending are single-fire', () async {
    final (container, transport, _) = _harness((fn, p) {
      final ops = p['p_operations'] as List;
      final localOp = (ops.single as Map)['local_operation_id'] as String;
      return {
        'ok': true,
        'results': [
          {'local_operation_id': localOp, 'status': 'applied', 'ok': true},
        ],
      };
    });
    final notifier = container.read(kdsVoidAckControllerProvider.notifier);
    await notifier.acknowledge('o1');
    await notifier.acknowledge('o1'); // still pending -> no second send
    expect(transport.calls, hasLength(1));
  });

  test('a retry after failure sends again', () async {
    var attempt = 0;
    final (container, transport, source) = _harness((fn, p) {
      attempt++;
      if (attempt == 1) throw StateError('offline');
      final ops = p['p_operations'] as List;
      final localOp = (ops.single as Map)['local_operation_id'] as String;
      return {
        'ok': true,
        'results': [
          {'local_operation_id': localOp, 'status': 'applied', 'ok': true},
        ],
      };
    });
    final notifier = container.read(kdsVoidAckControllerProvider.notifier);
    await notifier.acknowledge('o1');
    expect(container.read(kdsVoidAckControllerProvider).failed, {'o1'});
    await notifier.acknowledge('o1'); // retry clears failed, succeeds
    final state = container.read(kdsVoidAckControllerProvider);
    expect(state.failed, isEmpty);
    expect(state.pending, {'o1'});
    expect(transport.calls, hasLength(2));
    expect(source.refreshCalls, 1);
  });
}
