// [POS-OFFLINE-OPERATIONS-002] Pass A — the hold-then-upgrade transport.
//
// The degraded offline boot mounts the app over this transport in HOLD mode;
// these tests pin its whole contract: a hold-mode call throws the transient
// SyncTransportException SYNCHRONOUSLY with zero IO (never a server answer,
// never a 42501 that could poison the outbox), the single permanent upgrade
// switches it to delegate in place, and the upgrade listeners fire exactly
// once.
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:test/test.dart';

final class _RecordingTransport implements SyncRpcTransport {
  final List<(String, Map<String, dynamic>)> calls = [];
  Object? answer = const <String, dynamic>{'ok': true};

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return answer;
  }
}

void main() {
  group('hold mode', () {
    test('throws the transient SyncTransportException SYNCHRONOUSLY '
        '(zero IO — no await ever happens)', () {
      final transport = UpgradableSyncTransport();
      expect(transport.isUpgraded, isFalse);
      // NOT awaited and NOT wrapped in an async matcher: the throw must
      // escape the invoke() call itself, proving no event-loop turn (and so
      // no wire) was ever involved.
      SyncTransportException? caught;
      try {
        transport.invoke('pos_menu', <String, dynamic>{});
      } on SyncTransportException catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught!.kind, SyncTransportErrorKind.transient);
      expect(caught.message, contains('boot retry pending'));
      expect(transport.heldCallCount, 1);
      expect(transport.isUpgraded, isFalse);
    });

    test('every call is refused and counted while held', () {
      final transport = UpgradableSyncTransport();
      for (var i = 0; i < 3; i++) {
        expect(
          () => transport.invoke('sync_push', <String, dynamic>{}),
          throwsA(
            isA<SyncTransportException>().having(
              (e) => e.kind,
              'kind',
              SyncTransportErrorKind.transient,
            ),
          ),
        );
      }
      expect(transport.heldCallCount, 3);
    });
  });

  group('upgrade', () {
    test('delegates calls to the real transport after upgrade', () async {
      final transport = UpgradableSyncTransport();
      final real = _RecordingTransport();
      transport.upgrade(real);
      expect(transport.isUpgraded, isTrue);

      final answer = await transport.invoke('restore_device_session', {
        'p_device_id': 'dev-1',
      });
      expect(answer, {'ok': true});
      expect(real.calls.single.$1, 'restore_device_session');
      expect(real.calls.single.$2, {'p_device_id': 'dev-1'});
      expect(
        transport.heldCallCount,
        0,
        reason: 'a delegated call is not a held call',
      );
    });

    test('fires the upgrade listeners exactly once; a second upgrade is a '
        'no-op that keeps the FIRST delegate', () async {
      final transport = UpgradableSyncTransport();
      final first = _RecordingTransport()..answer = 'first';
      final second = _RecordingTransport()..answer = 'second';
      var fired = 0;
      transport.addOnUpgrade(() => fired++);

      transport.upgrade(first);
      transport.upgrade(second);
      expect(fired, 1, reason: 'the single upgrade fires listeners once');
      expect(await transport.invoke('f', {}), 'first');
      expect(second.calls, isEmpty);
    });

    test('a listener registered AFTER the upgrade never fires', () {
      final transport = UpgradableSyncTransport();
      transport.upgrade(_RecordingTransport());
      var fired = 0;
      transport.addOnUpgrade(() => fired++);
      expect(fired, 0);
    });

    test('a removed listener does not fire', () {
      final transport = UpgradableSyncTransport();
      var fired = 0;
      void listener() => fired++;
      transport.addOnUpgrade(listener);
      transport.removeOnUpgrade(listener);
      transport.upgrade(_RecordingTransport());
      expect(fired, 0);
    });
  });
}
