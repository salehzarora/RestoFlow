import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// PRINT-STABILITY-001: the reliability-hardened Bluetooth connector. Drives a
/// scriptable [BluetoothThermalApi] fake (no device, no plugin) to prove chunked
/// writes, fresh-socket reconnect, one automatic retry, and honest error mapping.

class _FakeThermalApi implements BluetoothThermalApi {
  _FakeThermalApi({
    this.permissions = true,
    this.enabled = true,
    this.connected = false,
    this.connectResult = true,
    this.writeSucceedsFromConnect = 1,
    this.connectDelay,
  });

  bool permissions;
  bool enabled;
  bool connected;
  bool connectResult;

  /// writeBytes succeeds only once [connectCalls] has reached this value — lets a
  /// test model "the first attempt's writes fail, the retry after reconnect works".
  int writeSucceedsFromConnect;
  Duration? connectDelay;

  int connectCalls = 0;
  int disconnectCalls = 0;
  final List<List<int>> writes = <List<int>>[];
  final List<String> events = <String>[];

  @override
  Future<bool> ensurePermissions() async => permissions;

  @override
  Future<bool> get isEnabled async => enabled;

  @override
  Future<bool> get isConnected async => connected;

  @override
  Future<List<BluetoothDeviceInfo>> pairedDevices() async =>
      const <BluetoothDeviceInfo>[];

  @override
  Future<bool> connect(String address) async {
    events.add('connect');
    connectCalls++;
    if (connectDelay != null) await Future<void>.delayed(connectDelay!);
    connected = connectResult;
    return connectResult;
  }

  @override
  Future<bool> writeBytes(List<int> bytes) async {
    events.add('write');
    writes.add(bytes);
    return connectCalls >= writeSucceedsFromConnect;
  }

  @override
  Future<bool> disconnect() async {
    events.add('disconnect');
    disconnectCalls++;
    connected = false;
    return true;
  }
}

BluetoothThermalConnector _connector(_FakeThermalApi api) =>
    // chunkDelay 0 keeps the tests fast (and proves the delay is tunable).
    BluetoothThermalConnector(
      api: api,
      chunkBytes: 512,
      chunkDelay: Duration.zero,
    );

void main() {
  group('chunked writes', () {
    test(
      'streams a large payload in 512-byte chunks that reassemble exactly',
      () async {
        final api = _FakeThermalApi();
        final bytes = Uint8List.fromList(
          List<int>.generate(1300, (i) => i % 256),
        );
        final result = await _connector(api).send(address: 'AA', bytes: bytes);

        expect(result.ok, isTrue);
        expect(api.writes.map((w) => w.length).toList(), [512, 512, 276]);
        expect(api.writes.expand((w) => w).toList(), bytes.toList());
        // one connect, one disconnect (best-effort cleanup), no retry.
        expect(api.connectCalls, 1);
        expect(api.disconnectCalls, greaterThanOrEqualTo(1));
      },
    );

    test('an empty document is a trivial success with no writeBytes', () async {
      final api = _FakeThermalApi();
      final result = await _connector(
        api,
      ).send(address: 'AA', bytes: Uint8List(0));
      expect(result.ok, isTrue);
      expect(api.writes, isEmpty);
    });
  });

  group('fresh-socket reconnect', () {
    test('drops a stale/half-open connection BEFORE connecting', () async {
      final api = _FakeThermalApi(connected: true); // lingering socket
      await _connector(
        api,
      ).send(address: 'AA', bytes: Uint8List.fromList([1, 2, 3]));
      // the first thing that happens is a disconnect, then the connect.
      expect(api.events.first, 'disconnect');
      expect(api.events[1], 'connect');
    });
  });

  group('automatic retry', () {
    test(
      'one clean reconnect + retry recovers when the first write fails',
      () async {
        // writes fail on attempt 1 (connectCalls==1), succeed on attempt 2.
        final api = _FakeThermalApi(writeSucceedsFromConnect: 2);
        final result = await _connector(
          api,
        ).send(address: 'AA', bytes: Uint8List.fromList([9, 9, 9]));

        expect(result.ok, isTrue); // recovered without an app restart
        expect(api.connectCalls, 2); // retried once
        // a disconnect happened between the two connects (force-reset reconnect).
        final firstConnect = api.events.indexOf('connect');
        final secondConnect = api.events.indexOf('connect', firstConnect + 1);
        expect(secondConnect, greaterThan(firstConnect));
        expect(
          api.events
              .sublist(firstConnect + 1, secondConnect)
              .contains('disconnect'),
          isTrue,
        );
      },
    );

    test(
      'a persistent write failure retries once then fails honestly',
      () async {
        final api = _FakeThermalApi(
          writeSucceedsFromConnect: 99,
        ); // never writes ok
        final result = await _connector(
          api,
        ).send(address: 'AA', bytes: Uint8List.fromList([1]));
        expect(result.ok, isFalse);
        expect(
          result.category,
          pp.PrinterErrorCategory.unknown,
        ); // write failed
        expect(api.connectCalls, 2); // tried, then retried once
      },
    );
  });

  group('honest error mapping', () {
    test(
      'missing permission -> unsupported, never touches the socket',
      () async {
        final api = _FakeThermalApi(permissions: false);
        final result = await _connector(
          api,
        ).send(address: 'AA', bytes: Uint8List.fromList([1]));
        expect(result.category, pp.PrinterErrorCategory.unsupported);
        expect(api.connectCalls, 0);
      },
    );

    test('connect failure -> unreachable', () async {
      final api = _FakeThermalApi(connectResult: false);
      final result = await _connector(
        api,
      ).send(address: 'AA', bytes: Uint8List.fromList([1]));
      expect(result.category, pp.PrinterErrorCategory.unreachable);
    });

    test(
      'a hung connect times out -> unreachable (never hangs the UI)',
      () async {
        final api = _FakeThermalApi(connectDelay: const Duration(seconds: 5));
        final result = await _connector(api).send(
          address: 'AA',
          bytes: Uint8List.fromList([1]),
          timeout: const Duration(milliseconds: 20),
        );
        expect(result.ok, isFalse);
        expect(result.category, pp.PrinterErrorCategory.unreachable);
      },
    );
  });

  group('paired-devices listing', () {
    test(
      'permission denied -> a typed failure (drives the settings UI)',
      () async {
        final api = _FakeThermalApi(permissions: false);
        final res = await _connector(api).pairedDevices();
        expect(res.ok, isFalse);
        expect(res.error, BluetoothPrinterError.permissionDenied);
      },
    );

    test('bluetooth off -> a typed failure', () async {
      final api = _FakeThermalApi(enabled: false);
      final res = await _connector(api).pairedDevices();
      expect(res.error, BluetoothPrinterError.bluetoothOff);
    });
  });
}
