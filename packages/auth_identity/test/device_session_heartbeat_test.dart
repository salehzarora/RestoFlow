import 'dart:async';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:test/test.dart';

class _Timer implements Timer {
  _Timer(this.fire);
  final void Function() fire;
  @override
  bool isActive = true;
  @override
  int get tick => 0;
  @override
  void cancel() => isActive = false;
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
}

class _Wire implements SyncRpcTransport {
  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return 'wire-result';
  }
}

void main() {
  test(
    'S1 monotonic resume freshness skips 59 seconds and verifies at 60',
    () async {
      var elapsed = Duration.zero;
      var calls = 0;
      final scheduler = DeviceSessionHeartbeatScheduler(
        elapsed: () => elapsed,
        heartbeat: () async {
          calls++;
          return DeviceHeartbeatResult.active;
        },
        onResult: (_) {},
        periodicTimer: (_, callback) => _Timer(callback),
      );
      scheduler.replaceSession(active: true);
      scheduler.setForeground(true);
      await _flush();
      elapsed = const Duration(seconds: 59);
      scheduler.setForeground(false);
      scheduler.setForeground(true);
      await _flush();
      expect(calls, 1);
      elapsed = const Duration(seconds: 60);
      scheduler.setForeground(false);
      scheduler.setForeground(true);
      await _flush();
      expect(calls, 2);
      scheduler.dispose();
    },
  );
  test(
    'foreground startup, 15 minute cadence, resume; no background/unpaired work',
    () async {
      var calls = 0;
      final timers = <_Timer>[];
      var elapsed = Duration.zero;
      final scheduler = DeviceSessionHeartbeatScheduler(
        elapsed: () => elapsed,
        heartbeat: () async {
          calls++;
          return DeviceHeartbeatResult.active;
        },
        onResult: (_) {},
        periodicTimer: (duration, callback) {
          expect(duration, const Duration(minutes: 15));
          final timer = _Timer(callback);
          timers.add(timer);
          return timer;
        },
      );
      scheduler.setForeground(true);
      expect(calls, 0);
      scheduler.replaceSession(active: true);
      await _flush();
      expect(calls, 1);
      timers.last.fire();
      await _flush();
      expect(calls, 2);
      scheduler.setForeground(false);
      expect(timers.last.isActive, isFalse);
      scheduler.request();
      expect(calls, 2);
      elapsed = const Duration(seconds: 60);
      scheduler.setForeground(true);
      await _flush();
      expect(calls, 3);
      scheduler.replaceSession(active: false);
      expect(timers.last.isActive, isFalse);
      scheduler.request();
      expect(calls, 3);
      scheduler.dispose();
    },
  );
  test(
    'single flight coalesces ticks and discards results from old pairing',
    () async {
      final pending = <Completer<DeviceHeartbeatResult>>[];
      final results = <DeviceHeartbeatResult>[];
      final scheduler = DeviceSessionHeartbeatScheduler(
        heartbeat: () {
          final future = Completer<DeviceHeartbeatResult>();
          pending.add(future);
          return future.future;
        },
        onResult: results.add,
        periodicTimer: (_, callback) => _Timer(callback),
      );
      scheduler.replaceSession(active: true);
      scheduler.setForeground(true);
      scheduler.request();
      scheduler.request();
      expect(pending, hasLength(1));
      scheduler.replaceSession(active: false);
      scheduler.replaceSession(active: true);
      expect(pending, hasLength(1));
      pending.first.complete(DeviceHeartbeatResult.invalidSession);
      await _flush();
      expect(results, isEmpty);
      expect(pending, hasLength(2));
      pending.last.complete(DeviceHeartbeatResult.active);
      await _flush();
      expect(results, [DeviceHeartbeatResult.active]);
      scheduler.request();
      scheduler.dispose();
      pending.last.complete(DeviceHeartbeatResult.invalidSession);
      await _flush();
      expect(results, [DeviceHeartbeatResult.active]);
    },
  );
  test(
    'blocked protected calls produce retryable transient evidence without changing payloads',
    () async {
      final wire = _Wire();
      final guard = DeviceSessionGuardedTransport(wire)..block();
      final payload = <String, dynamic>{
        'operation_id': 'durable-op',
        'notes': 'no onions',
      };
      for (final rpc in [
        'sync_push',
        'sync_pull',
        'start_pin_session',
        'kiosk_submit_order',
      ]) {
        await expectLater(
          guard.invoke(rpc, payload),
          throwsA(
            isA<SyncTransportException>().having(
              (e) => e.kind,
              'kind',
              SyncTransportErrorKind.transient,
            ),
          ),
        );
      }
      expect(wire.calls, isEmpty);
      for (final rpc in [
        'restore_device_session',
        'heartbeat_device_session',
        'redeem_device_pairing',
        'revoke_device_session',
      ]) {
        expect(await guard.invoke(rpc, payload), 'wire-result');
      }
      guard.allow();
      await guard.invoke('sync_push', payload);
      expect(identical(wire.calls.last.$2, payload), isTrue);
      expect(payload, {'operation_id': 'durable-op', 'notes': 'no onions'});
    },
  );
}
